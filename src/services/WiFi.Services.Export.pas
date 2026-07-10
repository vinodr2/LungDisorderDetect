unit WiFi.Services.Export;

{
  WiFi.Services.Export

  Writes the current grid contents to CSV or Excel (.xlsx). Both writers take
  already-formatted string data (headers + rows) so the service is UI-agnostic
  and unit-testable, and so the caller can reuse the exact text the grid shows.

  The .xlsx writer builds a minimal but valid OpenXML (SpreadsheetML) package
  using only the RTL's System.Zip - no third-party dependency. Cells are written
  as inline strings, which keeps the package small and avoids a shared-strings
  table while still opening cleanly in Excel / LibreOffice.
}

interface

uses
  System.SysUtils, System.Classes;

type
  TExportService = class
  public
    /// <summary>Write an RFC-4180 CSV (UTF-8 with BOM) to AFileName.</summary>
    class procedure ExportCsv(const AFileName: string; const AHeaders: TArray<string>;
      const ARows: TArray<TArray<string>>); static;
    /// <summary>Write a minimal .xlsx workbook (single sheet) to AFileName.</summary>
    class procedure ExportXlsx(const AFileName: string; const AHeaders: TArray<string>;
      const ARows: TArray<TArray<string>>); static;
    /// <summary>Quote a single field per RFC-4180 (exposed for testing).</summary>
    class function CsvField(const AValue: string): string; static;
    /// <summary>Excel-style column reference letters for a 0-based index.</summary>
    class function ColRef(AIndex: Integer): string; static;
  end;

implementation

uses
  System.Zip;

{ TExportService }

class function TExportService.CsvField(const AValue: string): string;
begin
  if (AValue.IndexOf(',') >= 0) or (AValue.IndexOf('"') >= 0) or
     (AValue.IndexOf(#10) >= 0) or (AValue.IndexOf(#13) >= 0) then
    Result := '"' + AValue.Replace('"', '""', [rfReplaceAll]) + '"'
  else
    Result := AValue;
end;

class procedure TExportService.ExportCsv(const AFileName: string;
  const AHeaders: TArray<string>; const ARows: TArray<TArray<string>>);
var
  SB: TStringBuilder;
  Row: TArray<string>;
  Bytes, Preamble: TBytes;
  Stream: TFileStream;

  procedure WriteLine(const AFields: TArray<string>);
  var
    K: Integer;
  begin
    for K := 0 to High(AFields) do
    begin
      if K > 0 then
        SB.Append(',');
      SB.Append(CsvField(AFields[K]));
    end;
    SB.Append(#13#10);
  end;

begin
  SB := TStringBuilder.Create;
  try
    WriteLine(AHeaders);
    for Row in ARows do
      WriteLine(Row);
    // UTF-8 with BOM so Excel detects the encoding.
    Bytes := TEncoding.UTF8.GetBytes(SB.ToString);
    Preamble := TEncoding.UTF8.GetPreamble;
    Stream := TFileStream.Create(AFileName, fmCreate);
    try
      if Length(Preamble) > 0 then
        Stream.WriteBuffer(Preamble[0], Length(Preamble));
      if Length(Bytes) > 0 then
        Stream.WriteBuffer(Bytes[0], Length(Bytes));
    finally
      Stream.Free;
    end;
  finally
    SB.Free;
  end;
end;

class function TExportService.ColRef(AIndex: Integer): string;
var
  N: Integer;
begin
  // 0 -> A, 25 -> Z, 26 -> AA, ...
  Result := '';
  N := AIndex;
  repeat
    Result := Chr(Ord('A') + (N mod 26)) + Result;
    N := (N div 26) - 1;
  until N < 0;
end;

function XmlEscape(const AValue: string): string;
begin
  Result := AValue
    .Replace('&', '&amp;', [rfReplaceAll])
    .Replace('<', '&lt;', [rfReplaceAll])
    .Replace('>', '&gt;', [rfReplaceAll]);
end;

class procedure TExportService.ExportXlsx(const AFileName: string;
  const AHeaders: TArray<string>; const ARows: TArray<TArray<string>>);
const
  CONTENT_TYPES =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
    '<Default Extension="xml" ContentType="application/xml"/>' +
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
    '</Types>';
  ROOT_RELS =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>' +
    '</Relationships>';
  WORKBOOK =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"' +
    ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
    '<sheets><sheet name="Networks" sheetId="1" r:id="rId1"/></sheets></workbook>';
  WORKBOOK_RELS =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
    '</Relationships>';
var
  Zip: TZipFile;
  Sheet: TStringBuilder;
  RowNum: Integer;
  Row: TArray<string>;

  procedure AddText(const AName, AContent: string);
  begin
    Zip.Add(TEncoding.UTF8.GetBytes(AContent), AName, zcDeflate);
  end;

  procedure WriteCells(const AFields: TArray<string>);
  var
    K: Integer;
    Ref: string;
  begin
    Sheet.Append(Format('<row r="%d">', [RowNum]));
    for K := 0 to High(AFields) do
    begin
      Ref := ColRef(K) + IntToStr(RowNum);
      Sheet.Append(Format('<c r="%s" t="inlineStr"><is><t xml:space="preserve">%s</t></is></c>',
        [Ref, XmlEscape(AFields[K])]));
    end;
    Sheet.Append('</row>');
    Inc(RowNum);
  end;

begin
  Sheet := TStringBuilder.Create;
  try
    Sheet.Append('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    Sheet.Append('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">');
    Sheet.Append('<sheetData>');
    RowNum := 1;
    WriteCells(AHeaders);
    for Row in ARows do
      WriteCells(Row);
    Sheet.Append('</sheetData></worksheet>');

    Zip := TZipFile.Create;
    try
      Zip.Open(AFileName, zmWrite);
      AddText('[Content_Types].xml', CONTENT_TYPES);
      AddText('_rels/.rels', ROOT_RELS);
      AddText('xl/workbook.xml', WORKBOOK);
      AddText('xl/_rels/workbook.xml.rels', WORKBOOK_RELS);
      AddText('xl/worksheets/sheet1.xml', Sheet.ToString);
      Zip.Close;
    finally
      Zip.Free;
    end;
  finally
    Sheet.Free;
  end;
end;

end.
