unit WiFi.ViewModels.Main;

{
  WiFi.ViewModels.Main

  Presentation state for the main window. It receives scan snapshots (on the
  main thread), keeps an independent copy of the data, runs the RF analysis
  engine, and exposes filtered/sorted/grouped rows plus summary metrics for the
  grid, status bar and (later) dashboard. It holds no VCL controls, so the form
  stays free of business logic and the view-model is unit-testable on its own.

  Phase 4 adds multi-column sorting (an ordered list of sort keys) and optional
  grouping. The grid is fed a flat list of "display rows", each of which is
  either a group header or a data row, so the owner-drawn virtual grid can render
  group bands without any model state of its own.
}

interface

uses
  System.SysUtils, System.Generics.Collections,
  WiFi.Models, WiFi.Engine.Analysis, WiFi.Services.History;

type
  /// <summary>Logical grid columns; also the sort keys.</summary>
  TGridColumn = (gcSSID, gcBSSID, gcVendor, gcChannel, gcBand, gcWidth,
    gcFrequency, gcRSSI, gcQuality, gcPhy, gcSecurity, gcConnected);

  /// <summary>One column + direction in the ordered multi-sort.</summary>
  TSortKey = record
    Column: TGridColumn;
    Ascending: Boolean;
  end;

  /// <summary>Field the grid is grouped by (gfNone == flat list).</summary>
  TGroupField = (gfNone, gfBand, gfSecurity, gfVendor, gfChannel);

  TDisplayRowKind = (drData, drGroup);

  /// <summary>A row as shown in the grid: a group header or a data row.</summary>
  TDisplayRow = record
    Kind: TDisplayRowKind;
    GroupCaption: string;      // valid when Kind = drGroup
    AP: TAccessPoint;          // valid when Kind = drData
  end;

  TViewModelChangeEvent = procedure(Sender: TObject) of object;

  TMainViewModel = class
  private
    FAll: TAccessPointList;      // full copy of the latest snapshot
    FView: TAccessPointList;     // filtered + sorted data rows
    FRows: TList<TDisplayRow>;   // display rows (group headers + data)
    FEngine: TAnalysisEngine;
    FReport: TChannelReport;     // owned; may be nil before first scan
    FSnapshot: TScanSnapshot;    // owned copy used to feed the engine
    FHistory: THistoryService;   // owned; RSSI time-series + scan history
    FSearchText: string;
    FBandFilter: TWiFiBand;      // wbUnknown == all bands
    FSortKeys: TList<TSortKey>;
    FGroupField: TGroupField;
    FAdapterName: string;
    FLastScan: TDateTime;
    FOnChanged: TViewModelChangeEvent;
    procedure RebuildView;
    procedure BuildRows;
    function PassesFilter(const AAP: TAccessPoint): Boolean;
    function CompareColumn(AColumn: TGridColumn; const L, R: TAccessPoint): Integer;
    function CompareRows(const L, R: TAccessPoint): Integer;
    function GroupCompare(const L, R: TAccessPoint): Integer;
    function GroupCaptionOf(const AAP: TAccessPoint): string;
    procedure Changed;
    procedure SetSearchText(const AValue: string);
    procedure SetBandFilter(AValue: TWiFiBand);
    procedure SetGroupField(AValue: TGroupField);
  public
    constructor Create;
    destructor Destroy; override;

    /// <summary>Ingest a fresh snapshot (copies its data; does not take it).</summary>
    procedure UpdateFromSnapshot(ASnapshot: TScanSnapshot);
    /// <summary>Set/extend the sort. AAppend (Shift-click) adds a secondary key
    /// or flips it; otherwise the column becomes the sole key (or flips).</summary>
    procedure SortBy(AColumn: TGridColumn; AAppend: Boolean = False);

    // Display-row access (group headers + data rows).
    function VisibleCount: Integer;
    function RowKind(AIndex: Integer): TDisplayRowKind;
    function RowGroupCaption(AIndex: Integer): string;
    function RowData(AIndex: Integer): TAccessPoint;
    /// <summary>Alias for RowData; valid only for data rows.</summary>
    function Visible(AIndex: Integer): TAccessPoint;

    // Sort-state helpers for header rendering.
    /// <summary>1-based position of a column in the sort, or 0 if not sorted.</summary>
    function SortRank(AColumn: TGridColumn): Integer;
    function SortAscendingOf(AColumn: TGridColumn): Boolean;

    // Export helpers.
    /// <summary>Filtered + sorted data rows in display order (no group headers).</summary>
    function VisibleDataRows: TArray<TAccessPoint>;

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
    property GroupField: TGroupField read FGroupField write SetGroupField;
    property AdapterName: string read FAdapterName;
    property LastScan: TDateTime read FLastScan;
    property OnChanged: TViewModelChangeEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.Generics.Defaults, System.Math;

