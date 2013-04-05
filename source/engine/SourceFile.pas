unit SourceFile;

interface

uses
  SourceLocation,
  SourceToken,
  SourceNode,
  Classes,
  SysUtils,
  StrUtils,
  StringBuilder;

type
  TCharType = (ctEof, ctWhitespace, ctLetter, ctNumber, ctSymbol);
  TStringMode = (smNone, smAt, smOpen, smOpenRaw, smEscape, smRawEscape, smCharOpen, smCharEscape, smSlash, smLineComment, smBlockComment, smBlockCommentStar, smWildEscape); //, smUnicode4, smUnicode3, smUnicode2, smUnicode1)
  TFloatMode = (fmNone, fmMinus, fmNakedDot, fmPrefix, fmDot, fmFraction, fmSignedExponent);
  TBracketKind = (bkCurly, bkParens, bkBlock, bkAngle);
  TSeperatorKind = (skSemicolon, skComma);

  TSourceFile = class
  public
    FErrors: TStringList;
    FOutput: TSourceNode;
    constructor Create;
    destructor Destroy; override;

    procedure ReadFromFile(const FileName: String);

  private
    FPhase1Position: TLocation;
    FPhase1_2Mode: Boolean;
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
    procedure Phase1_1(B: Byte; Position: PLocation);
    procedure Phase1_5(B: Byte; Position: PLocation); // Strings
    procedure Phase1_5B(B: Byte; Position: PLocation); // Strings
    procedure Phase2(B: Byte; Position: PLocation); // first tokenization pass
    procedure Phase2B(Token: PToken);
    procedure Phase2C(B: Byte; Position: PLocation);
    procedure Phase3(Token: PToken); // floating point
    procedure Phase3B(Token: PToken); // floating point
    procedure Phase4(Token: PToken);

    procedure Error(const Message: String; Position: TLocation);

    procedure Group;
    procedure GroupByBrackets(Node: TSourceNode; BracketKind: TBracketKind; Kind: TSourceNodeKind);
    procedure GroupByBrackets_B(Node: TSourceNode; BracketKind: TBracketKind; Kind: TSourceNodeKind);
    procedure GroupBySeperator(Node: TSourceNode; SeperatorKind: TSeperatorKind);

    procedure ParseOperators;

  end;

implementation

type
  TFix = (fInfix, fPrefix, fPostfix);
  TOperatorRecord = record
    Key: Cardinal;
    Data: String;
    Fixness: TFix;
  end;

var
  RootNodeKind: TSourceNodeKind;
  SymbolNodeKind: TSourceNodeKind;
  CurlyBracketNodeKind: TSourceNodeKind;
  AngleBracketNodeKind: TSourceNodeKind;
  SquareBracketNodeKind: TSourceNodeKind;
  ParensNodeKind: TSourceNodeKind;
  CharTypeMapping : array[Byte] of TCharType;
  Operators : array of TOperatorRecord;
  SNK: array[TTokenKind] of TSourceNodeKind;
  OpenBracket: array[TBracketKind] of String;
  CloseBracket: array[TBracketKind] of String;
  BracketRequired: array[TBracketKind] of Boolean;
  Seperator: array[TSeperatorKind] of String;

constructor TSourceFile.Create;
begin
  FErrors := TStringList.Create;
  FPhase1_5Buffer := TStringBuilder.Create;
  FPhase2Buffer := TStringBuilder.Create;
  FPhase3Buffer := TStringBuilder.Create;

  FOutput := TSourceNode.Create;
  FOutput.Kind := RootNodeKind;
end;

destructor TSourceFile.Destroy;
begin
  FOutput.FreeChildren;
  FOutput.Free;
  FErrors.Free;
  FPhase1_5Buffer.Free;
  FPhase2Buffer.Free;
  FPhase3Buffer.Free;
end;

procedure TSourceFile.ReadFromFile(const FileName: String);
var
  Stream: TFileStream;
  Size, Len: Integer;
  I: Integer;
  Buffer: array of Byte;
const
  BufferSize = 65536;
begin
  FOutput.Data := FileName;

  FPhase1Position.Line := 1;
  FPhase1Position.Column := 1;
  FPhase1Position.Offset := 0;
  FPhase1Position.EndOffset := 1;

  FPhase1_2Mode := False;

  FPhase1_5Mode := smNone;
  FPhase1_5Token.Kind := tkEof;

  FPhase2Token.Kind := tkEof;
  FPhase2PreviousCharType := ctEof;

  Stream := TFileStream.Create(FileName, fmOpenRead);
  try
    Size := Stream.Size;
    SetLength(Buffer, BufferSize);
    while Size > 0 do begin
      Len := Size;
      if Len > BufferSize then
        Len := BufferSize;
      Stream.ReadBuffer(Buffer[0], Len);
      for I := 0 to Len-1 do begin
        Phase1(Buffer[I]);
      end;
      Dec(Size, Len);
    end;
  finally
    Stream.Free;
  end;
  Phase1(0);
  Group;
  ParseOperators;
end;

