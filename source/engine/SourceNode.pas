unit SourceNode;

interface

uses
  SourceLocation,
  SysUtils,
  StrUtils,
  Classes;

type
  TSourceNodeKind = class
  public
    Kind: String;

    constructor Create(const Kind_: String);
  end;

  TSourceNode = class
  public
    Parent: TSourceNode;
    Previous: TSourceNode;
    Next: TSourceNode;
    FirstChild: TSourceNode;
    LastChild: TSourceNode;

//    SourceFile: String;
    Position: TLocation;
    Data: String;
    Kind: TSourceNodeKind;

    procedure FreeChildren;

    procedure WriteTo(Out: TStrings);

  end;

implementation

constructor TSourceNodeKind.Create(const Kind_: String);
begin
  Kind := Kind_;
end;

procedure TSourceNode.FreeChildren;
var
  Node: TSourceNode;
begin
  while FirstChild <> nil do
  begin
    Node := FirstChild;
    Node.FreeChildren;
    FirstChild := Node.Next;
    if FirstChild <> nil then
      FirstChild.Previous := nil;
    Node.Free;
  end;
end;

procedure TSourceNode.WriteTo(Out: TStrings);
var
  Node: TSourceNode;
begin
  Out.Append(Kind.Kind + ':' + Data);
  Node := FirstChild;
  while Node <> nil do
  begin
    Node.WriteTo(Out);
    Node := Node.Next;
  end;
end;

end.
