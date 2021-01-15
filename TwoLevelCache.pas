{������:
  TMyClass = class (TObject)
   public
    FHello: string;
    function SetName(n: string): TMyClass;
  end;
function TMyClass.SetName(n: string): TMyClass;
begin
  FHello := 'Hello ' + n;
  Result:= Self;
end;


.....
var
  c: T2Cache <TMyClass>;
  o: TObject;
begin

  c:= T2Cache <TMyClass>.Create(2, 2, csAccessTime);
  c.SetObject('1', TMyClass.Create.SetName('����'));
  c.SetObject('2', TMyClass.Create.SetName('����'));
  c.SetObject('3', TMyClass.Create.SetName('����'));
  c.SetObject('4', TMyClass.Create.SetName('����'));
  c.SetObject('5', TMyClass.Create.SetName('����1'));
  ShowMessage(TMyClass(c.GetObject('1')).FHello);
  ShowMessage(TMyClass(c.GetObject('5')).FHello);
  ShowMessage(TMyClass(c.GetObject('4')).FHello);
  ShowMessage(TMyClass(c.GetObject('1')).FHello);
  ShowMessage(TMyClass(c.GetObject('3')).FHello);
  FreeAndNil(c);
end;
}
unit TwoLevelCache;

interface

uses
  System.Generics.Collections, SysUtils,
  System.Classes, Generics.defaults;

type
  // TCacheStrategy ��������� ����, �� �������/ �� ������� �������
  TCacheStrategy = (csFrequency, csAccessTime);

  // TCache ������� ����� ����
  TCache = class
  public
    // GetObject �������� �� ����
    function GetObject(Key: String): TObject; virtual; abstract;
    // SetObject �������� � ���
    procedure SetObject(Key: String; Obj: TObject); virtual; abstract;
    // RemoveObject ������� �� ����
    procedure RemoveObject(Key: String); virtual; abstract;
    // GetSize �������� ������� ������
    function GetSize(): Integer; virtual; abstract;
  end;

  // TMemCache ��� � ������
  TMemCache = class(TCache)
  private
    // FObjMap ��������� � ������
    FObjMap: TDictionary<String, TObject>;
  public
    // ���������� TCache
    function GetObject(Key: String): TObject; override;
    procedure SetObject(Key: String; Obj: TObject); override;
    procedure RemoveObject(Key: String); override;
    function GetSize(): Integer; override;
    constructor Create;
    destructor Destroy; override;
  end;

  // TDiskCache ��� �� �����, T - ����� ��������� TObject ��� ��������
  TDiskCache<T: class, constructor> = class(TCache)
  private
    // FFileContent ������������ ��� ��������/���������� � ����
    FFileContent: TStrings;
    // FFileMap ���������
    FFileMap: TDictionary<String, TFileName>;
  public
    // ���������� TCache
    function GetObject(Key: String): TObject; override;
    procedure SetObject(Key: String; Obj: TObject); override;
    procedure RemoveObject(Key: String); override;
    function GetSize(): Integer; override;
    constructor Create;
    destructor Destroy; override;
  end;

  // T2Cache ������������� ��� T - ����� ��������� TObject ��� ��������
  T2Cache<T: class, constructor> = class(TCache)
  private
    // FKeyBuf ��������������� ������, ��� ������������ ������������� ������
    FKeyBuf: TList<String>;
    // FMaxMemSize ������ ���� � ������
    FMaxMemSize: Integer;
    // FMaxDiskSize ������ ���� �� �����
    FMaxDiskSize: Integer;
    // FStrategy ��������� ��������
    FStrategy: TCacheStrategy;
    // FMemCache ��� � ������
    FMemCache: TMemCache;
    // FDiskCache ��� �� �����
    FDiskCache: TDiskCache<T>;
    // FFrequencyMap ������� �������
    FFrequencyMap: TDictionary<String, Integer>;
    // FAccessTimeMap ��������� ����� �������������
    FAccessTimeMap: TDictionary<String, TDateTime>;
    // IntRemoveObject ���������� ��������� ��������
    procedure IntRemoveObject(Key: String);
    // FillKeyBuf ��������� ����� ������� � ��������� � ������ �������
    procedure FillKeyBuf;
    // MoveToDisk ��������� ������ �� ����,  ���� ���, �� ������ �� ������
    procedure MoveToDisk(Key: String);
    // MoveToMem ��������� ������ � ������, ���� ���, �� ������ �� ������
    procedure MoveToMem(Key: String);
    // Rearrange ��������� �������� �������
    procedure Rearrange;
  public
    // ���������� TCache
    function GetObject(Key: String): TObject; override;
    procedure SetObject(Key: String; Obj: TObject); override;
    procedure RemoveObject(Key: String); override;
    function GetSize(): Integer; override;
    // �������� ��������� ������� � ������, �� �����, ��������� ����
    constructor Create(MaxMemSize: Integer; MaxDiskSize: Integer;
      Strategy: TCacheStrategy);
    destructor Destroy(); override;
  end;

