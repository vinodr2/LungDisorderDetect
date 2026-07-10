unit WiFi.UI.DashboardFrame;

{
  WiFi.UI.DashboardFrame

  The Dashboard view (Phase 5). A single custom-drawn, double-buffered surface
  showing at-a-glance summary cards, two animated gauges (connected-signal
  quality and worst-channel congestion), band and security distribution bars,
  and a signal-trend indicator for the connected network.

  It reads its numbers from the view-model (which is stable between scans on the
  main thread) and eases the gauge needles toward their targets with a timer, so
  updates feel smooth. All drawing uses the shared Theme palette, so it tracks
  light/dark mode with every other surface. No chart library.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.UITypes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls,
  WiFi.Models, WiFi.ViewModels.Main, WiFi.Services.Theme;

type
  TframeDashboard = class(TFrame)
    pbDash: TPaintBox;
    tmrAnim: TTimer;
    procedure pbDashPaint(Sender: TObject);
    procedure tmrAnimTimer(Sender: TObject);
  private
    FVM: TMainViewModel;
    FQualityTarget, FQualityDisplay: Double;
    FCongTarget, FCongDisplay: Double;
    procedure DrawCard(C: TCanvas; const R: TRect; const ATitle, AValue,
      ASub: string; AAccent: Boolean);
    procedure DrawGauge(C: TCanvas; const R: TRect; AValue: Double;
      const ACaption, AReadout: string; AGoodIsHigh: Boolean);
    procedure DrawHBar(C: TCanvas; const R: TRect; const ALabel: string;
      AValue, AMax: Integer; AColor: TColor);
    procedure DrawDistribution(C: TCanvas; const R: TRect);
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetViewModel(AVM: TMainViewModel);
    /// <summary>Refresh gauge targets after a scan and start the animation.</summary>
    procedure UpdateData;
  end;

implementation

{$R *.dfm}

uses
  System.Math, WiFi.Util.Format, WiFi.Engine.Analysis;

const
  BAND_COLORS: array[TWiFiBand] of TColor =
    ($00808080, $004080F0, $0040C0A0, $00C08040); // unknown,2.4,5,6

function GaugeColor(AFrac: Double; AGoodIsHigh: Boolean): TColor;
var
  T: Double;
begin
  T := EnsureRange(AFrac, 0, 1);
  if AGoodIsHigh then
    T := 1 - T;
  Result := RGB(Round(255 * T), Round(190 * (1 - T)), 48);
end;

{ TframeDashboard }

constructor TframeDashboard.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FQualityDisplay := 0;
  FCongDisplay := 0;
end;

procedure TframeDashboard.SetViewModel(AVM: TMainViewModel);
begin
  FVM := AVM;
end;

procedure TframeDashboard.UpdateData;
var
  AP: TAccessPoint;
begin
  FQualityTarget := 0;
  FCongTarget := 0;
  if FVM <> nil then
  begin
    if FVM.TryGetConnected(AP) then
    begin
      if AP.Quality > 0 then
        FQualityTarget := AP.Quality
      else
        FQualityTarget := RssiToQuality(AP.RSSI);
    end;
    if (FVM.Report <> nil) then
    begin
      var S: TChannelStat;
      for S in FVM.Report.Stats do
        if (S.Band = FVM.Report.MostCongestedBand) and
           (S.Channel = FVM.Report.MostCongestedChannel) then
          FCongTarget := S.CongestionScore;
    end;
  end;
  tmrAnim.Enabled := True; // ease toward the new targets
  pbDash.Invalidate;
end;

procedure TframeDashboard.tmrAnimTimer(Sender: TObject);
const
  EPS = 0.6;
  procedure Ease(var ADisplay: Double; ATarget: Double);
  begin
    ADisplay := ADisplay + (ATarget - ADisplay) * 0.25;
    if Abs(ATarget - ADisplay) < EPS then
      ADisplay := ATarget;
  end;
begin
  Ease(FQualityDisplay, FQualityTarget);
  Ease(FCongDisplay, FCongTarget);
  pbDash.Invalidate;
  if (Abs(FQualityTarget - FQualityDisplay) < EPS) and
     (Abs(FCongTarget - FCongDisplay) < EPS) then
    tmrAnim.Enabled := False; // settled
end;

procedure TframeDashboard.DrawCard(C: TCanvas; const R: TRect;
  const ATitle, AValue, ASub: string; AAccent: Boolean);
begin
  C.Brush.Color := Theme.Color(trCardFill);
  C.Pen.Color := Theme.Color(trCardBorder);
  C.Pen.Width := 1;
  C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, 8, 8);

  C.Brush.Style := bsClear;
  // Title.
  C.Font.Style := [];
  C.Font.Height := -11;
  C.Font.Color := Theme.Color(trTextSecondary);
  C.TextOut(R.Left + 10, R.Top + 8, ATitle);
  // Value.
  C.Font.Style := [fsBold];
  C.Font.Height := -20;
  if AAccent then
    C.Font.Color := Theme.Color(trAccent)
  else
    C.Font.Color := Theme.Color(trTextPrimary);
  C.TextOut(R.Left + 10, R.Top + 26, AValue);
  // Subtitle.
  C.Font.Style := [];
  C.Font.Height := -11;
  C.Font.Color := Theme.Color(trTextSecondary);
  C.TextOut(R.Left + 10, R.Bottom - 20, ASub);
  C.Brush.Style := bsSolid;