{ TMainViewModel }

constructor TMainViewModel.Create;
var
  Key: TSortKey;
begin
  inherited Create;
  FAll := TAccessPointList.Create;
  FView := TAccessPointList.Create;
  FRows := TList<TDisplayRow>.Create;
  FEngine := TAnalysisEngine.Create;
  FHistory := THistoryService.Create;
  FSortKeys := TList<TSortKey>.Create;
  FBandFilter := wbUnknown;
  FGroupField := gfNone;
  // Default: strongest signal first.
  Key.Column := gcRSSI;
  Key.Ascending := False;
  FSortKeys.Add(Key);
end;

destructor TMainViewModel.Destroy;
begin
  FReport.Free;
  FSnapshot.Free;
  FHistory.Free;
  FEngine.Free;
  FSortKeys.Free;
  FRows.Free;
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

procedure TMainViewModel.SetGroupField(AValue: TGroupField);
begin
  if FGroupField = AValue then
    Exit;
  FGroupField := AValue;
  RebuildView;
  Changed;
end;

procedure TMainViewModel.SortBy(AColumn: TGridColumn; AAppend: Boolean);
var
  I, Found: Integer;
  Key: TSortKey;
begin
  Found := -1;
  for I := 0 to FSortKeys.Count - 1 do
    if FSortKeys[I].Column = AColumn then
    begin
      Found := I;
      Break;
    end;

  if AAppend then
  begin
    if Found >= 0 then
    begin
      Key := FSortKeys[Found];
      Key.Ascending := not Key.Ascending;
      FSortKeys[Found] := Key;
    end
    else
    begin
      Key.Column := AColumn;
      Key.Ascending := True;
      FSortKeys.Add(Key);
    end;
  end
  else
  begin
    if (FSortKeys.Count = 1) and (Found = 0) then
    begin
      // Clicking the sole sort column flips its direction.
      Key := FSortKeys[0];
      Key.Ascending := not Key.Ascending;
      FSortKeys[0] := Key;
    end
    else
    begin
      FSortKeys.Clear;
      Key.Column := AColumn;
      Key.Ascending := True;
      FSortKeys.Add(Key);
    end;
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

function TMainViewModel.CompareColumn(AColumn: TGridColumn;
  const L, R: TAccessPoint): Integer;
begin
  case AColumn of
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
end;

function TMainViewModel.CompareRows(const L, R: TAccessPoint): Integer;
var
  I, C: Integer;
begin
  for I := 0 to FSortKeys.Count - 1 do
  begin
    C := CompareColumn(FSortKeys[I].Column, L, R);
    if not FSortKeys[I].Ascending then
      C := -C;
    if C <> 0 then
      Exit(C);
  end;
  Result := 0;
end;

function TMainViewModel.GroupCaptionOf(const AAP: TAccessPoint): string;
begin
  case FGroupField of
    gfBand:     Result := 'Band: ' + BandToStr(AAP.Band);
    gfSecurity: Result := 'Security: ' + SecurityToStr(AAP);
    gfVendor:   if AAP.Vendor = '' then Result := 'Vendor: (unknown)'
                else Result := 'Vendor: ' + AAP.Vendor;
    gfChannel:  Result := Format('Channel %d (%s)', [AAP.Channel, BandToStr(AAP.Band)]);
  else
    Result := '';
  end;
end;

