unit WiFi.Engine.Analysis;

{
  WiFi.Engine.Analysis

  The RF analysis engine. Given an immutable scan snapshot it produces a
  TChannelReport describing, per band, how busy each channel is and which
  channel is least congested (the recommendation).

  Phase 2 scope: per-channel access-point counts, co-channel vs adjacent-
  channel interference, an RSSI-weighted congestion score, a utilization
  estimate, and a recommended channel per band.

  All methods are pure functions of their input, so the engine is trivially
  testable with canned snapshots and never touches the WLAN API or the VCL.
}

interface

uses
  System.Generics.Collections,
  WiFi.Models, WiFi.Engine.Channels;

type
  /// <summary>Aggregated statistics for one channel within a band.</summary>
  TChannelStat = record
    Channel: Integer;
    Band: TWiFiBand;
    CenterFreqMHz: Integer;    // channel center used for span/overlap maths
    ApCount: Integer;          // networks whose primary channel is this one
    CoChannelCount: Integer;   // networks sharing this exact channel (== ApCount)
    AdjacentCount: Integer;    // overlapping networks on a *different* channel
    OverlapCount: Integer;     // total overlapping networks (co + adjacent)
    StrongestRSSI: Integer;    // dBm; -999 when no AP present
    /// <summary>Absolute 0..100 busy estimate from co/adjacent occupancy.</summary>
    Utilization: Double;
    /// <summary>Relative 0..100 congestion score (normalised to the busiest).</summary>
    CongestionScore: Double;
  end;

  TChannelStatList = TList<TChannelStat>;

  /// <summary>
  ///  Result of analysing a snapshot. Owns its stat list; callers Free it.
  /// </summary>
  TChannelReport = class
  private
    FStats: TChannelStatList;
    FRecommended24: Integer;
    FRecommended5: Integer;
    FRecommended6: Integer;
    FMostCongestedChannel: Integer;
    FMostCongestedBand: TWiFiBand;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>All channel stats, ordered by band then channel.</summary>
    property Stats: TChannelStatList read FStats;
    property Recommended24: Integer read FRecommended24;
    property Recommended5: Integer read FRecommended5;
    property Recommended6: Integer read FRecommended6;
    property MostCongestedChannel: Integer read FMostCongestedChannel;
    property MostCongestedBand: TWiFiBand read FMostCongestedBand;
    /// <summary>Recommended channel for a band (0 when not analysable).</summary>
    function RecommendedFor(ABand: TWiFiBand): Integer;
    /// <summary>Stats for a single band, in channel order (new list; caller frees).</summary>
    function StatsForBand(ABand: TWiFiBand): TChannelStatList;
  end;

  /// <summary>Stateless RF analysis engine.</summary>
  TAnalysisEngine = class
  private
    /// <summary>Convert an RSSI (dBm) to a 0..1 interference weight.</summary>
    class function RssiWeight(ARssi: Integer): Double; static;
  public
    /// <summary>
    ///  Analyse a snapshot. Never returns nil; an empty snapshot yields an
    ///  empty report. The caller owns the returned report.
    /// </summary>
    function Analyze(ASnapshot: TScanSnapshot): TChannelReport;
  end;

implementation

uses
  System.Math, System.Generics.Defaults;

const
  // The non-overlapping 2.4 GHz channels we prefer to recommend.
  PREFERRED_24: array[0..2] of Integer = (1, 6, 11);
  RSSI_FLOOR = -95; // dBm treated as "no signal"
  RSSI_CEIL  = -35; // dBm treated as "very strong"
  // Adjacent-channel interference counts for less than co-channel.
  ADJACENT_WEIGHT = 0.5;

function BandChannelKey(ABand: TWiFiBand; AChannel: Integer): Integer; inline;
begin
  Result := Ord(ABand) * 1000 + AChannel;
end;

{ TChannelReport }

constructor TChannelReport.Create;
begin
  inherited Create;
  FStats := TChannelStatList.Create;
  FMostCongestedBand := wbUnknown;
end;

destructor TChannelReport.Destroy;
begin
  FStats.Free;
  inherited;
end;

function TChannelReport.RecommendedFor(ABand: TWiFiBand): Integer;
begin
  case ABand of
    wb24GHz: Result := FRecommended24;
    wb5GHz:  Result := FRecommended5;
    wb6GHz:  Result := FRecommended6;
  else
    Result := 0;
  end;
end;

function TChannelReport.StatsForBand(ABand: TWiFiBand): TChannelStatList;
var
  S: TChannelStat;
begin
  Result := TChannelStatList.Create;
  for S in FStats do
    if S.Band = ABand then
      Result.Add(S);
end;

{ TAnalysisEngine }

class function TAnalysisEngine.RssiWeight(ARssi: Integer): Double;
begin
  // Linear map RSSI_FLOOR..RSSI_CEIL -> 0..1, clamped.
  if ARssi <= RSSI_FLOOR then
    Exit(0);
  if ARssi >= RSSI_CEIL then
    Exit(1);
  Result := (ARssi - RSSI_FLOOR) / (RSSI_CEIL - RSSI_FLOOR);
