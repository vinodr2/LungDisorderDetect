unit WiFi.Api.WlanTypes;

{
  WiFi.Api.WlanTypes

  Pascal translations of the Native Wi-Fi (WLAN) API structures, enumerations
  and constants exported by wlanapi.dll, plus the external function
  declarations used by the wrapper in WiFi.Api.Wlan.

  Reference: Windows SDK header <wlanapi.h> and <windot11.h>.

  IMPORTANT (marshaling):
    * These records are declared with 8-byte alignment ({$ALIGN 8}) so their
      layout matches the C default alignment used by wlanapi.dll on both Win64
      and Win32. Do NOT mark them "packed".
    * C enums are 4 bytes. To avoid any dependency on the compiler's enum-size
      setting, the WLAN enum-typed fields are declared as DWORD and paired with
      named constants below.
    * Every buffer returned through a P... out-parameter is owned by the WLAN
      service and MUST be released with WlanFreeMemory.

  This unit is Windows-only.
}

interface

{$ALIGN 8}
{$MINENUMSIZE 4}

uses
  Winapi.Windows;

const
  WLANAPI_DLL = 'wlanapi.dll';

  // Client version negotiated with WlanOpenHandle. 2 == Windows Vista+.
  WLAN_API_VERSION_2_0 = 2;

  // Fixed-size array bounds taken from the SDK headers.
  DOT11_SSID_MAX_LENGTH      = 32;
  DOT11_RATE_SET_MAX_LENGTH  = 126;
  WLAN_MAX_NAME_LENGTH       = 256;
  WLAN_MAX_PHY_TYPE_NUMBER   = 8;

  // Success code shared by all wlanapi.dll entry points.
  ERROR_SUCCESS_WLAN = ERROR_SUCCESS;

  // Flags for WlanGetAvailableNetworkList.
  WLAN_AVAILABLE_NETWORK_INCLUDE_ALL_ADHOC_PROFILES = $00000001;
  WLAN_AVAILABLE_NETWORK_INCLUDE_ALL_MANUAL_HIDDEN_PROFILES = $00000002;

  // WLAN_AVAILABLE_NETWORK.dwFlags bits.
  WLAN_AVAILABLE_NETWORK_CONNECTED = $00000001;
  WLAN_AVAILABLE_NETWORK_HAS_PROFILE = $00000002;

  // DOT11_BSS_TYPE values.
  dot11_BSS_type_infrastructure = 1;
  dot11_BSS_type_independent     = 2;
  dot11_BSS_type_any             = 3;

  // WLAN_INTF_OPCODE values (subset).
  wlan_intf_opcode_current_connection = 7;

  // DOT11_PHY_TYPE values.
  dot11_phy_type_unknown     = 0;
  dot11_phy_type_any         = 0;
  dot11_phy_type_fhss        = 1;
  dot11_phy_type_dsss        = 2;
  dot11_phy_type_irbaseband  = 3;
  dot11_phy_type_ofdm        = 4;   // 802.11a
  dot11_phy_type_hrdsss      = 5;   // 802.11b
  dot11_phy_type_erp         = 6;   // 802.11g
  dot11_phy_type_ht          = 7;   // 802.11n
  dot11_phy_type_vht         = 8;   // 802.11ac
  dot11_phy_type_dmg         = 9;   // 802.11ad
  dot11_phy_type_he          = 10;  // 802.11ax
  dot11_phy_type_eht         = 11;  // 802.11be

  // DOT11_AUTH_ALGORITHM values.
  DOT11_AUTH_ALGO_80211_OPEN        = 1;
  DOT11_AUTH_ALGO_80211_SHARED_KEY  = 2;
  DOT11_AUTH_ALGO_WPA               = 3;
  DOT11_AUTH_ALGO_WPA_PSK           = 4;
  DOT11_AUTH_ALGO_WPA_NONE          = 5;
  DOT11_AUTH_ALGO_RSNA              = 6;
  DOT11_AUTH_ALGO_RSNA_PSK          = 7;
  DOT11_AUTH_ALGO_WPA3              = 8;
  DOT11_AUTH_ALGO_WPA3_SAE          = 9;
  DOT11_AUTH_ALGO_OWE               = 10;
  DOT11_AUTH_ALGO_WPA3_ENT          = 11;

  // DOT11_CIPHER_ALGORITHM values.
  DOT11_CIPHER_ALGO_NONE           = $00;
  DOT11_CIPHER_ALGO_WEP40          = $01;
  DOT11_CIPHER_ALGO_TKIP           = $02;
  DOT11_CIPHER_ALGO_CCMP           = $04;
  DOT11_CIPHER_ALGO_WEP104         = $05;
  DOT11_CIPHER_ALGO_BIP            = $06;
  DOT11_CIPHER_ALGO_GCMP           = $08;
  DOT11_CIPHER_ALGO_GCMP_256       = $09;
  DOT11_CIPHER_ALGO_CCMP_256       = $0A;
  DOT11_CIPHER_ALGO_WPA_USE_GROUP  = $100;
  DOT11_CIPHER_ALGO_RSN_USE_GROUP  = $100;
  DOT11_CIPHER_ALGO_WEP            = $101;

  // WLAN_INTERFACE_STATE values.
  wlan_interface_state_not_ready           = 0;
  wlan_interface_state_connected           = 1;
  wlan_interface_state_ad_hoc_network_formed = 2;
  wlan_interface_state_disconnecting       = 3;
  wlan_interface_state_disconnected        = 4;
  wlan_interface_state_associating         = 5;
  wlan_interface_state_discovering         = 6;
  wlan_interface_state_authenticating      = 7;

