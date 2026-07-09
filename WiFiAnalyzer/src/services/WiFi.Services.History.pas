unit WiFi.Services.History;

{
  WiFi.Services.History

  Keeps the temporal data the Signal Visualization tab needs:

    * a per-BSSID ring buffer of RSSI samples over time (for the live graph and
      trend analysis);
    * the latest AccessPoint seen for each BSSID (to name/label networks);
    * a bounded history of past scans, so any two can be compared.

  It is a plain main-thread object (fed from the view-model when a snapshot is
  ingested); no threading or WLAN/VCL dependency, so it is unit-testable.
}

interface

uses
  System.SysUtils, System.Generics.Collections,
  WiFi.Models;

type
  /// <summary>One RSSI reading at a point in time.</summary>
  TRssiSample = record
    Time: TDateTime;
    RSSI: Integer;
  end;

  /// <summary>How a network changed between two compared snapshots.
  /// Ordered so that the most interesting rows sort first.</summary>
  TComparisonStatus = (csAdded, csRemoved, csChanged, csSame);

  /// <summary>One row of a snapshot-to-snapshot comparison.</summary>
  TComparisonRow = record
    BSSID: string;
    SSID: string;
    Status: TComparisonStatus;
    OldRSSI: Integer;   // meaningful unless csAdded
    NewRSSI: Integer;   // meaningful unless csRemoved
  end;

  THistoryService = class
  private
  type
    TStoredScan = class
      Time: TDateTime;
      ByBssid: TDictionary<string, TAccessPoint>;
      constructor Create;
      destructor Destroy; override;
    end;
  private
    FCapacity: Integer;
    FMaxSnapshots: Integer;
    FSeries: TObjectDictionary<string, TList<TRssiSample>>;
    FLatest: TDictionary<string, TAccessPoint>;
    FSnapshots: TObjectList<TStoredScan>;
  public
    constructor Create(ACapacity: Integer = 240; AMaxSnapshots: Integer = 60);
    destructor Destroy; override;

    /// <summary>Append a scan: extend every network's RSSI series and store the
    /// snapshot for later comparison.</summary>
    procedure RecordSnapshot(ASnapshot: TScanSnapshot);

    /// <summary>Copy of a network's RSSI samples, oldest first.</summary>
    function SeriesFor(const ABssid: string): TArray<TRssiSample>;
    /// <summary>Signal trend (dBm) over the last ASamples readings: the mean of
    /// the recent half minus the mean of the older half. Positive == improving.
    /// Returns 0 when there is too little history.</summary>
    function TrendFor(const ABssid: string; ASamples: Integer = 8): Double;
    /// <summary>Latest AccessPoint for every known BSSID, strongest first.</summary>
    function KnownNetworks: TArray<TAccessPoint>;

    function SnapshotCount: Integer;
    function SnapshotTime(AIndex: Integer): TDateTime;
    /// <summary>Compare two stored snapshots by index (older, newer).</summary>
    function Compare(AOlder, ANewer: Integer): TArray<TComparisonRow>;

    property Capacity: Integer read FCapacity;
  end;

implementation

uses
  System.Generics.Defaults;

{ THistoryService.TStoredScan }

constructor THistoryService.TStoredScan.Create;
begin
  inherited Create;
  ByBssid := TDictionary<string, TAccessPoint>.Create;
end;

destructor THistoryService.TStoredScan.Destroy;
begin
  ByBssid.Free;
  inherited;
end;

{ THistoryService }

constructor THistoryService.Create(ACapacity, AMaxSnapshots: Integer);
begin
  inherited Create;
  FCapacity := ACapacity;
  FMaxSnapshots := AMaxSnapshots;
  FSeries := TObjectDictionary<string, TList<TRssiSample>>.Create([doOwnsValues]);
  FLatest := TDictionary<string, TAccessPoint>.Create;
  FSnapshots := TObjectList<TStoredScan>.Create(True {owns});
end;

destructor THistoryService.Destroy;
begin
  FSnapshots.Free;
  FLatest.Free;
  FSeries.Free;
  inherited;
end;

procedure THistoryService.RecordSnapshot(ASnapshot: TScanSnapshot);
var
  AP: TAccessPoint;
  Series: TList<TRssiSample>;
  Sample: TRssiSample;
  Scan: TStoredScan;
begin
  if ASnapshot = nil then
    Exit;

  Scan := TStoredScan.Create;
  Scan.Time := ASnapshot.Timestamp;

  for AP in ASnapshot.Items do
  begin
    if AP.BSSID = '' then
      Continue;

    if not FSeries.TryGetValue(AP.BSSID, Series) then
    begin
      Series := TList<TRssiSample>.Create;
      FSeries.Add(AP.BSSID, Series);
    end;
    Sample.Time := ASnapshot.Timestamp;
    Sample.RSSI := AP.RSSI;
    Series.Add(Sample);
    while Series.Count > FCapacity do
      Series.Delete(0);

    FLatest.AddOrSetValue(AP.BSSID, AP);
    Scan.ByBssid.AddOrSetValue(AP.BSSID, AP);
  end;

  FSnapshots.Add(Scan);
  while FSnapshots.Count > FMaxSnapshots do
    FSnapshots.Delete(0);
