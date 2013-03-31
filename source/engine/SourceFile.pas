unit SourceFile;

interface

uses
  SourceLocation,
  SourceToken,
  Classes,
  SysUtils,
  StrUtils,
  StringBuilder;

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
    FPhase1_5Buffer: TStringBuilder;
    FPhase2Token: TToken;
    FPhase2Buffer: TStringBuilder;
    FPhase2PreviousCharType: TCharType;
    FPhase3Mode: TFloatMode;
    FPhase3Token: TToken;
    FPhase3Buffer: TStringBuilder;

    procedure Phase1(B: Byte); // locations and newline conversion
    procedure Phase1_5(B: Byte; const Position: TLocation); // Strings
    procedure Phase2(B: Byte; const Position: TLocation); // first tokenization pass
    procedure Phase2B(const Token: TToken);
    procedure Phase3(const Token: TToken); // floating point
    procedure Phase4(const Token: TToken);

    procedure Error(const Message: String; Position: TLocation);

  end;

implementation

constructor TSourceFile.Create;
begin
  FOutput := TStringList.Create;
  FPhase1_5Buffer := TStringBuilder.Create;
  FPhase2Buffer := TStringBuilder.Create;
  FPhase3Buffer := TStringBuilder.Create;
end;

destructor TSourceFile.Destroy;
begin
  FOutput.Free;
  FPhase1_5Buffer.Free;
  FPhase2Buffer.Free;
  FPhase3Buffer.Free;
end;

procedure TSourceFile.ReadFromFile(const FileName: String);
var
  Stream: TFileStream;
  Size: Integer;
  I: Integer;
  Buffer: array of Byte;
begin
  FPhase1Position.Line := 1;
  FPhase1Position.Column := 1;
  FPhase1Position.Offset := 0;
  FPhase1Position.Length := 1;

  FPhase1_5Mode := smNone;
  FPhase1_5Token.Kind := tkEof;

  FPhase2Token.Kind := tkEof;
  FPhase2PreviousCharType := ctEof;

  Stream := TFileStream.Create(FileName, fmOpenRead);
  try
    Size := Stream.Size;
    SetLength(Buffer, Size);
    Stream.ReadBuffer(Buffer[0], Size);
  finally
    Stream.Free;
  end;
  for I := 0 to Size-1 do begin
    Phase1(Buffer[I]);
  end;
  Phase1(0);
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

