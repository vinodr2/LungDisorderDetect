program WiFiAnalyzerTests;

{
  DUnitX console test runner for the WiFiAnalyzer engine layer.

  Requires the DUnitX framework that ships with Delphi 12 (search path is set
  automatically by the IDE). Build as a Win64 console app and run to exercise
  the channel maths, RF analysis and the fake WLAN client - no radio needed.
}

{$IFNDEF TESTINSIGHT}
{$APPTYPE CONSOLE}
{$ENDIF}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  {$IFDEF TESTINSIGHT}
  TestInsight.DUnitX,
  {$ENDIF }
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  WiFi.Models in '..\src\models\WiFi.Models.pas',
  WiFi.Api.WlanTypes in '..\src\api\WiFi.Api.WlanTypes.pas',
  WiFi.Api.Wlan in '..\src\api\WiFi.Api.Wlan.pas',
  WiFi.Engine.Channels in '..\src\engine\WiFi.Engine.Channels.pas',
  WiFi.Engine.Analysis in '..\src\engine\WiFi.Engine.Analysis.pas',
  WiFi.Services.History in '..\src\services\WiFi.Services.History.pas',
  WiFi.Services.Export in '..\src\services\WiFi.Services.Export.pas',
  WiFi.ViewModels.Main in '..\src\viewmodels\WiFi.ViewModels.Main.pas',
  WiFi.Tests.Engine in 'WiFi.Tests.Engine.pas';

var
  Runner: ITestRunner;
  Results: IRunResults;
  Logger: ITestLogger;
begin
  try
    {$IFDEF TESTINSIGHT}
    TestInsight.DUnitX.RunRegisteredTests;
    {$ELSE}
    TDUnitX.CheckCommandLine;
    Runner := TDUnitX.CreateRunner;
    Runner.UseRTTI := True;
    Runner.FailsOnNoAsserts := False;
    Logger := TDUnitXConsoleLogger.Create(True);
    Runner.AddLogger(Logger);
    Results := Runner.Execute;
    if not Results.AllPassed then
      System.ExitCode := EXIT_ERRORS;
    {$IFNDEF CI}
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      System.Write('Done.. press <Enter> key to quit.');
      System.Readln;
    end;
    {$ENDIF}
    {$ENDIF}
  except
    on E: Exception do
      System.Writeln(E.ClassName, ': ', E.Message);
  end;
end.
