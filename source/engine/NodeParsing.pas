unit NodeParsing;

interface

uses
  SourceNode;

type
  TBracketKind = (bkCurly, bkParens, bkBlock, bkAngle);
  TSeperatorKind = (skSemicolon, skComma);

  TNodeParser = class
  public
    procedure Process(Node: TSourceNode);

  private
    FOutput: TSourceNode;

    procedure Group;
    procedure GroupByBrackets(Node: TSourceNode; BracketKind: TBracketKind; Kind: TSourceNodeKind);
    procedure GroupByBrackets_B(Node: TSourceNode; BracketKind: TBracketKind; Kind: TSourceNodeKind);
    procedure GroupBySeperator(Node: TSourceNode; SeperatorKind: TSeperatorKind);

    procedure ParseOperators;

    procedure OperatorPrecedence;

  end;

var
  RootNodeKind: TSourceNodeKind;
  SymbolNodeKind: TSourceNodeKind;
  CurlyBracketNodeKind: TSourceNodeKind;
  AngleBracketNodeKind: TSourceNodeKind;
  SquareBracketNodeKind: TSourceNodeKind;
  ParensNodeKind: TSourceNodeKind;

implementation

uses
  SourceLocation,
  NodeHelper;

type
  TAssociativeness = (aLR, aRL);
  TFix = (fInfix, fPrefix, fPostfix);
  TOperatorRecord = record
    Key: Cardinal;
    Data: String;
    Fixness: TFix;
    Precedence: Integer;
    Associativeness: TAssociativeness;
  end;

var
  Operators : array of TOperatorRecord;
  OpenBracket: array[TBracketKind] of String;
  CloseBracket: array[TBracketKind] of String;
  BracketRequired: array[TBracketKind] of Boolean;
  Seperator: array[TSeperatorKind] of String;

procedure TNodeParser.Process(Node: TSourceNode);
begin
  FOutput := Node;
  Group;
  ParseOperators;
  OperatorPrecedence;
end;

procedure TNodeParser.Group;
begin
  GroupByBrackets(FOutput, bkCurly, CurlyBracketNodeKind);
  GroupByBrackets(FOutput, bkParens, ParensNodeKind);
  GroupByBrackets(FOutput, bkBlock, SquareBracketNodeKind);
  GroupByBrackets(FOutput, bkAngle, AngleBracketNodeKind);
  GroupBySeperator(FOutput, skSemicolon);
  GroupBySeperator(FOutput, skComma);
end;

procedure TNodeParser.GroupByBrackets(Node: TSourceNode; BracketKind: TBracketKind; Kind: TSourceNodeKind);
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

procedure TNodeParser.GroupByBrackets_B(Node: TSourceNode; BracketKind: TBracketKind; Kind: TSourceNodeKind);
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
    InsertErrorAfter(Anchor.Parent.LastChild, 'Expected '+CloseBracket[BracketKind], @EndLocation);
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

procedure TNodeParser.GroupBySeperator(Node: TSourceNode; SeperatorKind: TSeperatorKind);
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

procedure TNodeParser.ParseOperators;

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

procedure TNodeParser.OperatorPrecedence;
begin
end;
    
procedure BuildNodeKinds;
begin
  RootNodeKind := TSourceNodeKind.Create('root');
  SymbolNodeKind := TSourceNodeKind.Create('symbol');
  CurlyBracketNodeKind := TSourceNodeKind.Create('curly');
  AngleBracketNodeKind := TSourceNodeKind.Create('angle');
  SquareBracketNodeKind := TSourceNodeKind.Create('square');
  ParensNodeKind := TSourceNodeKind.Create('parens');
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

procedure BuildOperators;
  procedure Add(Operator: String; Fix: TFix; Precedence: Integer; Associativeness: TAssociativeness);
  var
    Op: TOperatorRecord;
    Key: Cardinal;
  begin
    Op.Data := Operator;
    Op.Fixness := Fix;
    Op.Precedence := Precedence;
    Op.Associativeness := Associativeness;

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

  Add('::', fInfix, 1, aLR);

  Add('++', fPostfix, 2, aLR);
  Add('--', fPostfix, 2, aLR);
  Add('(', fPostfix, 2, aLR);
  Add('[', fPostfix, 2, aLR);
  Add('.', fInfix, 2, aLR);
  Add('->', fInfix, 2, aLR);

  Add('++', fPrefix, 3, aRL);
  Add('--', fPrefix, 3, aRL);
  Add('+', fPrefix, 3, aRL);
  Add('-', fPrefix, 3, aRL);
  Add('~', fPrefix, 3, aRL);
  Add('!', fPrefix, 3, aRL);
  Add('?', fPrefix, 3, aRL);
  Add('&', fPrefix, 3, aRL);
  Add('*', fPrefix, 3, aRL);
  Add('(', fPrefix, 3, aRL);

  Add('**', fInfix, 4, aLR);

  Add('*', fInfix, 5, aLR);
  Add('/', fInfix, 5, aLR);
  Add('%', fInfix, 5, aLR);

  Add('+', fInfix, 6, aLR);
  Add('-', fInfix, 6, aLR);

  Add('<<', fInfix, 7, aLR);
  Add('>>', fInfix, 7, aLR);
  Add('>>>', fInfix, 7, aLR);

  Add('<=', fInfix, 8, aLR);
  Add('>=', fInfix, 8, aLR);
  Add('<', fInfix, 8, aLR);
  Add('>', fInfix, 8, aLR);

  Add('==', fInfix, 9, aLR);
  Add('!=', fInfix, 9, aLR);
  Add('===', fInfix, 9, aLR);
  Add('!==', fInfix, 9, aLR);

  Add('&', fInfix, 10, aLR);

  Add('^', fInfix, 11, aLR);

  Add('|', fInfix, 12, aLR);

  Add('&&', fInfix, 13, aLR);

  Add('||', fInfix, 14, aLR);

  Add('??', fInfix, 15, aLR);

  Add('..', fInfix, 16, aLR);
  Add('...', fInfix, 16, aLR);

  Add('=', fInfix, 17, aRL);
  Add('+=', fInfix, 17, aRL);
  Add('-=', fInfix, 17, aRL);
  Add('*=', fInfix, 17, aRL);
  Add('/=', fInfix, 17, aRL);
  Add('%=', fInfix, 17, aRL);
  Add('&=', fInfix, 17, aRL);
  Add('^=', fInfix, 17, aRL);
  Add('|=', fInfix, 17, aRL);
  Add('<<=', fInfix, 17, aRL);
  Add('>>=', fInfix, 17, aRL);
  Add('>>>=', fInfix, 17, aRL);
  Add(':=:', fInfix, 17, aRL);

  Add('=>', fInfix, 18, aLR);
end;


initialization
  BuildOperators;
  BuildBrackets;

end.
 