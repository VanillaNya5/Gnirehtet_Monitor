[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
}
"@ -ErrorAction SilentlyContinue | Out-Null

$windowDone = $false
function Fix-Window {
    if ($windowDone) { return }
    try {
        $hwnd = [Win32]::GetConsoleWindow();
        [Win32]::SetWindowPos($hwnd, [IntPtr]-1, 0,0,0,0, 0x0001 -bor 0x0010);
        [Win32]::SetForegroundWindow($hwnd);
        $script:windowDone = $true
    } catch {}
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$exe = Join-Path $scriptDir 'gnirehtet.exe'

if (-not (Test-Path $exe)) {
    Write-Host "x gnirehtet.exe 不存在：$exe" -ForegroundColor Red
    Fix-Window
    pause
    exit 2
}

# 端口占用处理函数
function KillPortProcess {
    param([int]$port = 31416)
    
    Write-Host "⚠ 处理端口 $port 占用..." -ForegroundColor Yellow
    $processKilled = $false
    
    try {
        $netstatOutput = netstat -ano -p tcp | findstr ":$port "
        
        if ($netstatOutput) {
            $lines = $netstatOutput -split "`r?`n"
            foreach ($line in $lines) {
                if ($line -match '\s+(\d+)$') {
                    $processId = [int]$matches[1]
                    if ($processId -eq 0) { continue }
                    
                    Write-Host "找到占用端口 $port 的进程 PID: $processId" -ForegroundColor Cyan
                    
                    try {
                        $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
                        if ($proc) {
                            Stop-Process -Id $processId -Force -ErrorAction Stop
                            Write-Host "进程 $processId 已结束" -ForegroundColor Green
                            $processKilled = $true
                        } else {
                            Write-Host "i 进程 $processId 已不存在" -ForegroundColor Gray
                        }
                    } catch {
                        Write-Host "x 结束进程 $processId 时出错: $_" -ForegroundColor Red
                    }
                }
            }
        }
    } catch {
        Write-Host "x 处理端口占用时出错: $_" -ForegroundColor Red
    }
    
    return $processKilled
}

Write-Host "启动 gnirehtet..." -ForegroundColor Gray

$issueDetected = $false
$startTimeout3s = $false
$connectTimeout3s = $false
$inactivityTimeout = $false
$portKilledSuccess = $false

try {
    # 清理旧的输出文件
    if (Test-Path "output.txt") { Remove-Item "output.txt" -ErrorAction SilentlyContinue }
    
    # 启动进程（仅重定向标准输出）
    $process = Start-Process -FilePath $exe -ArgumentList 'run' `
        -NoNewWindow -PassThru `
        -RedirectStandardOutput "output.txt"
    
    # 第一阶段：等待Checking日志（2秒）
    Write-Host "等待客户端检查日志（2秒）..." -ForegroundColor Gray
    $checkingDetected = $false
    $startTime = Get-Date
    $timeout = 2
    $lastReadPosition = 0
    $timeoutWarned = $false
    
    while (-not $checkingDetected -and -not $issueDetected -and -not $process.HasExited) {
        # 超时判断+提前警告
        $elapsedTime = (Get-Date) - $startTime
        if ($elapsedTime.TotalSeconds -ge 1 -and -not $timeoutWarned) {
            Write-Host "⚠ 启动即将超时" -ForegroundColor Yellow
            $timeoutWarned = $true
        }
        if ($elapsedTime.TotalSeconds -gt $timeout) {
            Write-Host "x 启动超时（${timeout}秒内未找到Checking日志）" -ForegroundColor Red
            $startTimeout3s = $true
            $issueDetected = $true
            Fix-Window
            exit 3
        }
        
        # 检查文件输出
        if (Test-Path "output.txt") {
            try {
                $content = Get-Content "output.txt" -ErrorAction SilentlyContinue
                if ($content -and $content.Count -gt $lastReadPosition) {
                    for ($i = $lastReadPosition; $i -lt $content.Count; $i++) {
                        $line = $content[$i]
                        if ($line -and $line.Trim() -ne '') {
                            Write-Host $line
                            
                            # 检测端口占用错误
                            if ($line -match 'os error 10048' -or $line -match 'Address already in use' -or $line -match 'EADDRINUSE') {
                                Write-Host "⚠ 检测到端口占用错误..." -ForegroundColor Yellow
                                $portKilledSuccess = KillPortProcess -port 31416
                                $issueDetected = $true
                                Fix-Window
                                if ($portKilledSuccess) {
                                    exit 5
                                } else {
                                    $issueDetected = $true
                                    break
                                }
                            }
                            
                            if ($line -match 'Checking gnirehtet client') {
                                Write-Host "检测到Checking日志" -ForegroundColor Green
                                $checkingDetected = $true
                                $lastReadPosition = $content.Count
                                break
                            }
                        }
                    }
                    $lastReadPosition = $content.Count
                }
            } catch {
                # 忽略读取错误
            }
        }
        
        Start-Sleep -Milliseconds 100
    }
    
    if ($issueDetected -or $process.HasExited) {
        throw "第一阶段失败"
    }
    
    # 第二阶段：等待连接（3秒）
    Write-Host "等待客户端连接（3秒）..." -ForegroundColor Gray
    $connected = $false
    $connectStartTime = Get-Date
    $connectTimeout = 3
    
    while (-not $connected -and -not $issueDetected -and -not $process.HasExited) {
        # 超时判断
        $elapsedTime = (Get-Date) - $connectStartTime
        if ($elapsedTime.TotalSeconds -gt $connectTimeout) {
            Write-Host "x 连接超时（${connectTimeout}秒内未建立连接）" -ForegroundColor Red
            $connectTimeout3s = $true
            $issueDetected = $true
            Fix-Window
            exit 4
        }
        
        # 检查文件输出
        if (Test-Path "output.txt") {
            try {
                $content = Get-Content "output.txt" -ErrorAction SilentlyContinue
                if ($content -and $content.Count -gt $lastReadPosition) {
                    for ($i = $lastReadPosition; $i -lt $content.Count; $i++) {
                        $line = $content[$i]
                        if ($line -and $line.Trim() -ne '') {
                            Write-Host $line
                            
                            if ($line -match 'Client.*connected' -or 
                                $line -match 'TunnelServer.*Client' -or
                                $line -match 'Relay.*started' -and $line -match 'client') {
                                Write-Host "客户端连接成功" -ForegroundColor Green
                                $connected = $true
                                $lastReadPosition = $content.Count
                                break
                            }
                        }
                    }
                    $lastReadPosition = $content.Count
                }
            } catch {
                # 忽略读取错误
            }
        }
        
        Start-Sleep -Milliseconds 50
    }
    
    
    if ($issueDetected -or -not $connected) {
        Fix-Window
        throw "连接失败"
    }
    
    # 第三阶段：监控运行状态
    Write-Host "`ngnirehtet 运行正常（按Ctrl+C退出）" -ForegroundColor Green
    $lastActivityTime = Get-Date
    $inactivityTimeoutSec = 300
    
    while (-not $issueDetected -and -not $process.HasExited) {
        $hasNewOutput = $false
        
        # 检查输出文件
        if (Test-Path "output.txt") {
            try {
                $content = Get-Content "output.txt" -ErrorAction SilentlyContinue
                if ($content -and $content.Count -gt $lastReadPosition) {
                    for ($i = $lastReadPosition; $i -lt $content.Count; $i++) {
                        $line = $content[$i]
                        if ($line -and $line.Trim() -ne '') {
                            Write-Host $line
                            $lastActivityTime = Get-Date
                            $hasNewOutput = $true
                            
                            if ($line -match 'disconnected' -or $line -match 'Client.*disconnected') {
                                Write-Host "⚠ 检测到客户端断开连接" -ForegroundColor Yellow
                                $issueDetected = $true
                                Fix-Window
                                break
                            }
                        }
                    }
                    $lastReadPosition = $content.Count
                }
            } catch {
                # 忽略读取错误
            }
        }
        
        # 无活动超时判断
        $elapsedTime = (Get-Date) - $lastActivityTime
        if ($elapsedTime.TotalSeconds -gt $inactivityTimeoutSec) {
            Write-Host "x 无活动超时（${inactivityTimeoutSec}秒）" -ForegroundColor Red
            $inactivityTimeout = $true
            $issueDetected = $true
            Fix-Window
            break
        }
        
        if (-not $hasNewOutput) {
            Start-Sleep -Seconds 1
        }
    }
    
} catch {
    Write-Host "x 错误: $_" -ForegroundColor Red
    $issueDetected = $true
    Fix-Window
} finally {
    # 清理临时文件
    if (Test-Path "output.txt") {
        Remove-Item "output.txt" -ErrorAction SilentlyContinue
    }
    
    # 结束进程
    if ($process -and -not $process.HasExited) {
        try {
            Write-Host "终止gnirehtet进程..." -ForegroundColor Gray
            $process.Kill()
            Start-Sleep -Milliseconds 500
            Write-Host "进程已终止" -ForegroundColor Green
        } catch {
            Write-Host "x 终止进程时出错: $_" -ForegroundColor Red
        }
    } elseif ($process -and $process.HasExited) {
        Write-Host "ℹ gnirehtet进程已退出" -ForegroundColor Gray
    }
    
    # 释放进程资源
    if ($process) {
        $process.Dispose()
    }
}

# ========== 脚本失败/成功处理逻辑 ==========
if ($issueDetected) {
    exit 1
} else {
    Write-Host "`n脚本正常完成" -ForegroundColor Green
    pause
    exit 0
}