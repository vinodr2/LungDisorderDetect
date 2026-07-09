unit WiFi.Services.Scanner;

{
  WiFi.Services.Scanner

  Owns a dedicated background thread that repeatedly asks the WLAN adapter to
  scan, reads the resulting BSS list through IWlanClient, resolves vendors and
  publishes an immutable TScanSnapshot to the UI on the main thread.

  Design points:
    * The UI never calls the WLAN API and never blocks: everything happens on
      the worker thread, results are marshaled with TThread.Queue.
    * Snapshots are owned by the service. The OnSnapshot handler receives a
      snapshot that is valid only for the duration of the call; it must copy
      whatever it needs and must NOT free it.
    * The scan cadence is configurable at runtime; changing it takes effect on
      the next cycle, and RefreshNow forces an immediate rescan.
    * All adapter errors are reported through OnError and never crash the app.
}

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs,
  WiFi.Models, WiFi.Api.Wlan, WiFi.Services.Oui;

type
  TSnapshotEvent = procedure(Sender: TObject; ASnapshot: TScanSnapshot) of object;
  TScannerErrorEvent = procedure(Sender: TObject; const AMessage: string) of object;

  TScannerService = class
  private
  type
    TScanThread = class(TThread)
    private
      FOwner: TScannerService;
      FWake: TEvent;
    protected
      procedure Execute; override;
      procedure TerminatedSet; override;
    public
      constructor Create(AOwner: TScannerService);
      destructor Destroy; override;
      procedure Wake;
    end;
  private
    FClient: IWlanClient;
    FOui: IOuiVendorService;
    FThread: TScanThread;
    FIntervalMs: Integer;
    FOnSnapshot: TSnapshotEvent;
    FOnError: TScannerErrorEvent;
    FIntervalLock: TCriticalSection;
    function GetIntervalMs: Integer;
    procedure SetIntervalMs(AValue: Integer);
    procedure PublishSnapshot(ASnapshot: TScanSnapshot);
    procedure ReportError(const AMessage: string);
    function RunOnce: TScanSnapshot;
  public
    constructor Create(const AClient: IWlanClient; const AOui: IOuiVendorService);
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    /// <summary>Force an immediate rescan without waiting for the interval.</summary>
    procedure RefreshNow;
    /// <summary>Scan cadence in milliseconds (clamped to a sane minimum).</summary>
    property IntervalMs: Integer read GetIntervalMs write SetIntervalMs;
    property OnSnapshot: TSnapshotEvent read FOnSnapshot write FOnSnapshot;
    property OnError: TScannerErrorEvent read FOnError write FOnError;
  end;

const
  DEFAULT_SCAN_INTERVAL_MS = 5000;
  MIN_SCAN_INTERVAL_MS     = 1000;
  // Time given to the adapter to complete a scan before reading results.
  SCAN_SETTLE_MS           = 3000;

implementation

uses
  WiFi.Services.Logger;

{ TScannerService }

constructor TScannerService.Create(const AClient: IWlanClient;
  const AOui: IOuiVendorService);
begin
  inherited Create;
  FClient := AClient;
  FOui := AOui;
  FIntervalMs := DEFAULT_SCAN_INTERVAL_MS;
  FIntervalLock := TCriticalSection.Create;
end;

destructor TScannerService.Destroy;
begin
  Stop;
  FIntervalLock.Free;
  FClient := nil;
  FOui := nil;
  inherited;
end;

function TScannerService.GetIntervalMs: Integer;
begin
  FIntervalLock.Enter;
  try
    Result := FIntervalMs;
  finally
    FIntervalLock.Leave;
  end;
end;

procedure TScannerService.SetIntervalMs(AValue: Integer);
begin
  if AValue < MIN_SCAN_INTERVAL_MS then
    AValue := MIN_SCAN_INTERVAL_MS;
  FIntervalLock.Enter;
  try
    FIntervalMs := AValue;
  finally
    FIntervalLock.Leave;
  end;
end;

procedure TScannerService.Start;
begin
  if FThread <> nil then
    Exit;
  // Create suspended and assign the field BEFORE the thread runs, so RunOnce
  // never observes a nil FThread.
  FThread := TScanThread.Create(Self);
  FThread.Start;
end;