end;

function TAnalysisEngine.Analyze(ASnapshot: TScanSnapshot): TChannelReport;
var
  Stats: TDictionary<Integer, TChannelStat>;
  AP: TAccessPoint;
  Key: Integer;
  Keys: TArray<Integer>;
  Stat: TChannelStat;
  ChSpan, ApSpan: TFreqRange;
  Raw, MaxScore, WorstScore: Double;

  procedure PickRecommendation(ABand: TWiFiBand; var ATarget: Integer);
  var
    S: TChannelStat;
    Best: Double;
    BestChannel, Candidate, K: Integer;
  begin
    Best := MaxDouble;
    BestChannel := 0;
    if ABand = wb24GHz then
    begin
      for Candidate in PREFERRED_24 do
      begin
        K := BandChannelKey(ABand, Candidate);
        if Stats.TryGetValue(K, S) then
        begin
          if S.CongestionScore < Best then
          begin
            Best := S.CongestionScore;
            BestChannel := Candidate;
          end;
        end
        else
        begin
          BestChannel := Candidate; // an empty preferred channel is ideal
          Break;
        end;
      end;
    end
    else
    begin
      for S in Stats.Values do
        if (S.Band = ABand) and (S.CongestionScore < Best) then
        begin
          Best := S.CongestionScore;
          BestChannel := S.Channel;
        end;
    end;
    ATarget := BestChannel;
  end;

begin
  Result := TChannelReport.Create;
  if (ASnapshot = nil) or (ASnapshot.Count = 0) then
    Exit;

  Stats := TDictionary<Integer, TChannelStat>.Create;
  try
    // Pass 1: per-channel AP counts, strongest signal, representative center.
    for AP in ASnapshot.Items do
    begin
      if (AP.Band = wbUnknown) or (AP.Channel = 0) then
        Continue;
      Key := BandChannelKey(AP.Band, AP.Channel);
      if not Stats.TryGetValue(Key, Stat) then
      begin
        Stat := Default(TChannelStat);
        Stat.Channel := AP.Channel;
        Stat.Band := AP.Band;
        Stat.CenterFreqMHz := AP.FrequencyMHz;
        Stat.StrongestRSSI := -999;
      end;
      Inc(Stat.ApCount);
      if AP.RSSI > Stat.StrongestRSSI then
        Stat.StrongestRSSI := AP.RSSI;
      Stats.AddOrSetValue(Key, Stat);
    end;

    // Pass 2: for each channel, classify every AP in the band as co-channel or
    // adjacent (overlapping, different channel) and accumulate a weighted score.
    Keys := Stats.Keys.ToArray;
    for Key in Keys do
    begin
      Stat := Stats[Key];
      ChSpan := ChannelSpan(Stat.CenterFreqMHz, cw20);
      Raw := 0;
      Stat.CoChannelCount := 0;
      Stat.AdjacentCount := 0;
      for AP in ASnapshot.Items do
      begin
        if AP.Band <> Stat.Band then
          Continue;
        if AP.Channel = Stat.Channel then
        begin
          Inc(Stat.CoChannelCount);
          Raw := Raw + RssiWeight(AP.RSSI);
        end
        else
        begin
          ApSpan := ChannelSpan(AP.FrequencyMHz, AP.Width);
          if ChSpan.Overlaps(ApSpan) then
          begin
            Inc(Stat.AdjacentCount);
            Raw := Raw + RssiWeight(AP.RSSI) * ADJACENT_WEIGHT;
          end;
        end;
      end;
      Stat.OverlapCount := Stat.CoChannelCount + Stat.AdjacentCount;
      Stat.CongestionScore := Raw; // normalised below
      Stat.Utilization := Min(100.0, Stat.CoChannelCount * 15.0 + Stat.AdjacentCount * 7.0);
      Stats[Key] := Stat;
    end;

    // Normalise congestion to 0..100 and copy out, tracking the busiest channel.
    MaxScore := 0;
    for Stat in Stats.Values do
      if Stat.CongestionScore > MaxScore then
        MaxScore := Stat.CongestionScore;
    if MaxScore <= 0 then
      MaxScore := 1;

    WorstScore := -1;
    for Key in Keys do
    begin
      Stat := Stats[Key];
      Stat.CongestionScore := (Stat.CongestionScore / MaxScore) * 100;
      FStats.Add(Stat);
      if Stat.CongestionScore > WorstScore then
      begin
        WorstScore := Stat.CongestionScore;
        FMostCongestedChannel := Stat.Channel;
        FMostCongestedBand := Stat.Band;
      end;
    end;

    FStats.Sort(TComparer<TChannelStat>.Construct(
      function(const L, R: TChannelStat): Integer
      begin
        Result := Ord(L.Band) - Ord(R.Band);
        if Result = 0 then
          Result := L.Channel - R.Channel;
      end));

    PickRecommendation(wb24GHz, FRecommended24);
    PickRecommendation(wb5GHz, FRecommended5);
    PickRecommendation(wb6GHz, FRecommended6);
  finally
    Stats.Free;
  end;
end;

end.
