unit WiFi.UI.ChannelsFrame;

{
  WiFi.UI.ChannelsFrame

  The Channel Analysis view (Phase 2). A self-contained VCL frame that renders,
  for a chosen band:

    * a spectrum graph - one arc per detected network, centered on its channel,
      as tall as its signal and as wide as its channel width (inSSIDer-style);
    * a congestion heatmap strip - one cell per channel, green (quiet) to red
      (busy) from the analysis engine's congestion score;
    * the recommended channel, highlighted and labelled.

  Everything is drawn by hand on a TPaintBox (TCanvas/GDI) - no chart library.
  The frame owns copies of the data it needs, so it is safe to repaint after the
  underlying snapshot/report has been replaced.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.UITypes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls,
  Vcl.ExtCtrls,
  WiFi.Models, WiFi.Engine.Channels, WiFi.Engine.Analysis;

type
  TframeChannels = class(TFrame)
    pnlHeader: TPanel;
    lblBand: TLabel;
    cboBand: TComboBox;
    chkFill: TCheckBox;
    lblRec: TLabel;
    pbSpectrum: TPaintBox;
    procedure cboBandChange(Sender: TObject);
    procedure chkFillClick(Sender: TObject);
    procedure pbSpectrumPaint(Sender: TObject);
  private
    FStats: TArray<TChannelStat>;
    FAps: TArray<TAccessPoint>;
    FRec24, FRec5, FRec6: Integer;
    function SelectedBand: TWiFiBand;
    function RecommendedForSelected: Integer;
    procedure BandRange(ABand: TWiFiBand; out ALoMHz, AHiMHz: Integer);
    function FreqToX(AFreqMHz, ALoMHz, AHiMHz, ALeft, AWidth: Integer): Integer;
    function RssiToY(ARssi, ATop, ABottom: Integer): Integer;
    procedure DrawEmpty(ACanvas: TCanvas; const AArea: TRect);
    procedure DrawSpectrum(ACanvas: TCanvas; ABand: TWiFiBand;
      const APlot: TRect; ALoMHz, AHiMHz: Integer);
    procedure DrawHeatmap(ACanvas: TCanvas; ABand: TWiFiBand;
      const AStrip: TRect; ALoMHz, AHiMHz: Integer);
    procedure DrawAxis(ACanvas: TCanvas; ABand: TWiFiBand;
      const APlot, AStrip: TRect; ALoMHz, AHiMHz: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Refresh from the latest report + network list. Copies what it
    /// needs, so the caller may free/replace them afterwards.</summary>
    procedure UpdateData(AReport: TChannelReport; const AAps: TArray<TAccessPoint>);
  end;

implementation

{$R *.dfm}

uses
  System.Math, WiFi.Services.Theme;

const
  // Distinct, theme-neutral series colours for the arcs.
  ARC_PALETTE: array[0..9] of TColor = (
    $00C08040, $004080F0, $0040C0A0, $008040C0, $0040C0F0,
    $00F0A040, $00A0C040, $00F06060, $0060A0F0, $00C060A0);
  RSSI_TOP    = -20;   // dBm mapped to the top of the plot
  RSSI_BOTTOM = -100;  // dBm mapped to the baseline

function Lighten(AColor: TColor; AAmount: Double): TColor;
var
  R, G, B: Byte;
  C: LongInt;
begin
  C := ColorToRGB(AColor);
  R := GetRValue(C); G := GetGValue(C); B := GetBValue(C);
  R := Round(R + (255 - R) * AAmount);
  G := Round(G + (255 - G) * AAmount);
  B := Round(B + (255 - B) * AAmount);
  Result := RGB(R, G, B);
end;

function ScoreColor(AScore: Double): TColor;
var
  T: Double;
begin
  T := EnsureRange(AScore / 100, 0, 1);
  Result := RGB(Round(255 * T), Round(200 * (1 - T)), 48); // green -> red
end;

{ TframeChannels }

constructor TframeChannels.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  cboBand.ItemIndex := 0;
end;

function TframeChannels.SelectedBand: TWiFiBand;
begin
  case cboBand.ItemIndex of
    1: Result := wb5GHz;
    2: Result := wb6GHz;
  else
    Result := wb24GHz;
  end;
end;

function TframeChannels.RecommendedForSelected: Integer;
begin
  case SelectedBand of
    wb5GHz: Result := FRec5;
    wb6GHz: Result := FRec6;
  else
    Result := FRec24;
  end;
end;

procedure TframeChannels.UpdateData(AReport: TChannelReport;
  const AAps: TArray<TAccessPoint>);
var
  I: Integer;
begin
  FAps := Copy(AAps);
  if AReport <> nil then
  begin
    SetLength(FStats, AReport.Stats.Count);
    for I := 0 to AReport.Stats.Count - 1 do
      FStats[I] := AReport.Stats[I];
    FRec24 := AReport.Recommended24;
    FRec5 := AReport.Recommended5;
    FRec6 := AReport.Recommended6;
  end
  else
    SetLength(FStats, 0);
  pbSpectrum.Invalidate;
end;

procedure TframeChannels.cboBandChange(Sender: TObject);
begin
  pbSpectrum.Invalidate;
end;

procedure TframeChannels.chkFillClick(Sender: TObject);
begin
  pbSpectrum.Invalidate;
end;

procedure TframeChannels.BandRange(ABand: TWiFiBand; out ALoMHz, AHiMHz: Integer);
begin
  case ABand of
    wb24GHz: begin ALoMHz := 2400; AHiMHz := 2500; end;
    wb5GHz:  begin ALoMHz := 5150; AHiMHz := 5895; end;
    wb6GHz:  begin ALoMHz := 5925; AHiMHz := 7125; end;
  else
    begin ALoMHz := 2400; AHiMHz := 2500; end;
  end;
end;

function TframeChannels.FreqToX(AFreqMHz, ALoMHz, AHiMHz, ALeft, AWidth: Integer): Integer;
begin
  if AHiMHz = ALoMHz then
    Exit(ALeft);
  Result := ALeft + Round((AFreqMHz - ALoMHz) / (AHiMHz - ALoMHz) * AWidth);
end;

function TframeChannels.RssiToY(ARssi, ATop, ABottom: Integer): Integer;
var
  T: Double;
begin
  T := EnsureRange((ARssi - RSSI_BOTTOM) / (RSSI_TOP - RSSI_BOTTOM), 0, 1);
  Result := ABottom - Round(T * (ABottom - ATop));
end;

procedure TframeChannels.DrawEmpty(ACanvas: TCanvas; const AArea: TRect);
begin
  ACanvas.Brush.Color := Theme.Color(trBackground);
  ACanvas.FillRect(AArea);
  ACanvas.Font.Color := Theme.Color(trTextSecondary);
  ACanvas.Brush.Style := bsClear;
  ACanvas.TextOut(AArea.Left + 16, AArea.Top + 16,
    'No networks on this band yet - scanning...');
  ACanvas.Brush.Style := bsSolid;
end;

procedure TframeChannels.DrawSpectrum(ACanvas: TCanvas; ABand: TWiFiBand;
  const APlot: TRect; ALoMHz, AHiMHz: Integer);
var
  AP: TAccessPoint;
  Idx, Cx, Cy, HalfW, WidthMHz, Px, Py, StepX: Integer;
  Color: TColor;
  Pts: array of TPoint;
  N, I: Integer;
  Rel: Double;
  Caption: string;
begin
  Idx := 0;
  for AP in FAps do
  begin
    if AP.Band <> ABand then
      Continue;
    Color := ARC_PALETTE[Idx mod Length(ARC_PALETTE)];
    Inc(Idx);

    Cx := FreqToX(AP.FrequencyMHz, ALoMHz, AHiMHz, APlot.Left, APlot.Width);
    Cy := RssiToY(AP.RSSI, APlot.Top, APlot.Bottom);
    WidthMHz := WidthToMHz(AP.Width);
    if WidthMHz = 0 then
      WidthMHz := 20;
    HalfW := Max(6, Round(WidthMHz / 2 / (AHiMHz - ALoMHz) * APlot.Width));

    // Build a parabolic bell: baseline -> peak -> baseline across the width.
    N := 24;
    SetLength(Pts, N + 1);
    StepX := (2 * HalfW) div N;
    if StepX < 1 then StepX := 1;
    for I := 0 to N do
    begin
      Px := Cx - HalfW + I * StepX;
      Rel := (Px - Cx) / HalfW;                 // -1..+1
      Py := APlot.Bottom - Round((APlot.Bottom - Cy) * (1 - Rel * Rel));
      Pts[I] := Point(EnsureRange(Px, APlot.Left, APlot.Right), Py);
    end;

    if chkFill.Checked then
    begin
      ACanvas.Brush.Color := Lighten(Color, 0.72);
      ACanvas.Pen.Style := psClear;
      // Close the polygon along the baseline.
      SetLength(Pts, N + 3);
      Pts[N + 1] := Point(Pts[N].X, APlot.Bottom);
      Pts[N + 2] := Point(Pts[0].X, APlot.Bottom);
      ACanvas.Polygon(Pts);
      SetLength(Pts, N + 1);
      ACanvas.Pen.Style := psSolid;
    end;

    ACanvas.Pen.Color := Color;
    ACanvas.Pen.Width := 2;
    ACanvas.Polyline(Pts);
    ACanvas.Pen.Width := 1;

    // Label the peak with SSID (or BSSID for hidden nets).
    if AP.Hidden then
      Caption := '(' + AP.BSSID + ')'
    else
      Caption := AP.SSID;
    if Caption <> '' then
    begin
      ACanvas.Font.Color := Color;
      ACanvas.Brush.Style := bsClear;
      ACanvas.TextOut(Cx - ACanvas.TextWidth(Caption) div 2, Cy - 16, Caption);
      ACanvas.Brush.Style := bsSolid;
    end;
  end;
end;

procedure TframeChannels.DrawHeatmap(ACanvas: TCanvas; ABand: TWiFiBand;
  const AStrip: TRect; ALoMHz, AHiMHz: Integer);
var
  S: TChannelStat;
  X0, X1: Integer;
  R: TRect;
  Lbl: string;
begin
  for S in FStats do
  begin
    if S.Band <> ABand then
      Continue;
    X0 := FreqToX(S.CenterFreqMHz - 10, ALoMHz, AHiMHz, AStrip.Left, AStrip.Width);
    X1 := FreqToX(S.CenterFreqMHz + 10, ALoMHz, AHiMHz, AStrip.Left, AStrip.Width);
    R := Rect(X0 + 1, AStrip.Top, X1 - 1, AStrip.Bottom);
    ACanvas.Brush.Color := ScoreColor(S.CongestionScore);
    ACanvas.FillRect(R);
    // Show utilization percent when the cell is wide enough.
    Lbl := IntToStr(Round(S.Utilization)) + '%';
    if R.Width > ACanvas.TextWidth(Lbl) + 4 then
    begin
      ACanvas.Font.Color := clWhite;
      ACanvas.Brush.Style := bsClear;
      ACanvas.TextOut(R.Left + (R.Width - ACanvas.TextWidth(Lbl)) div 2,
        R.Top + (R.Height - ACanvas.TextHeight(Lbl)) div 2, Lbl);
      ACanvas.Brush.Style := bsSolid;
    end;
  end;
end;

procedure TframeChannels.DrawAxis(ACanvas: TCanvas; ABand: TWiFiBand;
  const APlot, AStrip: TRect; ALoMHz, AHiMHz: Integer);
var
  Seen: array of Integer;

  function AlreadySeen(ACh: Integer): Boolean;
  var V: Integer;
  begin
    for V in Seen do
      if V = ACh then Exit(True);
    Result := False;
  end;

  procedure Tick(ACh, AFreq: Integer; AHighlight: Boolean);
  var
    X: Integer;
    Lbl: string;
  begin
    X := FreqToX(AFreq, ALoMHz, AHiMHz, APlot.Left, APlot.Width);
    if AHighlight then
    begin
      ACanvas.Pen.Color := $0060C060;
      ACanvas.Pen.Width := 2;
    end
    else
    begin
      ACanvas.Pen.Color := Theme.Color(trGridLine);
      ACanvas.Pen.Width := 1;
    end;
    ACanvas.MoveTo(X, APlot.Top);
    ACanvas.LineTo(X, APlot.Bottom);
    ACanvas.Pen.Width := 1;
    Lbl := IntToStr(ACh);
    if AHighlight then
      ACanvas.Font.Color := $0030A030
    else
      ACanvas.Font.Color := Theme.Color(trTextPrimary);
    ACanvas.Brush.Style := bsClear;
    ACanvas.TextOut(X - ACanvas.TextWidth(Lbl) div 2, AStrip.Bottom + 2, Lbl);
    ACanvas.Brush.Style := bsSolid;
  end;

var
  AP: TAccessPoint;
  Rec: Integer;
begin
  SetLength(Seen, 0);
  Rec := RecommendedForSelected;
  // Grid + labels for every channel that carries a network in this band.
  for AP in FAps do
  begin
    if (AP.Band <> ABand) or (AP.Channel = 0) or AlreadySeen(AP.Channel) then
      Continue;
    SetLength(Seen, Length(Seen) + 1);
    Seen[High(Seen)] := AP.Channel;
    Tick(AP.Channel, AP.FrequencyMHz, AP.Channel = Rec);
  end;
end;

procedure TframeChannels.pbSpectrumPaint(Sender: TObject);
var
  Bmp: TBitmap;
  Cv: TCanvas;
  Area, Plot, Strip: TRect;
  ABand: TWiFiBand;
  LoMHz, HiMHz, Count: Integer;
  AP: TAccessPoint;
  Rec: Integer;
begin
  // Double-buffer: render into an offscreen bitmap, then blit once (no flicker).
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(Max(1, pbSpectrum.ClientWidth), Max(1, pbSpectrum.ClientHeight));
    Cv := Bmp.Canvas;
    Cv.Font.Assign(pbSpectrum.Font);
    Area := Rect(0, 0, Bmp.Width, Bmp.Height);
    ABand := SelectedBand;

    Cv.Brush.Color := Theme.Color(trBackground);
    Cv.FillRect(Area);

    Count := 0;
    for AP in FAps do
      if AP.Band = ABand then
        Inc(Count);

    Rec := RecommendedForSelected;
    if Rec > 0 then
      lblRec.Caption := Format('Recommended channel: %d', [Rec])
    else
      lblRec.Caption := 'Recommended channel: -';

    if Count = 0 then
    begin
      DrawEmpty(Cv, Area);
    end
    else
    begin
      // Layout: spectrum plot on top, heatmap strip below, axis at the foot.
      Plot := Rect(Area.Left + 40, Area.Top + 12, Area.Right - 12, Area.Bottom - 56);
      Strip := Rect(Plot.Left, Plot.Bottom + 4, Plot.Right, Plot.Bottom + 24);

      BandRange(ABand, LoMHz, HiMHz);

      // Baseline + plot border.
      Cv.Pen.Color := Theme.Color(trGridLine);
      Cv.Pen.Width := 1;
      Cv.MoveTo(Plot.Left, Plot.Bottom);
      Cv.LineTo(Plot.Right, Plot.Bottom);

      DrawAxis(Cv, ABand, Plot, Strip, LoMHz, HiMHz);
      DrawSpectrum(Cv, ABand, Plot, LoMHz, HiMHz);
      DrawHeatmap(Cv, ABand, Strip, LoMHz, HiMHz);

      // Y-axis RSSI ticks.
      Cv.Font.Color := Theme.Color(trTextSecondary);
      Cv.Brush.Style := bsClear;
      Cv.TextOut(Area.Left + 4, Plot.Top - 2, IntToStr(RSSI_TOP));
      Cv.TextOut(Area.Left + 4, Plot.Bottom - 8, IntToStr(RSSI_BOTTOM));
      Cv.Brush.Style := bsSolid;
    end;

    pbSpectrum.Canvas.Draw(0, 0, Bmp);
  finally
    Bmp.Free;
  end;
end;

end.
