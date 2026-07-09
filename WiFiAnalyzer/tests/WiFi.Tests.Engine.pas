unit WiFi.Tests.Engine;

{
  WiFi.Tests.Engine

  DUnitX tests for the pure engine layer (channel maths + RF analysis) and the
  fake WLAN client. These run without a radio and are the primary automated
  gate for the analysis logic. Run on Windows with the DUnitX test project.
}

interface

uses
  DUnitX.TestFramework, Vcl.Graphics,
  WiFi.Models, WiFi.Engine.Channels, WiFi.Engine.Analysis, WiFi.Api.Wlan,
  WiFi.Services.History, WiFi.Services.Export, WiFi.Services.Theme,
  WiFi.ViewModels.Main;

type
  [TestFixture]
  TChannelTests = class
  public
    [Test]
    [TestCase('ch1',  '2412,1')]
    [TestCase('ch6',  '2437,6')]
    [TestCase('ch11', '2462,11')]
    [TestCase('ch14', '2484,14')]
    procedure FrequencyToChannel_24GHz(AFreq, AChannel: Integer);

    [Test]
    procedure ChannelToFrequency_RoundTrips;

    [Test]
    procedure Band_Classification;

    [Test]
    procedure Spans_Overlap_WhenAdjacentWide;

    [Test]
    procedure Spans_DoNotOverlap_WhenSeparated;
  end;

  [TestFixture]
  TAnalysisTests = class
  private
    function MakeAP(const ABssid: string; AChannel: Integer; ABand: TWiFiBand;
      ARssi: Integer): TAccessPoint;
    function MakeSnapshot(const APs: array of TAccessPoint): TScanSnapshot;
  public
    [Test]
    procedure EmptySnapshot_YieldsEmptyReport;

    [Test]
    procedure Recommends_LeastCongested_24GHz;

    [Test]
    procedure Counts_APsPerChannel;

    [Test]
    procedure CoChannel_And_Adjacent_Counted;

    [Test]
    procedure FakeClient_ReturnsSeededData;
  end;

  [TestFixture]
  THistoryTests = class
  private
    function MakeAP(const ABssid: string; ARssi: Integer): TAccessPoint;
    function MakeSnapshot(const APs: array of TAccessPoint): TScanSnapshot;
  public
    [Test]
    procedure Series_AppendsAndCapsToCapacity;

    [Test]
    procedure Compare_DetectsAddedRemovedChanged;

    [Test]
    procedure Trend_DetectsImprovingSignal;
  end;

  [TestFixture]
  TThemeTests = class
  public
    [Test]
    procedure DarkAndLight_DifferInBackground;
  end;

  [TestFixture]
  TExportTests = class
  public
    [Test]
    procedure CsvField_QuotesWhenNeeded;

    [Test]
    [TestCase('A',  '0,A')]
    [TestCase('Z',  '25,Z')]
    [TestCase('AA', '26,AA')]
    procedure ColRef_Letters(AIndex: Integer; const AExpected: string);
  end;

  [TestFixture]
  TViewModelTests = class
  private
    function MakeAP(const ABssid: string; AChannel: Integer; ABand: TWiFiBand;
      ARssi: Integer): TAccessPoint;
    function MakeSnapshot(const APs: array of TAccessPoint): TScanSnapshot;
  public
    [Test]
    procedure Grouping_InsertsBandHeaders;

    [Test]
    procedure MultiSort_OrdersByPrimaryKey;
  end;

implementation

uses
  System.SysUtils;

{ TChannelTests }

procedure TChannelTests.FrequencyToChannel_24GHz(AFreq, AChannel: Integer);
begin
  Assert.AreEqual(AChannel, FrequencyToChannel(AFreq));
end;

