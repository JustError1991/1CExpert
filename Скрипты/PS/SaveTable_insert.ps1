# Укажите путь к папке с исходными файлами
$sourceFolder = "C:\path\to\source\files"
# Укажите путь к папке для результатов
$outputFolder = "C:\path\to\output\folder"

# Создаем хеш-таблицу для хранения содержимого по таблицам
$tableContents = @{}

# Получаем все файлы в исходной папке
$files = Get-ChildItem -Path $sourceFolder -File

foreach ($file in $files) {
    # Читаем содержимое файла
    $content = Get-Content -Path $file.FullName
    
    # Обрабатываем каждую строку
    foreach ($line in $content) {
        if ($line -match '^Insert into \[dbo\]\.\[([^\]]+)\]') {
            # Извлекаем имя таблицы
            $tableName = $matches[1]
            
            # Если такой таблицы еще нет в хеш-таблице, добавляем
            if (-not $tableContents.ContainsKey($tableName)) {
                $tableContents[$tableName] = @()
            }
            
            # Добавляем строку в массив для этой таблицы
            $tableContents[$tableName] += $line
        }
    }
}

# Создаем выходную папку, если ее нет
if (-not (Test-Path -Path $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder | Out-Null
}

# Сохраняем данные для каждой таблицы в отдельный файл
foreach ($table in $tableContents.Keys) {
    $outputFile = Join-Path -Path $outputFolder -ChildPath "$table.sql"
    
    # Записываем все INSERT для этой таблицы в файл
    $tableContents[$table] | Out-File -FilePath $outputFile -Encoding utf8
    
    Write-Host "Создан файл: $outputFile с $($tableContents[$table].Count) записями для таблицы $table"
}

Write-Host "Обработка завершена. Создано $($tableContents.Count) файлов."