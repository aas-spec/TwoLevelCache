unit MainForm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls;

type
  TMyClass = class (TObject)
   public
    FHello: string;
    function SetName(n: string): TMyClass;
  end;
  TForm1 = class(TForm)
    Button1: TButton;
    Button2: TButton;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

uses TwoLevelCache;

{ TMyClass }



procedure TForm1.Button1Click(Sender: TObject);
var
  c: T2Cache <TMyClass>;
  o: TObject;
begin

  c:= T2Cache <TMyClass>.Create(2, 2, csAccessTime);
  c.SetObject('1', TMyClass.Create.SetName('Вася'));
  c.SetObject('2', TMyClass.Create.SetName('Федя'));
  c.SetObject('3', TMyClass.Create.SetName('Саша'));
  c.SetObject('4', TMyClass.Create.SetName('Митя'));
  c.SetObject('5', TMyClass.Create.SetName('Митя1'));
  ShowMessage(TMyClass(c.GetObject('1')).FHello);
  ShowMessage(TMyClass(c.GetObject('5')).FHello);

end;

function TMyClass.SetName(n: string): TMyClass;
begin
  FHello := n;
  Result:= Self;
end;

end.
