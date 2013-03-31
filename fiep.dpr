program fiep;

uses
  QForms,
  MainForm in 'source\MainForm.pas' {FormMain},
  Engine in 'source\engine\Engine.pas',
  SourceFile in 'source\engine\SourceFile.pas',
  SourceLocation in 'source\engine\SourceLocation.pas',
  SourceToken in 'source\engine\SourceToken.pas',
  StringBuilder in 'source\StringBuilder.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
