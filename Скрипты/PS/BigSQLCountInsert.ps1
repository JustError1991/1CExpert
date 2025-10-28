# execute_large_sql.ps1
param(
    [string]$ServerInstance = "rec02.corp.local",
    [string]$Database = "ERP_prod_Recovered",
    [string]$SqlFile = "D:\large_script.sql",
    [int]$BatchSize = 1000
)

# Загрузка модуля SQLServer
Import-Module SqlServer

# Функция для выполнения скрипта по частям
function Execute-SqlInBatches {
    param($filePath, $batchSize)
    
    $batch = New-Object System.Text.StringBuilder
    $counter = 0
    $totalExecuted = 0
    
    Get-Content $filePath | ForEach-Object {
        $batch.AppendLine($_) | Out-Null
        $counter++
        
        if ($counter -ge $batchSize) {
            $sql = $batch.ToString()
            if (-not [string]::IsNullOrWhiteSpace($sql)) {
                try {
                    Invoke-SqlCmd -ServerInstance $ServerInstance -Database $Database -Query $sql
                    $totalExecuted += $counter
                    Write-Host "Executed $totalExecuted statements..."
                }
                catch {
                    Write-Error "Error executing batch: $_"
                }
            }
            $batch.Clear() | Out-Null
            $counter = 0
        }
    }
    
    # Выполнить оставшиеся команды
    if ($batch.Length -gt 0) {
        $sql = $batch.ToString()
        try {
            Invoke-SqlCmd -ServerInstance $ServerInstance -Database $Database -Query $sql
            $totalExecuted += $counter
            Write-Host "Final batch executed. Total: $totalExecuted statements"
        }
        catch {
            Write-Error "Error executing final batch: $_"
        }
    }
}

# Выполнение скрипта
Execute-SqlInBatches -filePath $SqlFile -batchSize $BatchSize