end;

procedure TframeDashboard.DrawGauge(C: TCanvas; const R: TRect; AValue: Double;
  const ACaption, AReadout: string; AGoodIsHigh: Boolean);
const
  STEPS = 64;
var
  Cx, Cy, Rad, I, VSteps: Integer;
  Ang, VFrac: Double;
  X, Y, PrevX, PrevY, Nx, Ny: Integer;
begin
  Cx := (R.Left + R.Right) div 2;
  Cy := R.Bottom - 24;
  Rad := Max(20, Min((R.Width - 24) div 2, R.Height - 44));
  VFrac := EnsureRange(AValue / 100, 0, 1);

  C.Pen.Width := 10;
  C.Pen.Color := Theme.Color(trGridLine);
  PrevX := 0; PrevY := 0;
  for I := 0 to STEPS do
  begin
    Ang := Pi - (I / STEPS) * Pi;
    X := Cx + Round(Rad * Cos(Ang));
    Y := Cy - Round(Rad * Sin(Ang));
    if I > 0 then begin C.MoveTo(PrevX, PrevY); C.LineTo(X, Y); end;
    PrevX := X; PrevY := Y;
  end;

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

  Ang := Pi - VFrac * Pi;
  Nx := Cx + Round((Rad - 6) * Cos(Ang));
  Ny := Cy - Round((Rad - 6) * Sin(Ang));
  C.Pen.Width := 2;
  C.Pen.Color := Theme.Color(trTextPrimary);
  C.MoveTo(Cx, Cy);
  C.LineTo(Nx, Ny);
  C.Brush.Color := Theme.Color(trTextPrimary);
  C.Ellipse(Cx - 3, Cy - 3, Cx + 3, Cy + 3);

  C.Pen.Width := 1;
  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Height := -16;
  C.Font.Color := Theme.Color(trTextPrimary);
  C.TextOut(Cx - C.TextWidth(AReadout) div 2, Cy - 20, AReadout);
  C.Font.Style := [];
  C.Font.Height := -11;
  C.Font.Color := Theme.Color(trTextSecondary);
  C.TextOut(Cx - C.TextWidth(ACaption) div 2, Cy + 8, ACaption);
  C.Brush.Style := bsSolid;
end;

procedure TframeDashboard.DrawHBar(C: TCanvas; const R: TRect;
  const ALabel: string; AValue, AMax: Integer; AColor: TColor);
var
  BarLeft, BarW, FillW: Integer;