procedure TChannelTests.ChannelToFrequency_RoundTrips;
begin
  Assert.AreEqual(2437, ChannelToFrequency(6, wb24GHz), '2.4GHz ch6');
  Assert.AreEqual(5180, ChannelToFrequency(36, wb5GHz), '5GHz ch36');
  Assert.AreEqual(5955, ChannelToFrequency(1, wb6GHz), '6GHz ch1');
  // Round-trip 5 GHz channel 36.
  Assert.AreEqual(36, FrequencyToChannel(5180), '5GHz back to ch36');
end;

procedure TChannelTests.Band_Classification;
begin
  Assert.AreEqual(Ord(wb24GHz), Ord(BandOfFrequency(2412)));
  Assert.AreEqual(Ord(wb5GHz), Ord(BandOfFrequency(5180)));
  Assert.AreEqual(Ord(wb6GHz), Ord(BandOfFrequency(5955)));
  Assert.AreEqual(Ord(wbUnknown), Ord(BandOfFrequency(1000)));
end;

procedure TChannelTests.Spans_Overlap_WhenAdjacentWide;
var
  A, B: TFreqRange;
begin
  // 2.4 GHz ch1 (2412) and ch3 (2422) at 20 MHz overlap.
  A := ChannelSpan(2412, cw20);
  B := ChannelSpan(2422, cw20);
  Assert.IsTrue(A.Overlaps(B), 'ch1 and ch3 should overlap at 20MHz');
end;

procedure TChannelTests.Spans_DoNotOverlap_WhenSeparated;
var
  A, B: TFreqRange;
begin
  // ch1 (2412) and ch11 (2462) at 20 MHz do not overlap.
  A := ChannelSpan(2412, cw20);
  B := ChannelSpan(2462, cw20);
  Assert.IsFalse(A.Overlaps(B), 'ch1 and ch11 should not overlap');
end;

{ TAnalysisTests }

function TAnalysisTests.MakeAP(const ABssid: string; AChannel: Integer;
  ABand: TWiFiBand; ARssi: Integer): TAccessPoint;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.SSID := 'net-' + ABssid;
  Result.BSSID := ABssid;
  Result.Vendor := '';
  Result.Channel := AChannel;
  Result.Band := ABand;
  Result.FrequencyMHz := ChannelToFrequency(AChannel, ABand);
  Result.Width := cw20;
  Result.RSSI := ARssi;
  Result.Quality := 50;
end;

function TAnalysisTests.MakeSnapshot(const APs: array of TAccessPoint): TScanSnapshot;
var
  List: TAccessPointList;
  AP: TAccessPoint;
begin
  List := TAccessPointList.Create;
  for AP in APs do
    List.Add(AP);
  Result := TScanSnapshot.Create(List, 'Test Adapter');
end;

procedure TAnalysisTests.EmptySnapshot_YieldsEmptyReport;
var
  Engine: TAnalysisEngine;
  Snap: TScanSnapshot;
  Report: TChannelReport;
begin
  Engine := TAnalysisEngine.Create;
  Snap := MakeSnapshot([]);
  try
    Report := Engine.Analyze(Snap);
    try
      Assert.AreEqual(0, Report.Stats.Count);
    finally
      Report.Free;
    end;
  finally
    Snap.Free;
    Engine.Free;
  end;
end;

procedure TAnalysisTests.Recommends_LeastCongested_24GHz;
var
  Engine: TAnalysisEngine;
  Snap: TScanSnapshot;
  Report: TChannelReport;
begin
  // Channel 1 crowded (3 strong APs), 6 has one, 11 empty -> expect 11.
  Engine := TAnalysisEngine.Create;
  Snap := MakeSnapshot([
    MakeAP('AA:00:00:00:00:01', 1, wb24GHz, -45),
    MakeAP('AA:00:00:00:00:02', 1, wb24GHz, -50),
    MakeAP('AA:00:00:00:00:03', 1, wb24GHz, -55),
    MakeAP('AA:00:00:00:00:04', 6, wb24GHz, -70)]);
  try
    Report := Engine.Analyze(Snap);
    try
      Assert.AreEqual(11, Report.Recommended24,
        'channel 11 is empty and should be recommended');
    finally
      Report.Free;
    end;
  finally
    Snap.Free;
    Engine.Free;
  end;
