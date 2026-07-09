program WiFiAnalyzer;

{
  WiFiAnalyzer - a Windows-only Wi-Fi Analyzer built in Delphi 12 VCL.

  Discovers nearby wireless networks through the native Windows WLAN API,
  runs an RF analysis engine and presents a real-time dashboard. See
  docs/ARCHITECTURE.md for the layering and README.md for build instructions.

  Phase 1: WLAN wrapper, models, channel/analysis engine, scanner service,
  view-model and a live networks grid.
}

uses
  Vcl.Forms,
  Vcl.Themes,
  Vcl.Styles,
  WiFi.Models in 'src\models\WiFi.Models.pas',
  WiFi.Api.WlanTypes in 'src\api\WiFi.Api.WlanTypes.pas',
  WiFi.Api.Wlan in 'src\api\WiFi.Api.Wlan.pas',
  WiFi.Engine.Channels in 'src\engine\WiFi.Engine.Channels.pas',
  WiFi.Engine.Analysis in 'src\engine\WiFi.Engine.Analysis.pas',
  WiFi.Services.Logger in 'src\services\WiFi.Services.Logger.pas',
  WiFi.Services.Oui in 'src\services\WiFi.Services.Oui.pas',
  WiFi.Services.Scanner in 'src\services\WiFi.Services.Scanner.pas',
  WiFi.Util.Format in 'src\util\WiFi.Util.Format.pas',
  WiFi.Util.Config in 'src\util\WiFi.Util.Config.pas',
  WiFi.ViewModels.Main in 'src\viewmodels\WiFi.ViewModels.Main.pas',
  WiFi.UI.Main in 'src\ui\WiFi.UI.Main.pas' {frmMain};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'Wi-Fi Analyzer';
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