implementation

uses
  System.IOUtils,
  {https://github.com/onryldz/x-superobject/}
  XSuperObject;

procedure SaveToFile(RootObject: TComponent; const FileName: TFileName);
var
  FileStream: TFileStream;
  MemStream: TMemoryStream;
begin
  FileStream := TFileStream.Create(FileName, fmCreate);
  MemStream := TMemoryStream.Create;
  try
    MemStream.WriteComponent(RootObject);
    MemStream.Position := 0;
    ObjectBinaryToText(MemStream, FileStream);
  finally
    MemStream.Free;
    FileStream.Free;
  end;
end;

procedure LoadFromFile(RootObject: TComponent; const FileName: TFileName);
var
  FileStream: TFileStream;
  MemStream: TMemoryStream;
begin
  FileStream := TFileStream.Create(FileName, 0);
  MemStream := TMemoryStream.Create;
  try
    ObjectTextToBinary(FileStream, MemStream);
    MemStream.Position := 0;
    MemStream.ReadComponent(RootObject);
  finally
    MemStream.Free;
    FileStream.Free;
  end;
end;

{ TMemCache }

constructor TMemCache.Create;
begin
  FObjMap := TDictionary<String, TObject>.Create;
end;

destructor TMemCache.Destroy;
var
  Key: String;
begin
  inherited;
  // ������ ������� ����� ���������
  for Key in FObjMap.Keys do
    FObjMap[Key].Destroy;
  FObjMap.Destroy;
end;

function TMemCache.GetObject(Key: String): TObject;
var
  Obj: TObject;
begin
  Result := nil;
  if not FObjMap.TryGetValue(Key, Obj) then
    Exit;
  Result := Obj;
end;

function TMemCache.GetSize: Integer;
begin
  Result := FObjMap.Count;
end;

procedure TMemCache.RemoveObject(Key: String);
var
  Obj: TObject;
begin
  // ������� ������, ������ ����� ���������
  Obj := GetObject(Key);
  if Obj <> nil then
    Obj.Destroy;
  FObjMap.Remove(Key);
end;

procedure TMemCache.SetObject(Key: String; Obj: TObject);
begin
  FObjMap.Add(Key, Obj);
end;

{ TDiskCache }

constructor TDiskCache<T>.Create;
begin
  FFileMap := TDictionary<String, TFileName>.Create;
  FFileContent := TStringList.Create;
end;

destructor TDiskCache<T>.Destroy;
var
  Key: String;
begin
  inherited;
  FFileContent.Destroy;
  // ������ �����
  for Key in FFileMap.Keys do
    DeleteFile(FFileMap.Items[Key]);
  FFileMap.Destroy;
end;

function TDiskCache<T>.GetObject(Key: String): TObject;
var
  FileName: TFileName;
begin
  Result := nil;
  // ���� ��� �����
  if not FFileMap.TryGetValue(Key, FileName) then
    Exit;
  // ��������
    FFileContent.LoadFromFile(FileName);
  // ������������
  Result := TJSON.Parse<T>(FFileContent.Text);
end;

function TDiskCache<T>.GetSize: Integer;
begin
  Result := FFileMap.Count;
end;

procedure TDiskCache<T>.RemoveObject(Key: String);
var
  FileName: TFileName;
begin
  if not FFileMap.TryGetValue(Key, FileName) then
    Exit;
  DeleteFile(FileName);
  FFileMap.Remove(Key);
end;

procedure TDiskCache<T>.SetObject(Key: String; Obj: TObject);
var
  FileName: TFileName;
begin
  FileName := TPath.GetTempFileName;
  FFileContent.Text := TJSON.Stringify(T(Obj));
  FFileContent.SaveToFile(FileName);
  FFileMap.Add(Key, FileName);
end;

{ T2Cache }
constructor T2Cache<T>.Create(MaxMemSize, MaxDiskSize: Integer;
  Strategy: TCacheStrategy);

begin
  FKeyBuf := TList<String>.Create;
  FMaxMemSize := MaxMemSize;
  FMaxDiskSize := MaxDiskSize;
  FStrategy := Strategy;
  FMemCache := TMemCache.Create;
  FDiskCache := TDiskCache<T>.Create;
  FFrequencyMap := TDictionary<String, Integer>.Create;
  FAccessTimeMap := TDictionary<String, TDateTime>.Create;
end;

destructor T2Cache<T>.Destroy;
begin
  inherited;
  FAccessTimeMap.Destroy;
  FFrequencyMap.Destroy;
  FDiskCache.Destroy;
  FMemCache.Destroy;
  FKeyBuf.Destroy;
end;

procedure T2Cache<T>.FillKeyBuf;
var
  Comparison: TComparison<String>;
  Key: String;
begin
  // ������ ������ ������
  FKeyBuf.Clear;
  // �������� ����
  for Key in FFrequencyMap.Keys do
    FKeyBuf.Add(Key);
  // ������� ���������
  Comparison := function(const Left, Right: String): Integer
    begin
      if FStrategy = csFrequency then
        Result := TComparer<Integer>.Default.Compare(FFrequencyMap.Items[Right],
          FFrequencyMap.Items[Left])
      else
        Result := TComparer<TDateTime>.
          Default.Compare(FAccessTimeMap.Items[Right],
          FAccessTimeMap.Items[Left]);
    end;
  // ��������
  FKeyBuf.Sort(TComparer<String>.Construct(Comparison));
end;

function T2Cache<T>.GetObject(Key: String): TObject;
var
  Freq: Integer;
begin
  Result := nil;
  // ���� ��� ������ �����, �� �����
  if not FFrequencyMap.TryGetValue(Key, Freq) then
    Exit;
  // ������� ������ �� ������
  Result := FMemCache.GetObject(Key);
  // ���� ���, ���� � �����
  if Result = nil then
    Result := FDiskCache.GetObject(Key);
  // ������������ ����������
  FAccessTimeMap.AddOrSetValue(Key, Now);
  FFrequencyMap.AddOrSetValue(Key, Freq + 1);
  // ���������������
  Rearrange;
end;

function T2Cache<T>.GetSize: Integer;
begin
  Result := FFrequencyMap.Count;
end;

procedure T2Cache<T>.IntRemoveObject(Key: String);
begin
  FFrequencyMap.Remove(Key);
  FAccessTimeMap.Remove(Key);
  FMemCache.RemoveObject(Key);
  FDiskCache.RemoveObject(Key);
end;

procedure T2Cache<T>.MoveToDisk(Key: String);
var
  Obj: TObject;
begin
  // ������� �� ������
  Obj := FMemCache.GetObject(Key);
  // ������ ���, ��, ������
  if Obj = nil then
    Exit;
  // ���������
  FDiskCache.SetObject(Key, Obj);
  // ������ �� ������
  FMemCache.RemoveObject(Key);
end;

procedure T2Cache<T>.MoveToMem(Key: String);
var
  Obj: TObject;
begin
  // ������� ������ � �����
  Obj := FDiskCache.GetObject(Key);
  // ������ ��� �� �����, ������
  if Obj = nil then
    Exit;
  // ���������
  FMemCache.SetObject(Key, Obj);
  // ������
  FDiskCache.RemoveObject(Key);
end;

procedure T2Cache<T>.Rearrange;
var
  I: Integer;
begin
  // �������� ����� � ��������
  FillKeyBuf;
  // �������������
  for I := 0 to FKeyBuf.Count - 1 do
  begin
    if I < FMaxMemSize then // ���� ������, �� �������� � ������
      MoveToMem(FKeyBuf.Items[I])
    else if I < GetSize then // ��������� �������� �� ����
      MoveToDisk(FKeyBuf.Items[I])
    else // ���� ������ ��� ����, ������
      IntRemoveObject(FKeyBuf.Items[FKeyBuf.Count - 1]);
  end;
end;

procedure T2Cache<T>.RemoveObject(Key: String);
begin
  // ������, ���� �������
  if not FFrequencyMap.ContainsKey(Key) then
    Exit;
  IntRemoveObject(Key);
  // ���������������
  Rearrange;
end;

procedure T2Cache<T>.SetObject(Key: String; Obj: TObject);
begin
  // ������, ���� ��� �����
  if FFrequencyMap.ContainsKey(Key) then
    IntRemoveObject(Key);
  // �������� ��������� ����������
  FFrequencyMap.Add(Key, 1);
  FAccessTimeMap.Add(Key, Now);
  // �������� � ������ ��������, ��� ��������
  FMemCache.SetObject(Key, Obj);
  // ����� Rearrange ������ ���� ����� ����������
  Rearrange;
end;

end.
