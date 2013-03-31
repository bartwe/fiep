unit StringBuilder;

interface

type
  TStringBuilder = class
  public
    constructor Create;
    destructor Destroy; override;

    procedure AppendByte(B: Byte); // ugly, assume it provedes an utf8 nibble
    procedure AppendString(const S: String);

    function ToString: String;
    procedure Clear;

  private
    FBuffer: array of Byte;
    FPosition: Integer;
  end;

implementation

uses
  Windows,
  Classes,
  SysUtils,
  StrUtils;

constructor TStringBuilder.Create;
begin
end;

destructor TStringBuilder.Destroy;
begin
end;

procedure TStringBuilder.AppendByte(B: Byte);
var
  L: Integer;
begin
  L := Length(FBuffer);
  if L <= (FPosition+1) then begin
    if L = 0 then
      L := 32;
    while L <= (FPosition+1) do begin
      L := L * 4;
    end;
    SetLength(FBuffer, L);
  end;
  FBuffer[FPosition] := B;
  Inc(FPosition);
end;

procedure TStringBuilder.AppendString(const S: String);
var
  SL, L: Integer;
begin
  SL := Length(S);
  L := Length(FBuffer);
  if L <= (FPosition+SL) then begin
    if L = 0 then
      L := 32;
    while L <= (FPosition+SL) do begin
      L := L * 4;
    end;
    SetLength(FBuffer, L);
  end;
  CopyMemory(@FBuffer[FPosition], @S[1], SL);
  Inc(FPosition, SL);
end;

function TStringBuilder.ToString: String;
begin
  SetString(Result, PChar(@FBuffer[0]), FPosition);
end;

procedure TStringBuilder.Clear;
begin
  FPosition := 0;
  if Length(FBuffer) > 4096 then
    SetLength(FBuffer, 0);
end;

end.