type
  // Aliases so declarations read like the SDK.
  DWORD    = Winapi.Windows.DWORD;
  ULONG    = Cardinal;
  LONG     = Integer;
  USHORT   = Word;
  UCHAR    = Byte;
  BOOLEANW = ByteBool;

  // Raw 6-byte hardware address (BSSID).
  TDot11MacAddress = array[0..5] of UCHAR;
  PDot11MacAddress = ^TDot11MacAddress;

  // DOT11_SSID: length-prefixed, NOT null-terminated.
  TDot11Ssid = record
    uSSIDLength: ULONG;
    ucSSID: array[0..DOT11_SSID_MAX_LENGTH - 1] of UCHAR;
  end;
  PDot11Ssid = ^TDot11Ssid;

  // WLAN_RATE_SET.
  TWlanRateSet = record
    uRateSetLength: ULONG;
    usRateSet: array[0..DOT11_RATE_SET_MAX_LENGTH - 1] of USHORT;
  end;
  PWlanRateSet = ^TWlanRateSet;

  // WLAN_INTERFACE_INFO.
  TWlanInterfaceInfo = record
    InterfaceGuid: TGUID;
    strInterfaceDescription: array[0..WLAN_MAX_NAME_LENGTH - 1] of WideChar;
    isState: DWORD; // WLAN_INTERFACE_STATE
  end;
  PWlanInterfaceInfo = ^TWlanInterfaceInfo;

  // WLAN_INTERFACE_INFO_LIST. The InterfaceInfo array is variable length; the
  // [0..0] declaration is a header and must be indexed via a typed pointer.
  TWlanInterfaceInfoList = record
    dwNumberOfItems: DWORD;
    dwIndex: DWORD;
    InterfaceInfo: array[0..0] of TWlanInterfaceInfo;
  end;
  PWlanInterfaceInfoList = ^TWlanInterfaceInfoList;

  // WLAN_BSS_ENTRY - one scanned BSS (a single radio/BSSID of a network).
  TWlanBssEntry = record
    dot11Ssid: TDot11Ssid;
    uPhyId: ULONG;
    dot11Bssid: TDot11MacAddress;
    dot11BssType: DWORD;        // DOT11_BSS_TYPE
    dot11BssPhyType: DWORD;     // DOT11_PHY_TYPE
    lRssi: LONG;                // signal strength, dBm
    uLinkQuality: ULONG;        // 0..100
    bInRegDomain: BOOLEANW;
    usBeaconPeriod: USHORT;
    ullTimestamp: UInt64;
    ullHostTimestamp: UInt64;
    usCapabilityInformation: USHORT;
    ulChCenterFrequency: ULONG; // center frequency, kHz
    wlanRateSet: TWlanRateSet;
    ulIeOffset: ULONG;          // offset from the start of THIS record
    ulIeSize: ULONG;
  end;
  PWlanBssEntry = ^TWlanBssEntry;

  // WLAN_BSS_LIST.
  TWlanBssList = record
    dwTotalSize: DWORD;
    dwNumberOfItems: DWORD;
    wlanBssEntries: array[0..0] of TWlanBssEntry;
  end;
  PWlanBssList = ^TWlanBssList;

  // WLAN_AVAILABLE_NETWORK - one logical network (may aggregate several BSSIDs).
  TWlanAvailableNetwork = record
    strProfileName: array[0..WLAN_MAX_NAME_LENGTH - 1] of WideChar;
    dot11Ssid: TDot11Ssid;
    dot11BssType: DWORD;
    uNumberOfBssids: ULONG;
    bNetworkConnectable: BOOL;
    wlanNotConnectableReason: DWORD;
    uNumberOfPhyTypes: ULONG;
    dot11PhyTypes: array[0..WLAN_MAX_PHY_TYPE_NUMBER - 1] of DWORD;
    bMorePhyTypes: BOOL;
    wlanSignalQuality: ULONG;   // 0..100
    bSecurityEnabled: BOOL;
    dot11DefaultAuthAlgorithm: DWORD;
    dot11DefaultCipherAlgorithm: DWORD;
    dwFlags: DWORD;
    dwReserved: DWORD;
  end;
  PWlanAvailableNetwork = ^TWlanAvailableNetwork;

  // WLAN_AVAILABLE_NETWORK_LIST.
  TWlanAvailableNetworkList = record
    dwNumberOfItems: DWORD;
    dwIndex: DWORD;
    Network: array[0..0] of TWlanAvailableNetwork;
  end;
  PWlanAvailableNetworkList = ^TWlanAvailableNetworkList;

  // WLAN_ASSOCIATION_ATTRIBUTES.
  TWlanAssociationAttributes = record
    dot11Ssid: TDot11Ssid;
    dot11BssType: DWORD;
    dot11Bssid: TDot11MacAddress;
    dot11PhyType: DWORD;
    uDot11PhyIndex: ULONG;
    wlanSignalQuality: ULONG;
    ulRxRate: ULONG;
    ulTxRate: ULONG;
  end;

  // WLAN_SECURITY_ATTRIBUTES.
  TWlanSecurityAttributes = record
    bSecurityEnabled: BOOL;
    bOneXEnabled: BOOL;
    dot11AuthAlgorithm: DWORD;
    dot11CipherAlgorithm: DWORD;
  end;

  // WLAN_CONNECTION_ATTRIBUTES (returned by WlanQueryInterface).
  TWlanConnectionAttributes = record
    isState: DWORD;             // WLAN_INTERFACE_STATE
    wlanConnectionMode: DWORD;  // WLAN_CONNECTION_MODE
    strProfileName: array[0..WLAN_MAX_NAME_LENGTH - 1] of WideChar;
    wlanAssociationAttributes: TWlanAssociationAttributes;
    wlanSecurityAttributes: TWlanSecurityAttributes;
  end;
  PWlanConnectionAttributes = ^TWlanConnectionAttributes;

