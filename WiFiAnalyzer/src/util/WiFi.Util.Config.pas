unit WiFi.Util.Config;

{
  WiFi.Util.Config

  Loads and persists user preferences (scan interval, dark mode) to an INI file
  in the per-user AppData folder. Kept deliberately tiny; later phases add more
  keys without changing the call sites.
}

interface

type
  TAppConfig = class
  private
    FFileName: string;
    FScanIntervalMs: Integer;
    FDarkMode: Boolean;
  public
    constructor Create;
    procedure Load;
    procedure Save;
    property ScanIntervalMs: Integer read FScanIntervalMs write FScanIntervalMs;
    property DarkMode: Boolean read FDarkMode write FDarkMode;
  end;

implementation

uses
  System.SysUtils, System.IOUtils, System.IniFiles;

const
  SECTION_GENERAL = 'General';

{ TAppConfig }

constructor TAppConfig.Create;
var
  Folder: string;
begin
  inherited Create;
  Folder := TPath.Combine(TPath.GetHomePath, 'WiFiAnalyzer');
  if not TDirectory.Exists(Folder) then
    TDirectory.CreateDirectory(Folder);
  FFileName := TPath.Combine(Folder, 'settings.ini');
  FScanIntervalMs := 5000;
  FDarkMode := False;
end;

procedure TAppConfig.Load;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(FFileName);
  try
    FScanIntervalMs := Ini.ReadInteger(SECTION_GENERAL, 'ScanIntervalMs', FScanIntervalMs);
    FDarkMode := Ini.ReadBool(SECTION_GENERAL, 'DarkMode', FDarkMode);
  finally
    Ini.Free;
  end;
end;

procedure TAppConfig.Save;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(FFileName);
  try
    Ini.WriteInteger(SECTION_GENERAL, 'ScanIntervalMs', FScanIntervalMs);
    Ini.WriteBool(SECTION_GENERAL, 'DarkMode', FDarkMode);
  finally
    Ini.Free;
  end;
end;

end.
