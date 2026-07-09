unit WiFi.UI.SignalFrame;

{
  WiFi.UI.SignalFrame

  The Signal Visualization view (Phase 3). Driven by THistoryService, it shows:

    * a network checklist - tick the networks to plot;
    * a live RSSI-over-time line graph for the ticked networks (trend history);
    * two custom gauges for the selected network - signal quality and the
      congestion of its channel;
    * a snapshot comparison panel - pick two past scans and list what was
      added / removed / changed.

  All plotting is hand-drawn (double-buffered TCanvas), no chart library. The
  frame holds a reference to the shared history service and copies the small
  amount of report data it needs, so it is safe to repaint at any time.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.UITypes, System.Generics.Collections, Vcl.Graphics, Vcl.Controls,
  Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.CheckLst,
  WiFi.Models, WiFi.Engine.Analysis, WiFi.Services.History;

type
  TframeSignal = class(TFrame)
    pnlLeft: TPanel;
    lblNets: TLabel;
    clbNets: TCheckListBox;
    pnlCompare: TPanel;
    lblCompare: TLabel;
    lblFrom: TLabel;
    cboOlder: TComboBox;
    lblTo: TLabel;
    cboNewer: TComboBox;
    btnCompare: TButton;
    lstDiff: TListBox;
    pbGauges: TPaintBox;
    pbGraph: TPaintBox;
    procedure clbNetsClickCheck(Sender: TObject);
    procedure clbNetsClick(Sender: TObject);
    procedure btnCompareClick(Sender: TObject);
    procedure pbGraphPaint(Sender: TObject);
    procedure pbGaugesPaint(Sender: TObject);
  private
    FHistory: THistoryService;
    FStats: TArray<TChannelStat>;
    FNetworks: TArray<TAccessPoint>;   // aligned with clbNets items
    FChecked: TDictionary<string, Boolean>;
    FInitialized: Boolean;
    procedure SyncCheckedFromList;
    procedure RefreshNetworkList;
    procedure RefreshCompareCombos;
    function SelectedAP(out AAP: TAccessPoint): Boolean;
    function CongestionForChannel(ABand: TWiFiBand; AChannel: Integer): Double;
    procedure DrawGauge(C: TCanvas; const R: TRect; AValue: Double;
      const ACaption, AReadout: string; AGoodIsHigh: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Called once by the host to share the history service.</summary>
    procedure SetHistory(AHistory: THistoryService);
    /// <summary>Refresh from the latest report after a scan.</summary>
    procedure UpdateData(AReport: TChannelReport);
  end;

implementation

{$R *.dfm}

uses
  System.Math, System.DateUtils, WiFi.Util.Format;

const
  LINE_PALETTE: array[0..9] of TColor = (
    $00C08040, $004080F0, $0040C0A0, $008040C0, $0040C0F0,
    $00F0A040, $00A0C040, $00F06060, $0060A0F0, $00C060A0);
  RSSI_TOP    = -20;
  RSSI_BOTTOM = -100;
  AUTO_CHECK_TOP = 4; // networks auto-plotted on first population

function GaugeColor(AFrac: Double; AGoodIsHigh: Boolean): TColor;
var
  T: Double;
begin
  T := EnsureRange(AFrac, 0, 1);
  if AGoodIsHigh then
    T := 1 - T; // high value -> green
  Result := RGB(Round(255 * T), Round(190 * (1 - T)), 48);
end;

{ TframeSignal }

constructor TframeSignal.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FChecked := TDictionary<string, Boolean>.Create;
end;

destructor TframeSignal.Destroy;
begin
  FChecked.Free;
  inherited;
end;

procedure TframeSignal.SetHistory(AHistory: THistoryService);
begin
  FHistory := AHistory;
end;

procedure TframeSignal.UpdateData(AReport: TChannelReport);
var
  I: Integer;
begin
  if AReport <> nil then
  begin
    SetLength(FStats, AReport.Stats.Count);
    for I := 0 to AReport.Stats.Count - 1 do
      FStats[I] := AReport.Stats[I];
  end
  else
    SetLength(FStats, 0);

  RefreshNetworkList;
  RefreshCompareCombos;
  pbGraph.Invalidate;
  pbGauges.Invalidate;
end;

procedure TframeSignal.SyncCheckedFromList;
var
  I: Integer;
begin
  for I := 0 to clbNets.Items.Count - 1 do
    if I <= High(FNetworks) then
      FChecked.AddOrSetValue(FNetworks[I].BSSID, clbNets.Checked[I]);
end;

procedure TframeSignal.RefreshNetworkList;
var
  I: Integer;
  AP: TAccessPoint;
  Display, SelBssid: string;
  DefChecked: Boolean;
begin
  if FHistory = nil then
    Exit;

  // Remember the current selection and check states.
  SelBssid := '';
  if (clbNets.ItemIndex >= 0) and (clbNets.ItemIndex <= High(FNetworks)) then
    SelBssid := FNetworks[clbNets.ItemIndex].BSSID;
  SyncCheckedFromList;

  FNetworks := FHistory.KnownNetworks;

  clbNets.Items.BeginUpdate;
  try
    clbNets.Clear;
    for I := 0 to High(FNetworks) do
    begin
      AP := FNetworks[I];
      if AP.Hidden then
        Display := Format('(%s)  ch%d  %d dBm', [AP.BSSID, AP.Channel, AP.RSSI])
      else
        Display := Format('%s  ch%d  %d dBm', [AP.SSID, AP.Channel, AP.RSSI]);
      clbNets.Items.Add(Display);

      // Default check state: strongest few on first ever population.
      if not FChecked.TryGetValue(AP.BSSID, DefChecked) then
        DefChecked := (not FInitialized) and (I < AUTO_CHECK_TOP);
      clbNets.Checked[I] := DefChecked;
      FChecked.AddOrSetValue(AP.BSSID, DefChecked);

      if AP.BSSID = SelBssid then
        clbNets.ItemIndex := I;
    end;
  finally
    clbNets.Items.EndUpdate;
  end;
  FInitialized := True;
end;

procedure TframeSignal.RefreshCompareCombos;
var
  I, PrevOlder, PrevNewer: Integer;
  TimeStr: string;
begin
  if FHistory = nil then
    Exit;
  PrevOlder := cboOlder.ItemIndex;
  PrevNewer := cboNewer.ItemIndex;

  cboOlder.Items.BeginUpdate;
  cboNewer.Items.BeginUpdate;
  try
    cboOlder.Clear;
    cboNewer.Clear;
    for I := 0 to FHistory.SnapshotCount - 1 do
    begin
      TimeStr := Format('#%d  %s', [I + 1,
        FormatDateTime('hh:nn:ss', FHistory.SnapshotTime(I))]);
      cboOlder.Items.Add(TimeStr);
      cboNewer.Items.Add(TimeStr);
    end;
  finally
    cboOlder.Items.EndUpdate;
    cboNewer.Items.EndUpdate;
  end;

  // Keep prior picks; otherwise default to first vs last.
  if (PrevOlder >= 0) and (PrevOlder < cboOlder.Items.Count) then
    cboOlder.ItemIndex := PrevOlder
  else if cboOlder.Items.Count > 0 then
    cboOlder.ItemIndex := 0;
  if (PrevNewer >= 0) and (PrevNewer < cboNewer.Items.Count) then
    cboNewer.ItemIndex := PrevNewer
  else if cboNewer.Items.Count > 0 then
    cboNewer.ItemIndex := cboNewer.Items.Count - 1;
end;

function TframeSignal.SelectedAP(out AAP: TAccessPoint): Boolean;
begin
  Result := (clbNets.ItemIndex >= 0) and (clbNets.ItemIndex <= High(FNetworks));
  if Result then
    AAP := FNetworks[clbNets.ItemIndex];
end;

function TframeSignal.CongestionForChannel(ABand: TWiFiBand; AChannel: Integer): Double;
var
  S: TChannelStat;
begin
  Result := 0;
  for S in FStats do
    if (S.Band = ABand) and (S.Channel = AChannel) then
      Exit(S.CongestionScore);
end;

procedure TframeSignal.clbNetsClickCheck(Sender: TObject);
begin
  SyncCheckedFromList;
  pbGraph.Invalidate;
end;

procedure TframeSignal.clbNetsClick(Sender: TObject);
begin
  pbGauges.Invalidate;
  pbGraph.Invalidate; // highlight selected series
end;

procedure TframeSignal.btnCompareClick(Sender: TObject);
var
  Rows: TArray<TComparisonRow>;
  Row: TComparisonRow;
  Prefix, Detail: string;
begin
  lstDiff.Items.Clear;
  if (FHistory = nil) or (cboOlder.ItemIndex < 0) or (cboNewer.ItemIndex < 0) then
    Exit;

  Rows := FHistory.Compare(cboOlder.ItemIndex, cboNewer.ItemIndex);
  for Row in Rows do
  begin
    case Row.Status of
      csAdded:   begin Prefix := '[+] ';  Detail := Format('%d dBm', [Row.NewRSSI]); end;
      csRemoved: begin Prefix := '[-] ';  Detail := Format('was %d dBm', [Row.OldRSSI]); end;
      csChanged: begin Prefix := '[~] ';  Detail := Format('%d -> %d dBm', [Row.OldRSSI, Row.NewRSSI]); end;
    else
      begin Prefix := '    '; Detail := Format('%d dBm', [Row.NewRSSI]); end;
    end;
    lstDiff.Items.Add(Format('%s%s  %s',
      [Prefix, IfThen(Row.SSID = '', '(' + Row.BSSID + ')', Row.SSID), Detail]));
  end;
  if lstDiff.Items.Count = 0 then
    lstDiff.Items.Add('(no snapshots to compare yet)');
end;

procedure TframeSignal.pbGraphPaint(Sender: TObject);
var
  Bmp: TBitmap;
  C: TCanvas;
  Area, Plot: TRect;
  I, Idx, X, Y, PrevX, PrevY, PlottedSeries: Integer;
  AP: TAccessPoint;
  Samples: TArray<TRssiSample>;
  TMin, TMax, Span: Double;
  Color: TColor;
  RssiLine, LegendY: Integer;
  S: string;

  function TimeToX(ATime: TDateTime): Integer;
  begin
    if Span <= 0 then
      Exit(Plot.Right);
    Result := Plot.Left + Round((ATime - TMin) / Span * Plot.Width);
  end;

  function RssiToY(ARssi: Integer): Integer;
  var T: Double;
  begin
    T := EnsureRange((ARssi - RSSI_BOTTOM) / (RSSI_TOP - RSSI_BOTTOM), 0, 1);
    Result := Plot.Bottom - Round(T * Plot.Height);
  end;

begin
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(Max(1, pbGraph.ClientWidth), Max(1, pbGraph.ClientHeight));
    C := Bmp.Canvas;
    C.Font.Assign(pbGraph.Font);
    Area := Rect(0, 0, Bmp.Width, Bmp.Height);
    C.Brush.Color := clWindow;
    C.FillRect(Area);

    Plot := Rect(Area.Left + 44, Area.Top + 12, Area.Right - 12, Area.Bottom - 28);

    // Grid + Y (RSSI) labels every 20 dBm.
    C.Font.Color := clGrayText;
    RssiLine := RSSI_TOP;
    while RssiLine >= RSSI_BOTTOM do
    begin
      Y := RssiToY(RssiLine);
      C.Pen.Color := $00ECECEC;
      C.Pen.Width := 1;
      C.MoveTo(Plot.Left, Y);
      C.LineTo(Plot.Right, Y);
      C.Brush.Style := bsClear;
      C.TextOut(Area.Left + 4, Y - 7, IntToStr(RssiLine));
      C.Brush.Style := bsSolid;
      Dec(RssiLine, 20);
    end;

    // Global time window across the plotted series.
    TMin := 0; TMax := 0;
    PlottedSeries := 0;
    for I := 0 to High(FNetworks) do
    begin
      if (I >= clbNets.Items.Count) or (not clbNets.Checked[I]) or (FHistory = nil) then
        Continue;
      Samples := FHistory.SeriesFor(FNetworks[I].BSSID);
      if Length(Samples) = 0 then
        Continue;
      if (PlottedSeries = 0) then
      begin
        TMin := Samples[0].Time;
        TMax := Samples[High(Samples)].Time;
      end
      else
      begin
        TMin := Min(TMin, Samples[0].Time);
        TMax := Max(TMax, Samples[High(Samples)].Time);
      end;
      Inc(PlottedSeries);
    end;

    if PlottedSeries = 0 then
    begin
      C.Font.Color := clGrayText;
      C.Brush.Style := bsClear;
      C.TextOut(Plot.Left + 12, Plot.Top + 12,
        'Tick one or more networks on the left to plot their signal over time.');
      C.Brush.Style := bsSolid;
      pbGraph.Canvas.Draw(0, 0, Bmp);
      Exit;
    end;
    Span := TMax - TMin;

    // One coloured polyline per checked network.
    LegendY := Plot.Top + 2;
    for I := 0 to High(FNetworks) do
    begin
      if (I >= clbNets.Items.Count) or (not clbNets.Checked[I]) then
        Continue;
      AP := FNetworks[I];
      Samples := FHistory.SeriesFor(AP.BSSID);
      if Length(Samples) = 0 then
        Continue;
      Color := LINE_PALETTE[I mod Length(LINE_PALETTE)];
      C.Pen.Color := Color;
      C.Pen.Width := 2;
      PrevX := 0; PrevY := 0;
      for Idx := 0 to High(Samples) do
      begin
        X := TimeToX(Samples[Idx].Time);
        Y := RssiToY(Samples[Idx].RSSI);
        if Idx = 0 then
        begin
          if Length(Samples) = 1 then
            C.Ellipse(X - 2, Y - 2, X + 2, Y + 2);
        end
        else
        begin
          C.MoveTo(PrevX, PrevY);
          C.LineTo(X, Y);
        end;
        PrevX := X; PrevY := Y;
      end;

      // Legend entry.
      C.Brush.Color := Color;
      C.FillRect(Rect(Plot.Right - 150, LegendY, Plot.Right - 138, LegendY + 10));
      C.Brush.Style := bsClear;
      C.Font.Color := clWindowText;
      if AP.Hidden then S := '(' + AP.BSSID + ')' else S := AP.SSID;
      C.TextOut(Plot.Right - 134, LegendY - 2, S);
      C.Brush.Style := bsSolid;
      Inc(LegendY, 14);
    end;

    C.Pen.Width := 1;
    C.Pen.Color := $00C0C0C0;
    C.MoveTo(Plot.Left, Plot.Bottom);
    C.LineTo(Plot.Right, Plot.Bottom);

    // X axis: start / end times.
    C.Font.Color := clGrayText;
    C.Brush.Style := bsClear;
    C.TextOut(Plot.Left, Plot.Bottom + 6, FormatDateTime('hh:nn:ss', TMin));
    S := FormatDateTime('hh:nn:ss', TMax);
    C.TextOut(Plot.Right - C.TextWidth(S), Plot.Bottom + 6, S);
    C.Brush.Style := bsSolid;

    pbGraph.Canvas.Draw(0, 0, Bmp);
  finally
    Bmp.Free;
  end;
end;

procedure TframeSignal.DrawGauge(C: TCanvas; const R: TRect; AValue: Double;
  const ACaption, AReadout: string; AGoodIsHigh: Boolean);
const
  STEPS = 64;
var
  Cx, Cy, Rad, I, VSteps: Integer;
  Ang, VFrac: Double;
  X, Y, PrevX, PrevY, Nx, Ny: Integer;
begin
  Cx := (R.Left + R.Right) div 2;
  Cy := R.Bottom - 22;
  Rad := Max(20, Min((R.Width - 24) div 2, R.Height - 42));
  VFrac := EnsureRange(AValue / 100, 0, 1);

  // Background arc (light grey), left(180) -> right(0).
  C.Pen.Width := 10;
  C.Pen.Color := $00E4E4E4;
  PrevX := 0; PrevY := 0;
  for I := 0 to STEPS do
  begin
    Ang := Pi - (I / STEPS) * Pi;
    X := Cx + Round(Rad * Cos(Ang));
    Y := Cy - Round(Rad * Sin(Ang));
    if I > 0 then begin C.MoveTo(PrevX, PrevY); C.LineTo(X, Y); end;
    PrevX := X; PrevY := Y;
  end;

  // Value arc, coloured by magnitude.
  VSteps := Round(STEPS * VFrac);
  PrevX := 0; PrevY := 0;
  for I := 0 to VSteps do
  begin
    Ang := Pi - (I / STEPS) * Pi;
    X := Cx + Round(Rad * Cos(Ang));
    Y := Cy - Round(Rad * Sin(Ang));
    C.Pen.Color := GaugeColor(I / STEPS, AGoodIsHigh);
    if I > 0 then begin C.MoveTo(PrevX, PrevY); C.LineTo(X, Y); end;
    PrevX := X; PrevY := Y;
  end;

  // Needle.
  Ang := Pi - VFrac * Pi;
  Nx := Cx + Round((Rad - 6) * Cos(Ang));
  Ny := Cy - Round((Rad - 6) * Sin(Ang));
  C.Pen.Width := 2;
  C.Pen.Color := clWindowText;
  C.MoveTo(Cx, Cy);
  C.LineTo(Nx, Ny);
  C.Brush.Color := clWindowText;
  C.Ellipse(Cx - 3, Cy - 3, Cx + 3, Cy + 3);

  // Readout + caption.
  C.Pen.Width := 1;
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Color := clWindowText;
  C.TextOut(Cx - C.TextWidth(AReadout) div 2, Cy - 18, AReadout);
  C.Font.Style := [];
  C.Font.Color := clGrayText;
  C.TextOut(Cx - C.TextWidth(ACaption) div 2, Cy + 6, ACaption);
  C.Brush.Style := bsSolid;
end;

procedure TframeSignal.pbGaugesPaint(Sender: TObject);
var
  Bmp: TBitmap;
  C: TCanvas;
  Area, Left, Right: TRect;
  AP: TAccessPoint;
  HasSel: Boolean;
  Quality, Cong: Double;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(Max(1, pbGauges.ClientWidth), Max(1, pbGauges.ClientHeight));
    C := Bmp.Canvas;
    C.Font.Assign(pbGauges.Font);
    Area := Rect(0, 0, Bmp.Width, Bmp.Height);
    C.Brush.Color := clWindow;
    C.FillRect(Area);

    HasSel := SelectedAP(AP);
    if HasSel then
    begin
      Quality := AP.Quality;
      if Quality = 0 then
        Quality := RssiToQuality(AP.RSSI);
      Cong := CongestionForChannel(AP.Band, AP.Channel);
    end
    else
    begin
      Quality := 0; Cong := 0;
    end;

    Left := Rect(Area.Left, Area.Top, Area.Left + Area.Width div 2, Area.Bottom);
    Right := Rect(Left.Right, Area.Top, Area.Right, Area.Bottom);

    if HasSel then
    begin
      DrawGauge(C, Left, Quality, 'Signal quality', Format('%.0f%%', [Quality]), True);
      DrawGauge(C, Right, Cong, 'Channel congestion', Format('%.0f', [Cong]), False);
    end
    else
    begin
      C.Font.Color := clGrayText;
      C.Brush.Style := bsClear;
      C.TextOut(Area.Left + 16, Area.Top + 16,
        'Select a network on the left to see its quality and channel congestion.');
      C.Brush.Style := bsSolid;
    end;

    pbGauges.Canvas.Draw(0, 0, Bmp);
  finally
    Bmp.Free;
  end;
end;

end.
