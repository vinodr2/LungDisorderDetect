unit WiFi.Models;

{
  WiFi.Models

  Plain domain model types shared across every layer. These types carry no
  behaviour beyond trivial helpers and have no dependency on the VCL or on the
  WLAN API, so they can be constructed in tests without a live radio.
}

interface

uses
  System.SysUtils, System.Generics.Collections;

type
  /// <summary>Radio frequency band an access point operates in.</summary>
  TWiFiBand = (wbUnknown, wb24GHz, wb5GHz, wb6GHz);

  /// <summary>802.11 PHY type, mapped from DOT11_PHY_TYPE.</summary>
  TPhyType = (ptUnknown, ptFHSS, ptDSSS, ptIR, ptOFDM, ptHRDSSS, ptERP,
    ptHT {11n}, ptVHT {11ac}, ptDMG {11ad}, ptHE {11ax}, ptEHT {11be});

  /// <summary>Authentication algorithm, mapped from DOT11_AUTH_ALGORITHM.</summary>
  TAuthAlgorithm = (aaUnknown, aaOpen, aaSharedKey, aaWPA, aaWPAPSK, aaWPANone,
    aaRSNA, aaRSNAPSK, aaWPA3, aaWPA3SAE, aaOWE, aaWPA3Ent);

  /// <summary>Cipher algorithm, mapped from DOT11_CIPHER_ALGORITHM.</summary>
  TCipherAlgorithm = (caUnknown, caNone, caWEP40, caTKIP, caCCMP, caWEP104,
    caBIP, caGCMP, caGCMP256, caCCMP256, caWEP);

  /// <summary>Channel bandwidth in MHz. cwUnknown when not derivable.</summary>
  TChannelWidth = (cwUnknown, cw20, cw40, cw80, cw160, cw320);

  /// <summary>
  ///  A single detected BSS (one radio/BSSID of a Wi-Fi network). Value-style
  ///  record: copying it produces an independent snapshot row.
  /// </summary>
  TAccessPoint = record
    SSID: string;              // may be empty for hidden networks
    BSSID: string;             // formatted MAC, e.g. "AA:BB:CC:DD:EE:FF"
    Vendor: string;            // resolved from the OUI, may be empty
    Channel: Integer;          // logical channel number
    FrequencyMHz: Integer;     // center frequency
    Band: TWiFiBand;
    Width: TChannelWidth;
    RSSI: Integer;             // dBm (negative)
    Quality: Integer;          // 0..100
    Phy: TPhyType;
    Auth: TAuthAlgorithm;
    Cipher: TCipherAlgorithm;
    SecurityEnabled: Boolean;
    Connected: Boolean;
    Hidden: Boolean;
    FirstSeen: TDateTime;
    LastSeen: TDateTime;
    /// <summary>True when this is a real, populated row.</summary>
    function IsValid: Boolean;
  end;

  TAccessPointList = TList<TAccessPoint>;

  /// <summary>
  ///  Immutable result of one scan pass. The owning list is transferred to the
  ///  snapshot; callers must Free the snapshot (which frees the list).
  /// </summary>
  TScanSnapshot = class
  private
    FItems: TAccessPointList;
    FTimestamp: TDateTime;
    FAdapterName: string;
  public
    constructor Create(AItems: TAccessPointList; const AAdapterName: string);
    destructor Destroy; override;
    property Items: TAccessPointList read FItems;
    property Timestamp: TDateTime read FTimestamp;
    property AdapterName: string read FAdapterName;
    function Count: Integer;
  end;

// --- display helpers ---------------------------------------------------------

function BandToStr(ABand: TWiFiBand): string;
function PhyToStr(APhy: TPhyType): string;
function AuthToStr(AAuth: TAuthAlgorithm): string;
function CipherToStr(ACipher: TCipherAlgorithm): string;
function ChannelWidthToStr(AWidth: TChannelWidth): string;
/// <summary>Human-readable security summary combining auth + cipher.</summary>
function SecurityToStr(const AAP: TAccessPoint): string;

implementation

{ TAccessPoint }

function TAccessPoint.IsValid: Boolean;
begin
  Result := BSSID <> '';
end;

{ TScanSnapshot }

constructor TScanSnapshot.Create(AItems: TAccessPointList; const AAdapterName: string);
begin
  inherited Create;
  if AItems <> nil then
    FItems := AItems
  else
    FItems := TAccessPointList.Create;
  FAdapterName := AAdapterName;
  FTimestamp := Now;
end;

destructor TScanSnapshot.Destroy;
begin
  FItems.Free;
  inherited;
end;

function TScanSnapshot.Count: Integer;
begin
  Result := FItems.Count;
end;

{ helpers }

function BandToStr(ABand: TWiFiBand): string;
begin
  case ABand of
    wb24GHz: Result := '2.4 GHz';
    wb5GHz:  Result := '5 GHz';
    wb6GHz:  Result := '6 GHz';
  else
    Result := 'Unknown';
  end;
end;

function PhyToStr(APhy: TPhyType): string;
begin
  case APhy of
    ptFHSS:   Result := 'FHSS';
    ptDSSS:   Result := 'DSSS';
    ptIR:     Result := 'IR';
    ptOFDM:   Result := '802.11a';
    ptHRDSSS: Result := '802.11b';
    ptERP:    Result := '802.11g';
    ptHT:     Result := '802.11n';
    ptVHT:    Result := '802.11ac';
    ptDMG:    Result := '802.11ad';
    ptHE:     Result := '802.11ax';
    ptEHT:    Result := '802.11be';
  else
    Result := 'Unknown';
  end;
end;

function AuthToStr(AAuth: TAuthAlgorithm): string;
begin
  case AAuth of
    aaOpen:      Result := 'Open';
    aaSharedKey: Result := 'Shared';
    aaWPA:       Result := 'WPA-Enterprise';
    aaWPAPSK:    Result := 'WPA-Personal';
    aaWPANone:   Result := 'WPA-None';
    aaRSNA:      Result := 'WPA2-Enterprise';
    aaRSNAPSK:   Result := 'WPA2-Personal';
    aaWPA3:      Result := 'WPA3';
    aaWPA3SAE:   Result := 'WPA3-Personal';
    aaOWE:       Result := 'OWE';
    aaWPA3Ent:   Result := 'WPA3-Enterprise';
  else
    Result := 'Unknown';
  end;
end;

function CipherToStr(ACipher: TCipherAlgorithm): string;
begin
  case ACipher of
    caNone:    Result := 'None';
    caWEP40:   Result := 'WEP-40';
    caTKIP:    Result := 'TKIP';
    caCCMP:    Result := 'AES-CCMP';
    caWEP104:  Result := 'WEP-104';
    caBIP:     Result := 'BIP';
    caGCMP:    Result := 'GCMP';
    caGCMP256: Result := 'GCMP-256';
    caCCMP256: Result := 'CCMP-256';
    caWEP:     Result := 'WEP';
  else
    Result := 'Unknown';
  end;
end;

function ChannelWidthToStr(AWidth: TChannelWidth): string;
begin
  case AWidth of
    cw20:  Result := '20 MHz';
    cw40:  Result := '40 MHz';
    cw80:  Result := '80 MHz';
    cw160: Result := '160 MHz';
    cw320: Result := '320 MHz';
  else
    Result := '';
  end;
end;

function SecurityToStr(const AAP: TAccessPoint): string;
begin
  if not AAP.SecurityEnabled then
    Exit('Open');
  Result := AuthToStr(AAP.Auth);
  if AAP.Cipher <> caUnknown then
    Result := Result + ' / ' + CipherToStr(AAP.Cipher);
end;

end.