end;

procedure TAnalysisTests.Counts_APsPerChannel;
var
  Engine: TAnalysisEngine;
  Snap: TScanSnapshot;
  Report: TChannelReport;
  S: TChannelStat;
  Ch1Count: Integer;
begin
  Engine := TAnalysisEngine.Create;
  Snap := MakeSnapshot([
    MakeAP('AA:00:00:00:00:01', 1, wb24GHz, -45),
    MakeAP('AA:00:00:00:00:02', 1, wb24GHz, -50),
    MakeAP('AA:00:00:00:00:04', 6, wb24GHz, -70)]);
  try
    Report := Engine.Analyze(Snap);
    try
      Ch1Count := 0;
      for S in Report.Stats do
        if (S.Band = wb24GHz) and (S.Channel = 1) then
          Ch1Count := S.ApCount;
      Assert.AreEqual(2, Ch1Count, 'two APs on channel 1');
    finally
      Report.Free;
    end;
  finally
    Snap.Free;
    Engine.Free;
  end;
end;

procedure TAnalysisTests.CoChannel_And_Adjacent_Counted;
var
  Engine: TAnalysisEngine;
  Snap: TScanSnapshot;
  Report: TChannelReport;
  S: TChannelStat;
  Co, Adj: Integer;
begin
  // Two APs on channel 1, one on channel 3 (overlaps channel 1 at 20 MHz).
  Engine := TAnalysisEngine.Create;
  Snap := MakeSnapshot([
    MakeAP('AA:00:00:00:00:01', 1, wb24GHz, -45),
    MakeAP('AA:00:00:00:00:02', 1, wb24GHz, -50),
    MakeAP('AA:00:00:00:00:03', 3, wb24GHz, -55)]);
  try
    Report := Engine.Analyze(Snap);
    try
      Co := -1; Adj := -1;
      for S in Report.Stats do
        if (S.Band = wb24GHz) and (S.Channel = 1) then
        begin
          Co := S.CoChannelCount;
          Adj := S.AdjacentCount;
        end;
      Assert.AreEqual(2, Co, 'channel 1 has two co-channel APs');
      Assert.AreEqual(1, Adj, 'channel 3 AP is adjacent to channel 1');
    finally
      Report.Free;
    end;
  finally
    Snap.Free;
    Engine.Free;
  end;
end;

procedure TAnalysisTests.FakeClient_ReturnsSeededData;
var
  Seed: TAccessPointList;
  Client: IWlanClient;
  Fake: TFakeWlanClient;
  Got: TAccessPointList;
begin
  Seed := TAccessPointList.Create;
  Seed.Add(MakeAP('BB:00:00:00:00:01', 36, wb5GHz, -40));
  Fake := TFakeWlanClient.Create(Seed); // takes ownership of Seed
  Client := Fake;
  Client.Open;
  Got := Client.GetAccessPoints(TGUID.Empty);
  try
    Assert.AreEqual(1, Got.Count);
    Assert.AreEqual('BB:00:00:00:00:01', Got[0].BSSID);
  finally
    Got.Free;
  end;
end;

{ THistoryTests }

function THistoryTests.MakeAP(const ABssid: string; ARssi: Integer): TAccessPoint;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.SSID := 'net-' + ABssid;
  Result.BSSID := ABssid;
  Result.Vendor := '';
  Result.Channel := 6;
  Result.Band := wb24GHz;
  Result.FrequencyMHz := 2437;
  Result.Width := cw20;
  Result.RSSI := ARssi;
end;

function THistoryTests.MakeSnapshot(const APs: array of TAccessPoint): TScanSnapshot;
var
  List: TAccessPointList;
  AP: TAccessPoint;
begin
  List := TAccessPointList.Create;
  for AP in APs do
    List.Add(AP);
  Result := TScanSnapshot.Create(List, 'Test Adapter');
end;

