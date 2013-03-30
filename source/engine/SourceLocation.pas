unit SourceLocation;

interface

uses
  Classes,
  SysUtils,
  StrUtils;

type
  TLocation = record
    SourceName: String;
    Offset: Integer;
    Line: Integer;
    Column: Integer;
    Length: Integer;
  end;

function DescribeLocation(const Location: TLocation): String;

implementation

function DescribeLocation(const Location: TLocation): String;
begin
  Result := '('+Location.SourceName+':'+IntToStr(Location.Line)+':'+IntToStr(Location.Column)+')['+IntToStr(Location.Offset)+':'+IntToStr(Location.Length)+']';
end;

end.