procedure TSourceFile.Phase1(B: Byte);
begin
  if B = 0 then begin
    Phase1_1(B, @FPhase1Position);
    Exit;
  end;
  if B = 13 then begin
    Inc(FPhase1Position.Offset);
    Inc(FPhase1Position.EndOffset);
    Exit; // Dos newlines are a bother
  end;
  Phase1_1(B, @FPhase1Position);
  Inc(FPhase1Position.Offset);
  Inc(FPhase1Position.EndOffset);
  Inc(FPhase1Position.Column);
  if B = 10 then
  begin
    Inc(FPhase1Position.Line);
    FPhase1Position.Column := 1;
  end;
end;

procedure TSourceFile.Phase1_1(B: Byte; Position: PLocation);
begin
  if FPhase1_2Mode then begin
    FPhase1_2Mode := False;
    if B = 10 then
      Exit;
    Dec(Position.Offset);
    Dec(Position.EndOffset);
    Dec(Position.Column);
    Phase1_5(92, Position);
    Inc(Position.Offset);
    Inc(Position.EndOffset);
    Inc(Position.Column);
  end;
  if B = 92 then begin
    FPhase1_2Mode := True;
    Exit;
  end;
  Phase1_5(B, Position);
end;

procedure TSourceFile.Phase1_5(B: Byte; Position: PLocation);
begin
  if (CharTypeMapping[B] <> ctEof) and (FPhase1_5Mode = smNone) and (B <> 34) and (B <> 47) and (B <> 39) and (B <> 92) and (B <> 64) and (B <> 35) then begin
    Phase2(B, Position);
  end
  else begin
    Phase1_5B(B, Position);
  end;
end;

