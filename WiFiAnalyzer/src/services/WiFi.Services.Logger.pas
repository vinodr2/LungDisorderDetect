unit WiFi.Services.Logger;

{
  WiFi.Services.Logger

  Minimal, thread-safe application logger. A single process-wide instance is
  exposed via the Log function. Messages are appended to a daily file next to
  the executable and, in debug builds, mirrored to OutputDebugString.

  The logger never raises: logging failures must not take down a scan.
}

interface

type
  TLogLevel = (llDebug, llInfo, llWarn, llError);

  ILogger = interface
    ['{7A3D5F41-1C9E-4B2A-8D6F-0E2B4C7A9D31}']
    procedure Write(ALevel: TLogLevel; const AMessage: string);
    procedure Debug(const AMessage: string);
    procedure Info(const AMessage: string);
    procedure Warn(const AMessage: string);
    procedure Error(const AMessage: string);
  end;

/// <summary>Process-wide logger singleton.</summary>
function Log: ILogger;

implementation

uses
  System.SysUtils, System.IOUtils, System.SyncObjs, Winapi.Windows;

type
  TFileLogger = class(TInterfacedObject, ILogger)
  private
    FLock: TCriticalSection;
    FFolder: string;
    function FileForToday: string;
    class function LevelStr(ALevel: TLogLevel): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Write(ALevel: TLogLevel; const AMessage: string);
    procedure Debug(const AMessage: string);
    procedure Info(const AMessage: string);
    procedure Warn(const AMessage: string);
    procedure Error(const AMessage: string);
  end;

var
  GLogger: ILogger = nil;
  GLoggerLock: TCriticalSection = nil;

{ TFileLogger }

constructor TFileLogger.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FFolder := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'logs');
end;

destructor TFileLogger.Destroy;
begin
  FLock.Free;
  inherited;
end;

class function TFileLogger.LevelStr(ALevel: TLogLevel): string;
begin
  case ALevel of
    llDebug: Result := 'DEBUG';
    llInfo:  Result := 'INFO ';
    llWarn:  Result := 'WARN ';
    llError: Result := 'ERROR';
  else
    Result := '?????';
  end;
end;

function TFileLogger.FileForToday: string;
begin
  Result := TPath.Combine(FFolder,
    'wifianalyzer-' + FormatDateTime('yyyymmdd', Now) + '.log');
end;

procedure TFileLogger.Write(ALevel: TLogLevel; const AMessage: string);
var
  Line: string;
begin
  Line := Format('%s [%s] %s',
    [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), LevelStr(ALevel), AMessage]);
  {$IFDEF DEBUG}
  OutputDebugString(PChar(Line));
  {$ENDIF}
  FLock.Enter;
  try
    try
      if not TDirectory.Exists(FFolder) then
        TDirectory.CreateDirectory(FFolder);
      TFile.AppendAllText(FileForToday, Line + sLineBreak, TEncoding.UTF8);
    except
      // Logging must never propagate an exception.
    end;
  finally
    FLock.Leave;
  end;
end;

procedure TFileLogger.Debug(const AMessage: string);
begin
  Write(llDebug, AMessage);
end;

procedure TFileLogger.Info(const AMessage: string);
begin
  Write(llInfo, AMessage);
end;

procedure TFileLogger.Warn(const AMessage: string);
begin
  Write(llWarn, AMessage);
end;

procedure TFileLogger.Error(const AMessage: string);
begin
  Write(llError, AMessage);
end;

function Log: ILogger;
begin
  if GLogger = nil then
  begin
    GLoggerLock.Enter;
    try
      if GLogger = nil then
        GLogger := TFileLogger.Create;
    finally
      GLoggerLock.Leave;
    end;
  end;
  Result := GLogger;
end;

initialization
  GLoggerLock := TCriticalSection.Create;

finalization
  GLogger := nil;
  GLoggerLock.Free;

end.