procedure TSourceFile.Phase1_5(B: Byte; const Position: TLocation);
begin
  if CharTypeMapping[B] = ctEof then begin
    if FPhase1_5Mode <> smNone then begin
      Error('Unterminated string constant', FPhase1_5Token.Position);
      FPhase1_5Token.Data := FPhase1_5Buffer.ToString;
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
         FPhase1_5Buffer.Clear;
      end
      else begin
        Phase2(B, Position);
      end;
    end;
    smOpen: begin
      Inc(FPhase1_5Token.Position.Length);
      if B = Ord('"') then begin
         FPhase1_5Mode := smNone;
         FPhase1_5Token.Data := FPhase1_5Buffer.ToString;
         Phase2B(FPhase1_5Token);
      end
      else if B = Ord('\') then begin
         FPhase1_5Mode := smEscape;
      end
      else begin
        FPhase1_5Buffer.AppendByte(B);
      end;
    end;
    smEscape: begin
      Inc(FPhase1_5Token.Position.Length);
      case B of
        92: begin // \
          FPhase1_5Buffer.AppendByte(B);
          FPhase1_5Mode := smOpen;
        end;
        110: begin // n
          FPhase1_5Buffer.AppendByte(B);
          FPhase1_5Mode := smOpen;
        end;
        34: begin // "
          FPhase1_5Buffer.AppendByte(B);
          FPhase1_5Mode := smOpen;
        end;
        else begin
          Error('Unrecognized escape sequence', Position);
          FPhase1_5Buffer.AppendByte(B);
          FPhase1_5Mode := smOpen;
        end;
      end;
    end;
  end;
end;

procedure TSourceFile.Phase2(B: Byte; const Position: TLocation);
begin
  case CharTypeMapping[B] of
    ctEof: begin
      FPhase2PreviousCharType := ctEof;
      if FPhase2Token.Kind <> tkEof then begin
        FPhase2Token.Data := FPhase2Buffer.ToString;
        Phase3(FPhase2Token);
      end;
      FPhase2Token.Position := Position;
      FPhase2Token.Kind := tkEof;
      FPhase2Token.Data := '';
      Phase3(FPhase2Token);
    end;
    ctWhitespace: begin
      if FPhase2PreviousCharType <> ctWhitespace then begin
        if FPhase2Token.Kind <> tkEof then begin
          FPhase2Token.Data := FPhase2Buffer.ToString;
          Phase3(FPhase2Token);
        end;
      end;
      FPhase2PreviousCharType := ctWhitespace;
      FPhase2Token.Position := Position;
      FPhase2Token.Kind := tkEof;
      FPhase2Token.Data := '';
    end;
    ctLetter: begin
      if (FPhase2PreviousCharType = ctLetter) or (FPhase2PreviousCharType = ctNumber) then begin
        Inc(FPhase2Token.Position.Length);
        FPhase2Buffer.AppendByte(B);
      end
      else begin
        if FPhase2Token.Kind <> tkEof then begin
          FPhase2Token.Data := FPhase2Buffer.ToString;
          Phase3(FPhase2Token);
        end;
        FPhase2PreviousCharType := ctLetter;
        FPhase2Token.Position := Position;
        FPhase2Token.Kind := tkIdentifier;
        FPhase2Token.Data := '';
        FPhase2Buffer.Clear();
        Fphase2Buffer.AppendByte(B);
      end;
    end;
    ctNumber: begin
      if (FPhase2PreviousCharType = ctLetter) or (FPhase2PreviousCharType = ctNumber) then begin
        Inc(FPhase2Token.Position.Length);
        Fphase2Buffer.AppendByte(B);
      end
      else begin
        if FPhase2Token.Kind <> tkEof then begin
          FPhase2Token.Data := FPhase2Buffer.ToString;
          Phase3(FPhase2Token);
        end;
        FPhase2PreviousCharType := ctNumber;
        FPhase2Token.Position := Position;
        FPhase2Token.Kind := tkNumber;
        Fphase2Buffer.Clear();
        Fphase2Buffer.AppendByte(B);
      end;
    end;
    ctSymbol: begin
      if FPhase2Token.Kind <> tkEof then begin
        FPhase2Token.Data := FPhase2Buffer.ToString;
        Phase3(FPhase2Token);
      end;
      FPhase2PreviousCharType := ctSymbol;
      FPhase2Token.Position := Position;
      FPhase2Token.Kind := tkSymbol;
      FPhase2Token.Data := Chr(B);   // bad mkay
      Phase3(FPhase2Token);
      FPhase2Token.Kind := tkEof;
      FPhase2Token.Data := '';
    end;
  end;
end;

procedure TSourceFile.Phase2B(const Token: TToken);
begin
  FPhase2PreviousCharType := ctEof;
  if FPhase2Token.Kind <> tkEof then begin
    FPhase2Token.Data := FPhase2Buffer.ToString;
    Phase3(FPhase2Token);
  end;
  FPhase2Token.Kind := tkEof;
  FPhase2Token.Data := '';
  Phase3(Token);
end;

// Parses more than strictly floating point numbers
// including integers, hex, bin and octal literals
// and also a good amount of invalid forms.
procedure TSourceFile.Phase3(const Token: TToken);
var
  S: String;
begin
  if FPhase3Mode <> fmNone then begin
    if Token.Position.Offset <> FPhase3Token.Position.Offset + FPhase3Token.Position.Length then begin
      FPhase3Token.Data := FPhase3Buffer.ToString;
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
        FPhase3Buffer.Clear();
        FPhase3Buffer.AppendString(FPhase3Token.Data);
        FPhase3Buffer.AppendString(Token.Data);
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
        FPhase3Buffer.Clear();
        FPhase3Buffer.AppendString(FPhase3Token.Data);
        FPhase3Buffer.AppendString(Token.Data);
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
        FPhase3Buffer.Clear();
        FPhase3Buffer.AppendString(FPhase3Token.Data);
        FPhase3Buffer.AppendString(Token.Data);
        FPhase3Mode := fmDot;
        Exit;
      end;
      if AnsiEndsText('e', FPhase3Token.Data) and not (AnsiStartsText('0x', FPhase3Token.Data) or AnsiStartsText('-0x', FPhase3Token.Data)) then begin
        if (Token.Kind = tkSymbol) and ((Token.Data = '-') or (Token.Data = '+')) then begin
          Inc(FPhase3Token.Position.Length, Token.Position.Length);
          FPhase3Buffer.Clear();
          FPhase3Buffer.AppendString(FPhase3Token.Data);
          FPhase3Buffer.AppendString(Token.Data);
          FPhase3Mode := fmSignedExponent;
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
        FPhase3Buffer.AppendString(Token.Data);
        FPhase3Mode := fmFraction;
        Exit;
      end;
      if Token.Kind = tkIdentifier then begin
        Inc(FPhase3Token.Position.Length, Token.Position.Length);
        FPhase3Buffer.AppendString(Token.Data);
        FPhase3Token.Data := FPhase3Buffer.ToString;
        Phase4(FPhase3Token);
        FPhase3Mode := fmNone;
        Exit;
      end;
      FPhase3Token.Data := FPhase3Buffer.ToString;
      Phase4(FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmFraction: begin
      S := FPhase3Buffer.ToString;
      if AnsiEndsText('e', S) and not (AnsiStartsText('0x', S) or AnsiStartsText('-0x', S)) then begin
        if (Token.Kind = tkSymbol) and ((Token.Data = '-') or (Token.Data = '+')) then begin
          Inc(FPhase3Token.Position.Length, Token.Position.Length);
          FPhase3Buffer.AppendString(Token.Data);
          FPhase3Mode := fmSignedExponent;
          Exit;
        end;
        if Token.Kind = tkNumber then begin
          Inc(FPhase3Token.Position.Length, Token.Position.Length);
          FPhase3Buffer.AppendString(Token.Data);
          Phase4(FPhase3Token);
          FPhase3Mode := fmNone;
          Exit;
        end;
      end;
      FPhase3Token.Data := S;
      Phase4(FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmSignedExponent: begin
      if Token.Kind = tkNumber then begin
        Inc(FPhase3Token.Position.Length, Token.Position.Length);
        FPhase3Buffer.AppendString(Token.Data);
        Phase4(FPhase3Token);
        FPhase3Mode := fmNone;
        Exit;
      end;
      FPhase3Token.Data := FPhase3Buffer.ToString;
      Phase4(FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
  end;
end;

procedure TSourceFile.Phase4(const Token: TToken);
begin
  if FOutput.Count < 1000 then
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
  if FOutput.Count < 1000 then
    FOutput.Append('Error: '+Message+' '+DescribeLocation(Position));
end;

initialization
  BuildCharTypeMapping;
  BuildOperators;

finalization
  FreeAndNil(Operators);

end.
