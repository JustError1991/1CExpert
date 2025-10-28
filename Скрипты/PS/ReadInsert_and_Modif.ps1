# Process-InsertsWithConversionErrors.ps1

param(
    [string]$logDir = "D:\Logs_systools_temp\2",
    [string]$outputDir = "D:\Logs_systools_temp\2\ProcessedInserts"
)

# Создаем выходную директорию если не существует
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir | Out-Null
}

# Определяем последний обработанный файл
$lastProcessedFile = $null
$lastFileNumber = -1

# Получаем все файлы в выходной директории и находим последний номер
Get-ChildItem -Path $outputDir -File -Filter "ErrorLog*_processed.txt" | ForEach-Object {
    if ($_.BaseName -match 'ErrorLog(\d+)_processed$') {
        $fileNumber = [int]$matches[1]
        if ($fileNumber -gt $lastFileNumber) {
            $lastFileNumber = $fileNumber
            $lastProcessedFile = $_.Name
        }
    }
}

Write-Host "Последний обработанный файл: $($lastProcessedFile ?? 'не найден')"
Write-Host "Начинаем с номера: $($lastFileNumber + 1)"

# Получаем все файлы из исходной директории и сортируем по номеру
$sourceFiles = Get-ChildItem -Path $logDir -File -Filter "ErrorLog*" | Where-Object {
    $_.BaseName -match '^ErrorLog(\d+)$'
} | Sort-Object @{Expression = {[int]($_.BaseName -replace 'ErrorLog', '')}}

# Обрабатываем только файлы, начиная со следующего после последнего обработанного
$filesToProcess = $sourceFiles | Where-Object {
    $fileNumber = [int]($_.BaseName -replace 'ErrorLog', '')
    $fileNumber -gt $lastFileNumber
}

if ($filesToProcess.Count -eq 0) {
    Write-Host "Нет новых файлов для обработки." -ForegroundColor Yellow
    pause
    exit
}

Write-Host "Найдено файлов для обработки: $($filesToProcess.Count)"

