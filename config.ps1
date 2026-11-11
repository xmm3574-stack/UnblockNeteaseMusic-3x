<#
    UNM 3.x 适配版 · 快捷配置器
    双击 config.bat 运行，或: powershell -ExecutionPolicy Bypass -File config.ps1
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path $root '.env'

# ---------------- 读取现有配置 ----------------
$text = ''
if (Test-Path $envFile) {
    $text = [IO.File]::ReadAllText($envFile, [Text.UTF8Encoding]::new($false))
}

function Get-Val([string]$key, [string]$default = '') {
    if ($text -match "(?m)^\s*$key=(.*)$") { return $Matches[1].Trim() }
    return $default
}

function Set-Val([string]$key, [string]$value) {
    # 原地替换，保留文件结构；用脚本块避免 $ 被当成替换变量
    if ($script:text -match "(?m)^\s*$key=") {
        $script:text = [regex]::Replace($script:text, "(?m)^\s*$key=.*$", { param($m) "$key=$value" })
    }
    elseif ($script:text -match "(?m)^#\s*$key=") {
        $script:text = [regex]::Replace($script:text, "(?m)^#\s*$key=.*$", { param($m) "$key=$value" })
    }
    else {
        $script:text = $script:text.TrimEnd() + "`r`n$key=$value`r`n"
    }
}

function Del-Val([string]$key) {
    if ($script:text -match "(?m)^\s*$key=") {
        $script:text = [regex]::Replace($script:text, "(?m)^\s*$key=.*$", { param($m) "# $key=" })
    }
}

function As-Bool([string]$v) { return ($v -eq 'true') }

function Show-Bool([string]$v) {
    if ($v -eq 'true') { return '开' }
    if ($v -eq '') { return '关' }
    return $v
}

function Toggle-Bool([string]$v) {
    if ($v -eq 'true') { return 'false' } else { return 'true' }
}

# ---------------- 开机自启 ----------------
$runKey  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$regName = 'UnblockNeteaseMusic'

function Get-AutostartState {
    try {
        $v = (Get-ItemProperty -Path $runKey -Name $regName -ErrorAction Stop).$regName
        if ($v) { return 'on' }
        return 'off'
    } catch {
        return 'off'
    }
}

function Get-ExePath {
    foreach ($p in @(
            (Join-Path $root 'unm-3x.exe'),
            (Join-Path $root 'dist\unm-3x.exe')
        )) {
        if (Test-Path $p) { return (Resolve-Path $p).Path }
    }
    return $null
}

function Enable-Autostart {
    $exe = Get-ExePath
    if (-not $exe) { throw '找不到 unm-3x.exe，请确认它和 config.bat 在同一个包里' }

    $vbs = Join-Path $root 'autostart.vbs'
    $dir = Split-Path $exe -Parent
    $log = Join-Path $dir 'service.log'

    # 隐藏窗口启动（不经 cmd，避免 /c 的引号解析陷阱）
    $lines = @(
        'Set sh = CreateObject("WScript.Shell")'
        ('sh.CurrentDirectory = "' + $dir + '"')
        ('sh.Run """' + $exe + '"" -p 8080:8081 -a 127.0.0.1", 0, False')
    )
    [IO.File]::WriteAllText($vbs, ($lines -join "`r`n"), [Text.Encoding]::Unicode)

    if (-not (Test-Path $runKey)) { New-Item -Path $runKey -Force | Out-Null }
    Set-ItemProperty -Path $runKey -Name $regName -Value ('wscript.exe "' + $vbs + '"')
    return $exe
}

function Disable-Autostart {
    Remove-ItemProperty -Path $runKey -Name $regName -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $root 'autostart.vbs') -ErrorAction SilentlyContinue
}

