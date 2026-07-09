unit WiFi.Util.Format;

{
  WiFi.Util.Format

  Small presentation helpers shared by the view-model and UI: signal strength
  formatting and a coarse RSSI-to-quality classification used for colour
  coding. Pure functions, no VCL dependency.
}

interface

type
  /// <summary>Coarse signal band used to colour rows/bars.</summary>
  TSignalGrade = (sgNone, sgWeak, sgFair, sgGood, sgExcellent);

/// <summary>Format an RSSI in dBm, e.g. "-63 dBm".</summary>
function FormatRssi(ARssi: Integer): string;

/// <summary>Classify an RSSI (dBm) into a coarse quality grade.</summary>
function GradeOfRssi(ARssi: Integer): TSignalGrade;

/// <summary>Map an RSSI (dBm) to an approximate 0..100 quality percent.</summary>
function RssiToQuality(ARssi: Integer): Integer;

implementation

uses
  System.SysUtils, System.Math;

function FormatRssi(ARssi: Integer): string;
begin
  Result := Format('%d dBm', [ARssi]);
end;

function GradeOfRssi(ARssi: Integer): TSignalGrade;
begin
  if ARssi >= -50 then
    Result := sgExcellent
  else if ARssi >= -60 then
    Result := sgGood
  else if ARssi >= -70 then
    Result := sgFair
  else if ARssi >= -80 then
    Result := sgWeak
  else
    Result := sgNone;
end;

function RssiToQuality(ARssi: Integer): Integer;
begin
  // Standard Microsoft mapping: -50 dBm or better => 100%, -100 dBm => 0%.
  if ARssi <= -100 then
    Result := 0
  else if ARssi >= -50 then
    Result := 100
  else
    Result := 2 * (ARssi + 100);
  Result := EnsureRange(Result, 0, 100);
end;

end.
