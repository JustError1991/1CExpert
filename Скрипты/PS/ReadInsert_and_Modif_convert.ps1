# Process-SqlLogs.ps1

# Параметры директорий
$logDir = "L:\Logs"
$outputDir = Join-Path $logDir "Cleaned"

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
            
            # Преобразуем hex в BigInteger (для работы с большими числами)
            Add-Type -AssemblyName System.Numerics
            $bigIntValue = [System.Numerics.BigInteger]::Parse($HexValue.Substring(2), 
                [System.Globalization.NumberStyles]::AllowHexSpecifier)
            
            # Преобразуем в десятичное число с учетом scale
            $decimalValue = [decimal]$bigIntValue / [math]::Pow(10, $scale)
            
            # Проверяем, соответствует ли значение precision
            $maxValue = [math]::Pow(10, $precision - $scale) - 1 / [math]::Pow(10, $scale)
            $minValue = -[math]::Pow(10, $precision - $scale) + 1 / [math]::Pow(10, $scale)
            
            return $decimalValue -ge $minValue -and $decimalValue -le $maxValue
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
        # (простая проверка - значение должно быть положительным и не слишком большим)
        return $value -gt 0 -and $value -lt [DateTime]::MaxValue.Ticks
    }
    catch {
        # Если не удалось преобразовать, считаем несовместимым
        return $false
    }
}

# Обработка файлов
Get-ChildItem $logDir -File | ForEach-Object {
    $inputFile = $_.FullName
    $outputFile = Join-Path $outputDir ($_.BaseName + "_cleaned" + $_.Extension)
    
    Write-Host "Обработка файла: $inputFile"
    
    # Чтение всего файла
    $content = Get-Content $inputFile -Raw
    
    # Разбиваем на строки
    $lines = $content -split "`r?`n"
    $result = @()
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $currentLine = $lines[$i]
        
        # Проверяем, является ли строка INSERT
        if ($currentLine -match 'Code:[01]\s+ERROR:0\s+MSG:Insert into') {
            # Сохраняем оригинальную строку
            $cleanLine = $currentLine -replace '^Code:[01]\s+ERROR:0\s+MSG:', ''
            
            # Ищем все CONVERT/Convert выражения в строке
            $matches = [regex]::Matches($cleanLine, '(CONVERT|Convert)\(([^,]+),\s*(0x[0-9a-fA-F]+)')
            
            foreach ($match in $matches) {
                $fullMatch = $match.Groups[0].Value
                $funcName = $match.Groups[1].Value
                $typeDef = $match.Groups[2].Value
                $hexValue = $match.Groups[3].Value
                
                # Проверяем совместимость значения с типом
                $isCompatible = $false
                
                if ($funcName -eq "CONVERT" -and $typeDef -match 'numeric\(\d+,\d+\)') {
                    $isCompatible = Test-NumericCompatibility $typeDef $hexValue
                }
                elseif ($funcName -eq "Convert" -and $typeDef -match 'datetime2\(.*\)') {
$isCompatible = Test-Datetime2Compatibility $typeDef $hexValue
                }
                else {
                    # Для других типов считаем значение корректным
                    $isCompatible = $true
                }
                
                if (-not $isCompatible) {
                    # Выполняем замену в зависимости от типа
                    if ($funcName -eq "CONVERT" -and $typeDef -match 'numeric\(\d+,\d+\)') {
                        $cleanLine = $cleanLine -replace [regex]::Escape($fullMatch), "CONVERT($typeDef,0)"
                    }
                    elseif ($funcName -eq "Convert" -and $typeDef -match 'datetime2\(.*\)') {
                        $cleanLine = $cleanLine -replace [regex]::Escape($fullMatch), "Convert($typeDef,'2010-01-01')"
                    }
                }
            }
            
            # Добавляем строку в результат
            $result += $cleanLine
        }
    }
    
    # Сохранение результата
    if ($result.Count -gt 0) {
        $result | Out-File $outputFile -Encoding utf8
        Write-Host "Сохранено строк: $($result.Count)"
        Write-Host "Результат в: $outputFile"
    } else {
        Write-Host "Файл не содержит строк INSERT: $inputFile"
    }
}

Write-Host "`nОбработка завершена. Результаты в: $outputDir"