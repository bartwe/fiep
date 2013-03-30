unit Engine;

interface

uses
  Classes,
  StrUtils;

type
  TEngine = class
  public
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
end;

destructor TEngine.Destroy;
begin
  FSourceFiles.Free;
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
  // intended to work on a running system, so it only adds and replaces vmt entries and such, it deletes no methods or types and doesn't delete compiled code.
  for I := 0 to FSourceFiles.Count-1 do
  begin
    FileName = FSourceFiles[I];
    SourceFile := TSourceFile.Create;
    SourceFile.ReadFromFile(FileName);

    SourceFile.Free;
  end;
end;

end.
