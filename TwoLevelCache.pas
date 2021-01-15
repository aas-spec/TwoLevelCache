{Пример:
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
  c.SetObject('1', TMyClass.Create.SetName('Вася'));
  c.SetObject('2', TMyClass.Create.SetName('Федя'));
  c.SetObject('3', TMyClass.Create.SetName('Саша'));
  c.SetObject('4', TMyClass.Create.SetName('Митя'));
  c.SetObject('5', TMyClass.Create.SetName('Митя1'));
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
  // TCacheStrategy Стратегия кэша, по частоте/ по времени доступа
  TCacheStrategy = (csFrequency, csAccessTime);

  // TCache Базовый класс кэша
  TCache = class
  public
    // GetObject Получить из кэша
    function GetObject(Key: String): TObject; virtual; abstract;
    // SetObject Положить в кэш
    procedure SetObject(Key: String; Obj: TObject); virtual; abstract;
    // RemoveObject Удалить из кэша
    procedure RemoveObject(Key: String); virtual; abstract;
    // GetSize Получить текущий размер
    function GetSize(): Integer; virtual; abstract;
  end;

  // TMemCache Кэш в памяти
  TMemCache = class(TCache)
  private
    // FObjMap Хранилище в памяти
    FObjMap: TDictionary<String, TObject>;
  public
    // Аналогично TCache
    function GetObject(Key: String): TObject; override;
    procedure SetObject(Key: String; Obj: TObject); override;
    procedure RemoveObject(Key: String); override;
    function GetSize(): Integer; override;
    constructor Create;
    destructor Destroy; override;
  end;

  // TDiskCache Кэш на диске, T - класс наследник TObject для харнения
  TDiskCache<T: class, constructor> = class(TCache)
  private
    // FFileContent Используется для загрузки/сохранения в файл
    FFileContent: TStrings;
    // FFileMap Хранилище
    FFileMap: TDictionary<String, TFileName>;
  public
    // Аналогично TCache
    function GetObject(Key: String): TObject; override;
    procedure SetObject(Key: String; Obj: TObject); override;
    procedure RemoveObject(Key: String); override;
    function GetSize(): Integer; override;
    constructor Create;
    destructor Destroy; override;
  end;

  // T2Cache Двухуровневый кэш T - класс наследник TObject для хранения
  T2Cache<T: class, constructor> = class(TCache)
  private
    // FKeyBuf Вспомогательный список, для формирование сортированных ключей
    FKeyBuf: TList<String>;
    // FMaxMemSize Размер кэша в памяти
    FMaxMemSize: Integer;
    // FMaxDiskSize Размер кэша на диске
    FMaxDiskSize: Integer;
    // FStrategy Стратегия хранения
    FStrategy: TCacheStrategy;
    // FMemCache Кэш в памяти
    FMemCache: TMemCache;
    // FDiskCache Кэш на диске
    FDiskCache: TDiskCache<T>;
    // FFrequencyMap Частота доступа
    FFrequencyMap: TDictionary<String, Integer>;
    // FAccessTimeMap Последнее время использования
    FAccessTimeMap: TDictionary<String, TDateTime>;
    // IntRemoveObject Внутренняя процедура удаления
    procedure IntRemoveObject(Key: String);
    // FillKeyBuf Заполняет буфер ключами и сортирует в нужном порядке
    procedure FillKeyBuf;
    // MoveToDisk Переносит объект на диск,  если уже, то ничего не делает
    procedure MoveToDisk(Key: String);
    // MoveToMem Переносит объект в память, если уже, то ничего не делает
    procedure MoveToMem(Key: String);
    // Rearrange Управляет порядком записей
    procedure Rearrange;
  public
    // Аналогично TCache
    function GetObject(Key: String): TObject; override;
    procedure SetObject(Key: String; Obj: TObject); override;
    procedure RemoveObject(Key: String); override;
    function GetSize(): Integer; override;
    // Задаются параметры Размера в памяти, на диске, стратегия кэша
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
  // Очищаю объекты перед удалением
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
  // Получаю объект, очищаю перед удалением
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
  // Удаляю файлы
  for Key in FFileMap.Keys do
    DeleteFile(FFileMap.Items[Key]);
  FFileMap.Destroy;
end;

function TDiskCache<T>.GetObject(Key: String): TObject;
var
  FileName: TFileName;
begin
  Result := nil;
  // Беру имя файла
  if not FFileMap.TryGetValue(Key, FileName) then
    Exit;
  // Загружаю
    FFileContent.LoadFromFile(FileName);
  // Десериализую
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
  // Очищаю список ключей
  FKeyBuf.Clear;
  // Заполняю ключ
  for Key in FFrequencyMap.Keys do
    FKeyBuf.Add(Key);
  // Функция сравнения
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
  // Сортирую
  FKeyBuf.Sort(TComparer<String>.Construct(Comparison));
end;

function T2Cache<T>.GetObject(Key: String): TObject;
var
  Freq: Integer;
begin
  Result := nil;
  // Если нет такого ключа, то выход
  if not FFrequencyMap.TryGetValue(Key, Freq) then
    Exit;
  // Получаю объект из памяти
  Result := FMemCache.GetObject(Key);
  // Если нет, беру с диска
  if Result = nil then
    Result := FDiskCache.GetObject(Key);
  // Устанавливаю статистику
  FAccessTimeMap.AddOrSetValue(Key, Now);
  FFrequencyMap.AddOrSetValue(Key, Freq + 1);
  // Перераспределяю
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
  // Получаю из памяти
  Obj := FMemCache.GetObject(Key);
  // Такого нет, ок, выхожу
  if Obj = nil then
    Exit;
  // Перемешаб
  FDiskCache.SetObject(Key, Obj);
  // Удаляю из памяти
  FMemCache.RemoveObject(Key);
end;

procedure T2Cache<T>.MoveToMem(Key: String);
var
  Obj: TObject;
begin
  // Получаю объект с диска
  Obj := FDiskCache.GetObject(Key);
  // Такого нет на диске, выхожу
  if Obj = nil then
    Exit;
  // Перемешаю
  FMemCache.SetObject(Key, Obj);
  // Удаляю
  FDiskCache.RemoveObject(Key);
end;

procedure T2Cache<T>.Rearrange;
var
  I: Integer;
begin
  // Заполняю ключи и сортирую
  FillKeyBuf;
  // Синхронизирую
  for I := 0 to FKeyBuf.Count - 1 do
  begin
    if I < FMaxMemSize then // Если паямть, то переношу в память
      MoveToMem(FKeyBuf.Items[I])
    else if I < GetSize then // Остальные переношу на диск
      MoveToDisk(FKeyBuf.Items[I])
    else // Если больше чем надо, удаляю
      IntRemoveObject(FKeyBuf.Items[FKeyBuf.Count - 1]);
  end;
end;

procedure T2Cache<T>.RemoveObject(Key: String);
begin
  // Удаляю, если найдено
  if not FFrequencyMap.ContainsKey(Key) then
    Exit;
  IntRemoveObject(Key);
  // Перераспределяю
  Rearrange;
end;

procedure T2Cache<T>.SetObject(Key: String; Obj: TObject);
begin
  // Удаляю, если был такой
  if FFrequencyMap.ContainsKey(Key) then
    IntRemoveObject(Key);
  // Добавляю начальную статистику
  FFrequencyMap.Add(Key, 1);
  FAccessTimeMap.Add(Key, Now);
  // Добавляю в память временно, для простоты
  FMemCache.SetObject(Key, Obj);
  // После Rearrange размер кэша будет правильный
  Rearrange;
end;

end.
