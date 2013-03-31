unit SourceLocation;

interface

uses
  Classes,
  SysUtils,
  StrUtils;

type
  TLocation = record
    Offset: Integer;
    Line: Integer;
    Column: Integer;
    Length: Integer;
  end;
  PLocation = ^TLocation;

function DescribeLocation(const Location: TLocation): String;

implementation

function DescribeLocation(const Location: TLocation): String;
begin
  Result := '(:'+IntToStr(Location.Line)+':'+IntToStr(Location.Column)+')['+IntToStr(Location.Offset)+':'+IntToStr(Location.Length)+']';
end;

end.
