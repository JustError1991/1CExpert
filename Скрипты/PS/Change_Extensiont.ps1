#пример вызова: .\ChangeExtension.ps1 -Path "C:\Путь к папке" -NewExtension "txt"
param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    
    [Parameter(Mandatory=$true)]
    [string]$NewExtension
)

# Убедимся, что новое расширение начинается с точки
if (!$NewExtension.StartsWith('.')) {
    $NewExtension = ".$NewExtension"
}

# Проверим существование директории
if (!(Test-Path -Path $Path -PathType Container)) {
    Write-Error "Директория '$Path' не существует!"
    exit 1
}

# Получим все файлы в указанной директории (без вложенных папок)
Get-ChildItem -Path $Path -File | ForEach-Object {
    # Формируем новое имя файла
    $NewName = [System.IO.Path]::ChangeExtension($_.Name, $NewExtension)
    
    # Переименовываем файл
    Rename-Item -Path $_.FullName -NewName $NewName -Force
}

Write-Host "Расширения файлов успешно изменены на '$NewExtension'"