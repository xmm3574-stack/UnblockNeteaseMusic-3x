<#
  UnblockNeteaseMusic 3.x 适配版 · 启动脚本
  用法:
    .\start.ps1                 # 默认 8080(HTTP) / 8081(HTTPS-MITM)
    .\start.ps1 -Port 8090      # 自定义 HTTP 端口，HTTPS 自动 +1
    .\start.ps1 -LogLevel info  # 安静模式
    .\start.ps1 -MinBr 999000   # 强制换源(低于该码率一律替换)，调试用
#>
param(
    [int]$Port = 8080,
    [int]$HttpsPort = 0,
    [string]$LogLevel = 'debug',
    [string]$MinBr = '',
    [string]$Sources = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

if ($HttpsPort -le 0) { $HttpsPort = $Port + 1 }

# ---- 前置检查 ----
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { Write-Host "[x] 找不到 node，请先安装 Node.js 18+" -ForegroundColor Red; exit 1 }
Write-Host "[*] node $(node --version)" -ForegroundColor DarkGray

if (-not (Test-Path "$root\node_modules\pino")) {
    Write-Host "[*] 首次运行，安装依赖..." -ForegroundColor Yellow
    $env:npm_config_registry = 'https://registry.npmmirror.com'
    npm install --omit=dev --no-audit --no-fund
}

# 端口占用检查
foreach ($p in @($Port, $HttpsPort)) {
    $busy = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    if ($busy) {
        Write-Host "[x] 端口 $p 已被占用 (PID $($busy[0].OwningProcess))" -ForegroundColor Red
        exit 1
    }
}

# ---- 证书 ----
if (-not (Test-Path "$root\server.crt") -or -not (Test-Path "$root\server.key")) {
    Write-Host "[!] 缺少 server.crt / server.key" -ForegroundColor Red
    exit 1
}
$ca = Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -match 'UnblockNeteaseMusic' } | Select-Object -First 1
if (-not $ca) {
    Write-Host "[!] 系统根证书区没有 UNM 的 CA，客户端会因证书不受信而拒绝连接" -ForegroundColor Yellow
    Write-Host "    导入方式(管理员): certutil -addstore -f Root `"$root\ca.crt`"" -ForegroundColor Yellow
} else {
    Write-Host "[*] CA 已在证书区: $($ca.Thumbprint)" -ForegroundColor DarkGray
}

# ---- 环境 ----
$env:LOG_LEVEL   = $LogLevel
$env:ENABLE_FLAC = 'true'
if ($MinBr)   { $env:MIN_BR = $MinBr }   else { Remove-Item Env:\MIN_BR -ErrorAction SilentlyContinue }
if ($Sources) { $env:ENABLE_FLAC = 'true' }

Write-Host ""
Write-Host "  HTTP  代理 : 127.0.0.1:$Port"        -ForegroundColor Green
Write-Host "  HTTPS MITM : 127.0.0.1:$HttpsPort"    -ForegroundColor Green
Write-Host "  客户端设置 : 工具 -> 自定义代理 -> 127.0.0.1 : $Port" -ForegroundColor Cyan
Write-Host "  (网易云 3.x 只走 HTTPS，两个端口都必须监听，否则请求会被判 blank)" -ForegroundColor DarkGray
Write-Host ""

# ---- 运行 ----
$nodeArgs = @('src/app.js', '-p', "${Port}:${HttpsPort}", '-a', '127.0.0.1')
if ($Sources) { $nodeArgs += @('-o') + ($Sources -split ',') }

node @nodeArgs
