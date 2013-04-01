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
function BeyondLocation(const Location: TLocation): TLocation;

implementation

function DescribeLocation(const Location: TLocation): String;
begin
  Result := '(:'+IntToStr(Location.Line)+':'+IntToStr(Location.Column)+')['+IntToStr(Location.Offset)+':'+IntToStr(Location.Length)+']';
end;

function BeyondLocation(const Location: TLocation): TLocation;
begin
  Result := Location;
  Inc(Result.Offset, Result.Length);
  Inc(Result.Column, Result.Length);
  Result.Length := 1;
end;

end.
