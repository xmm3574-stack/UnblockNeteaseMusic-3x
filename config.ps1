<#
    UNM 3.x 适配版 · 快捷配置器
    双击 config.bat 运行，或: powershell -ExecutionPolicy Bypass -File config.ps1
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path $root '.env'
$taskName = 'UnblockNeteaseMusic-Watchdog'
$regName = 'UnblockNeteaseMusic'

# ---------------- 读取现有配置 ----------------
$text = ''
if (Test-Path $envFile) {
    $text = [IO.File]::ReadAllText($envFile, [Text.UTF8Encoding]::new($false))
}

function Get-Val([string]$key, [string]$default = '') {
    if ($text -match "(?m)^\s*$key=(.*)$") { return $Matches[1].Trim() }
    return $default
}

# schtasks 失败时会把 stderr 变成 terminating error（ErrorActionPreference=Stop），
# 统一包一层：临时放宽错误处理，只看退出码。
function Invoke-Schtasks {
    param([string[]]$TaskArgs)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & schtasks @TaskArgs 2>&1 | Out-Null
        return $LASTEXITCODE
    }
    catch {
        return 1
    }
    finally {
        $ErrorActionPreference = $old
    }
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
    # 计划任务（含守护）优先，注册表作为兜底
    $taskOk = $false
    try {
        if ((Invoke-Schtasks @('/Query','/TN',$taskName,'/FO','LIST')) -eq 0) { $taskOk = $true }
    }
    catch { }
    if ($taskOk) { return 'on(守护)' }

    try {
        $v = (Get-ItemProperty -Path $runKey -Name $regName -ErrorAction Stop).$regName
        if ($v) { return 'on' }
        return 'off'
    }
    catch {
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

    $dir = Split-Path $exe -Parent

    # 端口/地址跟随 .env（默认 8080:8081 / 127.0.0.1，客户端不用改）
    $p = Get-Val 'LISTEN_PORT'
    $a = Get-Val 'LISTEN_ADDR'
    if (-not $p) { $p = '8080:8081' }
    if (-not $a) { $a = '127.0.0.1' }

    # 1) 隐藏启动器：立即拉起服务用（窗口模式 0 = 不弹黑框）
    $vbs = Join-Path $root 'autostart.vbs'
    $vbsBody = @(
        'Set sh = CreateObject("WScript.Shell")'
        ('sh.CurrentDirectory = "' + $dir + '"')
        ('sh.Run """' + $exe + '"" -p ' + $p + ' -a ' + $a + '", 0, False')
    ) -join "`r`n"
    [IO.File]::WriteAllText($vbs, $vbsBody + "`r`n", [Text.Encoding]::Unicode)

    # 2) 看护启动器：计划任务调它，隐藏跑 watchdog.ps1
    $wvbs = Join-Path $root 'watchdog_run.vbs'
    $ps1 = Join-Path $root 'watchdog.ps1'
    $wvbsBody = @(
        'Set sh = CreateObject("WScript.Shell")'
        ('sh.CurrentDirectory = "' + $root + '"')
        ('sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""' + $ps1 + '""", 0, False')
    ) -join "`r`n"
    [IO.File]::WriteAllText($wvbs, $wvbsBody + "`r`n", [Text.Encoding]::Unicode)

    # 3) 计划任务：开机登录后每分钟检查一次，服务不在就拉起
    Invoke-Schtasks @('/Create','/TN',$taskName,'/TR',('wscript.exe "' + $wvbs + '"'),'/SC','MINUTE','/MO','1','/F') | Out-Null

    # 4) 立即起一次，省得等下一分钟
    Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $vbs + '"') -WindowStyle Hidden

    # 5) 兼容旧的注册表方式（部分环境计划任务被策略禁用时兜底）
    if (-not (Test-Path $runKey)) { New-Item -Path $runKey -Force | Out-Null }
    Set-ItemProperty -Path $runKey -Name $regName -Value ('wscript.exe "' + $vbs + '"')

    return $exe
}

