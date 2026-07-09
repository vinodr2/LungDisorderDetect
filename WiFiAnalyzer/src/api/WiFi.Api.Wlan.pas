unit WiFi.Api.Wlan;

{
  WiFi.Api.Wlan

  Thin, testable wrapper around the Native Wi-Fi API. All P/Invoke and struct
  marshaling lives here; the rest of the application depends only on the
  IWlanClient interface and the domain models in WiFi.Models.

  TWlanClient is the production implementation backed by wlanapi.dll.
  TFakeWlanClient returns canned data so the engine/service layers can be
  exercised without a radio (used by the DUnitX tests and by the UI in
  designer/preview scenarios).

  Threading: an IWlanClient instance is owned and used by a single thread
  (the scanner thread). It is not designed for concurrent access.
}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  Winapi.Windows,
  WiFi.Models, WiFi.Api.WlanTypes, WiFi.Engine.Channels;

type
  /// <summary>A WLAN adapter enumerated from the system.</summary>
  TWlanIface = record
    Guid: TGUID;
    Description: string;
    State: DWORD;
    function IsConnected: Boolean;
  end;

  /// <summary>Raised for any non-success WLAN API return code.</summary>
  EWlanError = class(Exception)
  private
    FCode: DWORD;
  public
    constructor Create(const AOperation: string; ACode: DWORD);
    property Code: DWORD read FCode;
  end;

  /// <summary>Abstraction over the WLAN API used by the service layer.</summary>
  IWlanClient = interface
    ['{2B0C6C1E-6C2A-4B0E-9A2E-9F1E0F7B3A11}']
    procedure Open;
    procedure Close;
    /// <summary>All wireless adapters currently present.</summary>
    function EnumInterfaces: TArray<TWlanIface>;
    /// <summary>Ask the adapter to (re)scan. Returns quickly; results arrive
    /// asynchronously and are read via GetAccessPoints.</summary>
    procedure Scan(const AIfaceGuid: TGUID);
    /// <summary>Build the current list of detected access points for an adapter.
    /// The caller owns and must Free the returned list.</summary>
    function GetAccessPoints(const AIfaceGuid: TGUID): TAccessPointList;
  end;

  /// <summary>Production IWlanClient backed by wlanapi.dll.</summary>
  TWlanClient = class(TInterfacedObject, IWlanClient)
  private
    FHandle: THandle;
    FOpen: Boolean;
    function ConnectedBssid(const AIfaceGuid: TGUID): string;
    procedure MergeAvailableNetworks(const AIfaceGuid: TGUID;
      AList: TAccessPointList);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Open;
    procedure Close;
    function EnumInterfaces: TArray<TWlanIface>;
    procedure Scan(const AIfaceGuid: TGUID);
    function GetAccessPoints(const AIfaceGuid: TGUID): TAccessPointList;
  end;

  /// <summary>In-memory IWlanClient returning canned data for tests/design.</summary>
  TFakeWlanClient = class(TInterfacedObject, IWlanClient)
  private
    FSeed: TAccessPointList;
  public
    constructor Create(ASeed: TAccessPointList = nil);
    destructor Destroy; override;
    procedure Open;
    procedure Close;
    function EnumInterfaces: TArray<TWlanIface>;
    procedure Scan(const AIfaceGuid: TGUID);
    function GetAccessPoints(const AIfaceGuid: TGUID): TAccessPointList;
  end;

// --- mapping helpers (exposed for unit testing) ------------------------------

function FormatBssid(const AMac: TDot11MacAddress): string;
function DecodeSsid(const ASsid: TDot11Ssid): string;
function MapPhy(APhy: DWORD): TPhyType;
function MapAuth(AAuth: DWORD): TAuthAlgorithm;
function MapCipher(ACipher: DWORD): TCipherAlgorithm;

implementation

{ EWlanError }

constructor EWlanError.Create(const AOperation: string; ACode: DWORD);
begin
  inherited CreateFmt('%s failed (WLAN error %u / 0x%.8x)', [AOperation, ACode, ACode]);
  FCode := ACode;
end;

{ TWlanIface }

function TWlanIface.IsConnected: Boolean;
begin
  Result := State = wlan_interface_state_connected;
end;

{ mapping helpers }

function FormatBssid(const AMac: TDot11MacAddress): string;
begin
  Result := Format('%.2X:%.2X:%.2X:%.2X:%.2X:%.2X',
    [AMac[0], AMac[1], AMac[2], AMac[3], AMac[4], AMac[5]]);
