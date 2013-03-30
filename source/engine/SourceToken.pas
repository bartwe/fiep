unit SourceToken;

interface

uses
  SourceLocation;

type
  TTokenKind = (tkIdentifier, tkSymbol, tkNumber, tkEof);

  TToken = record
    Position: TLocation;
    Data: String;
    Kind: TTokenKind;
  end;

implementation

end.
 