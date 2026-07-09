unit WiFi.Engine.Analysis;

{
  WiFi.Engine.Analysis

  The RF analysis engine. Given an immutable scan snapshot it produces a
  TChannelReport describing, per band, how busy each channel is and which
  channel is least congested (the recommendation).

  Phase 1 scope: per-channel access-point counts, an RSSI/overlap-weighted
  congestion score, and a recommended channel per band. Later phases extend
  TChannelReport with utilization and co-/adjacent-channel breakdowns without
  changing this public surface.

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
    ApCount: Integer;          // networks whose primary channel is this one
    OverlapCount: Integer;     // networks whose span overlaps this channel
    StrongestRSSI: Integer;    // dBm; -999 when no AP present
    /// <summary>Weighted 0..100 congestion score (higher == busier).</summary>
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
  Stats: TDictionary<Integer, TChannelStat>; // key = Band*1000 + Channel
  AP: TAccessPoint;
  Key: Integer;
  Stat: TChannelStat;
  Span, OtherSpan: TFreqRange;
  Other: TAccessPoint;
  I: Integer;

  function MakeKey(ABand: TWiFiBand; AChannel: Integer): Integer;
  begin
    Result := Ord(ABand) * 1000 + AChannel;
  end;

  procedure PickRecommendation(ABand: TWiFiBand; var ATarget: Integer);
  var
    S: TChannelStat;
    Best: Double;
    BestChannel: Integer;
    Candidate: Integer;
  begin
    Best := MaxDouble;
    BestChannel := 0;
    // For 2.4 GHz, only consider the non-overlapping trio.
    if ABand = wb24GHz then
    begin
      for Candidate in PREFERRED_24 do
      begin
        Key := MakeKey(ABand, Candidate);
        if Stats.TryGetValue(Key, S) then
        begin
          if S.CongestionScore < Best then
          begin
            Best := S.CongestionScore;
            BestChannel := Candidate;
          end;
        end
        else
        begin
          // A completely empty preferred channel is ideal.
          BestChannel := Candidate;
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
    // First pass: per-channel AP counts and strongest signal.
    for AP in ASnapshot.Items do
    begin
      if (AP.Band = wbUnknown) or (AP.Channel = 0) then
        Continue;
      Key := MakeKey(AP.Band, AP.Channel);
      if not Stats.TryGetValue(Key, Stat) then
      begin
        FillChar(Stat, SizeOf(Stat), 0);
        Stat.Channel := AP.Channel;
        Stat.Band := AP.Band;
        Stat.StrongestRSSI := -999;
      end;
      Inc(Stat.ApCount);
      if AP.RSSI > Stat.StrongestRSSI then
        Stat.StrongestRSSI := AP.RSSI;
      Stats.AddOrSetValue(Key, Stat);
    end;

    // Second pass: overlap count + weighted congestion score. O(n^2) is fine
    // for the hundreds of networks we expect; upgraded to a sweep in Phase 2.
    for I := 0 to ASnapshot.Items.Count - 1 do
    begin
      AP := ASnapshot.Items[I];
      if (AP.Band = wbUnknown) or (AP.Channel = 0) then
        Continue;
      Key := MakeKey(AP.Band, AP.Channel);
      if not Stats.TryGetValue(Key, Stat) then
        Continue;
      Span := ChannelSpan(AP.FrequencyMHz, AP.Width);
      for Other in ASnapshot.Items do
      begin
        if (Other.Band <> AP.Band) or (Other.BSSID = AP.BSSID) then
          Continue;
        OtherSpan := ChannelSpan(Other.FrequencyMHz, Other.Width);
        if Span.Overlaps(OtherSpan) then
        begin
          Inc(Stat.OverlapCount);
          Stat.CongestionScore := Stat.CongestionScore + RssiWeight(Other.RSSI);
        end;
      end;
      // Include this channel's own occupants in the score.
      Stat.CongestionScore := Stat.CongestionScore + RssiWeight(AP.RSSI);
      Stats.AddOrSetValue(Key, Stat);
    end;

    // Find the peak raw score for normalisation.
    var MaxScore: Double := 0;
    for Stat in Stats.Values do
      if Stat.CongestionScore > MaxScore then
        MaxScore := Stat.CongestionScore;
    if MaxScore <= 0 then
      MaxScore := 1;

    // Normalise to 0..100, copy out, and track the single busiest channel.
    var WorstScore: Double := -1;
    for Key in Stats.Keys do
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

    // Order by band then channel for stable presentation.
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
