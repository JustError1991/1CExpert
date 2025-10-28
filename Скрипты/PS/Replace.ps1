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

# Получим все .sql файлы в указанной директории
$sqlFiles = Get-ChildItem -Path $Path -Filter "*.sql" -Recurse:$Recursive

foreach ($file in $sqlFiles) {
    try {
        # Читаем содержимое файла
        $content = Get-Content -Path $file.FullName -Raw
        
        # Заменяем все вхождения "))" на ")"
        $newContent = $content -replace '\){2}', ')'
        
        # Если содержимое изменилось, записываем обратно в файл
        if ($newContent -ne $content) {
            Set-Content -Path $file.FullName -Value $newContent -NoNewline
            Write-Host "Обработан файл: $($file.Name)"
        }
    }
    catch {
        Write-Error "Ошибка при обработке файла $($file.FullName): $_"
    }
}

Write-Host "Обработка завершена! Обработано файлов: $($sqlFiles.Count)"