begin
  C.Brush.Style := bsClear;
  C.Font.Style := [];
  C.Font.Height := -12;
  C.Font.Color := Theme.Color(trTextPrimary);
  C.TextOut(R.Left, R.Top + 1, ALabel);

  BarLeft := R.Left + 64;
  BarW := R.Right - BarLeft - 40;
  if BarW < 10 then
    BarW := 10;
  // Track.
  C.Brush.Style := bsSolid;
  C.Brush.Color := Theme.Color(trGridLine);
  C.FillRect(Rect(BarLeft, R.Top, BarLeft + BarW, R.Top + 14));
  // Fill.
  if AMax > 0 then
    FillW := Round(BarW * (AValue / AMax))
  else
    FillW := 0;
  C.Brush.Color := AColor;
  C.FillRect(Rect(BarLeft, R.Top, BarLeft + FillW, R.Top + 14));
  // Count.
  C.Brush.Style := bsClear;
  C.Font.Color := Theme.Color(trTextPrimary);
  C.TextOut(BarLeft + BarW + 8, R.Top + 1, IntToStr(AValue));
  C.Brush.Style := bsSolid;
end;

procedure TframeDashboard.DrawDistribution(C: TCanvas; const R: TRect);
var
  C24, C5, C6, MaxBand, Y, Sec, Opn, MaxSec: Integer;
begin
  C24 := FVM.BandCount(wb24GHz);
  C5 := FVM.BandCount(wb5GHz);
  C6 := FVM.BandCount(wb6GHz);
  MaxBand := Max(1, Max(C24, Max(C5, C6)));

  C.Brush.Style := bsClear;
  C.Font.Style := [fsBold];
  C.Font.Height := -13;
  C.Font.Color := Theme.Color(trTextPrimary);
  C.TextOut(R.Left, R.Top, 'Band distribution');
  C.Font.Style := [];

  Y := R.Top + 24;
  DrawHBar(C, Rect(R.Left, Y, R.Right, Y + 16), '2.4 GHz', C24, MaxBand, BAND_COLORS[wb24GHz]);
  Inc(Y, 24);
  DrawHBar(C, Rect(R.Left, Y, R.Right, Y + 16), '5 GHz', C5, MaxBand, BAND_COLORS[wb5GHz]);
  Inc(Y, 24);
  DrawHBar(C, Rect(R.Left, Y, R.Right, Y + 16), '6 GHz', C6, MaxBand, BAND_COLORS[wb6GHz]);

  Inc(Y, 40);
  C.Font.Style := [fsBold];
  C.Font.Height := -13;
  C.Font.Color := Theme.Color(trTextPrimary);
  C.TextOut(R.Left, Y, 'Security');
  C.Font.Style := [];
  Sec := FVM.SecuredCount;
  Opn := FVM.OpenCount;
  MaxSec := Max(1, Max(Sec, Opn));
  Inc(Y, 24);
  DrawHBar(C, Rect(R.Left, Y, R.Right, Y + 16), 'Secured', Sec, MaxSec, $004CAF50);
  Inc(Y, 24);
  DrawHBar(C, Rect(R.Left, Y, R.Right, Y + 16), 'Open', Opn, MaxSec, $004040F0);
end;

procedure TframeDashboard.pbDashPaint(Sender: TObject);
var
  Bmp: TBitmap;
  C: TCanvas;
  W, H, Margin, Gap, CardW, CardH, X, Top: Integer;
  AP, Strong, Weak: TAccessPoint;
  HasConn: Boolean;
  Rpt: TChannelReport;
  ConnVal, ConnSub, CongVal, BestVal: string;
  GaugeRect, DistRect: TRect;
  Trend: Double;
  TrendStr: string;
