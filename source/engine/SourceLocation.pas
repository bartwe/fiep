unit SourceLocation;

interface

type
  TLocation = record
    SourceName: String;
    Offset: Integer;
    Line: Integer;
    Column: Integer;
    Length: Integer;
  end;

implementation

end.
