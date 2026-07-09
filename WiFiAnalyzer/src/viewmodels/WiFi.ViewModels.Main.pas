unit WiFi.ViewModels.Main;

{
  WiFi.ViewModels.Main

  Presentation state for the main window. It receives scan snapshots (on the
  main thread), keeps an independent copy of the data, runs the RF analysis
  engine, and exposes filtered/sorted rows plus summary metrics for the grid,
  status bar and (later) dashboard. It holds no VCL controls, so the form stays
  free of business logic and the view-model is unit-testable on its own.
}

interface

uses
  System.SysUtils, System.Generics.Collections,
  WiFi.Models, WiFi.Engine.Analysis, WiFi.Services.History;

type
  /// <summary>Logical grid columns; also the sort keys.</summary>
  TGridColumn = (gcSSID, gcBSSID, gcVendor, gcChannel, gcBand, gcWidth,
    gcFrequency, gcRSSI, gcQuality, gcPhy, gcSecurity, gcConnected);

  TViewModelChangeEvent = procedure(Sender: TObject) of object;

  TMainViewModel = class
  private
    FAll: TAccessPointList;      // full copy of the latest snapshot
    FView: TAccessPointList;     // filtered + sorted, rebuilt on demand
    FEngine: TAnalysisEngine;
    FReport: TChannelReport;     // owned; may be nil before first scan
    FSnapshot: TScanSnapshot;    // owned copy used to feed the engine
    FHistory: THistoryService;   // owned; RSSI time-series + scan history
    FSearchText: string;
    FBandFilter: TWiFiBand;      // wbUnknown == all bands
    FSortColumn: TGridColumn;
    FSortAscending: Boolean;
    FAdapterName: string;
    FLastScan: TDateTime;
    FOnChanged: TViewModelChangeEvent;
    procedure RebuildView;
    function PassesFilter(const AAP: TAccessPoint): Boolean;
    function CompareRows(const L, R: TAccessPoint): Integer;
    procedure Changed;
    procedure SetSearchText(const AValue: string);
    procedure SetBandFilter(AValue: TWiFiBand);
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Ingest a fresh snapshot (copies its data; does not take it).</summary>
    procedure UpdateFromSnapshot(ASnapshot: TScanSnapshot);
    /// <summary>Toggle/set the sort column; clicking the same column flips order.</summary>
    procedure SortBy(AColumn: TGridColumn);

    // Grid data access (filtered + sorted view).
    function VisibleCount: Integer;
    function Visible(AIndex: Integer): TAccessPoint;

    // Summary metrics (computed from the full set).
    function TotalNetworks: Integer;
    function TryGetConnected(out AAP: TAccessPoint): Boolean;
    function Strongest: TAccessPoint;
    function Weakest: TAccessPoint;
    function BandCount(ABand: TWiFiBand): Integer;
    function SecuredCount: Integer;
    function OpenCount: Integer;
    /// <summary>A copy of every detected network (all bands, unfiltered).</summary>
    function AllNetworks: TArray<TAccessPoint>;

    property Report: TChannelReport read FReport;
    /// <summary>Shared RSSI/scan history (owned by the view-model).</summary>
    property History: THistoryService read FHistory;
    property SearchText: string read FSearchText write SetSearchText;
    property BandFilter: TWiFiBand read FBandFilter write SetBandFilter;
    property SortColumn: TGridColumn read FSortColumn;
    property SortAscending: Boolean read FSortAscending;
    property AdapterName: string read FAdapterName;
    property LastScan: TDateTime read FLastScan;
    property OnChanged: TViewModelChangeEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.Generics.Defaults, System.Math;

{ TMainViewModel }

constructor TMainViewModel.Create;
begin
  inherited Create;
  FAll := TAccessPointList.Create;
  FView := TAccessPointList.Create;
  FEngine := TAnalysisEngine.Create;
  FHistory := THistoryService.Create;
  FBandFilter := wbUnknown;
  FSortColumn := gcRSSI;
  FSortAscending := False; // strongest first by default
end;

destructor TMainViewModel.Destroy;
begin
  FReport.Free;
  FSnapshot.Free;
  FHistory.Free;
  FEngine.Free;
  FView.Free;
  FAll.Free;
  inherited;
end;

procedure TMainViewModel.Changed;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TMainViewModel.UpdateFromSnapshot(ASnapshot: TScanSnapshot);
var
  AP: TAccessPoint;
  Copy: TAccessPointList;
begin
  if ASnapshot = nil then
    Exit;

  FAll.Clear;
  for AP in ASnapshot.Items do
    FAll.Add(AP);
  FAdapterName := ASnapshot.AdapterName;
  FLastScan := ASnapshot.Timestamp;

  // Build an independent snapshot to feed the engine (engine reads Items only).
  Copy := TAccessPointList.Create;
  for AP in FAll do
    Copy.Add(AP);
  FSnapshot.Free;
  FSnapshot := TScanSnapshot.Create(Copy, FAdapterName);

  FReport.Free;
  FReport := FEngine.Analyze(FSnapshot);

  // Extend the RSSI time-series and store this scan for comparison.
  FHistory.RecordSnapshot(FSnapshot);

  RebuildView;
  Changed;
