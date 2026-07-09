unit WiFi.Engine.Channels;

{
  WiFi.Engine.Channels

  Pure, stateless conversions between center frequency, channel number and
  band for the 2.4 GHz, 5 GHz and 6 GHz Wi-Fi bands, plus the frequency span a
  channel occupies for overlap analysis. No external dependencies, so this unit
  is fully unit-testable off Windows.

  Frequency inputs are in MHz. The WLAN API reports kHz; callers convert once
  at the boundary (see WiFi.Api.Wlan).
}

interface

uses
  WiFi.Models;

type
  /// <summary>The [low, high] frequency span (MHz) a channel occupies.</summary>
  TFreqRange = record
    LowMHz: Integer;
    HighMHz: Integer;
    function Overlaps(const AOther: TFreqRange): Boolean;
    function IsEmpty: Boolean;
  end;

/// <summary>Classify a center frequency (MHz) into a band.</summary>
function BandOfFrequency(AFreqMHz: Integer): TWiFiBand;

/// <summary>
///  Convert a center frequency (MHz) to a logical channel number.
///  Returns 0 when the frequency is not a recognised Wi-Fi channel.
/// </summary>
function FrequencyToChannel(AFreqMHz: Integer): Integer;

/// <summary>
///  Convert a channel number + band back to its center frequency (MHz).
///  Returns 0 when the pairing is invalid.
/// </summary>
function ChannelToFrequency(AChannel: Integer; ABand: TWiFiBand): Integer;

/// <summary>
///  The frequency span occupied by a channel of the given width, centered on
///  AFreqMHz. When AWidth is cwUnknown a 20 MHz span is assumed.
/// </summary>
function ChannelSpan(AFreqMHz: Integer; AWidth: TChannelWidth): TFreqRange;

/// <summary>Bandwidth in MHz for a channel-width enum (0 when unknown).</summary>
function WidthToMHz(AWidth: TChannelWidth): Integer;

implementation

{ TFreqRange }

function TFreqRange.IsEmpty: Boolean;
begin
  Result := (LowMHz = 0) and (HighMHz = 0);
end;

function TFreqRange.Overlaps(const AOther: TFreqRange): Boolean;
begin
  if IsEmpty or AOther.IsEmpty then
    Exit(False);
  // Two ranges overlap unless one ends before the other begins.
  Result := (LowMHz < AOther.HighMHz) and (AOther.LowMHz < HighMHz);
end;

function BandOfFrequency(AFreqMHz: Integer): TWiFiBand;
begin
  if (AFreqMHz >= 2401) and (AFreqMHz <= 2495) then
    Result := wb24GHz
  else if (AFreqMHz >= 5150) and (AFreqMHz <= 5895) then
    Result := wb5GHz
  else if (AFreqMHz >= 5925) and (AFreqMHz <= 7125) then
    Result := wb6GHz
  else
    Result := wbUnknown;
end;

function FrequencyToChannel(AFreqMHz: Integer): Integer;
begin
  Result := 0;
  case BandOfFrequency(AFreqMHz) of
    wb24GHz:
      begin
        if AFreqMHz = 2484 then
          Result := 14  // Japan-only channel, spaced differently
        else if (AFreqMHz >= 2412) and (AFreqMHz <= 2472) then
          Result := (AFreqMHz - 2407) div 5;  // ch1..13 spaced 5 MHz
      end;
    wb5GHz:
      // 5 GHz channels are centered on 5000 + 5*n.
      Result := (AFreqMHz - 5000) div 5;
    wb6GHz:
      // 6 GHz (UNII-5..8): channel 1 centered at 5955, then +5 MHz per 4 chans.
      Result := (AFreqMHz - 5950) div 5;
  end;
  if Result < 0 then
    Result := 0;
end;

function ChannelToFrequency(AChannel: Integer; ABand: TWiFiBand): Integer;
begin
  Result := 0;
  case ABand of
    wb24GHz:
      if AChannel = 14 then
        Result := 2484
      else if (AChannel >= 1) and (AChannel <= 13) then
        Result := 2407 + AChannel * 5;
    wb5GHz:
      if (AChannel >= 1) and (AChannel <= 196) then
        Result := 5000 + AChannel * 5;
    wb6GHz:
      if (AChannel >= 1) and (AChannel <= 233) then
        Result := 5950 + AChannel * 5;
  end;
end;

function WidthToMHz(AWidth: TChannelWidth): Integer;
begin
  case AWidth of
    cw20:  Result := 20;
    cw40:  Result := 40;
    cw80:  Result := 80;
    cw160: Result := 160;
    cw320: Result := 320;
  else
    Result := 0;
  end;
end;

function ChannelSpan(AFreqMHz: Integer; AWidth: TChannelWidth): TFreqRange;
var
  HalfWidth: Integer;
begin
  HalfWidth := WidthToMHz(AWidth) div 2;
  if HalfWidth = 0 then
    HalfWidth := 10; // default to 20 MHz occupancy
  Result.LowMHz := AFreqMHz - HalfWidth;
  Result.HighMHz := AFreqMHz + HalfWidth;
end;

end.
