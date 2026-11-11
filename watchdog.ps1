# UnblockNeteaseMusic 3.x 看护脚本
# 由计划任务每 N 分钟调用一次：端口在监听就什么都不做，
# 掉了就以隐藏窗口重新拉起 unm-3x.exe。
# 若端口被"别的程序"占着，只记录日志、不抢端口，避免和别人打架。

$ErrorActionPreference = 'SilentlyContinue'
$root = $PSScriptRoot
$logFile = Join-Path $root 'watchdog.log'

function Write-Log($msg) {
    $line = ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg)
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

# --- 读 .env 里的端口/地址（不引入外部依赖，按行解析） ---
$port = '8080:8081'
$addr = '127.0.0.1'
$envFile = Join-Path $root '.env'
if (Test-Path $envFile) {
    $raw = [IO.File]::ReadAllText($envFile, [Text.UTF8Encoding]::new($false))
    foreach ($line in ($raw -split "`r?`n")) {
        $t = $line.Trim()
        if ($t.StartsWith('#')) { continue }
        if ($t -match '^LISTEN_PORT\s*=\s*(\S+)') { $port = $Matches[1] }
        if ($t -match '^LISTEN_ADDR\s*=\s*(\S+)') { $addr = $Matches[1] }
    }
}
$httpPort = [int]($port.Split(':')[0])

# --- 1. 已经在监听？ ---
$listening = Get-NetTCPConnection -LocalPort $httpPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listening) {
    $procName = (Get-Process -Id $listening.OwningProcess -ErrorAction SilentlyContinue).ProcessName
    if ($procName -like 'unm-3x*') { exit 0 }   # 正常，静默退出

    # 端口被别的程序占了：不抢，只记一笔（每分钟只记一次，避免刷屏）
    if (Test-Path $logFile) {
        $last = Get-Content $logFile -Tail 1
        if ($last -notmatch [regex]::Escape("占用 $httpPort")) {
            Write-Log "端口 $httpPort 被 $procName (PID $($listening.OwningProcess)) 占用，跳过本轮拉起"
        }
    } else {
        Write-Log "端口 $httpPort 被 $procName (PID $($listening.OwningProcess)) 占用，跳过本轮拉起"
    }
    exit 1
}

# --- 2. 没在监听：拉起 ---
$exe = Join-Path $root 'unm-3x.exe'
if (-not (Test-Path $exe)) {
    Write-Log "找不到 $exe，无法拉起"
    exit 1
}

Start-Process -FilePath $exe `
    -ArgumentList '-p', $port, '-a', $addr `
    -WorkingDirectory $root -WindowStyle Hidden
Start-Sleep -Seconds 3

$ok = Get-NetTCPConnection -LocalPort $httpPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($ok) {
    Write-Log "服务未运行，已自动拉起 (端口 $httpPort, PID $($ok.OwningProcess))"
    exit 0
} else {
    Write-Log "尝试拉起失败，端口 $httpPort 仍未监听"
    exit 1
}