# ---------------- 主循环 ----------------
$dirty = $false
while ($true) {
    Clear-Host
    $vip   = Get-Val 'ENABLE_LOCAL_VIP'
    $flac  = Get-Val 'ENABLE_FLAC'
    $ads   = Get-Val 'BLOCK_ADS'
    $upg   = Get-Val 'DISABLE_UPGRADE_CHECK'
    $maxbr = Get-Val 'SELECT_MAX_BR'
    $order = Get-Val 'FOLLOW_SOURCE_ORDER'
    $minbr = Get-Val 'MIN_BR'
    $level = Get-Val 'LOG_LEVEL' 'info'
    $ncm   = Get-Val 'NETEASE_COOKIE'
    $qq    = Get-Val 'QQ_COOKIE'
    $auto  = Get-AutostartState

    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor DarkCyan
    Write-Host '          UnblockNeteaseMusic · 3.x 适配版  配置' -ForegroundColor Cyan
    Write-Host '  ============================================================' -ForegroundColor DarkCyan
    Write-Host ''
    Write-Host ('   [1] 本地 VIP          : ' + $(if ($vip) { $vip } else { '(关)' }))
    Write-Host ('   [2] 优先无损 FLAC     : ' + (Show-Bool $flac))
    Write-Host ('   [3] 屏蔽广告          : ' + (Show-Bool $ads))
    Write-Host ('   [4] 禁用升级检测      : ' + (Show-Bool $upg))
    Write-Host ('   [5] 选择最高码率      : ' + (Show-Bool $maxbr))
    Write-Host ('   [6] 严格音源顺序      : ' + (Show-Bool $order))
    Write-Host ('   [7] 最低码率 MIN_BR   : ' + $(if ($minbr) { $minbr } else { '(不限)' }))
    Write-Host ('   [8] 日志等级          : ' + $level)
    Write-Host ('   [9] 网易 Cookie       : ' + $(if ($ncm) { '(已设置)' } else { '(未设置)' }))
    Write-Host ('   [Q] QQ Cookie         : ' + $(if ($qq) { '(已设置)' } else { '(未设置)' }))
    if ($auto -eq 'on') {
        Write-Host ('   [A] 开机自启          : ') -NoNewline
        Write-Host '已开启' -ForegroundColor Green
    }
    else {
        Write-Host ('   [A] 开机自启          : ') -NoNewline
        Write-Host '关闭' -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '   ------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '   [S] 保存      [R] 保存并重启服务      [E] 记事本编辑原文' -ForegroundColor Yellow
    Write-Host '   [X] 退出（不保存）' -ForegroundColor DarkGray
    Write-Host ''
    if ($dirty) { Write-Host '   * 有未保存的改动' -ForegroundColor Yellow }
    $c = Read-Host '   请选择'

    switch ($c.Trim().ToUpper()) {
        '1' {
            Write-Host ''
            Write-Host '   本地 VIP：1=svip(推荐)  2=cvip  3=true  4=关闭'
            $n = Read-Host '   选择'
            switch ($n.Trim()) {
                '1' { Set-Val 'ENABLE_LOCAL_VIP' 'svip'; $dirty = $true }
                '2' { Set-Val 'ENABLE_LOCAL_VIP' 'cvip'; $dirty = $true }
                '3' { Set-Val 'ENABLE_LOCAL_VIP' 'true'; $dirty = $true }
                '4' { Del-Val 'ENABLE_LOCAL_VIP'; $dirty = $true }
                default { }
            }
        }
        '2' { Set-Val 'ENABLE_FLAC' (Toggle-Bool $flac); $dirty = $true }
        '3' { Set-Val 'BLOCK_ADS' (Toggle-Bool $ads); $dirty = $true }
        '4' { Set-Val 'DISABLE_UPGRADE_CHECK' (Toggle-Bool $upg); $dirty = $true }
        '5' { Set-Val 'SELECT_MAX_BR' (Toggle-Bool $maxbr); $dirty = $true }
        '6' { Set-Val 'FOLLOW_SOURCE_ORDER' (Toggle-Bool $order); $dirty = $true }
        '7' {
            Write-Host ''
            Write-Host '   最低码率：直接回车=不限；320000=320kbps；999000=无损'
            $n = Read-Host '   数值'
            if ($n.Trim() -eq '') { Del-Val 'MIN_BR' } else { Set-Val 'MIN_BR' $n.Trim() }
            $dirty = $true
        }
        '8' {
            Write-Host ''
            Write-Host '   日志等级：1=debug(排障) 2=info(默认) 3=warn 4=error'
            $n = Read-Host '   选择'
            switch ($n.Trim()) {
                '1' { Set-Val 'LOG_LEVEL' 'debug' }
                '2' { Set-Val 'LOG_LEVEL' 'info' }
                '3' { Set-Val 'LOG_LEVEL' 'warn' }
                '4' { Set-Val 'LOG_LEVEL' 'error' }
                default { }
            }
            $dirty = $true
        }
        '9' {
            Write-Host ''
            Write-Host '   粘贴网易云 Cookie（浏览器 F12 里复制整串；直接回车=清空）'
            $n = Read-Host '   Cookie'
            if ($n.Trim() -eq '') { Del-Val 'NETEASE_COOKIE' } else { Set-Val 'NETEASE_COOKIE' $n.Trim() }
            $dirty = $true
        }
        'Q' {
            Write-Host ''
            Write-Host '   粘贴 QQ 音乐 Cookie（uin=xxx; qm_keyst=xxx；回车=清空）'
            $n = Read-Host '   Cookie'
            if ($n.Trim() -eq '') { Del-Val 'QQ_COOKIE' } else { Set-Val 'QQ_COOKIE' $n.Trim() }
            $dirty = $true
        }
        'A' {
            Write-Host ''
            if ((Get-AutostartState) -eq 'on') {
                Disable-Autostart
                Write-Host '   已关闭开机自启。' -ForegroundColor Yellow
            }
            else {
                try {
                    $exe = Enable-Autostart
                    Write-Host '   已开启开机自启。' -ForegroundColor Green
                    Write-Host ('   启动项: ' + $exe) -ForegroundColor DarkGray
                    Write-Host ('   隐藏启动器: ' + (Join-Path $root 'autostart.vbs')) -ForegroundColor DarkGray
                    Write-Host ('   日志: ' + (Join-Path (Split-Path $exe -Parent) 'service.log')) -ForegroundColor DarkGray
                    Write-Host '   (可在 任务管理器 → 启动 里看到并随时禁用)' -ForegroundColor DarkGray
                }
                catch {
                    Write-Host ('   开启失败: ' + $_.Exception.Message) -ForegroundColor Red
                }
            }
            Start-Sleep -Seconds 2
        }
        'S' { break }
        'R' { break }
        'E' {
            if (-not (Test-Path $envFile)) { [IO.File]::WriteAllText($envFile, $text, [Text.UTF8Encoding]::new($false)) }
            Start-Process notepad.exe $envFile
            Write-Host '   记事本已打开，改完保存后按回车重新加载...' -ForegroundColor Yellow
            Read-Host | Out-Null
            $text = [IO.File]::ReadAllText($envFile, [Text.UTF8Encoding]::new($false))
        }
        'X' {
            Write-Host ''
            Write-Host '   已退出，未保存。' -ForegroundColor DarkGray
            Read-Host '   按回车关闭' | Out-Null
            exit 0
        }
        default { }
    }

    # S / R 在这里处理（break 跳出 switch，用标记判断）
    if ($c.Trim().ToUpper() -eq 'S' -or $c.Trim().ToUpper() -eq 'R') {
        if ($text.Trim() -eq '') { $text = "# UNM 配置`r`n" }
        [IO.File]::WriteAllText($envFile, $text.TrimEnd() + "`r`n", [Text.UTF8Encoding]::new($false))
        Write-Host ''
        Write-Host "   已保存到: $envFile" -ForegroundColor Green

        if ($c.Trim().ToUpper() -eq 'R') {
            Write-Host '   正在重启服务...' -ForegroundColor Yellow
            $listen = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
            if ($listen) {
                Stop-Process -Id $listen[0].OwningProcess -Force -ErrorAction SilentlyContinue
                Start-Sleep -Milliseconds 900
            }
            $exe = Join-Path $root 'unm-3x.exe'
            if (-not (Test-Path $exe)) { $exe = Join-Path $root 'dist\unm-3x.exe' }
            if (Test-Path $exe) {
                Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden
                Start-Sleep -Seconds 3
                $ok = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue
                if ($ok) { Write-Host '   服务已启动 (8080/8081)' -ForegroundColor Green }
                else { Write-Host '   启动失败，请手动运行 unm-3x.exe 查看报错' -ForegroundColor Red }
            } else {
                Write-Host '   找不到 unm-3x.exe，请手动启动' -ForegroundColor Red
            }
        }

        Write-Host ''
        Read-Host '   按回车关闭' | Out-Null
        exit 0
    }
}
