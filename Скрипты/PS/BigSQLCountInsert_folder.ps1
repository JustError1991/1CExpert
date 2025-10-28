# execute_sql_folder.ps1
param(
    [string]$ServerInstance = "rec02.corp.local",
    [string]$Database = "YourDatabase",
    [string]$FolderPath = ".\",
    [int]$BatchSize = 1000,
    [string]$Username,
    [string]$Password,
    [string]$FilePattern = "*.sql"
)

# Функция для выполнения SQL-команд
function Execute-SqlBatch {
    param($connection, $sql)
    try {
        $command = $connection.CreateCommand()
        $command.CommandText = $sql
        $command.CommandTimeout = 0
        $result = $command.ExecuteNonQuery()
        return $result
    }
    catch {
        Write-Error "Error executing SQL batch: $($_.Exception.Message)"
        Write-Error "Problematic SQL: $sql"
        throw
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
        $fileProcessed = $false
        
        while ($null -ne ($line = $reader.ReadLine())) {
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
                    $affectedRows = Execute-SqlBatch $connection $sql
                    $totalExecuted += $affectedRows
                    Write-Host "  Executed batch. Total affected rows in file: $totalExecuted"
                }
                $batch.Clear() | Out-Null
                $counter = 0
            }
        }
        
        # Выполняем последний батч
        if ($batch.Length -gt 0) {
            $sql = $batch.ToString()
            $affectedRows = Execute-SqlBatch $connection $sql
            $totalExecuted += $affectedRows
            Write-Host "  Final batch executed. Total affected rows in file: $totalExecuted"
        }
        
        $reader.Close()
        $fileProcessed = $true
        Write-Host "  File processed successfully: $filePath" -ForegroundColor Green
    }
    catch {
        Write-Error "Error processing file $filePath : $($_.Exception.Message)"
        $fileProcessed = $false
    }
    finally {
        if ($connection -and $connection.State -eq 'Open') {
            $connection.Close()
        }
    }
    
    return $fileProcessed
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
    
    foreach ($file in $sqlFiles) {
        if (Process-SqlFile $file.FullName) {
            $successCount++
        } else {
            $errorCount++
        }
        
        # Небольшая пауза между файлами
        Start-Sleep -Milliseconds 100
    }
    
    # Выводим итоги
    Write-Host "`nProcessing completed!" -ForegroundColor Cyan
    Write-Host "Successfully processed: $successCount file(s)" -ForegroundColor Green
    Write-Host "Failed: $errorCount file(s)" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
}
catch {
    Write-Error "Unexpected error: $($_.Exception.Message)"
    exit 1
}