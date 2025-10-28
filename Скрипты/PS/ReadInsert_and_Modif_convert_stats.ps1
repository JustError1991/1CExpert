# Process-SqlLogs.ps1

# Засекаем общее время выполнения
$totalStartTime = Get-Date

# Параметры директорий
$logDir = "L:\Logs"
$outputDir = Join-Path $logDir "Cleaned"

# Статистика
$stats = @{
    TotalFiles = 0
    ProcessedFiles = 0
    TotalLines = 0
    ConvertedNumeric = 0
    ConvertedDatetime = 0
    SkippedLines = 0
}

# Проверка исходной директории
if (-not (Test-Path $logDir)) {
    Write-Host "Ошибка: Директория с логами не найдена: $logDir" -ForegroundColor Red
    pause
    exit 1
}

# Создание выходной директории
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
    Write-Host "Создана директория для результатов: $outputDir"
}

# Функция для проверки соответствия значения типу данных numeric
function Test-NumericCompatibility {
    param(
        [string]$TypeDefinition,
        [string]$HexValue
    )
    
    try {
        # Извлекаем precision и scale из определения типа
        if ($TypeDefinition -match 'numeric\((\d+),(\d+)\)') {
            $precision = [int]$matches[1]
            $scale = [int]$matches[2]
            
            # Преобразуем hex в BigInteger
            Add-Type -AssemblyName System.Numerics
            $bigIntValue = [System.Numerics.BigInteger]::Parse($HexValue.Substring(2), 
                [System.Globalization.NumberStyles]::AllowHexSpecifier)
            
            # Проверяем, соответствует ли значение precision
            $maxValue = [System.Numerics.BigInteger]::Pow(10, $precision) - 1
            $minValue = -$maxValue
            
            return $bigIntValue -ge $minValue -and $bigIntValue -le $maxValue
        }
        
        # Для других типов numeric считаем значение корректным
        return $true
    }
    catch {
        # Если не удалось преобразовать, считаем несовместимым
        return $false
    }
}

# Функция для проверки соответствия значения типу данных datetime2
function Test-Datetime2Compatibility {
    param(
        [string]$TypeDefinition,
        [string]$HexValue
    )
    
    try {
        # Преобразуем hex в число
        $value = [Convert]::ToInt64($HexValue, 16)
        
        # Для datetime2 проверяем, является ли значение допустимой датой
        return $value -gt 0 -and $value -lt [DateTime]::MaxValue.Ticks
    }
    catch {
        # Если не удалось преобразовать, считаем несовместимым
        return $false
    }
}

# Получаем список файлов для обработки
$files = Get-ChildItem $logDir -File
$stats.TotalFiles = $files.Count

Write-Host "Начинаем обработку $($stats.TotalFiles) файлов..."
Write-Host "================================================"

# Обработка файлов
$files | ForEach-Object {
    $fileStartTime = Get-Date
    $inputFile = $_.FullName
    $outputFile = Join-Path $outputDir ($_.BaseName + "_cleaned" + $_.Extension)
    
    Write-Host "Обработка файла: $($_.Name)"
    
    # Чтение всего файла
    $content = Get-Content $inputFile -Raw
    
    # Разбиваем на строки
    $lines = $content -split "`r?`n"
    $result = @()
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $currentLine = $lines[$i]
        
        # Проверяем, является ли строка INSERT
        if ($currentLine -match 'Insert into') {
            $stats.TotalLines++
            
            # Сохраняем оригинальную строку
            $cleanLine = $currentLine -replace '^Code:[01]\s+ERROR:0\s+MSG:', ''
            
            # Ищем все CONVERT/Convert выражения в строке с улучшенным регулярным выражением
            $matches = [regex]::Matches($cleanLine, '(CONVERT|Convert)\(([^,()]*(?:\([^)]+\))?[^,()]*),\s*(0x[0-9a-fA-F]+)')
            
            foreach ($match in $matches) {
                $fullMatch = $match.Groups[0].Value
                $funcName = $match.Groups[1].Value
                $typeDef = $match.Groups[2].Value
                $hexValue = $match.Groups[3].Value
                
                # Проверяем совместимость значения с типом
                $isCompatible = $false
                
                if ($funcName -eq "CONVERT" -and $typeDef
-match 'numeric\(\d+,\d+\)') {
                    $isCompatible = Test-NumericCompatibility $typeDef $hexValue
                    
                    if (-not $isCompatible) {
                        $stats.ConvertedNumeric++
                        $cleanLine = $cleanLine -replace [regex]::Escape($fullMatch), "CONVERT($typeDef,0)"
                    }
                }
                elseif ($funcName -eq "Convert" -and $typeDef -match 'datetime2\(.*\)') {
                    $isCompatible = Test-Datetime2Compatibility $typeDef $hexValue
                    
                    if (-not $isCompatible) {
                        $stats.ConvertedDatetime++
                        $cleanLine = $cleanLine -replace [regex]::Escape($fullMatch), "Convert($typeDef,'2010-01-01')"
                    }
                }
            }
            
            # Добавляем строку в результат
            $result += $cleanLine
        }
        else {
            $stats.SkippedLines++
        }
    }
    
    # Сохранение результата
    if ($result.Count -gt 0) {
        $result | Out-File $outputFile -Encoding utf8
        $stats.ProcessedFiles++
        
        $fileElapsedTime = (Get-Date) - $fileStartTime
        Write-Host "  Обработано строк: $($result.Count), Время: $($fileElapsedTime.TotalSeconds.ToString('0.00')) сек."
    } else {
        Write-Host "  Файл не содержит строк INSERT: $($_.Name)"
    }
}

# Вычисляем общее время выполнения
$totalElapsedTime = (Get-Date) - $totalStartTime

Write-Host "================================================"
Write-Host "ОБРАБОТКА ЗАВЕРШЕНА"
Write-Host "================================================"
Write-Host "Статистика:"
Write-Host "  Всего файлов: $($stats.TotalFiles)"
Write-Host "  Обработано файлов: $($stats.ProcessedFiles)"
Write-Host "  Всего строк: $($stats.TotalLines)"
Write-Host "  Пропущено строк: $($stats.SkippedLines)"
Write-Host "  Конвертаций numeric: $($stats.ConvertedNumeric)"
Write-Host "  Конвертаций datetime: $($stats.ConvertedDatetime)"
Write-Host "  Общее время выполнения: $($totalElapsedTime.TotalSeconds.ToString('0.00')) сек."
Write-Host "  Среднее время на файл: $(($totalElapsedTime.TotalSeconds / [math]::Max(1, $stats.ProcessedFiles)).ToString('0.00')) сек."
Write-Host "================================================"
Write-Host "Результаты сохранены в: $outputDir"
Write-Host "================================================"