procedure TScannerService.Stop;
begin
  if FThread = nil then
    Exit;
  FThread.Terminate; // TerminatedSet wakes the wait
  FThread.WaitFor;
  // Drop any snapshot deliveries queued but not yet dispatched.
  TThread.RemoveQueuedEvents(FThread);
  FreeAndNil(FThread);
end;

procedure TScannerService.RefreshNow;
begin
  if FThread <> nil then
    FThread.Wake;
end;

procedure TScannerService.ReportError(const AMessage: string);
begin
  Log.Error('Scanner: ' + AMessage);
  // Marshal to the main thread; owner may be gone by dispatch time only if
  // Stop() was called, which removes queued events first.
  TThread.Queue(FThread,
    procedure
    begin
      if Assigned(FOnError) then
        FOnError(Self, AMessage);
    end);
end;

procedure TScannerService.PublishSnapshot(ASnapshot: TScanSnapshot);
var
  Snap: TScanSnapshot;
begin
  Snap := ASnapshot;
  TThread.Queue(FThread,
    procedure
    begin
      try
        if Assigned(FOnSnapshot) then
          FOnSnapshot(Self, Snap);
      finally
        Snap.Free; // service owns the snapshot lifetime
      end;
    end);
end;

function TScannerService.RunOnce: TScanSnapshot;
var
  Ifaces: TArray<TWlanIface>;
  Chosen: TWlanIface;
  HasChosen: Boolean;
  Iface: TWlanIface;
  List: TAccessPointList;
  I: Integer;
  AP: TAccessPoint;
  AdapterName: string;
begin
  Result := nil;
  Ifaces := FClient.EnumInterfaces;
  if Length(Ifaces) = 0 then
  begin
    ReportError('No wireless adapter found.');
    Exit;
  end;

  // Prefer a connected adapter, else the first one.
  HasChosen := False;
  Chosen := Ifaces[0];
  for Iface in Ifaces do
    if Iface.IsConnected then
    begin
      Chosen := Iface;
      HasChosen := True;
      Break;
    end;
  if not HasChosen then
    Chosen := Ifaces[0];
  AdapterName := Chosen.Description;

  // Trigger a fresh scan; failure here is non-fatal (we still read caches).
  try
    FClient.Scan(Chosen.Guid);
  except
    on E: Exception do
      Log.Warn('WlanScan: ' + E.Message);
  end;

  // Give the radio time to gather results, staying responsive to Terminate.
  if FThread <> nil then
    FThread.FWake.WaitFor(SCAN_SETTLE_MS);
  if (FThread <> nil) and FThread.Terminated then
    Exit;

  List := FClient.GetAccessPoints(Chosen.Guid);
  // Resolve vendors on this thread (OUI map is read-only after load).
  if FOui <> nil then
    for I := 0 to List.Count - 1 do
    begin
      AP := List[I];
      if AP.Vendor = '' then
      begin
        AP.Vendor := FOui.LookupByBssid(AP.BSSID);
        List[I] := AP;
      end;
    end;

  Result := TScanSnapshot.Create(List, AdapterName);
end;

{ TScannerService.TScanThread }

constructor TScannerService.TScanThread.Create(AOwner: TScannerService);
begin
  FOwner := AOwner;
  FWake := TEvent.Create(nil, False {auto-reset}, False, '');
  inherited Create(True {suspended; owner calls Start});
end;

destructor TScannerService.TScanThread.Destroy;
begin
  FWake.Free;
  inherited;
end;

procedure TScannerService.TScanThread.Wake;
begin
  FWake.SetEvent;
end;

procedure TScannerService.TScanThread.TerminatedSet;
begin
  inherited;
  FWake.SetEvent; // interrupt any in-progress interval/settle wait
end;

procedure TScannerService.TScanThread.Execute;
var
  Snapshot: TScanSnapshot;
begin
  NameThreadForDebugging('WiFiScanner');
  while not Terminated do
  begin
    Snapshot := nil;
    try
      Snapshot := FOwner.RunOnce;
    except
      on E: Exception do
        FOwner.ReportError(E.Message);
    end;

    if Terminated then
    begin
      Snapshot.Free;
      Break;
    end;

    if Snapshot <> nil then
      FOwner.PublishSnapshot(Snapshot);

    // Interruptible wait until the next cycle (or RefreshNow / Terminate).
    FWake.WaitFor(Cardinal(FOwner.GetIntervalMs));
  end;
end;

end.
