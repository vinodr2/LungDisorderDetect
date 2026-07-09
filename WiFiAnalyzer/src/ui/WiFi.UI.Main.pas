unit WiFi.UI.Main;

{
  WiFi.UI.Main

  The main window. It is a thin view over TMainViewModel: it wires user input
  to the view-model, owns the scanner service, and renders the current view
  when the view-model reports a change. No RF or WLAN logic lives here.

  The network list uses an owner-drawn TDrawGrid in "virtual" fashion - it
  pulls each cell's text straight from the view-model on demand, so it stays
  responsive with hundreds of rows and never copies the whole model into
  control state.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.UITypes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.Grids, Vcl.ComCtrls, Vcl.Themes, Vcl.Styles,
  WiFi.Models, WiFi.Util.Format,
  WiFi.ViewModels.Main, WiFi.Services.Scanner, WiFi.Services.Oui,
  WiFi.Api.Wlan, WiFi.Util.Config, WiFi.UI.ChannelsFrame;

type
  TfrmMain = class(TForm)
    pnlTop: TPanel;
    lblSearch: TLabel;
    edtSearch: TEdit;
    lblBand: TLabel;
    cboBand: TComboBox;
    lblInterval: TLabel;
    cboInterval: TComboBox;
    btnRefresh: TButton;
    chkDark: TCheckBox;
    pgcMain: TPageControl;
    tsNetworks: TTabSheet;
    tsChannels: TTabSheet;
    grdNetworks: TDrawGrid;
    sbMain: TStatusBar;
    tmrUi: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure edtSearchChange(Sender: TObject);
    procedure cboBandChange(Sender: TObject);
    procedure cboIntervalChange(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure chkDarkClick(Sender: TObject);
    procedure grdNetworksDrawCell(Sender: TObject; ACol, ARow: Integer;
      Rect: TRect; State: TGridDrawState);
    procedure grdNetworksMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure tmrUiTimer(Sender: TObject);
  private
    FConfig: TAppConfig;
    FOui: IOuiVendorService;
    FScanner: TScannerService;
    FVM: TMainViewModel;
    FChannels: TframeChannels;
    procedure BuildColumns;
    procedure ConfigureIntervalCombo;
    function CellText(const AAP: TAccessPoint; ACol: Integer): string;
    procedure DrawHeaderCell(ACol: Integer; const Rect: TRect);
    procedure DrawDataCell(ACol, ARow: Integer; const Rect: TRect;
      Selected: Boolean);
    procedure ViewModelChanged(Sender: TObject);
    procedure ScannerSnapshot(Sender: TObject; ASnapshot: TScanSnapshot);
    procedure ScannerError(Sender: TObject; const AMessage: string);
    procedure ApplyTheme(ADark: Boolean);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

uses
  System.IOUtils, System.Math, System.DateUtils,
  WiFi.Services.Logger;

type
  TColumnDef = record
    Title: string;
    Width: Integer;
    Column: TGridColumn;
  end;

const
  COLUMNS: array[0..11] of TColumnDef = (
    (Title: 'SSID';       Width: 180; Column: gcSSID),
    (Title: 'BSSID';      Width: 130; Column: gcBSSID),
    (Title: 'Vendor';     Width: 130; Column: gcVendor),
    (Title: 'Ch';         Width: 44;  Column: gcChannel),
    (Title: 'Band';       Width: 64;  Column: gcBand),
    (Title: 'Width';      Width: 64;  Column: gcWidth),
    (Title: 'Freq';       Width: 64;  Column: gcFrequency),
    (Title: 'RSSI';       Width: 120; Column: gcRSSI),
    (Title: 'Quality';    Width: 60;  Column: gcQuality),
    (Title: 'PHY';        Width: 80;  Column: gcPhy),
    (Title: 'Security';   Width: 150; Column: gcSecurity),
    (Title: 'Conn';       Width: 48;  Column: gcConnected));

  CELL_PAD = 4;

{ signal grade -> fill colour }
function GradeColor(AGrade: TSignalGrade): TColor;
begin
  case AGrade of
    sgExcellent: Result := $004CAF50; // green
    sgGood:      Result := $008BC34A;
    sgFair:      Result := $0000C4FF; // amber-ish
    sgWeak:      Result := $000090FF; // orange
  else
    Result := $004040F0; // red
  end;
end;

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
var
  OuiFile: string;
  OuiSvc: TOuiVendorService;
begin
  Caption := 'Wi-Fi Analyzer';
  ReportMemoryLeaksOnShutdown := {$IFDEF DEBUG} True {$ELSE} False {$ENDIF};

  FConfig := TAppConfig.Create;
  FConfig.Load;

  // Load bundled OUI database (best effort); keep the interface for lifetime.
  OuiSvc := TOuiVendorService.Create;
  OuiFile := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'oui.txt');
  OuiSvc.LoadFromFile(OuiFile);
  FOui := OuiSvc;

  FVM := TMainViewModel.Create;
  FVM.OnChanged := ViewModelChanged;

  ConfigureIntervalCombo;
  cboBand.ItemIndex := 0;

  BuildColumns;

  FScanner := TScannerService.Create(TWlanClient.Create, FOui);
  FScanner.IntervalMs := FConfig.ScanIntervalMs;
  FScanner.OnSnapshot := ScannerSnapshot;
  FScanner.OnError := ScannerError;

  // Channel Analysis tab (Phase 2): a custom-drawn spectrum + heatmap frame.
  FChannels := TframeChannels.Create(Self);
  FChannels.Parent := tsChannels;
  FChannels.Align := alClient;

  chkDark.Checked := FConfig.DarkMode;
  ApplyTheme(FConfig.DarkMode);

  FScanner.Start;
  sbMain.SimpleText := 'Scanning...';
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  if FScanner <> nil then
    FScanner.Stop;
  if FConfig <> nil then
  begin
    FConfig.DarkMode := chkDark.Checked;
    FConfig.Save;
  end;
  FScanner.Free;
  FVM.Free;
  FConfig.Free;
  FOui := nil;
end;

procedure TfrmMain.ConfigureIntervalCombo;
begin
  cboInterval.Items.Clear;
  cboInterval.Items.AddObject('1 s', TObject(1000));
  cboInterval.Items.AddObject('2 s', TObject(2000));
  cboInterval.Items.AddObject('5 s', TObject(5000));
  cboInterval.Items.AddObject('10 s', TObject(10000));
  cboInterval.Items.AddObject('30 s', TObject(30000));
  case FConfig.ScanIntervalMs of
    1000:  cboInterval.ItemIndex := 0;
    2000:  cboInterval.ItemIndex := 1;
    10000: cboInterval.ItemIndex := 3;
    30000: cboInterval.ItemIndex := 4;
  else
    cboInterval.ItemIndex := 2;
  end;
end;

procedure TfrmMain.BuildColumns;
var
  I: Integer;
begin
  grdNetworks.ColCount := Length(COLUMNS);
  grdNetworks.FixedRows := 1;
  grdNetworks.FixedCols := 0;
  grdNetworks.RowCount := 2; // header + one placeholder until data arrives
  grdNetworks.DefaultRowHeight := 22;
  grdNetworks.Options := grdNetworks.Options + [goColSizing, goRowSelect,
    goVertLine, goHorzLine, goThumbTracking] - [goRangeSelect];
  for I := 0 to High(COLUMNS) do
    grdNetworks.ColWidths[I] := COLUMNS[I].Width;
end;

function TfrmMain.CellText(const AAP: TAccessPoint; ACol: Integer): string;
begin
  case COLUMNS[ACol].Column of
    gcSSID:      if AAP.Hidden then Result := '<hidden>' else Result := AAP.SSID;
    gcBSSID:     Result := AAP.BSSID;
    gcVendor:    Result := AAP.Vendor;
    gcChannel:   Result := IntToStr(AAP.Channel);
    gcBand:      Result := BandToStr(AAP.Band);
    gcWidth:     Result := ChannelWidthToStr(AAP.Width);
    gcFrequency: Result := IntToStr(AAP.FrequencyMHz);
    gcRSSI:      Result := FormatRssi(AAP.RSSI);
    gcQuality:   Result := IntToStr(AAP.Quality) + '%';
    gcPhy:       Result := PhyToStr(AAP.Phy);
    gcSecurity:  Result := SecurityToStr(AAP);
    gcConnected: if AAP.Connected then Result := '●' else Result := '';
  else
    Result := '';
  end;
end;

procedure TfrmMain.DrawHeaderCell(ACol: Integer; const Rect: TRect);
var
  Cv: TCanvas;
  Txt: string;
begin
  Cv := grdNetworks.Canvas;
  Cv.Brush.Color := StyleServices.GetSystemColor(clBtnFace);
  Cv.FillRect(Rect);
  Cv.Font.Style := [fsBold];
  Cv.Font.Color := StyleServices.GetSystemColor(clWindowText);
  Txt := COLUMNS[ACol].Title;
  if FVM.SortColumn = COLUMNS[ACol].Column then
    if FVM.SortAscending then Txt := Txt + ' ▲' else Txt := Txt + ' ▼';
  Cv.TextRect(Rect, Rect.Left + CELL_PAD, Rect.Top + 3, Txt);
  Cv.Font.Style := [];
end;

procedure TfrmMain.DrawDataCell(ACol, ARow: Integer; const Rect: TRect;
  Selected: Boolean);
var
  Cv: TCanvas;
  AP: TAccessPoint;
  Index: Integer;
  Txt: string;
  BarRect: TRect;
  Grade: TSignalGrade;
  QualW: Integer;
begin
  Cv := grdNetworks.Canvas;
  Index := ARow - 1;
  if (Index < 0) or (Index >= FVM.VisibleCount) then
  begin
    Cv.Brush.Color := StyleServices.GetSystemColor(clWindow);
    Cv.FillRect(Rect);
    Exit;
  end;
  AP := FVM.Visible(Index);

  if Selected then
    Cv.Brush.Color := StyleServices.GetSystemColor(clHighlight)
  else if AP.Connected then
    Cv.Brush.Color := StyleServices.GetSystemColor(clInfoBk)
  else
    Cv.Brush.Color := StyleServices.GetSystemColor(clWindow);
  Cv.FillRect(Rect);

  if Selected then
    Cv.Font.Color := StyleServices.GetSystemColor(clHighlightText)
  else
    Cv.Font.Color := StyleServices.GetSystemColor(clWindowText);

  // RSSI column: draw a strength bar sized to quality behind the text.
  if COLUMNS[ACol].Column = gcRSSI then
  begin
    Grade := GradeOfRssi(AP.RSSI);
    QualW := Round((Rect.Width - 2 * CELL_PAD) * (RssiToQuality(AP.RSSI) / 100));
    BarRect := TRect.Create(Rect.Left + CELL_PAD, Rect.Bottom - 6,
      Rect.Left + CELL_PAD + QualW, Rect.Bottom - 2);
    if not Selected then
    begin
      Cv.Brush.Color := GradeColor(Grade);
      Cv.FillRect(BarRect);
      Cv.Brush.Style := bsClear;
    end;
  end;

  Txt := CellText(AP, ACol);
  Cv.Brush.Style := bsClear;
  Cv.TextRect(Rect, Rect.Left + CELL_PAD, Rect.Top + 3, Txt);
  Cv.Brush.Style := bsSolid;
end;

procedure TfrmMain.grdNetworksDrawCell(Sender: TObject; ACol, ARow: Integer;
  Rect: TRect; State: TGridDrawState);
begin
  if ARow = 0 then
    DrawHeaderCell(ACol, Rect)
  else
    DrawDataCell(ACol, ARow, Rect, gdSelected in State);
end;

procedure TfrmMain.grdNetworksMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  Col, Row: Integer;
begin
  grdNetworks.MouseToCell(X, Y, Col, Row);
  if (Row = 0) and (Col >= 0) and (Col <= High(COLUMNS)) then
    FVM.SortBy(COLUMNS[Col].Column);
end;

procedure TfrmMain.ViewModelChanged(Sender: TObject);
var
  Rows: Integer;
begin
  Rows := FVM.VisibleCount;
  // Keep at least the header + one row so the grid stays valid when empty.
  grdNetworks.RowCount := Max(2, Rows + 1);
  grdNetworks.Invalidate;

  // Feed the Channel Analysis tab with the fresh report + full network list.
  if FChannels <> nil then
    FChannels.UpdateData(FVM.Report, FVM.AllNetworks);

  sbMain.SimpleText := Format('%d networks  •  %d shown  •  adapter: %s  •  last scan %s',
    [FVM.TotalNetworks, FVM.VisibleCount,
     IfThen(FVM.AdapterName = '', '(none)', FVM.AdapterName),
     FormatDateTime('hh:nn:ss', FVM.LastScan)]);
end;

procedure TfrmMain.ScannerSnapshot(Sender: TObject; ASnapshot: TScanSnapshot);
begin
  // Runs on the main thread (marshaled by the scanner). The snapshot is only
  // valid for the duration of this call; the view-model copies what it needs.
  FVM.UpdateFromSnapshot(ASnapshot);
end;

procedure TfrmMain.ScannerError(Sender: TObject; const AMessage: string);
begin
  sbMain.SimpleText := 'Scanner: ' + AMessage;
end;

procedure TfrmMain.edtSearchChange(Sender: TObject);
begin
  FVM.SearchText := edtSearch.Text;
end;

procedure TfrmMain.cboBandChange(Sender: TObject);
begin
  case cboBand.ItemIndex of
    1: FVM.BandFilter := wb24GHz;
    2: FVM.BandFilter := wb5GHz;
    3: FVM.BandFilter := wb6GHz;
  else
    FVM.BandFilter := wbUnknown;
  end;
end;

procedure TfrmMain.cboIntervalChange(Sender: TObject);
var
  Ms: Integer;
begin
  if cboInterval.ItemIndex < 0 then
    Exit;
  // Interval is stashed as the item's Object; use NativeInt for Win64 safety.
  Ms := Integer(NativeInt(cboInterval.Items.Objects[cboInterval.ItemIndex]));
  FScanner.IntervalMs := Ms;
  FConfig.ScanIntervalMs := Ms;
end;

procedure TfrmMain.btnRefreshClick(Sender: TObject);
begin
  FScanner.RefreshNow;
  sbMain.SimpleText := 'Rescanning...';
end;

procedure TfrmMain.chkDarkClick(Sender: TObject);
begin
  ApplyTheme(chkDark.Checked);
end;

procedure TfrmMain.ApplyTheme(ADark: Boolean);
const
  DARK_STYLES: array[0..2] of string = ('Windows11 Dark', 'Carbon', 'Onyx Blue');
  LIGHT_STYLES: array[0..1] of string = ('Windows11 Modern Light', 'Windows');
var
  Name: string;
begin
  // Best-effort: pick the first installed style matching the requested mode.
  // Full theming (custom palette, animated cards) is a later phase.
  if ADark then
  begin
    for Name in DARK_STYLES do
      if TStyleManager.TrySetStyle(Name, False) then
        Break;
  end
  else
  begin
    for Name in LIGHT_STYLES do
      if TStyleManager.TrySetStyle(Name, False) then
        Break;
  end;
  grdNetworks.Invalidate;
end;

procedure TfrmMain.tmrUiTimer(Sender: TObject);
begin
  // Reserved for a live "x seconds ago" indicator; no-op in Phase 1.
end;

end.