end;

function DecodeSsid(const ASsid: TDot11Ssid): string;
var
  Len: Integer;
  Bytes: TBytes;
begin
  Len := ASsid.uSSIDLength;
  if Len <= 0 then
    Exit('');
  if Len > DOT11_SSID_MAX_LENGTH then
    Len := DOT11_SSID_MAX_LENGTH;
  SetLength(Bytes, Len);
  Move(ASsid.ucSSID[0], Bytes[0], Len);
  // SSIDs are typically UTF-8; fall back to raw ANSI if invalid.
  try
    Result := TEncoding.UTF8.GetString(Bytes);
  except
    Result := TEncoding.ANSI.GetString(Bytes);
  end;
end;

function MapPhy(APhy: DWORD): TPhyType;
begin
  case APhy of
    dot11_phy_type_fhss:       Result := ptFHSS;
    dot11_phy_type_dsss:       Result := ptDSSS;
    dot11_phy_type_irbaseband: Result := ptIR;
    dot11_phy_type_ofdm:       Result := ptOFDM;
    dot11_phy_type_hrdsss:     Result := ptHRDSSS;
    dot11_phy_type_erp:        Result := ptERP;
    dot11_phy_type_ht:         Result := ptHT;
    dot11_phy_type_vht:        Result := ptVHT;
    dot11_phy_type_dmg:        Result := ptDMG;
    dot11_phy_type_he:         Result := ptHE;
    dot11_phy_type_eht:        Result := ptEHT;
  else
    Result := ptUnknown;
  end;
end;

function MapAuth(AAuth: DWORD): TAuthAlgorithm;
begin
  case AAuth of
    DOT11_AUTH_ALGO_80211_OPEN:       Result := aaOpen;
    DOT11_AUTH_ALGO_80211_SHARED_KEY: Result := aaSharedKey;
    DOT11_AUTH_ALGO_WPA:              Result := aaWPA;
    DOT11_AUTH_ALGO_WPA_PSK:          Result := aaWPAPSK;
    DOT11_AUTH_ALGO_WPA_NONE:         Result := aaWPANone;
    DOT11_AUTH_ALGO_RSNA:             Result := aaRSNA;
    DOT11_AUTH_ALGO_RSNA_PSK:         Result := aaRSNAPSK;
    DOT11_AUTH_ALGO_WPA3:             Result := aaWPA3;
    DOT11_AUTH_ALGO_WPA3_SAE:         Result := aaWPA3SAE;
    DOT11_AUTH_ALGO_OWE:              Result := aaOWE;
    DOT11_AUTH_ALGO_WPA3_ENT:         Result := aaWPA3Ent;
  else
    Result := aaUnknown;
  end;
end;

function MapCipher(ACipher: DWORD): TCipherAlgorithm;
begin
  case ACipher of
    DOT11_CIPHER_ALGO_NONE:     Result := caNone;
    DOT11_CIPHER_ALGO_WEP40:    Result := caWEP40;
    DOT11_CIPHER_ALGO_TKIP:     Result := caTKIP;
    DOT11_CIPHER_ALGO_CCMP:     Result := caCCMP;
    DOT11_CIPHER_ALGO_WEP104:   Result := caWEP104;
    DOT11_CIPHER_ALGO_BIP:      Result := caBIP;
    DOT11_CIPHER_ALGO_GCMP:     Result := caGCMP;
    DOT11_CIPHER_ALGO_GCMP_256: Result := caGCMP256;
    DOT11_CIPHER_ALGO_CCMP_256: Result := caCCMP256;
    DOT11_CIPHER_ALGO_WEP:      Result := caWEP;
  else
    Result := caUnknown;
  end;
end;

// Index a variable-length WLAN array using its fixed element stride.
function IfaceAt(AList: PWlanInterfaceInfoList; AIndex: Integer): PWlanInterfaceInfo; inline;
begin
  Result := PWlanInterfaceInfo(PByte(@AList.InterfaceInfo[0]) +
    NativeInt(AIndex) * SizeOf(TWlanInterfaceInfo));
end;

function BssAt(AList: PWlanBssList; AIndex: Integer): PWlanBssEntry; inline;
begin
  Result := PWlanBssEntry(PByte(@AList.wlanBssEntries[0]) +
    NativeInt(AIndex) * SizeOf(TWlanBssEntry));
end;