end;

function THistoryService.SeriesFor(const ABssid: string): TArray<TRssiSample>;
var
  Series: TList<TRssiSample>;
begin
  if FSeries.TryGetValue(ABssid, Series) then
    Result := Series.ToArray
  else
    SetLength(Result, 0);
end;

function THistoryService.TrendFor(const ABssid: string; ASamples: Integer): Double;
var
  S: TArray<TRssiSample>;
  N, Half, I: Integer;
  OldSum, NewSum: Double;
begin
  Result := 0;
  S := SeriesFor(ABssid);
  N := Length(S);
  if N < 4 then
    Exit;
  if (ASamples > 0) and (N > ASamples) then
  begin
    // Restrict to the most recent ASamples readings.
    S := System.Copy(S, N - ASamples, ASamples);
    N := ASamples;
  end;
  Half := N div 2;
  OldSum := 0;
  NewSum := 0;
  for I := 0 to Half - 1 do
    OldSum := OldSum + S[I].RSSI;
  for I := N - Half to N - 1 do
    NewSum := NewSum + S[I].RSSI;
  Result := (NewSum / Half) - (OldSum / Half);
end;

function THistoryService.KnownNetworks: TArray<TAccessPoint>;
var
  AP: TAccessPoint;
  I: Integer;
begin
  SetLength(Result, FLatest.Count);
  I := 0;
  for AP in FLatest.Values do
  begin
    Result[I] := AP;
    Inc(I);
  end;
  TArray.Sort<TAccessPoint>(Result, TComparer<TAccessPoint>.Construct(
    function(const L, R: TAccessPoint): Integer
    begin
      Result := R.RSSI - L.RSSI; // strongest first
      if Result = 0 then
        Result := CompareText(L.SSID, R.SSID);
    end));
end;

function THistoryService.SnapshotCount: Integer;
begin
  Result := FSnapshots.Count;
end;

function THistoryService.SnapshotTime(AIndex: Integer): TDateTime;
begin
  if (AIndex >= 0) and (AIndex < FSnapshots.Count) then
    Result := FSnapshots[AIndex].Time
  else
    Result := 0;
end;

function THistoryService.Compare(AOlder, ANewer: Integer): TArray<TComparisonRow>;
var
  OldScan, NewScan: TStoredScan;
  Keys: TDictionary<string, Boolean>;
  Key: string;
  OldAP, NewAP: TAccessPoint;
  InOld, InNew: Boolean;
  Row: TComparisonRow;
  List: TList<TComparisonRow>;
begin
  SetLength(Result, 0);
  if (AOlder < 0) or (AOlder >= FSnapshots.Count) or
     (ANewer < 0) or (ANewer >= FSnapshots.Count) then
    Exit;

  OldScan := FSnapshots[AOlder];
  NewScan := FSnapshots[ANewer];

  // Union of BSSIDs across both snapshots.
  Keys := TDictionary<string, Boolean>.Create;
  List := TList<TComparisonRow>.Create;
  try
    for Key in OldScan.ByBssid.Keys do
      Keys.AddOrSetValue(Key, True);
    for Key in NewScan.ByBssid.Keys do
      Keys.AddOrSetValue(Key, True);

    for Key in Keys.Keys do
    begin
      InOld := OldScan.ByBssid.TryGetValue(Key, OldAP);
      InNew := NewScan.ByBssid.TryGetValue(Key, NewAP);
      Row := Default(TComparisonRow);
      Row.BSSID := Key;
      if InNew then
        Row.SSID := NewAP.SSID
      else
        Row.SSID := OldAP.SSID;

      if InOld and InNew then
      begin
        Row.OldRSSI := OldAP.RSSI;
        Row.NewRSSI := NewAP.RSSI;
        if OldAP.RSSI = NewAP.RSSI then
          Row.Status := csSame
        else
          Row.Status := csChanged;
      end
      else if InNew then
      begin
        Row.Status := csAdded;
        Row.NewRSSI := NewAP.RSSI;
      end
      else
      begin
        Row.Status := csRemoved;
        Row.OldRSSI := OldAP.RSSI;
      end;
      List.Add(Row);
    end;

    // Order: added, removed, changed, same; then by SSID.
    List.Sort(TComparer<TComparisonRow>.Construct(
      function(const L, R: TComparisonRow): Integer
      begin
        Result := Ord(L.Status) - Ord(R.Status);
        if Result = 0 then
          Result := CompareText(L.SSID, R.SSID);
      end));
    Result := List.ToArray;
  finally
    List.Free;
    Keys.Free;
  end;
end;

end.
