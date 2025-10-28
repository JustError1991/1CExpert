<#
.SYNOPSIS
    Проверяет статус WinRM и собирает информацию о серверах (RAM, CPU, диски)
    с корректной обработкой кириллических символов.
#>

# Устанавливаем кодировку вывода UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$Servers = @(
    "srv1",
    "srv2"
    # Добавьте другие серверы...
)

$Results = foreach ($Server in $Servers) {
    Write-Host "Проверка сервера: $Server" -ForegroundColor Cyan

    # Создаем объект с результатами по умолчанию
    $Result = [PSCustomObject]@{
        Server          = $Server
        Online          = "off"
        WinRMService    = "N/A"
        WinRMPortOpen   = "N/A"
        WSManAvailable  = "N/A"
        TotalRAM_GB     = "N/A"
        CPU_Cores       = "N/A"
        Disks           = "N/A"
    }

    # Проверка доступности
    if (-not (Test-Connection -ComputerName $Server -Count 1 -Quiet -ErrorAction SilentlyContinue)) {
        Write-Host "[off] Сервер $Server недоступен!" -ForegroundColor Red
        $Result
        continue
    }

    $Result.Online = "on"

    try {
        # Получаем информацию о системе
        $SystemInfo = Invoke-Command -ComputerName $Server -ScriptBlock {
            # Оперативная память
            $RAM = [math]::Round(
                (Get-CimInstance Win32_PhysicalMemory | 
                 Measure-Object -Property Capacity -Sum).Sum / 1GB, 2
            )

            # Процессор
            $CPU = (Get-CimInstance Win32_Processor).NumberOfCores

            # Диски (только локальные)
            $Disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | 
                     ForEach-Object {
                         $Free = [math]::Round($_.FreeSpace / 1GB, 2)
                         $Total = [math]::Round($_.Size / 1GB, 2)
                         "$($_.DeviceID) ($Free/$Total GB)"
                     }

            [PSCustomObject]@{
                RAM = $RAM
                CPU = $CPU
                Disks = $Disks -join ", "
            }
        } -ErrorAction Stop

        # Заполняем данные
        $Result.TotalRAM_GB = $SystemInfo.RAM
        $Result.CPU_Cores = $SystemInfo.CPU
        $Result.Disks = $SystemInfo.Disks

        # Проверяем WinRM
        $Result.WinRMService = if ((Get-Service -ComputerName $Server -Name WinRM -ErrorAction SilentlyContinue).Status -eq "Running") {
            "on"
        } else {
            "off"
        }

        $Result.WinRMPortOpen = if (Test-NetConnection -ComputerName $Server -Port 5985 -WarningAction SilentlyContinue).TcpTestSucceeded {
            "on"
        } else {
            "off"
        }

        $Result.WSManAvailable = if (Test-WSMan -ComputerName $Server -ErrorAction SilentlyContinue) {
            "on"
        } else {
            "off"
        }

        Write-Host "[on] Данные успешно собраны" -ForegroundColor Green
    }
    catch {
        Write-Host "[error] Ошибка при сборе данных: $_" -ForegroundColor Red
        $Result.WinRMService = "error"
        $Result.WinRMPortOpen = "error"
        $Result.WSManAvailable = "error"
    }

    $Result
}

# Выводим результаты с поддержкой кириллицы
$Results | Format-Table -AutoSize -Property `
    @{Label="Server"; Expression={$_.Server}},
    @{Label="Online"; Expression={$_.Online}},
    @{Label="Service WinRM"; Expression={$_.WinRMService}},
    @{Label="Port 5985"; Expression={$_.WinRMPortOpen}},
    @{Label="WSMan"; Expression={$_.WSManAvailable}},
    @{Label="TotalRAM (GB)"; Expression={$_.TotalRAM_GB}},
    @{Label="Cores CPU"; Expression={$_.CPU_Cores}},
    @{Label="Disk (free/all)"; Expression={$_.Disks}}

# Экспорт в CSV с UTF-8
$Results | Export-Csv -Path "status_servers.csv" -NoTypeInformation -Encoding UTF8 -Force