procedure TSourceFile.Phase1_5B(B: Byte; Position: PLocation);
begin
  if CharTypeMapping[B] = ctEof then begin
    if FPhase1_5Mode = smSlash then begin
      Phase2(47, @FPhase1_5Token.Position);
      FPhase1_5Mode := smNone;
    end
    else
    if FPhase1_5Mode = smAt then begin
      Phase2(64, @FPhase1_5Token.Position);
      FPhase1_5Mode := smNone;
    end
    else
    if FPhase1_5Mode <> smNone then begin
      if (FPhase1_5Mode =  smOpen) or (FPhase1_5Mode = smEscape) or (FPhase1_5Mode = smOpenRaw) or (FPhase1_5Mode = smRawEscape) then
        Error('Unterminated string constant', FPhase1_5Token.Position);
      if (FPhase1_5Mode =  smCharOpen) or (FPhase1_5Mode = smCharEscape) then
        Error('Unterminated character constant', FPhase1_5Token.Position);
      if (FPhase1_5Mode =  smBlockComment) or (FPhase1_5Mode = smBlockCommentStar) then
        Error('Unterminated comment', FPhase1_5Token.Position);
      FPhase1_5Token.Data := FPhase1_5Buffer.ToString;
      Phase2B(@FPhase1_5Token);
      FPhase1_5Mode := smNone;
    end;
    Phase2(B, Position);
    Exit;
  end;
  case FPhase1_5Mode of
    smNone: begin
      if B = 34 then begin
         FPhase1_5Mode := smOpen;
         FPhase1_5Token.Kind := tkString;
         FPhase1_5Token.Position := Position^;
         FPhase1_5Buffer.Clear;
      end
      else
      if B = 39 then begin
         FPhase1_5Mode := smCharOpen;
         FPhase1_5Token.Kind := tkCharacter;
         FPhase1_5Token.Position := Position^;
         FPhase1_5Buffer.Clear;
      end
      else
      if B = 47 then begin
         FPhase1_5Mode := smSlash;
         FPhase1_5Token.Kind := tkComment;
         FPhase1_5Token.Position := Position^;
         FPhase1_5Buffer.Clear;
         FPhase1_5Buffer.AppendByte(B);
      end
      else
      if B = 92 then begin
         FPhase1_5Mode := smWildEscape;
         FPhase1_5Token.Position := Position^;
         FPhase1_5Buffer.Clear;
      end
      else
      if B = 35 then begin
         FPhase1_5Mode := smLineComment;
         FPhase1_5Token.Position := Position^;
         FPhase1_5Buffer.Clear;
         FPhase1_5Buffer.AppendByte(B);
      end
      else
      if B = 64 then begin
         FPhase1_5Mode := smAt;
         FPhase1_5Token.Position := Position^;
      end
      else
      begin
        Phase2(B, Position);
      end;
    end;
    smAt: begin
      if B <> 34 then begin
        Phase2(64, @FPhase1_5Token.Position);
        FPhase1_5Mode := smNone;
        Phase1_5B(B, Position);
        Exit;
      end;
      FPhase1_5Mode := smOpenRaw;
      FPhase1_5Token.Kind := tkString;
      FPhase1_5Buffer.Clear;
    end;
    smOpen: begin
      FPhase1_5Token.Position.EndOffset := Position.EndOffset;
      if B = 34 then begin
         FPhase1_5Mode := smNone;
         FPhase1_5Token.Data := FPhase1_5Buffer.ToString;
         Phase2B(@FPhase1_5Token);
      end
      else if B = 92 then begin
         FPhase1_5Mode := smEscape;
      end
      else begin
        FPhase1_5Buffer.AppendByte(B);
      end;
    end;
    smOpenRaw: begin
      FPhase1_5Token.Position.EndOffset := Position.EndOffset;
      if B = 34 then begin
         FPhase1_5Mode := smRawEscape;
      end
      else begin
        FPhase1_5Buffer.AppendByte(B);
      end;
    end;
    smRawEscape: begin
      FPhase1_5Token.Position.EndOffset := Position.EndOffset;
      if B = 34 then begin
        FPhase1_5Buffer.AppendByte(34);
        FPhase1_5Mode := smOpenRaw;
        Exit;
      end;
      FPhase1_5Mode := smNone;
      FPhase1_5Token.Data := FPhase1_5Buffer.ToString;
      Phase2B(@FPhase1_5Token);
      Phase1_1(B, Position);
      Exit;
    end;
    smEscape: begin
      FPhase1_5Token.Position.EndOffset := Position.EndOffset;
      FPhase1_5Mode := smOpen;
      case B of
        92: begin // \
          FPhase1_5Buffer.AppendByte(B);
        end;
        48: begin // 0
          FPhase1_5Buffer.AppendByte(0);
        end;
        97: begin // a
          FPhase1_5Buffer.AppendByte(7);
        end;
        98: begin // b
          FPhase1_5Buffer.AppendByte(8);
        end;
        102: begin // f
          FPhase1_5Buffer.AppendByte(12);
        end;
        110: begin // n
          FPhase1_5Buffer.AppendByte(10);
        end;
        114: begin // r // don't use plz
          FPhase1_5Buffer.AppendByte(13);
        end;
        116: begin // t
          FPhase1_5Buffer.AppendByte(9);
        end;
        118: begin // v
          FPhase1_5Buffer.AppendByte(11);
        end;
        34: begin // "
          FPhase1_5Buffer.AppendByte(B);
        end;
        39: begin // '
          FPhase1_5Buffer.AppendByte(B);
        end;
        //placeholdery
        120: begin // x
          FPhase1_5Buffer.AppendByte(92);
          FPhase1_5Buffer.AppendByte(B);
        end;
        117: begin // u
          FPhase1_5Buffer.AppendByte(92);
          FPhase1_5Buffer.AppendByte(B);
        end;
        86: begin // U
          FPhase1_5Buffer.AppendByte(92);
          FPhase1_5Buffer.AppendByte(B);
        end;
        else begin
          Error('Unrecognized escape sequence', Position^);
        end;
      end;
    end;
    smCharOpen: begin
      FPhase1_5Token.Position.EndOffset := Position.EndOffset;
      if B = 39 then begin
         FPhase1_5Mode := smNone;
         FPhase1_5Token.Data := FPhase1_5Buffer.ToString;
         Phase2B(@FPhase1_5Token);
      end
      else if B = 92 then begin
         FPhase1_5Mode := smCharEscape;
      end
      else begin
        FPhase1_5Buffer.AppendByte(B);
      end;
    end;
    smCharEscape: begin
      FPhase1_5Token.Position.EndOffset := Position.EndOffset;
      FPhase1_5Mode := smCharOpen;
      case B of
        92: begin // \
          FPhase1_5Buffer.AppendByte(B);
        end;
        48: begin // 0
          FPhase1_5Buffer.AppendByte(0);
        end;
        97: begin // a
          FPhase1_5Buffer.AppendByte(7);
        end;
        98: begin // b
          FPhase1_5Buffer.AppendByte(8);
        end;
        102: begin // f
          FPhase1_5Buffer.AppendByte(12);
        end;
        110: begin // n
          FPhase1_5Buffer.AppendByte(10);
        end;
        114: begin // r // don't use plz
          FPhase1_5Buffer.AppendByte(13);
        end;
        116: begin // t
          FPhase1_5Buffer.AppendByte(9);
        end;
        118: begin // v
          FPhase1_5Buffer.AppendByte(11);
        end;
        34: begin // "
          FPhase1_5Buffer.AppendByte(B);
        end;
        39: begin // '
          FPhase1_5Buffer.AppendByte(B);
        end;
        //placeholdery
        120: begin // x
          FPhase1_5Buffer.AppendByte(92);
          FPhase1_5Buffer.AppendByte(B);
        end;
        117: begin // u
          FPhase1_5Buffer.AppendByte(92);
          FPhase1_5Buffer.AppendByte(B);
        end;
        86: begin // U
          FPhase1_5Buffer.AppendByte(92);
          FPhase1_5Buffer.AppendByte(B);
        end;
        else begin
          Error('Unrecognized escape sequence', Position^);
          FPhase1_5Mode := smCharOpen;
        end;
      end;
    end;
    smSlash: begin
      if B = 47 then begin
        FPhase1_5Buffer.AppendByte(B);
        FPhase1_5Mode := smLineComment;
      end
      else if B = 42 then begin
        FPhase1_5Buffer.AppendByte(B);
        FPhase1_5Mode := smBlockComment;
      end
      else begin
        Phase2(47, @FPhase1_5Token.Position);
        Phase2(B, Position);
         FPhase1_5Mode := smNone;
      end;
    end;
    smLineComment: begin
      if B = 10 then begin
        FPhase1_5Token.Data := FPhase1_5Buffer.ToString;
        FPhase1_5Mode := smNone;
        Phase2B(@FPhase1_5Token);
        Phase2(B, Position);
      end
      else
      begin
         FPhase1_5Buffer.AppendByte(B);
      end;
    end;
    smBlockComment: begin
      if B = 42 then
        FPhase1_5Mode := smBlockCommentStar;
      FPhase1_5Buffer.AppendByte(B);
    end;
    smBlockCommentStar: begin
      FPhase1_5Buffer.AppendByte(B);
      if B = 47 then begin
        FPhase1_5Token.Data := FPhase1_5Buffer.ToString;
        FPhase1_5Mode := smNone;
        Phase2B(@FPhase1_5Token);
      end
      else if B <> 42 then
        FPhase1_5Mode := smBlockComment;
    end;
    smWildEscape: begin
      if B <> 10 then begin
        Phase2(92, @FPhase1_5Token.Position);
        Phase2(B, Position);
      end;
      FPhase1_5Mode := smNone;
    end;
  end;
