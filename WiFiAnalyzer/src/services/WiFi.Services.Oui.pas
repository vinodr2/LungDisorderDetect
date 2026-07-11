unit WiFi.Services.Oui;

{
  WiFi.Services.Oui

  Resolves the manufacturer (vendor) of an access point from the OUI - the
  first three octets of its BSSID/MAC. The mapping is loaded once from the
  bundled resources/oui.txt (tab- or space-separated "AABBCC<TAB>Vendor").

  The lookup is read-only after load and therefore safe to call from the
  scanner thread without locking.
}

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  IOuiVendorService = interface
    ['{9F1B2C3D-4E5F-4A6B-8C7D-0E1F2A3B4C5D}']
    /// <summary>Vendor for a full BSSID string ("AA:BB:CC:DD:EE:FF").
    /// Returns '' when unknown.</summary>
    function LookupByBssid(const ABssid: string): string;
    /// <summary>Number of OUI prefixes currently loaded.</summary>
    function Count: Integer;
  end;

  TOuiVendorService = class(TInterfacedObject, IOuiVendorService)
  private
    FMap: TDictionary<string, string>; // key = 6 hex chars, upper-case
    class function NormalizePrefix(const ABssid: string): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Load OUI data from a file; missing file is not an error.</summary>
    procedure LoadFromFile(const AFileName: string);
    function LookupByBssid(const ABssid: string): string;
    function Count: Integer;
  end;

implementation

uses
  System.Classes, System.IOUtils, System.Character,
  WiFi.Services.Logger;

{ TOuiVendorService }

constructor TOuiVendorService.Create;
begin
  inherited Create;
  FMap := TDictionary<string, string>.Create;
end;

destructor TOuiVendorService.Destroy;
begin
  FMap.Free;
  inherited;
end;

class function TOuiVendorService.NormalizePrefix(const ABssid: string): string;
var
  C: Char;
begin
  // Keep the first six hex digits, ignoring ':' '-' '.' separators.
  Result := '';
  for C in ABssid do
  begin
    if C.IsLetterOrDigit then
    begin
      Result := Result + UpCase(C);
      if Length(Result) = 6 then
        Break;
    end;
  end;
end;

procedure TOuiVendorService.LoadFromFile(const AFileName: string);
var
  Reader: TStreamReader;
  Line, Prefix, Vendor: string;
  TabPos: Integer;
begin
  if not TFile.Exists(AFileName) then
  begin
    Log.Warn('OUI file not found: ' + AFileName);
    Exit;
  end;
  try
    Reader := TStreamReader.Create(AFileName, TEncoding.UTF8);
    try
      while not Reader.EndOfStream do
      begin
        Line := Reader.ReadLine.Trim;
        if (Line = '') or Line.StartsWith('#') then
          Continue;
        // Split on the first whitespace/tab run.
        TabPos := Line.IndexOfAny([#9, ' ']);
        if TabPos <= 0 then
          Continue;
        Prefix := NormalizePrefix(Line.Substring(0, TabPos));
        Vendor := Line.Substring(TabPos + 1).Trim;
        if (Length(Prefix) = 6) and (Vendor <> '') then
          FMap.AddOrSetValue(Prefix, Vendor);
      end;
    finally
      Reader.Free;
    end;
    Log.Info(Format('Loaded %d OUI prefixes from %s', [FMap.Count, AFileName]));
  except
    on E: Exception do
      Log.Error('Failed to load OUI file: ' + E.Message);
  end;
end;

function TOuiVendorService.LookupByBssid(const ABssid: string): string;
var
  Prefix: string;
begin
  Prefix := NormalizePrefix(ABssid);
  if not FMap.TryGetValue(Prefix, Result) then
    Result := '';
end;

function TOuiVendorService.Count: Integer;
begin
  Result := FMap.Count;
end;

end.
