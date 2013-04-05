unit NodeHelper;

interface

uses
  SourceNode,
  SourceLocation;

procedure InsertErrorAfter(Node: TSourceNode; const Message: String; Location: PLocation);

implementation

procedure InsertErrorAfter(Node: TSourceNode; const Message: String; Location: PLocation);
begin
end;

end.
