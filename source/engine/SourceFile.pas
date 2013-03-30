unit SourceFile;

interface

uses
  SourceLocation,
  SourceToken;

type
  TCharType = (ctEof, ctWhitespace, ctLetter, ctNumber, ctSymbol);

  TSourceFile = class
  public
    constructor Create;
    destructor Destroy; override;

    procedure ReadFromFile(const FileName: String);
  private
    FPhase1Position: TLocation;
    FPhase2Token: TToken;
    FPhase2PreviousCharType: TCharType;

    procedure Phase1(B: Byte); // locations and newline conversion
    procedure Phase2(B: Byte; Position: TLocation); // first tokenization pass, lacking strings
    procedure Phase3(Token: TToken);

  end;

implementation

uses
  Classes, SysUtils;

constructor TSourceFile.Create;
begin
end;

destructor TSourceFile.Destroy;
begin
end;

procedure TSourceFile.ReadFromFile(const FileName: String);
var
  Stream: TFileStream;
  B: Byte;
  Size: Int64;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead);
  try
    FPhase1Position.Line := 1;
    FPhase1Position.Column := 1;
    FPhase1Position.Offset := 0;
    FPhase1Position.Length := 1;

    FPhase2Token.Kind := tkEof;
    FPhase2PreviousCharType := ctEof;

    Size := Stream.Size;
    while Size > 0 do
    begin
      Stream.ReadBuffer(B, 1);
      Phase1(B);
    end;
    Phase1(0);
  finally
    Stream.Free;
  end;
end;

var
  CharTypeMapping : array[Byte] of TCharType;
  Operators : TStringList;

procedure TSourceFile.Phase1(B: Byte);
begin
  if B = 0 then begin
    Phase2(B, FPhase1Position);
    Exit;
  end;
  Inc(FPhase1Position.Offset);
  if B = 13 then
    Exit; // Dos newlines are a bother
  Phase2(B, FPhase1Position);
  if B = 10 then
  begin
    Inc(FPhase1Position.Line);
    FPhase1Position.Column := 1;
  end;
end;

procedure TSourceFile.Phase2(B: Byte; Position: TLocation);
begin
  case CharTypeMapping[B] of
    ctEof: begin
      FPhase2PreviousCharType := ctEof;
      if FPhase2Token.Kind <> tkEof then
        Phase3(FPhase2Token);
      FPhase2Token.Position := Position;
      FPhase2Token.Kind := tkEof;
      FPhase2Token.Data := '';
      Phase3(FPhase2Token);
    end;
    ctWhitespace: begin
      if FPhase2PreviousCharType <> ctWhitespace then begin
        if FPhase2Token.Kind <> tkEof then
          Phase3(FPhase2Token);
      end;
      FPhase2PreviousCharType := ctWhitespace;
      FPhase2Token.Position := Position;
      FPhase2Token.Kind := tkEof;
      FPhase2Token.Data := '';
    end;
    ctLetter: begin
      if FPhase2PreviousCharType <> ctLetter then begin
        if FPhase2Token.Kind <> tkEof then
          Phase3(FPhase2Token);
        FPhase2PreviousCharType := ctLetter;
        FPhase2Token.Position := Position;
        FPhase2Token.Kind := tkIdentifier;
        FPhase2Token.Data := '' + Chr(B);   // bad mkay
      end
      else begin
        Inc(FPhase2Token.Position.Length);
        FPhase2Token.Data := FPhase2Token.Data + Chr(B);   // bad mkay
      end;
    end;
    ctNumber: begin
      if (FPhase2PreviousCharType = ctLetter) or (FPhase2PreviousCharType = ctNumber) then begin
        Inc(FPhase2Token.Position.Length);
        FPhase2Token.Data := FPhase2Token.Data + Chr(B);   // bad mkay
      end
      else begin
        if FPhase2Token.Kind <> tkEof then
          Phase3(FPhase2Token);
        FPhase2PreviousCharType := ctNumber;
        FPhase2Token.Position := Position;
        FPhase2Token.Kind := tkIdentifier;
        FPhase2Token.Data := '' + Chr(B);   // bad mkay
      end;
    end;
    ctSymbol: begin
      if FPhase2Token.Kind <> tkEof then
        Phase3(FPhase2Token);
      FPhase2PreviousCharType := ctSymbol;
      FPhase2Token.Position := Position;
      FPhase2Token.Kind := tkIdentifier;
      FPhase2Token.Data := '' + Chr(B);   // bad mkay
      Phase3(FPhase2Token);
      FPhase2Token.Kind := tkEof;
      FPhase2Token.Data := '';
    end;
  end;
end;

procedure BuildCharTypeMapping;
var
  B: Byte;
begin
  for B := 0 to 255 do
     CharTypeMapping[B] := ctEof;

  CharTypeMapping[9] := ctWhiteSpace;
  CharTypeMapping[10] := ctWhiteSpace;
  CharTypeMapping[13] := ctWhiteSpace;
  CharTypeMapping[32] := ctWhiteSpace;

  for B := 33 to 47 do
     CharTypeMapping[B] := ctSymbol;
  for B := 48 to 57 do
     CharTypeMapping[B] := ctNumber;
  for B := 58 to 64 do
     CharTypeMapping[B] := ctSymbol;
  for B := 65 to 90 do
     CharTypeMapping[B] := ctLetter;
  for B := 91 to 94 do
     CharTypeMapping[B] := ctSymbol;
  CharTypeMapping[95] := ctLetter;
  CharTypeMapping[96] := ctSymbol;
  for B := 97 to 122 do
     CharTypeMapping[B] := ctLetter;
  for B := 123 to 126 do
     CharTypeMapping[B] := ctSymbol;
end;

procedure BuildOperators;
begin
  Operators := TStringList.Create;
  Operators.Sorted := True;
  Operators.Duplicates := dupError;

  Operators.Add("+");
  Operators.Add("-");
  Operators.Add("!");
  Operators.Add("~");
  Operators.Add("*");
  Operators.Add("|");
  Operators.Add("&");
  Operators.Add("^");
  Operators.Add("%");
  Operators.Add("(");
  Operators.Add(")");
  Operators.Add("[");
  Operators.Add("]");
  Operators.Add("<");
  Operators.Add(">");
  Operators.Add(".");
  Operators.Add(",");
  Operators.Add("?");
  Operators.Add(":");
  Operators.Add("=");
  Operators.Add("::");
  Operators.Add("++");
  Operators.Add("--");
  Operators.Add("->");
  Operators.Add("<<");
  Operators.Add(">>");
  Operators.Add(">>>");
  Operators.Add("<=");
  Operators.Add(">=");
  Operators.Add("==");
  Operators.Add("===");
  Operators.Add("!=");
  Operators.Add("!==");
  Operators.Add("&&");
  Operators.Add("||");
  Operators.Add("??");
  Operators.Add("+=");
  Operators.Add("-=");
  Operators.Add("*=");
  Operators.Add("/=");
  Operators.Add("%=");
  Operators.Add("<<=");
  Operators.Add(">>=");
  Operators.Add(">>>=");
  Operators.Add("&=");
  Operators.Add("^=");
  Operators.Add("|=");
end;

initialization
  BuildCharTypeMapping;
  BuildOperators;

finalization
  FreeAndNil(Operators);

end.
