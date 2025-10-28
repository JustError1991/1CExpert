#пример вызова: .\Remove_Cleaned.ps1 -Path "C:\Путь к папке" 
param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    
    [Parameter(Mandatory=$false)]
    [switch]$Recursive
)

# Проверим существование директории
if (!(Test-Path -Path $Path -PathType Container)) {
    Write-Error "Директория '$Path' не существует!"
    exit 1
}

# Получим все файлы в указанной директории
$files = Get-ChildItem -Path $Path -File -Recurse:$Recursive

foreach ($file in $files) {
    # Проверим, содержит ли имя файла искомую фразу
    if ($file.Name -like "*_cleaned*") {
        # Заменим фразу "_cleaned" на пустую строку
        $NewName = $file.Name -replace "_cleaned", ""
        
        # Переименовываем файл
        try {
            Rename-Item -Path $file.FullName -NewName $NewName -Force
            Write-Host "Переименован: $($file.Name) -> $NewName"
        }
        catch {
            Write-Error "Ошибка при переименовании файла $($file.FullName): $_"
        }
    }
}
