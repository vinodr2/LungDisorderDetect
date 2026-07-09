unit WiFi.Tests.Engine;

{
  WiFi.Tests.Engine

  DUnitX tests for the pure engine layer (channel maths + RF analysis) and the
  fake WLAN client. These run without a radio and are the primary automated
  gate for the analysis logic. Run on Windows with the DUnitX test project.
}

interface

uses
  DUnitX.TestFramework,
  WiFi.Models, WiFi.Engine.Channels, WiFi.Engine.Analysis, WiFi.Api.Wlan;

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

initialization
  TDUnitX.RegisterTestFixture(TChannelTests);
  TDUnitX.RegisterTestFixture(TAnalysisTests);

end.