// --- wlanapi.dll entry points -------------------------------------------------

function WlanOpenHandle(dwClientVersion: DWORD; pReserved: Pointer;
  out pdwNegotiatedVersion: DWORD; out phClientHandle: THandle): DWORD; stdcall;
  external WLANAPI_DLL;

function WlanCloseHandle(hClientHandle: THandle; pReserved: Pointer): DWORD; stdcall;
  external WLANAPI_DLL;

procedure WlanFreeMemory(pMemory: Pointer); stdcall;
  external WLANAPI_DLL;

function WlanEnumInterfaces(hClientHandle: THandle; pReserved: Pointer;
  out ppInterfaceList: PWlanInterfaceInfoList): DWORD; stdcall;
  external WLANAPI_DLL;

function WlanScan(hClientHandle: THandle; const pInterfaceGuid: TGUID;
  pDot11Ssid: PDot11Ssid; pIeData: Pointer; pReserved: Pointer): DWORD; stdcall;
  external WLANAPI_DLL;

function WlanGetNetworkBssList(hClientHandle: THandle; const pInterfaceGuid: TGUID;
  pDot11Ssid: PDot11Ssid; dot11BssType: DWORD; bSecurityEnabled: BOOL;
  pReserved: Pointer; out ppWlanBssList: PWlanBssList): DWORD; stdcall;
  external WLANAPI_DLL;

function WlanGetAvailableNetworkList(hClientHandle: THandle; const pInterfaceGuid: TGUID;
  dwFlags: DWORD; pReserved: Pointer;
  out ppAvailableNetworkList: PWlanAvailableNetworkList): DWORD; stdcall;
  external WLANAPI_DLL;

function WlanQueryInterface(hClientHandle: THandle; const pInterfaceGuid: TGUID;
  OpCode: DWORD; pReserved: Pointer; out pdwDataSize: DWORD;
  out ppData: Pointer; pWlanOpcodeValueType: Pointer): DWORD; stdcall;
  external WLANAPI_DLL;

implementation

end.
