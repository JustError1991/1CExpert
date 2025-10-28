# Process-SqlLogs-MultiProcess.ps1

param(
    [int]$ProcessCount = 20,
    [string]$LogDir = "L:\Logs\Raw"
)

# Засекаем общее время выполнения
$totalStartTime = Get-Date

# Параметры директорий
$logDir = $LogDir
$outputDir = "L:\Logs\Cleaned"

# Создание выходной директории
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
    Write-Host "Создана директория для результатов: $outputDir"
}

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
    pause
    exit 0
}

Write-Host "Начинаем обработку $totalFiles файлов в $ProcessCount процессов..."
Write-Host "================================================"

# Разделяем файлы на группы для каждого процесса
$fileGroups = @()
$filesPerProcess = [math]::Ceiling($totalFiles / $ProcessCount)

for ($i = 0; $i -lt $ProcessCount; $i++) {
    $startIndex = $i * $filesPerProcess
    $endIndex = [math]::Min($startIndex + $filesPerProcess - 1, $totalFiles - 1)
    
    if ($startIndex -le $endIndex) {
        $fileGroups += ,@($files[$startIndex..$endIndex])
    }
}

# Создаем скрипт для обработки файлов
$processorScript = @'
param(
    [string]$FileList,
    [string]$OutputDir,
    [int]$GroupIndex
)

# Читаем список файлов из временного файла
$files = Get-Content $FileList | ForEach-Object { Get-Item $_ }

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
# Обрабатываем каждый файл
foreach ($file in $files) {
    $inputFile = $file.FullName
    $outputFile = Join-Path $OutputDir ($file.BaseName + ".sql")
    
    # Чтение всего файла
    $content = Get-Content $inputFile -Raw
    
    # Разбиваем на строки
    $lines = $content -split "`r?`n"
    $result = @()
    
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $currentLine = $lines[$i]
        
        # Проверяем, является ли строка INSERT (упрощенное условие)
        if ($currentLine -match 'Insert into') {
            # Сохраняем оригинальную строку, но удаляем префикс если он есть
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
                        $cleanLine = $cleanLine -replace [regex]::Escape($fullMatch), "CONVERT($typeDef,0"
                    }
                }
                elseif ($funcName -eq "Convert" -and $typeDef -match 'datetime2\(.*\)') {
                    $isCompatible = Test-Datetime2Compatibility $typeDef $hexValue
                    
                    if (-not $isCompatible) {
                        $cleanLine = $cleanLine -replace [regex]::Escape($fullMatch), "Convert($typeDef,'4010-01-01'"
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
        Write-Host "[Процесс $GroupIndex] Обработан файл: $($file.Name)"
    }
}

# Удаляем временный файл со списком файлов
Remove-Item $FileList -Force
'@

# Сохраняем скрипт во временный файл
$tempScriptPath = [System.IO.Path]::GetTempFileName() + ".ps1"
$processorScript | Out-File $tempScriptPath -Encoding UTF8

# Создаем временный каталог для хранения списков файлов
$tempDir = Join-Path $env:TEMP "SqlLogsProcessing"
if (-not (Test-Path $tempDir)) {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
}

# Запускаем процессы для обработки каждой группы файлов
$processes = @()
$groupIndex = 0

foreach ($group in $fileGroups) {
    if ($group.Count -eq 0) { continue }
    
    $groupIndex++
    
    # Создаем временный файл со списком файлов для этой группы
    $fileListPath = Join-Path $tempDir "filelist_$groupIndex.txt"
    $group.FullName | Out-File $fileListPath -Encoding UTF8
    
    # Создаем аргументы для PowerShell
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", ""$tempScriptPath"",
        "-FileList", ""$fileListPath"",
        "-OutputDir", ""$outputDir"",
        "-GroupIndex", $groupIndex
    )
    
    # Запускаем процесс
    $process = Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -PassThru -WindowStyle Hidden
    $processes += $process
    
    Write-Host "Запущен процесс $groupIndex для обработки $($group.Count) файлов"
}

# Ожидаем завершения всех процессов
Write-Host "Ожидание завершения обработки..."
$completed = $false
$startTime = Get-Date
while (-not $completed) {
    $completed = $true
    $runningProcesses = 0
    
    foreach ($process in $processes) {
        if (-not $process.HasExited) {
            $completed = $false
            $runningProcesses++
        }
    }
    
    if (-not $completed) {
        $elapsed = (Get-Date) - $startTime
        Write-Host "Обработка продолжается... Запущено процессов: $runningProcesses, Время: $($elapsed.ToString('hh\:mm\:ss'))"
        Start-Sleep -Seconds 5
    }
}

# Удаляем временный скрипт и каталог
Remove-Item $tempScriptPath -Force
Remove-Item $tempDir -Recurse -Force

# Вычисляем общее время выполнения
$totalElapsedTime = (Get-Date) - $totalStartTime

Write-Host "================================================"
Write-Host "ОБРАБОТКА ЗАВЕРШЕНА"
Write-Host "================================================"
Write-Host "Статистика:"
Write-Host "  Всего файлов: $totalFiles"
Write-Host "  Количество процессов: $ProcessCount"
Write-Host "  Общее время выполнения: $($totalElapsedTime.ToString('hh\:mm\:ss'))"
Write-Host "================================================"
Write-Host "Результаты сохранены в: $outputDir"
Write-Host "================================================"
