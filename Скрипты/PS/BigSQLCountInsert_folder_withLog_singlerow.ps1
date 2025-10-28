# execute_sql_folder_single_line.ps1
param(
    [string]$ServerInstance = "localhost",
    [string]$Database = "YourDatabase",
    [string]$FolderPath = ".\",
    [string]$Username,
    [string]$Password,
    [string]$FilePattern = "*.sql"
)

# Функция для выполнения одиночного SQL-запроса
function Execute-SingleSql {
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
        
        # Логируем только ошибку (без SQL)
        $errorLogFile = "$filePath.errors.log"
        $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Line $lineNumber : $errorMsg`n"
        Add-Content -Path $errorLogFile -Value $logEntry
        
        return @{ Success = $false; Error = $errorMsg }
    }
}

# Функция для обработки одного файла построчно
function Process-SqlFileLineByLine {
    param($filePath)
    
    Write-Host "Processing file: $filePath" -ForegroundColor Green
    
    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
        $connection.Open()
        
        $lines = Get-Content $filePath
        $totalLines = $lines.Count
        $processedCount = 0
        $errorCount = 0
        
        for ($i = 0; $i -lt $totalLines; $i++) {
            $line = $lines[$i].Trim()
            $lineNumber = $i + 1
            
            # Пропускаем пустые строки и комментарии
            if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("--")) {
                continue
            }
            
            # Выполняем каждую строку как отдельный запрос
            $result = Execute-SingleSql $connection $line $filePath $lineNumber
            
            if ($result.Success) {
                $processedCount++
                # Показываем прогресс каждые 1000 строк
                if ($processedCount % 1000 -eq 0) {
                    Write-Host "  Processed $processedCount lines (Errors: $errorCount)" -ForegroundColor Gray
                }
            } else {
                $errorCount++
            }
        }
        
        Write-Host "  File processing completed. Processed: $processedCount lines, Errors: $errorCount" -ForegroundColor Green
        return @{ Success = $true; Processed = $processedCount; Errors = $errorCount }
    }
    catch {
        Write-Error "Error processing file $filePath : $($_.Exception.Message)"
        return @{ Success = $false; Processed = $processedCount; Errors = $errorCount }
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
    
    # Обрабатываем каждый файл
    $successCount = 0
    $errorCount = 0
    $totalProcessed = 0
    $totalErrors = 0
    
    foreach ($file in $sqlFiles) {
        # Удаляем старый лог ошибок, если существует
        $errorLogFile = "$($file.FullName).errors.log"
        if (Test-Path $errorLogFile) {
            Remove-Item $errorLogFile -Force
        }
        
        $result = Process-SqlFileLineByLine $file.FullName
        
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
    Write-Host "Total lines processed: $totalProcessed" -ForegroundColor Green
    Write-Host "Total errors encountered: $totalErrors" -ForegroundColor $(if ($totalErrors -gt 0) { "Yellow" } else { "Gray" })
    
    if ($totalErrors -gt 0) {
        Write-Host "Error details logged in .errors.log files" -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Unexpected error: $($_.Exception.Message)"
    exit 1
}