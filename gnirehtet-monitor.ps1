# 简化版监视器脚本
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$main = Join-Path $scriptDir 'gnirehtet-main.ps1'

if (-not (Test-Path $main)) {
    Write-Host "gnirehtet-main.ps1 not found: $main" -ForegroundColor Red
    pause
    exit 1
}

$restartCount = 0
Write-Host "Gnirehtet 监视器启动."

while ($true) {
    $restartCount++
    Write-Host "启动本体窗口 (重启计数: $restartCount) ..."

    # 启动进程
    try {
        $body = Start-Process -FilePath 'powershell.exe' -ArgumentList '-ExecutionPolicy Bypass', "-File `"$main`"" -WorkingDirectory $scriptDir -WindowStyle Minimized -PassThru -ErrorAction Stop
        Write-Host "本体进程启动, PID = $($body.Id)"
        
        # 等待进程退出
        Wait-Process -Id $body.Id -ErrorAction Stop
        $exitCode = $body.ExitCode
        Write-Host "本体进程退出, exit code = $exitCode"
    } catch {
        Write-Host "启动/等待本体进程失败: $_" -ForegroundColor Red
        $exitCode = -1
        Start-Sleep -Seconds 2
    }

    # 退出码判断
    if ($exitCode -eq 0) {
        Write-Host "Body exited normally. Monitor will not restart. Press any key to close this window..." -ForegroundColor Cyan
        pause
        break
    }
    if ($exitCode -eq 3) { Write-Host "启动超时" -ForegroundColor Cyan}
    if ($exitCode -eq 4) { Write-Host "连接超时" -ForegroundColor Cyan}
    if ($exitCode -eq 5) { Write-Host "成功杀死占用端口的进程" -ForegroundColor Cyan}

    Write-Host "本体异常退出, 重启中 (current restart count: $restartCount) ..." -ForegroundColor Yellow

}