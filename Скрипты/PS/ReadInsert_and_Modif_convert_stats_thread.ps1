# Process-SqlLogs.ps1

param(
    [int]$ThreadCount = 20
)

# Засекаем общее время выполнения
$totalStartTime = Get-Date

# Параметры директорий
$logDir = "L:\Logs"
$outputDir = Join-Path $logDir "Cleaned"

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

# Основная логика обработки
function Main {
    # Проверка исходной директории
    if (-not (Test-Path $logDir)) {
        Write-Host "Ошибка: Директория с логами не найдена: $logDir" -ForegroundColor Red
        pause
        exit 1
    }
# Получаем список файлов для обработки
    $files = Get-ChildItem $logDir -File
    $totalFiles = $files.Count
    
    if ($totalFiles -eq 0) {
        Write-Host "В директории $logDir не найдено файлов для обработки"
        return
    }
    
    Write-Host "Начинаем обработку $totalFiles файлов в $ThreadCount потоков..."
    Write-Host "================================================"
    
    # Создаем пул runspace для многопоточной обработки
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThreadCount)
    $runspacePool.ApartmentState = "MTA"  # Многопоточное подразделение
    $runspacePool.ThreadOptions = "ReuseThread"  # Повторное использование потоков
    $runspacePool.Open()
    
    # Создаем сессионное состояние и добавляем в него наши функции
    $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $functionDefinitions = @()
    
    # Добавляем функции в сессионное состояние
    $functionDefinitions += "function Test-NumericCompatibility { ${function:Test-NumericCompatibility} }"
    $functionDefinitions += "function Test-Datetime2Compatibility { ${function:Test-Datetime2Compatibility} }"
    
    # Создаем скрипт-блок для обработки файла
    $scriptBlock = {
        param($File, $OutputDir, $FunctionDefinitions)
        
        # Выполняем определения функций в текущей области видимости
        Invoke-Expression $FunctionDefinitions
        
        $fileStats = @{
            ProcessedLines = 0
            ConvertedNumeric = 0
            ConvertedDatetime = 0
        }
        
        $inputFile = $File.FullName
        $outputFile = Join-Path $OutputDir ($File.BaseName + "_cleaned" + $File.Extension)
        
        # Чтение всего файла
        $content = Get-Content $inputFile -Raw
        
        # Разбиваем на строки
        $lines = $content -split "`r?`n"
        $result = @()
        
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $currentLine = $lines[$i]
            
            # Проверяем, является ли строка INSERT
            if ($currentLine -match 'Code:[01]\s+ERROR:0\s+MSG:Insert into') {
                $fileStats.ProcessedLines++
                
                # Сохраняем оригинальную строку
                $cleanLine = $currentLine -replace '^Code:[01]\s+ERROR:0\s+MSG:', ''
                
                # Ищем все CONVERT/Convert выражения в строке
                $matches = [regex]::Matches($cleanLine, '(CONVERT|Convert)\(([^,()]*(?:\([^)]+\))?[^,()]*),\s*(0x[0-9a-fA-F]+)')
                
                foreach ($match in $matches) {
                    $fullMatch = $match.Groups[0].Value
                    $funcName = $match.Groups[1].Value
                    $typeDef = $match.Groups[2].Value
                    $hexValue = $match.Groups[3].Value
                    
                    # Проверяем совместимость значения с типом
                    $isCompatible = $false
                    
                    if ($funcName -eq "CONVERT" -and $typeDef -match 'numeric\(\d+,\d+\)') {
                        $isCompatible = Test-NumericCompatibility $typeDef $hexValue
                        
                        if (-not $isCompatible) {
                            $fileStats.ConvertedNumeric++
                            $cleanLine = $cleanLine -replace [regex]::Escape($fullMatch), "CONVERT($typeDef,0)"
                        }
                    }
                    elseif ($funcName -eq "Convert" -and $typeDef -match 'datetime2\(.*\)') {
                        $isCompatible = Test-Datetime2Compatibility $typeDef $hexValue
                        
                        if (-not $isCompatible) {
                            $fileStats.ConvertedDatetime++
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
        }
        
        return $fileStats
    }
    
    $jobs = @()
    $totalStats = @{
        TotalFiles = $totalFiles
        ProcessedFiles = 0
        TotalLines = 0
        ConvertedNumeric = 0
        ConvertedDatetime = 0
    }
    
    # Запускаем обработку каждого файла в отдельном потоке
    foreach ($file in $files) {
        $powerShell = [powershell]::Create().AddScript($scriptBlock).AddArgument($file).AddArgument($outputDir).AddArgument($functionDefinitions)
        
        $powerShell.RunspacePool = $runspacePool
        $handle = $powerShell.BeginInvoke()
        
        $jobs += [PSCustomObject]@{
            PowerShell = $powerShell
            Handle = $handle
            File = $file
        }
    }
    
    # Ожидаем завершения всех задач и собираем результаты
    while ($jobs.Count -gt 0) {
        for ($i = 0; $i -lt $jobs.Count; $i++) {
            $job = $jobs[$i]
            if ($job.Handle.IsCompleted) {
                $result = $job.PowerShell.EndInvoke($job.Handle)
                $job.PowerShell.Dispose()
                
                # Обновляем общую статистику
                $totalStats.ProcessedFiles++
                $totalStats.TotalLines += $result.ProcessedLines
                $totalStats.ConvertedNumeric += $result.ConvertedNumeric
                $totalStats.ConvertedDatetime += $result.ConvertedDatetime
                
                Write-Host "Обработан файл: $($job.File.Name) (строк: $($result.ProcessedLines), конвертаций: $($result.ConvertedNumeric + $result.ConvertedDatetime))"
                
                # Удаляем завершенное задание
                $jobs = $jobs[0..($i-1)] + $jobs[($i+1)..($jobs.Count-1)]
                $i--  # Уменьшаем счетчик, так как массив изменился
            }
        }
        
        Start-Sleep -Milliseconds 100
    }
    
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    # Вычисляем общее время выполнения
    $totalElapsedTime = (Get-Date) - $totalStartTime
    
    Write-Host "================================================"
    Write-Host "ОБРАБОТКА ЗАВЕРШЕНА"
    Write-Host "================================================"
    Write-Host "Статистика:"
    Write-Host "  Всего файлов: $($totalStats.TotalFiles)"
    Write-Host "  Обработано файлов: $($totalStats.ProcessedFiles)"
    Write-Host "  Всего строк: $($totalStats.TotalLines)"
    Write-Host "  Конвертаций numeric: $($totalStats.ConvertedNumeric)"
    Write-Host "  Конвертаций datetime: $($totalStats.ConvertedDatetime)"
    Write-Host "  Общее время выполнения: $($totalElapsedTime.TotalSeconds.ToString('0.00')) сек."
    Write-Host "  Среднее время на файл: $(($totalElapsedTime.TotalSeconds / [math]::Max(1, $totalStats.ProcessedFiles)).ToString('0.00')) сек."
    Write-Host "================================================"
    Write-Host "Результаты сохранены в: $outputDir"
    Write-Host "================================================"
}

# Запускаем основную функцию
Main
