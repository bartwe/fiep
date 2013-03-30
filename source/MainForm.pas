unit MainForm;

interface

uses
  SysUtils, Types, Classes, Variants, QTypes, QGraphics, QControls, QForms, 
  QDialogs, QStdCtrls, QMenus, QComCtrls,

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
begin
  FreeAndNil(Engine);

  editorMemo.Lines.SaveToFile(dummyFile);

  Engine := TEngine.Create();
  Engine.AddSourceFile(dummyFile);
end;

end.
