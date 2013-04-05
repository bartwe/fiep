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
    procedure Unhook;
    procedure AttachAsChildOf(Node: TSourceNode);
    procedure AttachNextTo(Node: TSourceNode);

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
  LastChild := nil;
end;

procedure TSourceNode.WriteTo(Out: TStrings);
var
  Node: TSourceNode;
  Str: String;
begin
  Node := Parent;
  while Node <> nil do begin
    Node := Node.Parent;
    Str := Str + '-';
  end;
  Out.Append(Str+Kind.Kind + ':' + Data);
  Node := FirstChild;
  while Node <> nil do
  begin
    Node.WriteTo(Out);
    Node := Node.Next;
  end;
end;

procedure TSourceNode.Unhook;
begin
  FreeChildren;
  if Parent <> nil then begin
    if Parent.FirstChild = self then
      Parent.FirstChild := self.Next;
    if Parent.LastChild = self then
      Parent.LastChild := self.Previous;
    Parent := nil;
  end;
  if Next <> nil then
    Next.Previous := Previous;
  if Previous <> nil then
    Previous.Next := Next;
  Next := nil;
  Previous := nil;
end;

procedure TSourceNode.AttachAsChildOf(Node: TSourceNode);
begin
  if Parent <> nil then begin
    if Parent.FirstChild = self then
      Parent.FirstChild := self.Next;
    if Parent.LastChild = self then
      Parent.LastChild := self.Previous;
    Parent := nil;
  end;
  if Next <> nil then
    Next.Previous := Previous;
  if Previous <> nil then
    Previous.Next := Next;
  Next := nil;
  Previous := nil;

  Previous := Node.LastChild;
  if Previous <> nil then
    Previous.Next := Self;
  Node.LastChild := Self;
  if Node.FirstChild = nil then
    Node.FirstChild := Self;
  Parent := Node;
end;

procedure TSourceNode.AttachNextTo(Node: TSourceNode);
begin
  if Parent <> nil then begin
    if Parent.FirstChild = self then
      Parent.FirstChild := self.Next;
    if Parent.LastChild = self then
      Parent.LastChild := self.Previous;
    Parent := nil;
  end;
  if Next <> nil then
    Next.Previous := Previous;
  if Previous <> nil then
    Previous.Next := Next;
  Next := nil;
  Previous := nil;

  Previous := Node;
  Next := Node.Next;
  Parent := Node.Parent;
  if Next <> nil then
    Next.Previous := Self;
  Previous.Next := Self;
  if Parent.LastChild = Node then
    Parent.LastChild := Self;
end;

end.