procedure THistoryTests.Series_AppendsAndCapsToCapacity;
var
  Hist: THistoryService;
  I: Integer;
  Snap: TScanSnapshot;
  Series: TArray<TRssiSample>;
begin
  Hist := THistoryService.Create(3 {capacity}, 10);
  try
    for I := 1 to 5 do
    begin
      Snap := MakeSnapshot([MakeAP('AA:00:00:00:00:01', -40 - I)]);
      try
        Hist.RecordSnapshot(Snap);
      finally
        Snap.Free;
      end;
    end;
    Series := Hist.SeriesFor('AA:00:00:00:00:01');
    Assert.AreEqual(3, Length(Series), 'series capped to capacity');
    Assert.AreEqual(-45, Series[High(Series)].RSSI, 'newest sample retained');
  finally
    Hist.Free;
  end;
end;

procedure THistoryTests.Compare_DetectsAddedRemovedChanged;
var
  Hist: THistoryService;
  SnapA, SnapB: TScanSnapshot;
  Rows: TArray<TComparisonRow>;
  Row: TComparisonRow;
  FoundAdded, FoundRemoved, FoundChanged: Boolean;
begin
  Hist := THistoryService.Create(50, 10);
  try
    // A: keep + drop.   B: keep(changed rssi) + add.
    SnapA := MakeSnapshot([
      MakeAP('AA:00:00:00:00:01', -50),
      MakeAP('AA:00:00:00:00:02', -60)]);
    SnapB := MakeSnapshot([
      MakeAP('AA:00:00:00:00:01', -55),
      MakeAP('AA:00:00:00:00:03', -70)]);
    try
      Hist.RecordSnapshot(SnapA);
      Hist.RecordSnapshot(SnapB);
    finally
      SnapA.Free;
      SnapB.Free;
    end;

    Rows := Hist.Compare(0, 1);
    FoundAdded := False; FoundRemoved := False; FoundChanged := False;
    for Row in Rows do
    begin
      if (Row.BSSID = 'AA:00:00:00:00:03') and (Row.Status = csAdded) then
        FoundAdded := True;
      if (Row.BSSID = 'AA:00:00:00:00:02') and (Row.Status = csRemoved) then
        FoundRemoved := True;
      if (Row.BSSID = 'AA:00:00:00:00:01') and (Row.Status = csChanged) then
        FoundChanged := True;
    end;
    Assert.IsTrue(FoundAdded, 'network 03 added');
    Assert.IsTrue(FoundRemoved, 'network 02 removed');
    Assert.IsTrue(FoundChanged, 'network 01 changed RSSI');
  finally
    Hist.Free;
  end;
end;

procedure THistoryTests.Trend_DetectsImprovingSignal;
var
  Hist: THistoryService;
  I: Integer;
  Snap: TScanSnapshot;
begin
  Hist := THistoryService.Create;
  try
    // Rising RSSI (less negative) over 8 scans -> improving trend (> 0).
    for I := 0 to 7 do
    begin
      Snap := MakeSnapshot([MakeAP('AA:00:00:00:00:01', -80 + I * 2)]);
      try
        Hist.RecordSnapshot(Snap);
      finally
        Snap.Free;
      end;
    end;
    Assert.IsTrue(Hist.TrendFor('AA:00:00:00:00:01') > 0, 'rising signal trends positive');
  finally
    Hist.Free;
  end;
end;

{ TThemeTests }

procedure TThemeTests.DarkAndLight_DifferInBackground;
var
  Light, Dark: TColor;
begin
  Theme.Dark := False;
  Light := Theme.Color(trBackground);
  Theme.Dark := True;
  Dark := Theme.Color(trBackground);
  Theme.Dark := False; // restore
  Assert.AreNotEqual(Integer(Light), Integer(Dark), 'themes use distinct backgrounds');
end;

{ TExportTests }

