unit WiFi.Services.Theme;

{
  WiFi.Services.Theme

  A tiny process-wide palette used by all the custom-drawn surfaces (grid,
  Channels, Signal and Dashboard) so light/dark mode is coherent everywhere,
  independent of whether a VCL Style happens to be installed for the standard
  controls. Toggle Dark and every surface repaints with the matching colours.

  Colours are TColor literals in $00BBGGRR order.
}

interface

uses
  Vcl.Graphics;

type
  /// <summary>Semantic colour roles used across the UI.</summary>
  TThemeRole = (trBackground, trCardFill, trCardBorder, trTextPrimary,
    trTextSecondary, trAccent, trGridLine, trHeader, trSelection,
    trSelectionText, trConnected);

  TAppTheme = class
  private
    FDark: Boolean;
    procedure SetDark(AValue: Boolean);
  public
    /// <summary>Resolve a semantic role to a concrete colour.</summary>
    function Color(ARole: TThemeRole): TColor;
    property Dark: Boolean read FDark write SetDark;
  end;

/// <summary>Process-wide theme singleton.</summary>
function Theme: TAppTheme;

implementation

var
  GTheme: TAppTheme;

function Theme: TAppTheme;
begin
  if GTheme = nil then
    GTheme := TAppTheme.Create;
  Result := GTheme;
end;

{ TAppTheme }

procedure TAppTheme.SetDark(AValue: Boolean);
begin
  FDark := AValue;
end;

function TAppTheme.Color(ARole: TThemeRole): TColor;
begin
  if FDark then
  begin
    case ARole of
      trBackground:    Result := $001E1E1E;
      trCardFill:      Result := $002A2A2A;
      trCardBorder:    Result := $003C3C3C;
      trTextPrimary:   Result := $00F0F0F0;
      trTextSecondary: Result := $00A0A0A0;
      trAccent:        Result := $00E0A040;
      trGridLine:      Result := $00383838;
      trHeader:        Result := $00333333;
      trSelection:     Result := $00785A28;
      trSelectionText: Result := $00FFFFFF;
      trConnected:     Result := $00404A2A;
    else
      Result := $00F0F0F0;
    end;
  end
  else
  begin
    case ARole of
      trBackground:    Result := $00FFFFFF;
      trCardFill:      Result := $00F7F7F7;
      trCardBorder:    Result := $00E0E0E0;
      trTextPrimary:   Result := $00202020;
      trTextSecondary: Result := $00808080;
      trAccent:        Result := $00C07820;
      trGridLine:      Result := $00ECECEC;
      trHeader:        Result := $00F0F0F0;
      trSelection:     Result := $00E8C79A;
      trSelectionText: Result := $00000000;
      trConnected:     Result := $00E8F5E0;
    else
      Result := $00202020;
    end;
  end;
end;

initialization

finalization
  GTheme.Free;

end.