end;

procedure TMainViewModel.SetSearchText(const AValue: string);
begin
  if FSearchText = AValue then
    Exit;
  FSearchText := AValue;
  RebuildView;
  Changed;
end;

procedure TMainViewModel.SetBandFilter(AValue: TWiFiBand);
begin
  if FBandFilter = AValue then
    Exit;
  FBandFilter := AValue;
  RebuildView;
  Changed;
end;

procedure TMainViewModel.SortBy(AColumn: TGridColumn);
begin
  if FSortColumn = AColumn then
    FSortAscending := not FSortAscending
  else
  begin
    FSortColumn := AColumn;
    FSortAscending := True;
  end;
  RebuildView;
  Changed;
end;

function TMainViewModel.PassesFilter(const AAP: TAccessPoint): Boolean;
var
  Q: string;
begin
  if (FBandFilter <> wbUnknown) and (AAP.Band <> FBandFilter) then
    Exit(False);
  if FSearchText = '' then
    Exit(True);
  Q := FSearchText.ToLower;
  Result := AAP.SSID.ToLower.Contains(Q) or
            AAP.BSSID.ToLower.Contains(Q) or
            AAP.Vendor.ToLower.Contains(Q);
end;

function TMainViewModel.CompareRows(const L, R: TAccessPoint): Integer;
begin
  case FSortColumn of
    gcSSID:      Result := CompareText(L.SSID, R.SSID);
    gcBSSID:     Result := CompareText(L.BSSID, R.BSSID);
    gcVendor:    Result := CompareText(L.Vendor, R.Vendor);
    gcChannel:   Result := L.Channel - R.Channel;
    gcBand:      Result := Ord(L.Band) - Ord(R.Band);
    gcWidth:     Result := Ord(L.Width) - Ord(R.Width);
    gcFrequency: Result := L.FrequencyMHz - R.FrequencyMHz;
    gcRSSI:      Result := L.RSSI - R.RSSI;
    gcQuality:   Result := L.Quality - R.Quality;
    gcPhy:       Result := Ord(L.Phy) - Ord(R.Phy);
    gcSecurity:  Result := CompareText(SecurityToStr(L), SecurityToStr(R));
    gcConnected: Result := Ord(L.Connected) - Ord(R.Connected);
  else
    Result := 0;
  end;
  if not FSortAscending then
    Result := -Result;
end;

procedure TMainViewModel.RebuildView;
var
  AP: TAccessPoint;
begin
  FView.Clear;
  for AP in FAll do
    if PassesFilter(AP) then
      FView.Add(AP);
  FView.Sort(TComparer<TAccessPoint>.Construct(
    function(const L, R: TAccessPoint): Integer
    begin
      Result := CompareRows(L, R);
    end));
end;

function TMainViewModel.VisibleCount: Integer;
begin
  Result := FView.Count;
end;

function TMainViewModel.Visible(AIndex: Integer): TAccessPoint;
begin
  Result := FView[AIndex];
end;

function TMainViewModel.TotalNetworks: Integer;
begin
  Result := FAll.Count;
end;

function TMainViewModel.TryGetConnected(out AAP: TAccessPoint): Boolean;
var
  AP: TAccessPoint;
begin
  for AP in FAll do
    if AP.Connected then
    begin
      AAP := AP;
      Exit(True);
    end;
  Result := False;
end;

function TMainViewModel.Strongest: TAccessPoint;
var
  AP: TAccessPoint;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.RSSI := -1000;
  Result.SSID := '';
  Result.BSSID := '';
  Result.Vendor := '';
  for AP in FAll do
    if AP.RSSI > Result.RSSI then
      Result := AP;
end;

function TMainViewModel.Weakest: TAccessPoint;
var
  AP: TAccessPoint;
  First: Boolean;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.SSID := '';
  Result.BSSID := '';
  Result.Vendor := '';
  First := True;
  for AP in FAll do
    if First or (AP.RSSI < Result.RSSI) then
    begin
      Result := AP;
      First := False;
    end;
end;

function TMainViewModel.BandCount(ABand: TWiFiBand): Integer;
var
  AP: TAccessPoint;
begin
  Result := 0;
  for AP in FAll do
    if AP.Band = ABand then
      Inc(Result);
end;

function TMainViewModel.SecuredCount: Integer;
var
  AP: TAccessPoint;
begin
  Result := 0;
  for AP in FAll do
    if AP.SecurityEnabled then
      Inc(Result);
end;

function TMainViewModel.OpenCount: Integer;
begin
  Result := FAll.Count - SecuredCount;
end;

function TMainViewModel.AllNetworks: TArray<TAccessPoint>;
var
  I: Integer;
begin
  SetLength(Result, FAll.Count);
  for I := 0 to FAll.Count - 1 do
    Result[I] := FAll[I];
end;

end.