procedure TExportTests.CsvField_QuotesWhenNeeded;
begin
  Assert.AreEqual('plain', TExportService.CsvField('plain'));
  Assert.AreEqual('"a,b"', TExportService.CsvField('a,b'));
  Assert.AreEqual('"he said ""hi"""', TExportService.CsvField('he said "hi"'));
end;

procedure TExportTests.ColRef_Letters(AIndex: Integer; const AExpected: string);
begin
  Assert.AreEqual(AExpected, TExportService.ColRef(AIndex));
end;

{ TViewModelTests }

function TViewModelTests.MakeAP(const ABssid: string; AChannel: Integer;
  ABand: TWiFiBand; ARssi: Integer): TAccessPoint;
begin
  Result := Default(TAccessPoint);
  Result.SSID := 'net-' + ABssid;
  Result.BSSID := ABssid;
  Result.Channel := AChannel;
  Result.Band := ABand;
  Result.FrequencyMHz := ChannelToFrequency(AChannel, ABand);
  Result.Width := cw20;
  Result.RSSI := ARssi;
end;

function TViewModelTests.MakeSnapshot(const APs: array of TAccessPoint): TScanSnapshot;
var
  List: TAccessPointList;
  AP: TAccessPoint;
begin
  List := TAccessPointList.Create;
  for AP in APs do
    List.Add(AP);
  Result := TScanSnapshot.Create(List, 'Test Adapter');
end;

procedure TViewModelTests.Grouping_InsertsBandHeaders;
var
  VM: TMainViewModel;
  Snap: TScanSnapshot;
  I, Groups, DataRows: Integer;
begin
  VM := TMainViewModel.Create;
  try
    Snap := MakeSnapshot([
      MakeAP('AA:00:00:00:00:01', 1, wb24GHz, -40),
      MakeAP('AA:00:00:00:00:02', 6, wb24GHz, -50),
      MakeAP('AA:00:00:00:00:03', 36, wb5GHz, -60)]);
    try
      VM.UpdateFromSnapshot(Snap);
    finally
      Snap.Free;
    end;

    VM.GroupField := gfBand;
    Groups := 0; DataRows := 0;
    for I := 0 to VM.VisibleCount - 1 do
      if VM.RowKind(I) = drGroup then
        Inc(Groups)
      else
        Inc(DataRows);

    Assert.AreEqual(2, Groups, 'one header per band');
    Assert.AreEqual(3, DataRows, 'all data rows present');
    Assert.AreEqual(3, Length(VM.VisibleDataRows), 'export sees only data rows');
  finally
    VM.Free;
  end;
end;

procedure TViewModelTests.MultiSort_OrdersByPrimaryKey;
var
  VM: TMainViewModel;
  Snap: TScanSnapshot;
  Data: TArray<TAccessPoint>;
begin
  VM := TMainViewModel.Create;
  try
    Snap := MakeSnapshot([
      MakeAP('AA:00:00:00:00:01', 11, wb24GHz, -40),
      MakeAP('AA:00:00:00:00:02', 1, wb24GHz, -50),
      MakeAP('AA:00:00:00:00:03', 6, wb24GHz, -60)]);
    try
      VM.UpdateFromSnapshot(Snap);
    finally
      Snap.Free;
    end;

    VM.SortBy(gcChannel); // ascending by channel
    Data := VM.VisibleDataRows;
    Assert.AreEqual(3, Length(Data));
    Assert.AreEqual(1, Data[0].Channel);
    Assert.AreEqual(6, Data[1].Channel);
    Assert.AreEqual(11, Data[2].Channel);
    Assert.AreEqual(1, VM.SortRank(gcChannel), 'channel is the primary key');
  finally
    VM.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TChannelTests);
  TDUnitX.RegisterTestFixture(TAnalysisTests);
  TDUnitX.RegisterTestFixture(THistoryTests);
  TDUnitX.RegisterTestFixture(TExportTests);
  TDUnitX.RegisterTestFixture(TViewModelTests);
  TDUnitX.RegisterTestFixture(TThemeTests);

end.
