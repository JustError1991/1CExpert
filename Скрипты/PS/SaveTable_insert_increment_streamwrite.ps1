# Укажите путь к папке с исходными файлами
$sourceFolder = "C:\path\to\source\files"
# Укажите путь к папке для результатов
$outputFolder = "C:\path\to\output\folder"

# Максимальный размер файла в байтах (10 МБ)
$maxFileSize = 10MB

# Создаем выходную папку, если ее нет
if (-not (Test-Path -Path $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder | Out-Null
}

# Хэш-таблица для отслеживания потоков записи по таблицам
$tableStreams = @{}
# Хэш-таблица для отслеживания счетчиков файлов по таблицам
$tableFileCounters = @{}
# Хэш-таблица для отслеживания текущих размеров файлов
$tableFileSizes = @{}

# Счетчики для статистики
$totalFilesProcessed = 0
$totalInsertsProcessed = 0

# Функция для получения текущего файла для записи
function Get-OutputFileStream {
    param(
        [string]$TableName,
        [string]$Line
    )
    
    # Инициализируем структуры данных для таблицы, если нужно
    if (-not $tableStreams.ContainsKey($TableName)) {
        $tableStreams[$TableName] = $null
        $tableFileCounters[$TableName] = 1
        $tableFileSizes[$TableName] = 0
    }
    
    # Проверяем, нужно ли создать новый файл
    $lineSize = [System.Text.Encoding]::UTF8.GetByteCount($Line + "`r`n")
    if ($tableFileSizes[$TableName] + $lineSize -ge $maxFileSize -and $tableStreams[$TableName] -ne $null) {
        # Закрываем текущий поток
        $tableStreams[$TableName].Close()
        $tableStreams[$TableName].Dispose()
        $tableStreams[$TableName] = $null
        
        # Увеличиваем счетчик файлов
        $tableFileCounters[$TableName]++
        $tableFileSizes[$TableName] = 0
    }
    
    # Если поток не открыт, открываем новый
    if ($tableStreams[$TableName] -eq $null) {
        $currentCounter = $tableFileCounters[$TableName]
        if ($currentCounter -eq 1) {
            $outputFile = Join-Path -Path $outputFolder -ChildPath "$TableName.sql"
        } else {
            $outputFile = Join-Path -Path $outputFolder -ChildPath "${TableName}_$currentCounter.sql"
        }
        
        # Создаем поток для записи
        $tableStreams[$TableName] = [System.IO.StreamWriter]::new($outputFile, $true, [System.Text.Encoding]::UTF8)
    }
    
    # Возвращаем поток и обновляем размер
    $tableFileSizes[$TableName] += $lineSize
    return $tableStreams[$TableName]
}

# Функция для закрытия всех потоков
function Close-AllStreams {
    foreach ($stream in $tableStreams.Values) {
        if ($stream -ne $null) {
            $stream.Close()
            $stream.Dispose()
        }
    }
    $tableStreams.Clear()
    $tableFileSizes.Clear()
}
# Обрабатываем все файлы
try {
    $files = Get-ChildItem -Path $sourceFolder -File -Filter *.sql
    
    foreach ($file in $files) {
        $totalFilesProcessed++
        Write-Host "Обработка файла $($file.Name)..." -NoNewline
        
        # Читаем содержимое файла построчно
        $reader = [System.IO.File]::OpenText($file.FullName)
        $insertsInFile = 0
        
        try {
            while ($null -ne ($line = $reader.ReadLine())) {
                $trimmedLine = $line.Trim()
                if ($trimmedLine -match '^Insert into \[dbo\]\.\[([^\]]+)\]') {
                    $insertsInFile++
                    $tableName = $matches[1]
                    
                    # Получаем поток для записи
                    $stream = Get-OutputFileStream -TableName $tableName -Line $trimmedLine
                    
                    # Записываем строку
                    $stream.WriteLine($trimmedLine)
                }
            }
            $totalInsertsProcessed += $insertsInFile
            Write-Host " найдено $insertsInFile INSERT-запросов"
        }
        finally {
            $reader.Close()
        }
        
        # Периодически сбрасываем буферы для уменьшения использования памяти
        if ($totalFilesProcessed % 10 -eq 0) {
            foreach ($stream in $tableStreams.Values) {
                if ($stream -ne $null) {
                    $stream.Flush()
                }
            }
        }
    }
}
finally {
    # Закрываем все потоки
    Close-AllStreams
}

Write-Host "`nОбработка завершена:"
Write-Host " - Всего обработано файлов: $totalFilesProcessed"
Write-Host " - Всего обработано INSERT-запросов: $totalInsertsProcessed"
Write-Host " - Создано/обновлено файлов таблиц: $(@(Get-ChildItem $outputFolder -File | Where-Object { $_.Name -like '*.sql' }).Count)"

# Дополнительная статистика по файлам
#$outputFiles = Get-ChildItem -Path $outputFolder -File | Where-Object { $_.Name -like '*.sql' }
#Write-Host "`nСтатистика по выходным файлам:"
#$outputFiles | Group-Object BaseName | ForEach-Object {
#    $sizeMB = ($_.Group | Measure-Object Length -Sum).Sum / 1MB
#    Write-Host " - $($_.Name): $($_.Count) файл(ов), общий размер: {0:N2} МБ" -f $sizeMB
#}