end;

procedure TSourceFile.Phase2(B: Byte; Position: PLocation);
begin
  case CharTypeMapping[B] of
    ctEof: begin
      Phase2C(B, Position);
    end;
    ctWhitespace: begin
      if FPhase2PreviousCharType <> ctWhitespace then begin
        if FPhase2Token.Kind <> tkEof then begin
          Phase2C(B, Position);
          Exit;
        end;
      end;
      FPhase2PreviousCharType := ctWhitespace;
    end;
    ctLetter: begin
      if (FPhase2PreviousCharType = ctLetter) or (FPhase2PreviousCharType = ctNumber) then begin
        FPhase2Token.Position.EndOffset := Position.EndOffset;
        FPhase2Buffer.AppendByte(B);
      end
      else begin
        Phase2C(B, Position);
        Exit;
      end;
    end;
    ctNumber: begin
      if (FPhase2PreviousCharType = ctLetter) or (FPhase2PreviousCharType = ctNumber) then begin
        FPhase2Token.Position.EndOffset := Position.EndOffset;
        Fphase2Buffer.AppendByte(B);
      end
      else begin
        Phase2C(B, Position);
        Exit;
      end;
    end;
    ctSymbol: begin
      Phase2C(B, Position);
      Exit;
    end;
  end;
end;

procedure TSourceFile.Phase2C(B: Byte; Position: PLocation);
begin
  case CharTypeMapping[B] of
    ctEof: begin
      if FPhase2Token.Kind <> tkEof then begin
        FPhase2Token.Data := FPhase2Buffer.ToString;
        Phase3(@FPhase2Token);
      end;
      FPhase2PreviousCharType := ctEof;
      FPhase2Token.Position := Position^;
      FPhase2Token.Kind := tkEof;
      Phase3(@FPhase2Token);
    end;
    ctWhitespace: begin
      if FPhase2PreviousCharType <> ctWhitespace then begin
        if FPhase2Token.Kind <> tkEof then begin
          FPhase2Token.Data := FPhase2Buffer.ToString;
          Phase3(@FPhase2Token);
        end;
      end;
      FPhase2PreviousCharType := ctWhitespace;
      FPhase2Token.Kind := tkEof;
    end;
    ctLetter: begin
      if (FPhase2PreviousCharType = ctLetter) or (FPhase2PreviousCharType = ctNumber) then begin
        FPhase2Token.Position.EndOffset := Position.EndOffset;
        FPhase2Buffer.AppendByte(B);
      end
      else begin
        if FPhase2Token.Kind <> tkEof then begin
          FPhase2Token.Data := FPhase2Buffer.ToString;
          Phase3(@FPhase2Token);
        end;
        FPhase2PreviousCharType := ctLetter;
        FPhase2Token.Position := Position^;
        FPhase2Token.Kind := tkIdentifier;
        FPhase2Buffer.Clear();
        Fphase2Buffer.AppendByte(B);
      end;
    end;
    ctNumber: begin
      if (FPhase2PreviousCharType = ctLetter) or (FPhase2PreviousCharType = ctNumber) then begin
        FPhase2Token.Position.EndOffset := Position.EndOffset;
        Fphase2Buffer.AppendByte(B);
      end
      else begin
        if FPhase2Token.Kind <> tkEof then begin
          FPhase2Token.Data := FPhase2Buffer.ToString;
          Phase3(@FPhase2Token);
        end;
        FPhase2PreviousCharType := ctNumber;
        FPhase2Token.Position := Position^;
        FPhase2Token.Kind := tkNumber;
        Fphase2Buffer.Clear();
        Fphase2Buffer.AppendByte(B);
      end;
    end;
    ctSymbol: begin
      if FPhase2Token.Kind <> tkEof then begin
        FPhase2Token.Data := FPhase2Buffer.ToString;
        Phase3(@FPhase2Token);
      end;
      FPhase2PreviousCharType := ctSymbol;
      FPhase2Token.Position := Position^;
      FPhase2Token.Kind := tkSymbol;
      FPhase2Token.Data := CChr(B);
      Phase3(@FPhase2Token);
      FPhase2Token.Kind := tkEof;
    end;
  end;