function NetworkAt(AList: PWlanAvailableNetworkList; AIndex: Integer): PWlanAvailableNetwork; inline;
begin
  Result := PWlanAvailableNetwork(PByte(@AList.Network[0]) +
    NativeInt(AIndex) * SizeOf(TWlanAvailableNetwork));
end;

{ TWlanClient }

constructor TWlanClient.Create;
begin
  inherited Create;
  FHandle := 0;
  FOpen := False;
end;

destructor TWlanClient.Destroy;
begin
  Close;
  inherited;
end;

procedure TWlanClient.Open;
var
  Negotiated: DWORD;
  Res: DWORD;
begin
  if FOpen then
    Exit;
  Res := WlanOpenHandle(WLAN_API_VERSION_2_0, nil, Negotiated, FHandle);
  if Res <> ERROR_SUCCESS then
    raise EWlanError.Create('WlanOpenHandle', Res);
  FOpen := True;
end;

procedure TWlanClient.Close;
begin
  if FOpen and (FHandle <> 0) then
    WlanCloseHandle(FHandle, nil);
  FHandle := 0;
  FOpen := False;
end;

function TWlanClient.EnumInterfaces: TArray<TWlanIface>;
var
  List: PWlanInterfaceInfoList;
  Res: DWORD;
  I: Integer;
  Info: PWlanInterfaceInfo;
begin
  Open;
  List := nil;
  Res := WlanEnumInterfaces(FHandle, nil, List);
  if Res <> ERROR_SUCCESS then
    raise EWlanError.Create('WlanEnumInterfaces', Res);
  try
    SetLength(Result, List.dwNumberOfItems);
    for I := 0 to Integer(List.dwNumberOfItems) - 1 do
    begin
      Info := IfaceAt(List, I);
      Result[I].Guid := Info.InterfaceGuid;
      Result[I].Description := WideCharToString(PWideChar(@Info.strInterfaceDescription[0]));
      Result[I].State := Info.isState;
    end;
  finally
    WlanFreeMemory(List);
  end;
end;

procedure TWlanClient.Scan(const AIfaceGuid: TGUID);
var
  Res: DWORD;
begin
  Open;
  // A nil SSID/IE requests a full scan of all networks.
  Res := WlanScan(FHandle, AIfaceGuid, nil, nil, nil);
  // ERROR_SUCCESS only means the request was queued. A busy adapter may return
  // a transient error; surface it so the service can log and keep going.
  if Res <> ERROR_SUCCESS then
    raise EWlanError.Create('WlanScan', Res);
end;

function TWlanClient.ConnectedBssid(const AIfaceGuid: TGUID): string;
var
  Res: DWORD;
  DataSize: DWORD;
  Data: Pointer;
  Conn: PWlanConnectionAttributes;
begin
  Result := '';
  Data := nil;
  Res := WlanQueryInterface(FHandle, AIfaceGuid, wlan_intf_opcode_current_connection,
    nil, DataSize, Data, nil);
  if (Res <> ERROR_SUCCESS) or (Data = nil) then
    Exit; // not connected, or query unsupported: leave blank
  try
    Conn := PWlanConnectionAttributes(Data);
    if Conn.isState = wlan_interface_state_connected then
      Result := FormatBssid(Conn.wlanAssociationAttributes.dot11Bssid);
  finally
    WlanFreeMemory(Data);
  end;
end;

procedure TWlanClient.MergeAvailableNetworks(const AIfaceGuid: TGUID;
  AList: TAccessPointList);
var
  NetList: PWlanAvailableNetworkList;
  Res: DWORD;
  I, J: Integer;
  Net: PWlanAvailableNetwork;
  BySsid: TDictionary<string, TWlanAvailableNetwork>;
  Ssid: string;
  AP: TAccessPoint;
  Info: TWlanAvailableNetwork;
