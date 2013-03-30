unit SourceFile;

interface

uses
  SourceLocation,
  SourceToken,
  Classes,
  SysUtils,
  StrUtils;

type
  TCharType = (ctEof, ctWhitespace, ctLetter, ctNumber, ctSymbol);
  TStringMode = (smNone, smOpen, smEscape); //, smUnicode4, smUnicode3, smUnicode2, smUnicode1)
  TFloatMode = (fmNone, fmMinus, fmNakedDot, fmPrefix, fmDot, fmFraction, fmSignedExponent);

  TSourceFile = class
  public
    FOutput: TStringList;
    constructor Create;
    destructor Destroy; override;

    procedure ReadFromFile(const FileName: String);

  private
    FPhase1Position: TLocation;
    FPhase1_5Mode: TStringMode;
    FPhase1_5Token: TToken;
    FPhase2Token: TToken;
    FPhase2PreviousCharType: TCharType;
    FPhase3Mode: TFloatMode;
    FPhase3Token: TToken;

    procedure Phase1(B: Byte); // locations and newline conversion
    procedure Phase1_5(B: Byte; Position: TLocation); // Strings
    procedure Phase2(B: Byte; Position: TLocation); // first tokenization pass
    procedure Phase2B(Token: TToken);
    procedure Phase3(Token: TToken); // floating point
    procedure Phase4(Token: TToken);

    procedure Error(const Message: String; Position: TLocation);

  end;

implementation

constructor TSourceFile.Create;
begin
  FOutput := TStringList.Create;
end;

destructor TSourceFile.Destroy;
begin
  FOutput.Free;
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

    FPhase1_5Mode := smNone;
    FPhase1_5Token.Kind := tkEof;

    FPhase2Token.Kind := tkEof;
    FPhase2PreviousCharType := ctEof;

    Size := Stream.Size;
    while Size > 0 do
    begin
      Stream.ReadBuffer(B, 1);
      Phase1(B);
      Dec(Size);
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
    Phase1_5(B, FPhase1Position);
    Exit;
  end;
  Inc(FPhase1Position.Offset);
  Inc(FPhase1Position.Column);
  if B = 13 then
    Exit; // Dos newlines are a bother
  Phase1_5(B, FPhase1Position);
  if B = 10 then
  begin
    Inc(FPhase1Position.Line);
    FPhase1Position.Column := 1;
  end;
end;

