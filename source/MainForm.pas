unit MainForm;

interface

uses
  SysUtils, Types, Classes, Variants, QTypes, QGraphics, QControls, QForms, 
  QDialogs, QStdCtrls, QMenus, QComCtrls, Windows,

  Engine;

type
  TFormMain = class(TForm)
    TabControl1: TTabControl;
    MainMenu1: TMainMenu;
    File1: TMenuItem;
    ExitMenuItem: TMenuItem;
    EditorMemo: TMemo;
    Run1: TMenuItem;
    RunMenuItem: TMenuItem;
    Edit1: TMenuItem;
    GotoNextErrorMenuItem: TMenuItem;
    Memo1: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure ExitMenuItemClick(Sender: TObject);
    procedure RunMenuItemClick(Sender: TObject);
  private
    Engine: TEngine;
  public
    { Public declarations }
  end;

var
  FormMain: TFormMain;

implementation


const
  dummyFile: String = 'memo.txt';

{$R *.xfm}

procedure TFormMain.FormCreate(Sender: TObject);
begin
  if FileExists(dummyFile) then
    editorMemo.Lines.LoadFromFile(dummyFile);
end;

procedure TFormMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  editorMemo.Lines.SaveToFile(dummyFile);
end;

procedure TFormMain.ExitMenuItemClick(Sender: TObject);
begin
  Close;
end;

procedure TFormMain.RunMenuItemClick(Sender: TObject);
var
  F,A,B: Int64;
  I, L: Integer;
begin
  editorMemo.Lines.SaveToFile(dummyFile);

  QueryPerformanceFrequency(F);
  QueryPerformanceCounter(A);

//  Memo1.Lines.Clear;

  FreeAndNil(Engine);

  Engine := TEngine.Create();
  Engine.AddSourceFile(dummyFile);

  QueryPerformanceCounter(B);

  B := ((B - A) * 1000) div F;
  Memo1.Lines.Add('pre '+IntToStr(B));

  QueryPerformanceCounter(A);
//  while True do
  Engine.Reload;
  QueryPerformanceCounter(B);

  B := ((B - A) * 1000) div F;
  QueryPerformanceCounter(A);

  Memo1.Lines.Add('blip '+IntToStr(B));

  L := Engine.Output.Count-1;
  if L > 1000 then
    L := 1000;
//    L :=0 ;
  Memo1.Lines.BeginUpdate;
  for I := 0 to L do
    Memo1.Lines.Append(Engine.Output[I]);
  Memo1.Lines.EndUpdate;

  FreeAndNil(Engine);

  QueryPerformanceCounter(B);
  B := ((B - A) * 1000) div F;
  Memo1.Lines.Add('post '+IntToStr(B));
end;

end.