$filesToProcess | ForEach-Object {
    $inputFile = $_.FullName
    $currentFileNumber = [int]($_.BaseName -replace 'ErrorLog', '')
    $outputFile = Join-Path $outputDir ("ErrorLog" + $currentFileNumber + "_processed.txt")
    
    Write-Host "Processing: $inputFile (№ $currentFileNumber)"
    
    # Читаем файл построчно
    $lines = [System.IO.File]::ReadAllLines($inputFile)
    $results = @()
    $i = 0
    
    while ($i -lt $lines.Count) {
        $line = $lines[$i].Trim()
        
        # Ищем INSERT с последующей ошибкой конвертации
        if ($line -match 'Insert into') {
            $insertLine = $line
            $hasErrorNumeric = $false
            $hasErrorData = $false
            $hasErrorDocument = $false
            $hasError_Document1296_VT30313X1 = $false
            $hasError_Document1296_VT30244X1 = $false
            
            # Проверяем следующие строки на наличие ошибки конвертации
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                $nextLine = $lines[$j].Trim()
                
                if (($line -match '\[dbo]\.\[_Document1311\]') -or 
                    ($line -match '\[dbo]\.\[_Document1320X1\]') -or 
                    ($line -match '\[dbo]\.\[_Document1319_VT31262\]')){
                    $hasErrorDocument = $true
                    $i = $j # Пропускаем строку с ошибкой
                    break
                }
                elseif (($line -match '\[dbo]\.\[_Document1296_VT30313X1\]') -or 
                        ($line -match '\[dbo]\.\[_Document1296_VT30244X1\]')){
                    $hasError_Document1296_VT30313X1 = $true
                    $hasError_Document1296_VT30244X1 = $true
                    $i = $j # Пропускаем строку с ошибкой
                    break
                }
                elseif ($nextLine -match 'Error converting data type varbinary to numeric') {
                    $hasErrorNumeric = $true
                    $i = $j # Пропускаем строку с ошибкой
                    break
                }
                elseif ($nextLine -match 'Conversion failed when converting date and/or time from character string') {
                    $hasErrorData = $true
                    $i = $j # Пропускаем строку с ошибкой
                    break
                }
                elseif (-not [string]::IsNullOrWhiteSpace($nextLine)) {
                    break # Прерываем если нашли непустую строку без ошибки
}
            }
            
            if ($hasErrorNumeric) {
                # Модифицируем проблемные CONVERT выражения
                $modifiedInsert = $insertLine -replace 'CONVERT\(numeric\(7\,0\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(7,0), 0' `
                                              -replace 'CONVERT\(numeric\(5\,0\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(5,0), 0' `
                                              -replace 'CONVERT\(numeric\(1\,0\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(1,0), 0' `
                                              -replace 'CONVERT\(numeric\(2\,0\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(2,0), 0' `
                                              -replace 'CONVERT\(numeric\(9\,0\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(9,0), 0' `
                                              -replace 'CONVERT\(numeric\(15\,2\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(15,2), 0.01' `
                                              -replace 'CONVERT\(numeric\(15\,3\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(15,3), 0.001' `
                                              -replace 'CONVERT\(numeric\(16\,4\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(16,4), 0.0001' `
                                              -replace '^Code:[01]\s+ERROR:\d+\s+MSG:', ''
                                            
                $results += $modifiedInsert
            }
            if ($hasErrorData) {
                # Модифицируем проблемные CONVERT выражения
                $modifiedInsert = $insertLine -replace 'Convert\(datetime2\([^)]+\),\s*0x[0-9a-fA-F]+', 'Convert(datetime2(00), ''2010-01-01''' `
                                              -replace 'CONVERT\(numeric\([^)]+\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(7,0), 0' `
                                              -replace '^Code:[01]\s+ERROR:\d+\s+MSG:', ''
                                            
               $results += $modifiedInsert
            }
            if ($hasErrorDocument) {
                # Модифицируем проблемные CONVERT выражения
                $modifiedInsert = $insertLine -replace 'Convert\(datetime2\([^)]+\),\s*0x[0-9a-fA-F]+', 'Convert(datetime2(00), ''2010-01-01''' `
                                              -replace 'CONVERT\(numeric\(7\,0\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(7,0), 0' `
                                              -replace 'CONVERT\(numeric\(5\,0\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(5,0), 0' `
                                              -replace 'CONVERT\(numeric\(2\,0\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(2,0), 0' `
                                              -replace 'CONVERT\(numeric\(15\,2\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(15,2), 0.01' `
                                              -replace 'CONVERT\(numeric\(15\,3\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(15,3), 0.001' `
                                              -replace 'CONVERT\(numeric\(16\,4\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(16,4), 0.0001' `
                                              -replace 'NULL', '''2010-01-01''' `
                                              -replace '^Code:[01]\s+ERROR:\d+\s+MSG:', ''
                                            
                $results += $modifiedInsert
            }
            if (($hasError_Document1296_VT30313X1) -or
               ($hasError_Document1296_VT30244X1)){
                # Модифицируем проблемные CONVERT выражения
                $modifiedInsert = $insertLine -replace 'CONVERT\(numeric\(7\,0\),\s*0x[0-9a-fA-F]+', 'CONVERT(numeric(7,0), 0' `
                                              -replace '^Code:[01]\s+ERROR:\d+\s+MSG:', ''
                                              
                $results += $modifiedInsert
            }
            
        }
        
        $i++
    }
    
    # Сохраняем результаты
    if ($results.Count -gt 0) {
        $results | Out-File $outputFile -Encoding utf8
        Write-Host "Processed $($results.Count) problematic INSERT statements" -ForegroundColor Green
    }
    else {
Write-Host "No problematic INSERT statements found" -ForegroundColor Yellow
    }
}

Write-Host "`nProcessing complete. Results saved to: $outputDir"
Write-Host "Обработано файлов: $($filesToProcess.Count)"