function TMainViewModel.GroupCompare(const L, R: TAccessPoint): Integer;
begin
  case FGroupField of
    gfBand:     Result := Ord(L.Band) - Ord(R.Band);
    gfChannel:
      begin
        Result := Ord(L.Band) - Ord(R.Band);
        if Result = 0 then
          Result := L.Channel - R.Channel;
      end;
    gfSecurity: Result := CompareText(SecurityToStr(L), SecurityToStr(R));
    gfVendor:   Result := CompareText(L.Vendor, R.Vendor);
  else
    Result := 0;
  end;
end;

procedure TMainViewModel.RebuildView;
var
  AP: TAccessPoint;
begin
  FView.Clear;
  for AP in FAll do
    if PassesFilter(AP) then
      FView.Add(AP);

  // Multi-key sort. When grouping, the group key is the primary comparison so
  // members stay contiguous; the user's keys order rows within each group.
  FView.Sort(TComparer<TAccessPoint>.Construct(
    function(const L, R: TAccessPoint): Integer
    begin
      if FGroupField <> gfNone then
      begin
        Result := GroupCompare(L, R);
        if Result <> 0 then
          Exit;
      end;
      Result := CompareRows(L, R);
    end));

  BuildRows;
end;

procedure TMainViewModel.BuildRows;
var
  I, RunStart, J: Integer;
  Row: TDisplayRow;
  Caption: string;
begin
  FRows.Clear;
  if FGroupField = gfNone then
  begin
    for I := 0 to FView.Count - 1 do
    begin
      Row.Kind := drData;
      Row.GroupCaption := '';
      Row.AP := FView[I];
      FRows.Add(Row);
    end;
    Exit;
  end;

  // Emit a header before each contiguous run of equal group caption.
  I := 0;
  while I < FView.Count do
  begin
    Caption := GroupCaptionOf(FView[I]);
    RunStart := I;
    while (I < FView.Count) and (GroupCaptionOf(FView[I]) = Caption) do
      Inc(I);

    Row.Kind := drGroup;
    Row.GroupCaption := Format('%s  (%d)', [Caption, I - RunStart]);
    Row.AP := Default(TAccessPoint);
    FRows.Add(Row);

    for J := RunStart to I - 1 do
    begin
      Row.Kind := drData;
      Row.GroupCaption := '';
      Row.AP := FView[J];
      FRows.Add(Row);
    end;
  end;
end;

function TMainViewModel.VisibleCount: Integer;
begin
  Result := FRows.Count;
end;

function TMainViewModel.RowKind(AIndex: Integer): TDisplayRowKind;
begin
  Result := FRows[AIndex].Kind;
end;

function TMainViewModel.RowGroupCaption(AIndex: Integer): string;
begin
  Result := FRows[AIndex].GroupCaption;
end;

function TMainViewModel.RowData(AIndex: Integer): TAccessPoint;
begin
  Result := FRows[AIndex].AP;
end;

function TMainViewModel.Visible(AIndex: Integer): TAccessPoint;
begin
  Result := FRows[AIndex].AP;
end;

function TMainViewModel.SortRank(AColumn: TGridColumn): Integer;
var
  I: Integer;
begin
  for I := 0 to FSortKeys.Count - 1 do
    if FSortKeys[I].Column = AColumn then
      Exit(I + 1);
  Result := 0;
end;

function TMainViewModel.SortAscendingOf(AColumn: TGridColumn): Boolean;
var
  I: Integer;
begin
  for I := 0 to FSortKeys.Count - 1 do
    if FSortKeys[I].Column = AColumn then
      Exit(FSortKeys[I].Ascending);
  Result := True;
end;

function TMainViewModel.VisibleDataRows: TArray<TAccessPoint>;
var
  Row: TDisplayRow;
  List: TList<TAccessPoint>;
begin
  List := TList<TAccessPoint>.Create;
  try
    for Row in FRows do
      if Row.Kind = drData then
        List.Add(Row.AP);
    Result := List.ToArray;
  finally
    List.Free;
  end;
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
  Result := Default(TAccessPoint);
  Result.RSSI := -1000;
  for AP in FAll do
    if AP.RSSI > Result.RSSI then
      Result := AP;
end;

function TMainViewModel.Weakest: TAccessPoint;
var
  AP: TAccessPoint;
  First: Boolean;
begin
  Result := Default(TAccessPoint);
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
