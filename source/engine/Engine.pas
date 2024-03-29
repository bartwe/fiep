unit Engine;

interface

uses
  Classes,
  StrUtils;

type
  TEngine = class
  public
    Output: TStringList;

    constructor Create;
    destructor Destroy; override;
    procedure AddSourceFile(const FileName: String);

    procedure Reload();

  private
    FSourceFiles: TStringList;

  end;

implementation

uses
  SourceFile;

constructor TEngine.Create;
begin
  FSourceFiles := TStringList.Create;
  FSourceFiles.Sorted := True;
  FSourceFiles.Duplicates := dupIgnore;
  Output := TStringList.Create;
end;

destructor TEngine.Destroy;
begin
  FSourceFiles.Free;
  Output.Free;
end;

procedure TEngine.AddSourceFile(const FileName: String);
begin
  FSourceFiles.Add(FileName);
end;

procedure TEngine.Reload();
var
  I: Integer;
  FileName: String;
  SourceFile: TSourceFile;
begin
    Output.Clear;
  // intended to work on a running system, so it only adds and replaces vmt entries and such, it deletes no methods or types and doesn't delete compiled code.
//I := 0;
//  while True do
  for I := 0 to FSourceFiles.Count-1 do
  begin
    FileName := FSourceFiles[I];
    Output.Add(FileName);
    SourceFile := TSourceFile.Create;
    SourceFile.ReadFromFile(FileName);

    Output.AddStrings(SourceFile.FErrors);
//    SourceFile.FOutput.WriteTo(Output);
    SourceFile.Free;
  end;
end;

end.
