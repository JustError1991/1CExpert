# Укажите путь к папке с исходными файлами
$sourceFolder = "C:\path\to\source\files"
# Укажите путь к папке для результатов
$outputFolder = "C:\path\to\output\folder"

# Максимальный размер файла в байтах (100 МБ)
$maxFileSize = 100MB

# Создаем выходную папку, если ее нет
if (-not (Test-Path -Path $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder | Out-Null
}

# Хэш-таблица для отслеживания счетчиков файлов по таблицам
$tableFileCounters = @{}
# Хэш-таблица для отслеживания текущих размеров файлов
$currentFileSizes = @{}

# Счетчики для статистики
$totalFilesProcessed = 0
$totalInsertsProcessed = 0

# Получаем все файлы в исходной папке (рекурсивно, если нужно)
$files = Get-ChildItem -Path $sourceFolder -File -Filter *.sql

foreach ($file in $files) {
    $totalFilesProcessed++
    Write-Host "Обработка файла $($file.Name)..." -NoNewline
    
    # Читаем содержимое файла построчно (для экономии памяти)
    $reader = [System.IO.File]::OpenText($file.FullName)
    $insertsInFile = 0
    
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            $trimmedLine = $line.Trim()
            if ($trimmedLine -match '^Insert into \[dbo\]\.\[([^\]]+)\]') {
                $insertsInFile++
                $tableName = $matches[1]
                
                # Инициализируем счетчик для таблицы, если его еще нет
                if (-not $tableFileCounters.ContainsKey($tableName)) {
                    $tableFileCounters[$tableName] = 1
                    $currentFileSizes[$tableName] = @{}
                }
                
                # Получаем текущий счетчик
                $currentCounter = $tableFileCounters[$tableName]
                $baseFileName = "$tableName"
                
                # Формируем имя файла в зависимости от счетчика
                if ($currentCounter -eq 1) {
                    $outputFile = Join-Path -Path $outputFolder -ChildPath "$baseFileName.sql"
                } else {
                    $outputFile = Join-Path -Path $outputFolder -ChildPath "${baseFileName}_$currentCounter.sql"
                }
                
                # Проверяем размер текущего файла
                if (Test-Path -Path $outputFile) {
                    $fileSize = (Get-Item -Path $outputFile).Length
                } else {
                    $fileSize = 0
                }
                
                # Если файл превышает лимит, создаем новый файл
                if ($fileSize -ge $maxFileSize) {
                    $tableFileCounters[$tableName]++
                    $currentCounter = $tableFileCounters[$tableName]
                    
                    if ($currentCounter -eq 1) {
                        $outputFile = Join-Path -Path $outputFolder -ChildPath "$baseFileName.sql"
                    } else {
                        $outputFile = Join-Path -Path $outputFolder -ChildPath "${baseFileName}_$currentCounter.sql"
                    }
                    
                    # Сбрасываем размер для нового файла
                    $fileSize = 0
                }
                
                # Добавляем строку в конец файла
                Add-Content -Path $outputFile -Value $trimmedLine -Encoding UTF8
                
                # Обновляем размер файла в хэш-таблице (приблизительно)
                $lineSize = [System.Text.Encoding]::UTF8.GetByteCount($trimmedLine + "`r`n")
                if (-not $currentFileSizes[$tableName].ContainsKey($currentCounter)) {
                    $currentFileSizes[$tableName][$currentCounter] = 0
                }
                $currentFileSizes[$tableName][$currentCounter] += $lineSize
            }
        }
        $totalInsertsProcessed += $insertsInFile
        Write-Host " найдено $insertsInFile INSERT-запросов"
    }
    finally {
        $reader.Close()
    }
}
Write-Host "`nОбработка завершена:"
Write-Host " - Всего обработано файлов: $totalFilesProcessed"
Write-Host " - Всего обработано INSERT-запросов: $totalInsertsProcessed"
Write-Host " - Создано/обновлено файлов таблиц: $(@(Get-ChildItem $outputFolder).Count)"

# Дополнительная статистика по файлам
$outputFiles = Get-ChildItem -Path $outputFolder -File
Write-Host "`nСтатистика по выходным файлам:"
$outputFiles | Group-Object BaseName | ForEach-Object {
    $sizeMB = ($_.Group | Measure-Object Length -Sum).Sum / 1MB
    $fileCount = $_.Count
    Write-Host " - $($_.Name): $fileCount файл(ов), общий размер: {0:N2} МБ" -f $sizeMB
    
    # Показываем размер каждого файла отдельно
    $_.Group | Sort-Object Name | ForEach-Object {
        $fileSizeMB = $_.Length / 1MB
        Write-Host "   * $($_.Name): {0:N2} МБ" -f $fileSizeMB
    }
}

# Статистика по таблицам
Write-Host "`nСтатистика по таблицам:"
foreach ($tableName in $tableFileCounters.Keys | Sort-Object) {
    $fileCount = $tableFileCounters[$tableName]
    Write-Host " - $tableName: $fileCount файл(ов)"
}