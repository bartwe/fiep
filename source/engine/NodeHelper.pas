unit NodeHelper;

interface

uses
  SourceNode,
  SourceLocation;

procedure InsertErrorNextTo(Node: TSourceNode; const Message: String; Location: PLocation);

implementation

uses
  NodeParsing;

procedure InsertErrorNextTo(Node: TSourceNode; const Message: String; Location: PLocation);
var
  Error: TSourceNode;
begin
  Error.Kind := ErrorNodeKind;
  Error.Position := Location^;
  Error.Data := Message;
  Error.AttachNextTo(Node);
end;


end.