procedure TSourceFile.Phase1_5(B: Byte; Position: TLocation);
begin
  if CharTypeMapping[B] = ctEof then begin
    if FPhase1_5Mode <> smNone then begin
      Error('Unterminated string constant', FPhase1_5Token.Position);
      Phase2B(FPhase1_5Token);
      FPhase1_5Mode := smNone;
    end;
    Phase2(B, Position);
    Exit;
  end;
  case FPhase1_5Mode of
    smNone: begin
      if B = Ord('"') then begin
         FPhase1_5Mode := smOpen;
         FPhase1_5Token.Kind := tkString;
         FPhase1_5Token.Position := Position;
         FPhase1_5Token.Data := '';
      end
      else begin
        Phase2(B, Position);
      end;
    end;
    smOpen: begin
      Inc(FPhase1_5Token.Position.Length);
      if B = Ord('"') then begin
         FPhase1_5Mode := smNone;
         Phase2B(FPhase1_5Token);
      end
      else if B = Ord('\') then begin
         FPhase1_5Mode := smEscape;
      end
      else begin
        FPhase1_5Token.Data := FPhase1_5Token.Data + Chr(B);
      end;
    end;
    smEscape: begin
      Inc(FPhase1_5Token.Position.Length);
      case B of
        92: begin // \
          FPhase1_5Token.Data := FPhase1_5Token.Data + Chr(B);
          FPhase1_5Mode := smOpen;
        end;
        110: begin // n
          FPhase1_5Token.Data := FPhase1_5Token.Data + Chr(10);
          FPhase1_5Mode := smOpen;
        end;
        34: begin // "
          FPhase1_5Token.Data := FPhase1_5Token.Data + Chr(B);
          FPhase1_5Mode := smOpen;
        end;
        else begin
          Error('Unrecognized escape sequence', Position);
          FPhase1_5Token.Data := FPhase1_5Token.Data + Chr(B);
          FPhase1_5Mode := smOpen;
        end;
      end;
    end;
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
      if (FPhase2PreviousCharType = ctLetter) or (FPhase2PreviousCharType = ctNumber) then begin
        Inc(FPhase2Token.Position.Length);
        FPhase2Token.Data := FPhase2Token.Data + Chr(B);   // bad mkay
      end
      else begin
        if FPhase2Token.Kind <> tkEof then
          Phase3(FPhase2Token);
        FPhase2PreviousCharType := ctLetter;
        FPhase2Token.Position := Position;
        FPhase2Token.Kind := tkIdentifier;
        FPhase2Token.Data := '' + Chr(B);   // bad mkay
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
        FPhase2Token.Kind := tkNumber;
        FPhase2Token.Data := '' + Chr(B);   // bad mkay
      end;
    end;
    ctSymbol: begin
      if FPhase2Token.Kind <> tkEof then
        Phase3(FPhase2Token);
      FPhase2PreviousCharType := ctSymbol;
      FPhase2Token.Position := Position;
      FPhase2Token.Kind := tkSymbol;
      FPhase2Token.Data := '' + Chr(B);   // bad mkay
      Phase3(FPhase2Token);
      FPhase2Token.Kind := tkEof;
      FPhase2Token.Data := '';
    end;
  end;
end;

procedure TSourceFile.Phase2B(Token: TToken);
begin
  FPhase2PreviousCharType := ctEof;
  if FPhase2Token.Kind <> tkEof then
    Phase3(FPhase2Token);
  FPhase2Token.Kind := tkEof;
  FPhase2Token.Data := '';
  Phase3(Token);
end;

// Parses more than strictly floating point numbers
// including integers, hex, bin and octal literals
// and also a good amount of invalid forms.
procedure TSourceFile.Phase3(Token: TToken);
begin
  if FPhase3Mode <> fmNone then begin
    if Token.Position.Offset <> FPhase3Token.Position.Offset + FPhase3Token.Position.Length then begin
      Phase4(FPhase3Token);
      FPhase3Mode := fmNone;
    end;
  end;
  case FPhase3Mode of
    fmNone: begin
      if Token.Kind = tkNumber then begin
        FPhase3Token := Token;
        FPhase3Mode := fmPrefix;
        Exit;
      end;
      if (Token.Kind = tkSymbol) and (Token.Data = '-') then begin
        FPhase3Token := Token;
        FPhase3Mode := fmMinus;
        Exit;
      end;
      if (Token.Kind = tkSymbol) and (Token.Data = '.') then begin
        FPhase3Token := Token;
        FPhase3Mode := fmNakedDot;
        Exit;
      end;
      Phase4(Token);
    end;
    fmNakedDot: begin
      if Token.Kind = tkNumber then begin
        Inc(FPhase3Token.Position.Length, Token.Position.Length);
        FPhase3Token.Data := FPhase3Token.Data + Token.Data;
        FPhase3Token.Kind := tkNumber;
        FPhase3Mode := fmFraction;
        Exit;
      end;
      Phase4(FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmMinus: begin
      if Token.Kind = tkNumber then begin
        Inc(FPhase3Token.Position.Length, Token.Position.Length);
        FPhase3Token.Data := FPhase3Token.Data + Token.Data;
        FPhase3Token.Kind := tkNumber;
        FPhase3Mode := fmPrefix;
        Exit;
      end;
      if (Token.Kind = tkSymbol) and (Token.Data = '.') then begin
        Inc(FPhase3Token.Position.Length, Token.Position.Length);
        FPhase3Token.Data := FPhase3Token.Data + Token.Data;
        FPhase3Mode := fmDot;
        Exit;
      end;
      Phase4(FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmPrefix: begin
      if (Token.Kind = tkSymbol) and (Token.Data = '.') then begin
        Inc(FPhase3Token.Position.Length, Token.Position.Length);
        FPhase3Token.Data := FPhase3Token.Data + Token.Data;
        FPhase3Mode := fmDot;
        Exit;
      end;
      if AnsiEndsText('e', FPhase3Token.Data) and not (AnsiStartsText('0x', FPhase3Token.Data) or AnsiStartsText('-0x', FPhase3Token.Data)) then begin
        if (Token.Kind = tkSymbol) and ((Token.Data = '-') or (Token.Data = '+')) then begin
          Inc(FPhase3Token.Position.Length, Token.Position.Length);
          FPhase3Token.Data := FPhase3Token.Data + Token.Data;
          FPhase3Mode := fmSignedExponent;
          Exit;
        end;
        if Token.Kind = tkNumber then begin
          Inc(FPhase3Token.Position.Length, Token.Position.Length);
          FPhase3Token.Data := FPhase3Token.Data + Token.Data;
          Phase4(FPhase3Token);
          FPhase3Mode := fmNone;
          Exit;
        end;
      end;
      Phase4(FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmDot: begin
      if Token.Kind = tkNumber then begin
        Inc(FPhase3Token.Position.Length, Token.Position.Length);
        FPhase3Token.Data := FPhase3Token.Data + Token.Data;
        FPhase3Mode := fmFraction;
        Exit;
      end;
      if Token.Kind = tkIdentifier then begin
        Inc(FPhase3Token.Position.Length, Token.Position.Length);
        FPhase3Token.Data := FPhase3Token.Data + Token.Data;
        Phase4(FPhase3Token);
        FPhase3Mode := fmNone;
        Exit;
      end;
      Phase4(FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmFraction: begin
      if AnsiEndsText('e', FPhase3Token.Data) and not (AnsiStartsText('0x', FPhase3Token.Data) or AnsiStartsText('-0x', FPhase3Token.Data)) then begin
        if (Token.Kind = tkSymbol) and ((Token.Data = '-') or (Token.Data = '+')) then begin
          Inc(FPhase3Token.Position.Length, Token.Position.Length);
          FPhase3Token.Data := FPhase3Token.Data + Token.Data;
          FPhase3Mode := fmSignedExponent;
          Exit;
        end;
        if Token.Kind = tkNumber then begin
          Inc(FPhase3Token.Position.Length, Token.Position.Length);
          FPhase3Token.Data := FPhase3Token.Data + Token.Data;
          Phase4(FPhase3Token);
          FPhase3Mode := fmNone;
          Exit;
        end;
      end;
      Phase4(FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmSignedExponent: begin
      if Token.Kind = tkNumber then begin
        Inc(FPhase3Token.Position.Length, Token.Position.Length);
        FPhase3Token.Data := FPhase3Token.Data + Token.Data;
        Phase4(FPhase3Token);
        FPhase3Mode := fmNone;
        Exit;
      end;
      Phase4(FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
  end;
end;

procedure TSourceFile.Phase4(Token: TToken);
begin
  FOutput.Append('Token' + DescribeToken(Token));
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

  Operators.Add('+');
  Operators.Add('-');
  Operators.Add('!');
  Operators.Add('~');
  Operators.Add('*');
  Operators.Add('|');
  Operators.Add('&');
  Operators.Add('^');
  Operators.Add('%');
  Operators.Add('(');
  Operators.Add(')');
  Operators.Add('[');
  Operators.Add(']');
  Operators.Add('<');
  Operators.Add('>');
  Operators.Add('.');
  Operators.Add(',');
  Operators.Add('?');
  Operators.Add(':');
  Operators.Add('=');
  Operators.Add('::');
  Operators.Add('++');
  Operators.Add('--');
  Operators.Add('->');
  Operators.Add('<<');
  Operators.Add('>>');
  Operators.Add('>>>');
  Operators.Add('<=');
  Operators.Add('>=');
  Operators.Add('==');
  Operators.Add('===');
  Operators.Add('!=');
  Operators.Add('!==');
  Operators.Add('&&');
  Operators.Add('||');
  Operators.Add('??');
  Operators.Add('+=');
  Operators.Add('-=');
  Operators.Add('*=');
  Operators.Add('/=');
  Operators.Add('%=');
  Operators.Add('<<=');
  Operators.Add('>>=');
  Operators.Add('>>>=');
  Operators.Add('&=');
  Operators.Add('^=');
  Operators.Add('|=');
end;

procedure TSourceFile.Error(const Message: String; Position: TLocation);
begin
  FOutput.Append('Error: '+Message+' '+DescribeLocation(Position));
end;

initialization
  BuildCharTypeMapping;
  BuildOperators;

finalization
  FreeAndNil(Operators);

end.
