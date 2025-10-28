# execute_sql_folder_advanced.ps1
param(
    [string]$ServerInstance = "localhost",
    [string]$Database = "YourDatabase",
    [string]$FolderPath = ".\",
    [int]$BatchSize = 1000,
    [string]$Username,
    [string]$Password,
    [string]$FilePattern = "*.sql",
    [switch]$SkipErrors = $true
)

# Функция для выполнения SQL-команд с обработкой ошибок
function Execute-SqlBatch {
    param($connection, $sql, $filePath, $lineNumber)
    
    try {
        $command = $connection.CreateCommand()
        $command.CommandText = $sql
        $command.CommandTimeout = 0
        $result = $command.ExecuteNonQuery()
        return @{ Success = $true; Result = $result }
    }
    catch {
        $errorMsg = $_.Exception.Message
        Write-Host "  ERROR at line $lineNumber : $errorMsg" -ForegroundColor Red
        
        # Логируем ошибку
        $errorLogFile = "$filePath.errors.log"
        $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Line $lineNumber : $errorMsg`nSQL: $sql`n"
        Add-Content -Path $errorLogFile -Value $logEntry
        
        return @{ Success = $false; Error = $errorMsg }
    }
}

# Функция для обработки одного файла
function Process-SqlFile {
    param($filePath)
    
    Write-Host "Processing file: $filePath" -ForegroundColor Green
    
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
        $connection.Open()
        
        $reader = [System.IO.File]::OpenText($filePath)
        $batch = New-Object System.Text.StringBuilder
        $counter = 0
        $totalExecuted = 0
        $errorCount = 0
        $currentLine = 0
        
        while ($null -ne ($line = $reader.ReadLine())) {
            $currentLine++
            
            # Пропускаем пустые строки и комментарии
            if ([string]::IsNullOrWhiteSpace($line) -or $line.Trim().StartsWith("--")) {
                continue
            }
            
            $batch.AppendLine($line) | Out-Null
            $counter++
            
            # Если накопили достаточно команд для батча, выполняем
            if ($counter -ge $BatchSize) {
                $sql = $batch.ToString()
                if (-not [string]::IsNullOrWhiteSpace($sql)) {
                    $result = Execute-SqlBatch $connection $sql $filePath $currentLine
                    
                    if ($result.Success) {
                        $totalExecuted += $result.Result
                        Write-Host "  Executed batch. Total affected rows in file: $totalExecuted"
                    } else {
                        $errorCount++
                        if (-not $SkipErrors) {
                            throw "Stopping execution due to error (SkipErrors is disabled)"
                        }
                    }
                }
                $batch.Clear() | Out-Null
                $counter = 0
            }
        }
        
        # Выполняем последний батч
        if ($batch.Length -gt 0) {
            $sql = $batch.ToString()
            $result = Execute-SqlBatch $connection $sql $filePath $currentLine
            
            if ($result.Success) {
                $totalExecuted += $result.Result
                Write-Host "  Final batch executed. Total affected rows in file: $totalExecuted"
            } else {
                $errorCount++
            }
        }
        
        $reader.Close()
        Write-Host "  File processing completed. Total affected rows: $totalExecuted, Errors: $errorCount" -ForegroundColor Green
        return @{ Success = $true; Processed = $totalExecuted; Errors = $errorCount }
    }
    catch {
        Write-Error "Error processing file $filePath : $($_.Exception.Message)"
        return @{ Success = $false; Processed = $totalExecuted; Errors = $errorCount }
    }
    finally {
        if ($connection -and $connection.State -eq 'Open') {
            $connection.Close()
        }
    }
}
# Основной код
try {
    # Проверяем существование папки
    if (-not (Test-Path $FolderPath -PathType Container)) {
        Write-Error "Folder $FolderPath does not exist!"
        exit 1
    }
    
    # Создаем connection string
    $connectionString = "Server=$ServerInstance;Database=$Database;Integrated Security=true;"
    if ($Username -and $Password) {
        $connectionString = "Server=$ServerInstance;Database=$Database;User ID=$Username;Password=$Password;"
    }
    
    # Получаем все SQL-файлы в папке
    $sqlFiles = Get-ChildItem -Path $FolderPath -Filter $FilePattern | Sort-Object Name
    
    if ($sqlFiles.Count -eq 0) {
        Write-Host "No SQL files found in $FolderPath with pattern $FilePattern" -ForegroundColor Yellow
        exit 0
    }
    
    Write-Host "Found $($sqlFiles.Count) SQL file(s) to process" -ForegroundColor Cyan
    Write-Host "SkipErrors mode: $SkipErrors" -ForegroundColor Cyan
    
    # Обрабатываем каждый файл
    $successCount = 0
    $errorCount = 0
    $totalProcessed = 0
    $totalErrors = 0
    
    foreach ($file in $sqlFiles) {
        $result = Process-SqlFile $file.FullName
        
        if ($result.Success) {
            $successCount++
            $totalProcessed += $result.Processed
            $totalErrors += $result.Errors
            Write-Host "  File completed with $($result.Errors) errors" -ForegroundColor Green
        } else {
            $errorCount++
            Write-Host "  File failed to process completely" -ForegroundColor Red
        }
        
        # Небольшая пауза между файлами
        Start-Sleep -Milliseconds 100
    }
    
    # Выводим итоги
    Write-Host "`nProcessing completed!" -ForegroundColor Cyan
    Write-Host "Successfully processed: $successCount file(s)" -ForegroundColor Green
    Write-Host "Failed: $errorCount file(s)" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
    Write-Host "Total rows affected: $totalProcessed" -ForegroundColor Green
    Write-Host "Total errors encountered: $totalErrors" -ForegroundColor $(if ($totalErrors -gt 0) { "Yellow" } else { "Gray" })
    
    if ($totalErrors -gt 0) {
        Write-Host "Error details logged in .errors.log files" -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Unexpected error: $($_.Exception.Message)"
    exit 1
}