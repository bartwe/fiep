unit SourceToken;

interface

uses
  SourceLocation;

type
  TTokenKind = (tkIdentifier, tkSymbol, tkNumber, tkString, tkCharacter, tkComment, tkError, tkEof);

  TToken = record
    Position: TLocation;
    Data: String;
    Kind: TTokenKind;

  end;

  PToken = ^TToken;

function DescribeToken(const Token: TToken): String;

implementation

function DescribeToken(const Token: TToken): String;
begin
  Result := 'Token ';
  case Token.Kind of
    tkIdentifier:
      Result := Result + 'identifier ';
    tkSymbol:
      Result := Result + 'symbol ';
    tkNumber:
      Result := Result + 'number ';
    tkString:
      Result := Result + 'string ';
    tkCharacter:
      Result := Result + 'character ';
    tkComment:
      Result := Result + 'comment ';
    tkError:
      Result := Result + 'error ';
    tkEof:
      Result := Result + 'eof ';
  end;
  Result := Result + Token.Data;
  Result := Result + ' ' + DescribeLocation(Token.Position);
end;

end.
 