begin
  NetList := nil;
  Res := WlanGetAvailableNetworkList(FHandle, AIfaceGuid,
    WLAN_AVAILABLE_NETWORK_INCLUDE_ALL_MANUAL_HIDDEN_PROFILES, nil, NetList);
  if (Res <> ERROR_SUCCESS) or (NetList = nil) then
    Exit; // security/auth info simply stays at defaults
  BySsid := TDictionary<string, TWlanAvailableNetwork>.Create;
  try
    for I := 0 to Integer(NetList.dwNumberOfItems) - 1 do
    begin
      Net := NetworkAt(NetList, I);
      Ssid := DecodeSsid(Net.dot11Ssid);
      BySsid.AddOrSetValue(Ssid, Net^);
    end;
    for J := 0 to AList.Count - 1 do
    begin
      AP := AList[J];
      if BySsid.TryGetValue(AP.SSID, Info) then
      begin
        AP.SecurityEnabled := Info.bSecurityEnabled;
        AP.Auth := MapAuth(Info.dot11DefaultAuthAlgorithm);
        AP.Cipher := MapCipher(Info.dot11DefaultCipherAlgorithm);
        if AP.Quality = 0 then
          AP.Quality := Info.wlanSignalQuality;
        AList[J] := AP;
      end;
    end;
  finally
    BySsid.Free;
    WlanFreeMemory(NetList);
  end;
end;

function TWlanClient.GetAccessPoints(const AIfaceGuid: TGUID): TAccessPointList;
var
  BssList: PWlanBssList;
  Res: DWORD;
  I: Integer;
  Entry: PWlanBssEntry;
  AP: TAccessPoint;
  ConnBssid: string;
  NowTs: TDateTime;
begin
  Open;
  Result := TAccessPointList.Create;
  BssList := nil;
  Res := WlanGetNetworkBssList(FHandle, AIfaceGuid, nil, dot11_BSS_type_any,
    False, nil, BssList);
  if (Res <> ERROR_SUCCESS) or (BssList = nil) then
  begin
    if Res <> ERROR_SUCCESS then
      raise EWlanError.Create('WlanGetNetworkBssList', Res);
    Exit;
  end;
  try
    ConnBssid := ConnectedBssid(AIfaceGuid);
    NowTs := Now;
    for I := 0 to Integer(BssList.dwNumberOfItems) - 1 do
    begin
      Entry := BssAt(BssList, I);
      // Default() correctly finalizes managed fields between iterations
      // (FillChar would leak the previous row's string references).
      AP := Default(TAccessPoint);
      AP.SSID := DecodeSsid(Entry.dot11Ssid);
      AP.BSSID := FormatBssid(Entry.dot11Bssid);
      AP.Vendor := '';
      AP.FrequencyMHz := Integer(Entry.ulChCenterFrequency) div 1000;
      AP.Band := BandOfFrequency(AP.FrequencyMHz);
      AP.Channel := FrequencyToChannel(AP.FrequencyMHz);
      AP.Width := cwUnknown; // requires HT/VHT/HE IE parsing (later phase)
      AP.RSSI := Entry.lRssi;
      AP.Quality := Entry.uLinkQuality;
      AP.Phy := MapPhy(Entry.dot11BssPhyType);
      AP.Auth := aaUnknown;
      AP.Cipher := caUnknown;
      AP.SecurityEnabled := (Entry.usCapabilityInformation and $0010) <> 0; // Privacy bit
      AP.Hidden := AP.SSID = '';
      AP.Connected := (ConnBssid <> '') and SameText(ConnBssid, AP.BSSID);
      AP.FirstSeen := NowTs;
      AP.LastSeen := NowTs;
      Result.Add(AP);
    end;
  finally
    WlanFreeMemory(BssList);
  end;
  // Enrich with auth/cipher/quality from the available-network list.
  MergeAvailableNetworks(AIfaceGuid, Result);
end;

{ TFakeWlanClient }

constructor TFakeWlanClient.Create(ASeed: TAccessPointList);
begin
  inherited Create;
  FSeed := ASeed; // takes ownership if provided
end;

destructor TFakeWlanClient.Destroy;
begin
  FSeed.Free;
  inherited;
end;

procedure TFakeWlanClient.Open;
begin
end;

procedure TFakeWlanClient.Close;
begin
end;

function TFakeWlanClient.EnumInterfaces: TArray<TWlanIface>;
begin
  SetLength(Result, 1);
  Result[0].Guid := TGUID.Empty;
  Result[0].Description := 'Fake Wi-Fi Adapter';
  Result[0].State := wlan_interface_state_connected;
end;

procedure TFakeWlanClient.Scan(const AIfaceGuid: TGUID);
begin
end;

function TFakeWlanClient.GetAccessPoints(const AIfaceGuid: TGUID): TAccessPointList;
var
  AP: TAccessPoint;
begin
  Result := TAccessPointList.Create;
  if FSeed <> nil then
  begin
    for AP in FSeed do
      Result.Add(AP);
  end;
end;

end.