function Disable-Autostart {
    Invoke-Schtasks @('/Delete','/TN',$taskName,'/F') | Out-Null
    Remove-ItemProperty -Path $runKey -Name $regName -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $root 'autostart.vbs') -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $root 'watchdog_run.vbs') -ErrorAction SilentlyContinue
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
    $srcOrder = Get-Val 'MATCH_ORDER'
    $portCfg = Get-Val 'LISTEN_PORT'
    $addrCfg = Get-Val 'LISTEN_ADDR'
    if (-not $portCfg) { $portCfg = '8080:8081' }
    if (-not $addrCfg) { $addrCfg = '127.0.0.1' }
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
    Write-Host ('   [O] 音源顺序          : ' + $(if ($srcOrder) { $srcOrder } else { '(内置默认)' }))
    Write-Host ('   [P] 监听端口          : ' + $portCfg + '  @ ' + $addrCfg)
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
        'O' {
            Write-Host ''
            Write-Host '   音源顺序（内置默认: kugou,kuwo,migu,bilibili,ytdlp）'
            Write-Host '     1 = 只要国内三源       kugou,kuwo,migu（不要 B站）'
            Write-Host '     2 = 国内三源 + B站兜底  kugou,kuwo,migu,bilibili'
            Write-Host '     3 = 只留酷狗酷我       kugou,kuwo（最快）'
            Write-Host '     4 = 自定义（逗号分隔）'
            Write-Host '     5 = 恢复内置默认'
            $n = Read-Host '   选择'
            switch ($n.Trim()) {
                '1' { Set-Val 'MATCH_ORDER' 'kugou,kuwo,migu'; $dirty = $true }
                '2' { Set-Val 'MATCH_ORDER' 'kugou,kuwo,migu,bilibili'; $dirty = $true }
                '3' { Set-Val 'MATCH_ORDER' 'kugou,kuwo'; $dirty = $true }
                '4' {
                    Write-Host '   可用: kugou kuwo migu bilibili bilivideo bodian ytdlp qq joox youtube'
                    $v = Read-Host '   输入顺序'
                    if ($v.Trim()) {
                        Set-Val 'MATCH_ORDER' (($v.Trim() -split '[\s,]+' | Where-Object { $_ }) -join ',')
                        $dirty = $true
                    }
                }
                '5' { Del-Val 'MATCH_ORDER'; $dirty = $true }
                default { }
            }
        }
        'P' {
            Write-Host ''
            Write-Host '   监听端口（客户端代理端口 = 冒号前那个）'
            Write-Host '     1 = 8080:8081   默认，最容易和别的软件撞'
            Write-Host '     2 = 18080:18081 推荐，冲突概率低'
            Write-Host '     3 = 7890:7891   常见代理端口段'
            Write-Host '     4 = 自定义'
            $n = Read-Host '   选择'
            switch ($n.Trim()) {
                '1' { Set-Val 'LISTEN_PORT' '8080:8081'; $dirty = $true }
                '2' { Set-Val 'LISTEN_PORT' '18080:18081'; $dirty = $true }
                '3' { Set-Val 'LISTEN_PORT' '7890:7891'; $dirty = $true }
                '4' {
                    $v = Read-Host '   输入 http:https 端口，例如 18080:18081'
                    if ($v.Trim() -match '^\d+:\d+$') { Set-Val 'LISTEN_PORT' $v.Trim(); $dirty = $true }
                    else { Write-Host '   格式不对，要 数字:数字' -ForegroundColor Red; Start-Sleep -Seconds 2 }
                }
                default { }
            }
            Write-Host ''
            Write-Host '   绑定地址：1 = 127.0.0.1（只本机，推荐）  2 = 0.0.0.0（局域网可访问）'
            $a = Read-Host '   选择（直接回车保持不变）'
            if ($a.Trim() -eq '1') { Set-Val 'LISTEN_ADDR' '127.0.0.1'; $dirty = $true }
            elseif ($a.Trim() -eq '2') { Set-Val 'LISTEN_ADDR' '0.0.0.0'; $dirty = $true }
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
            $rp = Get-Val 'LISTEN_PORT'
            $ra = Get-Val 'LISTEN_ADDR'
            if (-not $rp) { $rp = '8080:8081' }
            if (-not $ra) { $ra = '127.0.0.1' }
            $httpPort = [int]($rp.Split(':')[0])
            $httpsPort = if ($rp.Contains(':')) { [int]($rp.Split(':')[1]) } else { $httpPort + 1 }

            # 新旧端口都扫一遍，防止改端口后旧进程还占着
            foreach ($pp in @($httpPort, $httpsPort, 8080, 8081)) {
                $listen = Get-NetTCPConnection -LocalPort $pp -State Listen -ErrorAction SilentlyContinue |
                    Where-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName -like 'unm-3x*' }
                if ($listen) {
                    Stop-Process -Id $listen[0].OwningProcess -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 900
                }
            }
            $exe = Join-Path $root 'unm-3x.exe'
            if (-not (Test-Path $exe)) { $exe = Join-Path $root 'dist\unm-3x.exe' }
            if (Test-Path $exe) {
                # 端口/地址跟随 .env，隐藏窗口启动
                Start-Process -FilePath $exe `
                    -ArgumentList '-p', $rp, '-a', $ra `
                    -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden
                Start-Sleep -Seconds 3
                $ok = Get-NetTCPConnection -LocalPort $httpPort -State Listen -ErrorAction SilentlyContinue
                $ok2 = Get-NetTCPConnection -LocalPort $httpsPort -State Listen -ErrorAction SilentlyContinue
                if ($ok -and $ok2) { Write-Host "   服务已启动 ($httpPort/$httpsPort)  客户端代理端口用 $httpPort" -ForegroundColor Green }
                elseif ($ok) { Write-Host "   警告：$httpPort 已起但 $httpsPort 未监听，客户端会请求失败" -ForegroundColor Yellow }
                else {
                    $blocker = Get-NetTCPConnection -LocalPort $httpPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($blocker) {
                        $bn = (Get-Process -Id $blocker.OwningProcess -ErrorAction SilentlyContinue).ProcessName
                        Write-Host "   启动失败：$httpPort 被 $bn (PID $($blocker.OwningProcess)) 占用，去 [P] 换个端口" -ForegroundColor Red
                    } else {
                        Write-Host '   启动失败，请手动运行 unm-3x.exe 查看报错' -ForegroundColor Red
                    }
                }
            } else {
                Write-Host '   找不到 unm-3x.exe，请手动启动' -ForegroundColor Red
            }
        }

        Write-Host ''
        Read-Host '   按回车关闭' | Out-Null
        exit 0
    }
}
