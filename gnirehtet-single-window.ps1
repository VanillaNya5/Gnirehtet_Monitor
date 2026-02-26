[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

$exe = '.\gnirehtet.exe'
$adbExe = '.\adb.exe'
$port = 31416

if (-not (Test-Path $exe)) {
    Write-Host "gnirehtet.exe 未找到"
    pause
    exit 2
}

if (-not (Test-Path $adbExe)) {
    Write-Host "adb.exe 未找到"
    pause
    exit 2
}

function Release-Port {
    param([int]$port)
    
    $netstatOutput = netstat -ano | findstr ":$port"
    
    if ($netstatOutput) {
        $processIds = @()
        foreach ($line in $netstatOutput) {
            if ($line -match '\s+(\d+)$') {
                $processIds += $matches[1]
            }
        }
        
        $uniqueProcessIds = $processIds | Select-Object -Unique
        
        foreach ($processId in $uniqueProcessIds) {
            if ($processId -ne 0) {
                $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
                if ($process) {
                    Write-Host "Port $port is occupied by process $($process.ProcessName) (PID: $processId)"
                    
                    if ($process.ProcessName -eq 'gnirehtet' -or $process.Path -like '*gnirehtet*') {
                        Write-Host "This is a gnirehtet related process, will terminate automatically..." -ForegroundColor Yellow
                        $process.Kill()
                        Write-Host "Process terminated" -ForegroundColor Green
                    } else {
                        Write-Host "Warning: Port is occupied by other application $($process.ProcessName)" -ForegroundColor Red
                        Write-Host "Terminate this process? (Y/N): " -ForegroundColor Yellow -NoNewline
                        $response = Read-Host
                        if ($response -eq 'Y' -or $response -eq 'y') {
                            $process.Kill()
                            Write-Host "Process terminated" -ForegroundColor Green
                        } else {
                            Write-Host "User chose not to terminate the process, waiting for user to handle..." -ForegroundColor Yellow
                            Write-Host "Press any key to continue..." -ForegroundColor Cyan
                            [void][System.Console]::ReadKey($true)
                            return $false
                        }
                    }
                } else {
                    Write-Host "Process $processId no longer exists, continuing..." -ForegroundColor Gray
                }
            }
        }
        
        return $true
    } else {
        return $true
    }
}

$restartCount = 0
$host.UI.RawUI.WindowTitle = "Gnirehtet Single Window"

while ($true) {
    $restartCount++
    Write-Host "`nStarting gnirehtet($restartCount)..."
    
    try {
        $portReleased = Release-Port -port $port
        if (-not $portReleased) {
            continue
        }
        
        $deviceConnected = $false
        
        Write-Host "Checking ADB device..."
        $adbOutput = & $adbExe devices
        if ($adbOutput -match '\d+\s+device') {
            $deviceConnected = $true
            Write-Host "ADB device connected!" -ForegroundColor Green
            $host.UI.RawUI.WindowTitle = "Gnirehtet Single Window (Proxying)"
        } else {
            Write-Host "ADB device not connected, waiting..." -ForegroundColor Yellow
            $host.UI.RawUI.WindowTitle = "Gnirehtet Single Window (Waiting)"
            $waitStartTime = Get-Date
            while ($true) {
                $adbOutput = & $adbExe devices
                if ($adbOutput -match '\d+\s+device') {
                    $deviceConnected = $true
                    $waitEndTime = Get-Date
                    $waitDuration = ($waitEndTime - $waitStartTime).TotalSeconds
                    Write-Host "ADB device connected! (Wait time: $($waitDuration.ToString('0.00')) seconds)" -ForegroundColor Green
                    $host.UI.RawUI.WindowTitle = "Gnirehtet Single Window (Proxying)"
                    break
                }
            }
        }
        
        if (-not $deviceConnected) {
            Write-Host "ADB device not found, skipping iteration..." -ForegroundColor Yellow
            continue
        }
        
        Write-Host "Starting gnirehtet process..." -ForegroundColor Cyan
        $process = Start-Process -FilePath $exe -ArgumentList 'run' -NoNewWindow -PassThru
        
        Write-Host "Gnirehtet process started, PID: $($process.Id)"
        
        while (-not $process.HasExited) {
            $adbOutput = & $adbExe devices
            if (-not ($adbOutput -match '\d+\s+device')) {
                Write-Host "`nADB device disconnected!" -ForegroundColor Red
                Write-Host "Terminating gnirehtet process..." -ForegroundColor Yellow
                $process.Kill()
                break
            }
        }
        
        Write-Host "Process exited, restarting immediately..." -ForegroundColor Yellow
        
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        $host.UI.RawUI.WindowTitle = "Gnirehtet Single Window (Error)"
        if ($_.Exception.Message -notmatch '第一阶段失败|连接失败') {
            Write-Host "`nUnrecognized error detected, press any key to continue..." -ForegroundColor Cyan
            [void][System.Console]::ReadKey($true)
        }
    }
}