end;

procedure TSourceFile.Phase2B(Token: PToken);
begin
  FPhase2PreviousCharType := ctEof;
  if FPhase2Token.Kind <> tkEof then begin
    FPhase2Token.Data := FPhase2Buffer.ToString;
    Phase3(@FPhase2Token);
  end;
  FPhase2Token.Kind := tkEof;
  Phase3(Token);
end;

// Parses more than strictly floating point numbers
// including integers, hex, bin and octal literals
// and also a good amount of invalid forms.
procedure TSourceFile.Phase3(Token: PToken);
begin
  if FPhase3Mode <> fmNone then begin
    if Token.Position.Offset <> FPhase3Token.Position.EndOffset then begin
      if (FPhase3Mode <> fmPrefix) and (FPhase3Mode <> fmMinus) and (FPhase3Mode <> fmNakedDot) then begin
        Phase3B(Token);
        Exit;
      end;
      Phase4(@FPhase3Token);
      FPhase3Mode := fmNone;
    end;
  end;
  case FPhase3Mode of
    fmNone: begin
      if Token.Kind = tkNumber then begin
        Phase3B(Token);
        Exit;
      end;
      if (Token.Kind = tkSymbol) and (Token.Data = '-') then begin
        Phase3B(Token);
        Exit;
      end;
      if (Token.Kind = tkSymbol) and (Token.Data = '.') then begin
        Phase3B(Token);
        Exit;
      end;
      Phase4(Token);
    end;
    fmNakedDot: begin
      if Token.Kind = tkNumber then begin
        Phase3B(Token);
        Exit;
      end;
      Phase4(@FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmMinus: begin
      if Token.Kind = tkNumber then begin
        Phase3B(Token);
        Exit;
      end;
      if (Token.Kind = tkSymbol) and (Token.Data = '.') then begin
        Phase3B(Token);
        Exit;
      end;
      Phase4(@FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmPrefix: begin
      if (Token.Kind = tkSymbol) then begin
        Phase3B(Token);
        Exit;
      end;
      Phase4(@FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmDot: begin
      if Token.Kind = tkNumber then begin
        FPhase3Token.Position.EndOffset := Token.Position.EndOffset;
        FPhase3Buffer.AppendString(Token.Data);
        FPhase3Mode := fmFraction;
        Exit;
      end;
      if Token.Kind = tkIdentifier then begin
        Phase3B(Token);
        Exit;
      end;
      Phase3B(Token);
      Exit;
    end;
    fmFraction: begin
      Phase3B(Token);
      Exit;
    end;
    fmSignedExponent: begin
      Phase3B(Token);
      Exit;
    end;
  end;
end;

procedure TSourceFile.Phase3B(Token: PToken);
var
  S: String;
begin
  if FPhase3Mode <> fmNone then begin
    if Token.Position.Offset <> FPhase3Token.Position.EndOffset then begin
      if (FPhase3Mode <> fmPrefix) and (FPhase3Mode <> fmMinus) and (FPhase3Mode <> fmNakedDot) then
        FPhase3Token.Data := FPhase3Buffer.ToString;
      Phase4(@FPhase3Token);
      FPhase3Mode := fmNone;
    end;
  end;
  case FPhase3Mode of
    fmNone: begin
      if Token.Kind = tkNumber then begin
        FPhase3Token := Token^;
        FPhase3Mode := fmPrefix;
        Exit;
      end;
      if (Token.Kind = tkSymbol) and (Token.Data = '-') then begin
        FPhase3Token := Token^;
        FPhase3Mode := fmMinus;
        Exit;
      end;
      if (Token.Kind = tkSymbol) and (Token.Data = '.') then begin
        FPhase3Token := Token^;
        FPhase3Mode := fmNakedDot;
        Exit;
      end;
      Phase4(Token);
    end;
    fmNakedDot: begin
      if Token.Kind = tkNumber then begin
        FPhase3Token.Position.EndOffset := Token.Position.EndOffset;
        FPhase3Buffer.Clear();
        FPhase3Buffer.AppendString(FPhase3Token.Data);
        FPhase3Buffer.AppendString(Token.Data);
        FPhase3Token.Kind := tkNumber;
        FPhase3Mode := fmFraction;
        Exit;
      end;
      Phase4(@FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmMinus: begin
      if Token.Kind = tkNumber then begin
        FPhase3Token.Position.EndOffset := Token.Position.EndOffset;
        FPhase3Token.Data := FPhase3Token.Data + Token.Data;
        FPhase3Token.Kind := tkNumber;
        FPhase3Mode := fmPrefix;
        Exit;
      end;
      if (Token.Kind = tkSymbol) and (Token.Data = '.') then begin
        FPhase3Token.Position.EndOffset := Token.Position.EndOffset;
        FPhase3Buffer.Clear();
        FPhase3Buffer.AppendString(FPhase3Token.Data);
        FPhase3Buffer.AppendString(Token.Data);
        FPhase3Mode := fmDot;
        Exit;
      end;
      Phase4(@FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmPrefix: begin
      if (Token.Kind = tkSymbol) and (Token.Data = '.') then begin
        FPhase3Token.Position.EndOffset := Token.Position.EndOffset;
        FPhase3Buffer.Clear();
        FPhase3Buffer.AppendString(FPhase3Token.Data);
        FPhase3Buffer.AppendString(Token.Data);
        FPhase3Mode := fmDot;
        Exit;
      end;
      if AnsiEndsText('e', FPhase3Token.Data) and not (AnsiStartsText('0x', FPhase3Token.Data) or AnsiStartsText('-0x', FPhase3Token.Data)) then begin
        if (Token.Kind = tkSymbol) and ((Token.Data = '-') or (Token.Data = '+')) then begin
          FPhase3Token.Position.EndOffset := Token.Position.EndOffset;
          FPhase3Buffer.Clear();
          FPhase3Buffer.AppendString(FPhase3Token.Data);
          FPhase3Buffer.AppendString(Token.Data);
          FPhase3Mode := fmSignedExponent;
          Exit;
        end;
      end;
      Phase4(@FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmDot: begin
      if Token.Kind = tkNumber then begin
        FPhase3Token.Position.EndOffset := Token.Position.EndOffset;
        FPhase3Buffer.AppendString(Token.Data);
        FPhase3Mode := fmFraction;
        Exit;
      end;
      if Token.Kind = tkIdentifier then begin
        FPhase3Token.Position.EndOffset := Token.Position.EndOffset;
        FPhase3Buffer.AppendString(Token.Data);
        FPhase3Token.Data := FPhase3Buffer.ToString;
        Phase4(@FPhase3Token);
        FPhase3Mode := fmNone;
        Exit;
      end;
      FPhase3Token.Data := FPhase3Buffer.ToString;
      Phase4(@FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmFraction: begin
      S := FPhase3Buffer.ToString;
      if AnsiEndsText('e', S) and not (AnsiStartsText('0x', S) or AnsiStartsText('-0x', S)) then begin
        if (Token.Kind = tkSymbol) and ((Token.Data = '-') or (Token.Data = '+')) then begin
          FPhase3Token.Position.EndOffset := Token.Position.EndOffset;
          FPhase3Buffer.AppendString(Token.Data);
          FPhase3Mode := fmSignedExponent;
          Exit;
        end;
        if Token.Kind = tkNumber then begin
          FPhase3Token.Position.EndOffset := Token.Position.EndOffset;
          FPhase3Buffer.AppendString(Token.Data);
          Phase4(@FPhase3Token);
          FPhase3Mode := fmNone;
          Exit;
        end;
      end;
      FPhase3Token.Data := S;
      Phase4(@FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
    fmSignedExponent: begin
      if Token.Kind = tkNumber then begin
        FPhase3Token.Position.EndOffset := Token.Position.EndOffset;
        FPhase3Buffer.AppendString(Token.Data);
        Phase4(@FPhase3Token);
        FPhase3Mode := fmNone;
        Exit;
      end;
      FPhase3Token.Data := FPhase3Buffer.ToString;
      Phase4(@FPhase3Token);
      FPhase3Mode := fmNone;
      Phase3(Token);
      Exit;
    end;
  end;
end;

procedure TSourceFile.Phase4(Token: PToken);
var
  SourceNode: TSourceNode;
begin
  if Token.Kind = tkEof then
    Exit;
  SourceNode := TSourceNode.Create;
  SourceNode.Position := Token.Position;
  SourceNode.Data := Token.Data;
  SourceNode.Kind := SNK[Token.Kind];

  if FOutput.LastChild = nil then begin
    FOutput.FirstChild := SourceNode;
  end
  else begin
    FOutput.LastChild.Next := SourceNode;
  end;
  SourceNode.Previous := FOutput.LastChild;
  FOutput.LastChild := SourceNode;
  SourceNode.Parent := FOutput;
end;

procedure TSourceFile.Group;
begin
  GroupByBrackets(FOutput, bkCurly, CurlyBracketNodeKind);
  GroupByBrackets(FOutput, bkParens, ParensNodeKind);
  GroupByBrackets(FOutput, bkBlock, SquareBracketNodeKind);
  GroupByBrackets(FOutput, bkAngle, AngleBracketNodeKind);
  GroupBySeperator(FOutput, skSemicolon);
  GroupBySeperator(FOutput, skComma);
end;

procedure TSourceFile.GroupByBrackets(Node: TSourceNode; BracketKind: TBracketKind; Kind: TSourceNodeKind);
var
  N: TSourceNode;
begin
  N := Node;
  while Node <> nil do begin
    if Node.FirstChild <> nil then
      GroupByBrackets(Node.FirstChild, BracketKind, Kind);
    Node := Node.Next;
  end;
  Node := N;
  while Node <> nil do begin
    if (Node.Kind = SymbolNodeKind) and (Node.Data = OpenBracket[BracketKind]) then
      GroupByBrackets_B(Node, BracketKind, Kind);
    Node := Node.Next;
  end;
end;

procedure TSourceFile.GroupByBrackets_B(Node: TSourceNode; BracketKind: TBracketKind; Kind: TSourceNodeKind);
var
  Anchor: TSourceNode;
  Terminator: TSourceNode;
  T: TSourceNode;
  EndLocation: TLocation;
begin
  Anchor := Node;
  Node := Node.Next;
  while Node <> nil do begin
    if Node.Kind = SymbolNodeKind then begin
      if Node.Data = OpenBracket[BracketKind] then begin
        GroupByBrackets_B(Node, BracketKind, Kind);
      end;
      if Node.Data = CloseBracket[BracketKind] then begin
        Break;
      end;
    end;
    Node := Node.Next;
  end;
  if Node = nil then begin
    if not BracketRequired[BracketKind] then begin
      Anchor.Data := '#' + Anchor.Data; 
      Exit;
    end;
    EndLocation := BeyondLocation(Anchor.Parent.LastChild.Position);
    Error('Expected '+CloseBracket[BracketKind], EndLocation);
    Terminator := Anchor.Parent.LastChild;
  end
  else begin
    EndLocation := Node.Position;
    Terminator := Node.Previous;
    Node.Unhook;
    Node.Free;
  end;
  Anchor.Kind := Kind;
  Anchor.Position.EndOffset := EndLocation.EndOffset;
  if Anchor <> Terminator then begin
    Node := Anchor.Next;
    while True do
    begin
      T := Node.Next;
      Node.AttachAsChildOf(Anchor);
      if Node = Terminator then
        Break;
      Node := T;
    end;
  end;
end;

procedure TSourceFile.GroupBySeperator(Node: TSourceNode; SeperatorKind: TSeperatorKind);
var
  N, C, CN: TSourceNode;
begin
  N := Node.LastChild;
  while N <> nil do begin
    GroupBySeperator(N, SeperatorKind);
    N:= N.Previous;
  end;

  N := Node.LastChild;
  while N <> nil do begin
    if (N.Kind = SymbolNodeKind) and (N.Data = Seperator[SeperatorKind]) then begin
      C := N.Next;
      while C <> nil do begin
        CN := C.Next;
        C.AttachAsChildOf(N);
        C := CN;
      end;
    end;
    N := N.Previous;
  end;
end;

procedure TSourceFile.ParseOperators;

procedure ProcessOperator(Key: Cardinal; A: TSourceNode; B: TSourceNode; C: TSourceNode; D: TSourceNode);
var
  I: Integer;
begin
  if Key < $100 then
    exit; // no need to process these
  for I := 0 to Length(Operators)-1 do begin
    if Operators[I].Key = Key then begin
      A.Data := Operators[I].Data;
      if Key >= $100 then begin
        A.Position.EndOffset := B.Position.EndOffset;
        B.Unhook;
        B.Free;
      end;
      if Key >= $10000 then begin
        A.Position.EndOffset := C.Position.EndOffset;
        C.Unhook;
        C.Free;
      end;
      if Key >= $1000000 then begin
        A.Position.EndOffset := D.Position.EndOffset;
        D.Unhook;
        D.Free;
      end;
      Exit;
    end;
  end;
  if Key >= $1000000 then
    ProcessOperator(Key and $ffffff, A, B, C, D)
  else if Key >= $10000 then
    ProcessOperator(Key and $ffff, A, B, C, D)
  else if Key >= $100 then
    ProcessOperator(Key and $ff, A, B, C, D);
end;

var
  Node: TSourceNode;
  A, B, C, D: TSourceNode;
  Key: Cardinal;
begin
  Node := FOutput;
  while Node <> nil do
  begin
    A := Node;
    B := nil;
    C := nil;
    D := nil;
    if A <> nil then
      B := A.Next;
    if B <> nil then
      C := B.Next;
    if C <> nil then
      D := C.Next;

    if (A = nil) or (A.Kind <> SymbolNodeKind) or (A.FirstChild <> nil) then
      A := nil;
    if (A = nil) or (B = nil) or (B.Kind <> SymbolNodeKind) or (B.FirstChild <> nil) then
      B := nil;
    if (B = nil) or (C = nil) or (C.Kind <> SymbolNodeKind) or (C.FirstChild <> nil) then
      C := nil;
    if (C = nil) or (D = nil) or (D.Kind <> SymbolNodeKind) or (D.FirstChild <> nil) then
      D := nil;

    if (A <> nil) and (A.Data = '#<') then
      A.Data := '<';

    if B <> nil then begin

      if (B <> nil) and (B.Data = '#<') then
        B.Data := '<';
      if (C <> nil) and (C.Data = '#<') then
        C.Data := '<';
      if (D <> nil) and (D.Data = '#<') then
        D.Data := '<';

      Key := 0;

      if A <> nil then
        Key := Key or Cardinal(A.Data[1]);
      if B <> nil then
        Key := Key or Cardinal(B.Data[1]) shl 8;
      if C <> nil then
        Key := Key or Cardinal(C.Data[1]) shl 16;
      if D <> nil then
        Key := Key or Cardinal(D.Data[1]) shl 24;

      if Key <> 0 then
        ProcessOperator(Key, A, B, C, D);
    end;


    if Node.FirstChild <> nil then
      Node := Node.FirstChild
    else begin
      while Node <> nil do begin
       if Node.Next <> nil then begin
         Node := Node.Next;
         break;
       end;
       Node := Node.Parent;
      end;
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

  for B := 128 to 255 do
   CharTypeMapping[B] := ctLetter; // le unicode
end;

procedure BuildOperators;
  procedure Add(Operator: String; Fix: TFix);
  var
    Op: TOperatorRecord;
    Key: Cardinal;
  begin
    Op.Data := Operator;
    Op.Fixness := Fix;

    Key := 0;

    if Length(Operator) >= 1 then
      Key := Key or Cardinal(Operator[1]);
    if Length(Operator) >= 2 then
      Key := Key or Cardinal(Operator[2]) shl 8;
    if Length(Operator) >= 3  then
      Key := Key or Cardinal(Operator[3]) shl 16;
    if Length(Operator) >= 4  then
      Key := Key or Cardinal(Operator[4]) shl 24;

    Op.Key := Key;

    SetLength(Operators, Length(Operators)+1);
    Operators[Length(Operators)-1] := Op;
  end;
begin
  SetLength(Operators, 0);

  Add('=', fInfix);
  Add('+', fInfix);
  Add('-', fInfix);
  Add('+', fPrefix);
  Add('-', fPrefix);
  Add('*', fInfix);
  Add('*', fPrefix);
  Add('/', fInfix);
  Add('%', fInfix);
  Add('~', fInfix);
  Add('~', fPrefix);
  Add('&', fInfix);
  Add('&', fPrefix);
  Add('|', fInfix);
  Add('^', fInfix);
  Add('!', fPrefix);
  Add('?', fPrefix);



  Add('::', fInfix);
  Add('++', fPrefix);
  Add('--', fPrefix);
  Add('++', fPostfix);
  Add('--', fPostfix);
  Add('->', fInfix);
  Add('<<', fInfix);
  Add('>>', fInfix);
  Add('&&', fInfix);
  Add('||', fInfix);
  Add('??', fInfix);
  Add('==', fInfix);
  Add('!=', fInfix);
  Add('<=', fInfix);
  Add('>=', fInfix);

  Add('+=', fInfix);
  Add('-=', fInfix);
  Add('*=', fInfix);
  Add('/=', fInfix);
  Add('%=', fInfix);
  Add('&=', fInfix);
  Add('^=', fInfix);
  Add('|=', fInfix);
  Add('..', fInfix);

  Add('...', fInfix);
  Add('<<=', fInfix);
  Add('>>=', fInfix);
  Add('>>>', fInfix);
  Add('===', fInfix);
  Add(':=:', fInfix);
  Add('!==', fInfix);
  Add('>>>=', fInfix);
end;

procedure TSourceFile.Error(const Message: String; Position: TLocation);
begin
  if FErrors.Count < 1000 then
    FErrors.Append('Error: '+Message+' '+DescribeLocation(Position));
end;

procedure BuildSNK;
begin
  RootNodeKind := TSourceNodeKind.Create('root');
  SymbolNodeKind := TSourceNodeKind.Create('symbol');
  CurlyBracketNodeKind := TSourceNodeKind.Create('curly');
  AngleBracketNodeKind := TSourceNodeKind.Create('angle');
  SquareBracketNodeKind := TSourceNodeKind.Create('square');
  ParensNodeKind := TSourceNodeKind.Create('parens');
  SNK[tkIdentifier] := TSourceNodeKind.Create('identifier');
  SNK[tkSymbol] := SymbolNodeKind;
  SNK[tkNumber] := TSourceNodeKind.Create('number');
  SNK[tkString] := TSourceNodeKind.Create('string');
  SNK[tkCharacter] := TSourceNodeKind.Create('character');
  SNK[tkComment] := TSourceNodeKind.Create('comment');
  SNK[tkError] := TSourceNodeKind.Create('error');
  SNK[tkEof] := TSourceNodeKind.Create('eof');
end;

procedure BuildBrackets;
begin
  OpenBracket[bkCurly] := '{';
  CloseBracket[bkCurly] := '}';
  BracketRequired[bkCurly] := True;
  OpenBracket[bkParens] := '(';
  CloseBracket[bkParens] := ')';
  BracketRequired[bkParens] := True;
  OpenBracket[bkBlock] := '[';
  CloseBracket[bkBlock] := ']';
  BracketRequired[bkBlock] := True;
  OpenBracket[bkAngle] := '<';
  CloseBracket[bkAngle] := '>';
  BracketRequired[bkAngle] := False;

  Seperator[skSemicolon] := ';';
  Seperator[skComma] := ',';
end;

initialization
  BuildCharTypeMapping;
  BuildOperators;
  BuildSNK;
  BuildBrackets;

finalization

end.
