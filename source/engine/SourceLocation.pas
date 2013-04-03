unit SourceLocation;

interface

uses
  Classes,
  SysUtils,
  StrUtils;

type
  TLocation = record
    Offset: Integer;
    EndOffset: Integer;
    Line: Integer;
    Column: Integer;
  end;
  PLocation = ^TLocation;

function DescribeLocation(const Location: TLocation): String;
function BeyondLocation(const Location: TLocation): TLocation;

implementation

function DescribeLocation(const Location: TLocation): String;
begin
  Result := '(:'+IntToStr(Location.Line)+':'+IntToStr(Location.Column)+')['+IntToStr(Location.Offset)+':'+IntToStr(Location.EndOffset)+']';
end;

function BeyondLocation(const Location: TLocation): TLocation;
begin
  Result := Location;
  Inc(Result.Column, Result.EndOffset - Result.Offset);
  Result.Offset := Result.EndOffset;
end;

end.