begin
  Bmp := TBitmap.Create;
  try
    W := Max(1, pbDash.ClientWidth);
    H := Max(1, pbDash.ClientHeight);
    Bmp.SetSize(W, H);
    C := Bmp.Canvas;
    C.Font.Assign(pbDash.Font);
    C.Brush.Color := Theme.Color(trBackground);
    C.FillRect(Rect(0, 0, W, H));

    if FVM = nil then
    begin
      pbDash.Canvas.Draw(0, 0, Bmp);
      Exit;
    end;

    Rpt := FVM.Report;
    HasConn := FVM.TryGetConnected(AP);
    Strong := FVM.Strongest;
    Weak := FVM.Weakest;

    Margin := 12;
    Gap := 10;
    CardH := 84;
    CardW := (W - 2 * Margin - 5 * Gap) div 6;
    Top := Margin;

    if HasConn then
    begin
      if AP.Hidden then ConnVal := '(hidden)' else ConnVal := AP.SSID;
      ConnSub := Format('ch %d  %d dBm', [AP.Channel, AP.RSSI]);
    end
    else
    begin
      ConnVal := 'Not connected';
      ConnSub := '';
    end;

    if Rpt <> nil then
    begin
      CongVal := Format('%s ch %d', [BandToStr(Rpt.MostCongestedBand), Rpt.MostCongestedChannel]);
      BestVal := Format('%d / %d', [Rpt.Recommended24, Rpt.Recommended5]);
    end
    else
    begin
      CongVal := '-';
      BestVal := '-';
    end;

    X := Margin;
    DrawCard(C, Rect(X, Top, X + CardW, Top + CardH), 'Connected', ConnVal, ConnSub, True);
    Inc(X, CardW + Gap);
    DrawCard(C, Rect(X, Top, X + CardW, Top + CardH), 'Networks', IntToStr(FVM.TotalNetworks), 'detected', False);
    Inc(X, CardW + Gap);
    DrawCard(C, Rect(X, Top, X + CardW, Top + CardH), 'Strongest',
      Format('%d dBm', [Strong.RSSI]), Strong.SSID, False);
    Inc(X, CardW + Gap);
    DrawCard(C, Rect(X, Top, X + CardW, Top + CardH), 'Weakest',
      Format('%d dBm', [Weak.RSSI]), Weak.SSID, False);
    Inc(X, CardW + Gap);
    DrawCard(C, Rect(X, Top, X + CardW, Top + CardH), 'Most congested', CongVal, 'busiest channel', False);
    Inc(X, CardW + Gap);
    DrawCard(C, Rect(X, Top, X + CardW, Top + CardH), 'Best channel', BestVal, '2.4 / 5 GHz', True);

    // Gauges (left half) + distributions (right half).
    Top := Margin + CardH + Gap + 8;
    GaugeRect := Rect(Margin, Top, Margin + (W - 2 * Margin) div 2 - Gap, H - Margin);
    DistRect := Rect(GaugeRect.Right + 2 * Gap, Top + 6, W - Margin, H - Margin);

    DrawGauge(C, Rect(GaugeRect.Left, GaugeRect.Top, (GaugeRect.Left + GaugeRect.Right) div 2, GaugeRect.Top + 180),
      FQualityDisplay, 'Connected signal', Format('%.0f%%', [FQualityDisplay]), True);
    DrawGauge(C, Rect((GaugeRect.Left + GaugeRect.Right) div 2, GaugeRect.Top, GaugeRect.Right, GaugeRect.Top + 180),
      FCongDisplay, 'Worst congestion', Format('%.0f', [FCongDisplay]), False);

    // Trend indicator for the connected network.
    if HasConn then
    begin
      Trend := FVM.History.TrendFor(AP.BSSID);
      if Trend > 1 then
      begin
        C.Font.Color := $004CAF50;
        TrendStr := Format('Signal trend:  improving  (+%.1f dBm)', [Trend]);
      end
      else if Trend < -1 then
      begin
        C.Font.Color := $004040F0;
        TrendStr := Format('Signal trend:  weakening  (%.1f dBm)', [Trend]);
      end
      else
      begin
        C.Font.Color := Theme.Color(trTextSecondary);
        TrendStr := 'Signal trend:  stable';
      end;
      C.Brush.Style := bsClear;
      C.Font.Style := [fsBold];
      C.Font.Height := -13;
      C.TextOut(GaugeRect.Left, GaugeRect.Top + 190, TrendStr);
      C.Font.Style := [];
      C.Brush.Style := bsSolid;
    end;

    DrawDistribution(C, DistRect);

    pbDash.Canvas.Draw(0, 0, Bmp);
  finally
    Bmp.Free;
  end;
end;

end.
