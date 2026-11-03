#Requires -Version 5.1
<#
  Charles 汉化安装器 - 公共函数库
  由 安装汉化.ps1（命令行）与 安装汉化-GUI.ps1（图形界面）共同引用
#>

$script:LogPath = Join-Path $PSScriptRoot 'install.log'
$script:LogSink = $null        # GUI 可挂接日志回调
$script:ProgressSink = $null   # GUI 可挂接进度回调（percent, text）
$script:BackupName = 'charles.jar.orig'

function Log([string]$msg, [string]$level = 'INFO') {
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $level, $msg
    try { Add-Content -Path $script:LogPath -Value $line -Encoding UTF8 } catch { }
    if ($script:LogSink) { try { & $script:LogSink $line $level } catch { } }
    else {
        switch ($level) {
            'OK'   { Write-Host $msg -ForegroundColor Green }
            'WARN' { Write-Host $msg -ForegroundColor Yellow }
            'ERR'  { Write-Host $msg -ForegroundColor Red }
            default { Write-Host $msg }
        }
    }
}

function Report([int]$percent, [string]$text) {
    if ($script:ProgressSink) { try { & $script:ProgressSink $percent $text } catch { } }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-Writable([string]$dir) {
    try {
        $probe = Join-Path $dir ('.write-test-{0}.tmp' -f $PID)
        [IO.File]::WriteAllText($probe, 'x')
        Remove-Item $probe -Force
        return $true
    } catch { return $false }
}

function Test-CharlesDir([string]$dir) {
    if ([string]::IsNullOrWhiteSpace($dir)) { return $false }
    return (Test-Path (Join-Path $dir 'lib\charles.jar'))
}

function Add-Candidate($list, [string]$path, [string]$source) {
    if (-not (Test-CharlesDir $path)) { return }
    try { $full = (Resolve-Path $path).Path } catch { return }
    if ($list | Where-Object { $_.Path -eq $full }) { return }
    $isMsix = $full -like '*\WindowsApps\*'
    $list.Add([pscustomobject]@{
        Path     = $full
        Source   = $source
        Writable = (Test-Writable $full)
        Msix     = $isMsix
        HasJar   = (Test-Path (Join-Path $full 'lib\charles.jar.orig'))
    }) | Out-Null
}

function Get-CharlesCandidates([switch]$SkipScan, [scriptblock]$OnProgress) {
    $list = New-Object System.Collections.Generic.List[object]

    # 1) 卸载注册表
    foreach ($root in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        Get-ItemProperty $root -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*Charles*' } |
            ForEach-Object {
                if ($_.InstallLocation) { Add-Candidate $list $_.InstallLocation '注册表 InstallLocation' }
                if ($_.DisplayIcon) {
                    $p = ($_.DisplayIcon -replace ',\d+$', '')
                    if ($p -like '*.exe') { Add-Candidate $list (Split-Path $p) '注册表 DisplayIcon' }
                }
                if ($_.UninstallString -match '^"?([^"]+\.exe)"?') {
                    Add-Candidate $list (Split-Path $Matches[1]) '注册表 UninstallString'
                }
            }
    }
    if ($OnProgress) { & $OnProgress '已检查注册表' }

    # 2) 常见安装位置
    foreach ($r in @(
            "$env:ProgramFiles\Charles",
            "${env:ProgramFiles(x86)}\Charles",
            "$env:LOCALAPPDATA\Programs\Charles",
            "$env:LOCALAPPDATA\Programs\Charles-CN",
            "$env:LOCALAPPDATA\Charles",
            "$env:APPDATA\Charles")) {
        if (Test-Path $r) { Add-Candidate $list $r '常见安装路径' }
    }
    if ($OnProgress) { & $OnProgress '已检查常见路径' }

    # 3) 各磁盘根目录
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($name in @('Charles', 'Charles-CN', 'CharlesProxy')) {
            $p = Join-Path $d.Root $name
            if (Test-Path $p) { Add-Candidate $list $p '磁盘根目录' }
        }
    }
    if ($OnProgress) { & $OnProgress '已检查磁盘根目录' }

    # 4) 运行中的进程
    Get-Process -Name 'Charles' -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Path) { Add-Candidate $list (Split-Path $_.Path) '运行中的进程' }
    }

    # 5) MSIX / 商店版
    $appx = Get-AppxPackage -Name 'XK72.Charles' -ErrorAction SilentlyContinue
    if ($appx) {
        $p = Join-Path $appx.InstallLocation 'VFS\ProgramFilesX64\Charles'
        if (Test-Path $p) { Add-Candidate $list $p 'Microsoft Store (MSIX)' }
    }
    if ($OnProgress) { & $OnProgress '已检查商店版' }

    # 6) 浅层扫描兜底
    if (-not $SkipScan) {
        $deadline = (Get-Date).AddSeconds(15)
        foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA, 'D:\', 'E:\') |
                Where-Object { $_ -and (Test-Path $_) }) {
            if ((Get-Date) -gt $deadline) { break }
            if ($OnProgress) { & $OnProgress "扫描 $root …" }
            Get-ChildItem -Path $root -Directory -Filter 'Charles*' -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                ForEach-Object { Add-Candidate $list $_.FullName '目录扫描' }
        }
    }
    return $list
}

function Stop-CharlesProcess {
    $procs = Get-Process -Name 'Charles' -ErrorAction SilentlyContinue
    if (-not $procs) { return $true }

    Log ("检测到 Charles 正在运行（PID: {0}），正在自动退出…" -f (($procs | ForEach-Object { $_.Id }) -join ', ')) 'WARN'
    foreach ($p in $procs) { try { $p.CloseMainWindow() | Out-Null } catch { } }
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 500
        if (-not (Get-Process -Name 'Charles' -ErrorAction SilentlyContinue)) {
            Log 'Charles 已正常退出' 'OK'
            return $true
        }
    }
    Log 'Charles 未响应关闭请求，强制结束进程…' 'WARN'
    Get-Process -Name 'Charles' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (Get-Process -Name 'Charles' -ErrorAction SilentlyContinue) {
        Log '无法结束 Charles 进程，请手动退出后重试' 'ERR'
        return $false
    }
    Log 'Charles 已强制结束' 'OK'
    return $true
}

function Get-Sha256([string]$path) {
    (Get-FileHash -Path $path -Algorithm SHA256).Hash
}

function Install-Patch([string]$dir, [string]$jarPath) {
    $targetJar = Join-Path $dir 'lib\charles.jar'
    $backupJar = Join-Path $dir ("lib\{0}" -f $script:BackupName)

    Report 5 '检查目录权限…'
    if (-not (Test-Writable (Join-Path $dir 'lib'))) {
        Log "目录不可写：$dir" 'ERR'
        return $false
    }

    Report 15 '结束正在运行的 Charles…'
    if (-not (Stop-CharlesProcess)) { return $false }

    try { (Get-Item $targetJar).IsReadOnly = $false } catch { }

    $newHash = Get-Sha256 $jarPath
    if ((Test-Path $targetJar) -and (Get-Sha256 $targetJar) -eq $newHash) {
        Report 100 '已是最新版本'
        Log '目标 jar 已经是当前汉化版本，无需重复安装' 'OK'
        return $true
    }

    Report 35 '备份原版 jar…'
    if (-not (Test-Path $backupJar)) {
        Copy-Item $targetJar $backupJar -Force
        Log "已备份原版：lib\$($script:BackupName)" 'OK'
    } else {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Copy-Item $targetJar (Join-Path $dir "lib\charles.jar.bak-$stamp") -Force
        Log "已保留历史备份：lib\charles.jar.bak-$stamp" 'OK'
    }

    Report 60 '写入汉化文件…'
    $ok = $false
    for ($i = 1; $i -le 3; $i++) {
        try { Copy-Item $jarPath $targetJar -Force; $ok = $true; break }
        catch {
            Log ("写入失败（第 {0} 次）：{1}" -f $i, $_.Exception.Message) 'WARN'
            Start-Sleep -Seconds 1
        }
    }
    if (-not $ok) { Log '写入 lib\charles.jar 失败，可能仍被占用或权限不足' 'ERR'; return $false }

    Report 85 '校验文件完整性…'
    $gotHash = Get-Sha256 $targetJar
    if ($gotHash -ne $newHash) {
        Log "哈希校验失败！期望 $newHash 实际 $gotHash" 'ERR'
        return $false
    }
    Report 100 '安装完成'
    Log "安装完成，SHA256 = $($gotHash.Substring(0,16))…" 'OK'
    return $true
}

function New-PortableCopy([string]$srcDir, [string]$jarPath) {
    $dst = Join-Path $env:LOCALAPPDATA 'Programs\Charles-CN'
    Report 10 "创建便携副本：$dst"
    Log "正在创建便携副本：$dst" 'INFO'
    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
    & robocopy $srcDir $dst /E /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { Log "复制失败（robocopy 退出码 $LASTEXITCODE）" 'ERR'; return $null }

    Report 55 '配置便携数据目录…'
    $ini = Join-Path $dst 'Charles.ini'
    if (Test-Path $ini) {
        $keep = Get-Content $ini | Where-Object { $_ -notmatch '^-Dcharles\.(data|config)=' }
        $idx = 0
        foreach ($l in $keep) { if ($l -match '^vmarg\.(\d+)=') { $n = [int]$Matches[1]; if ($n -gt $idx) { $idx = $n } } }
        $extra = @(
            ("vmarg.{0}=-Dcharles.data=.\data" -f ($idx + 1)),
            ("vmarg.{0}=-Dcharles.config=.\data\charles.config" -f ($idx + 2))
        )
        Set-Content -Path $ini -Value ($keep + $extra) -Encoding ASCII
        Log '已配置便携数据目录（.\data）' 'OK'
    }
    New-Item -ItemType Directory -Path (Join-Path $dst 'data') -Force | Out-Null

    if (-not (Install-Patch $dst $jarPath)) { return $null }
    return $dst
}

function Find-RestoreTargets {
    $found = New-Object System.Collections.Generic.List[object]
    $roots = @("$env:ProgramFiles\Charles", "${env:ProgramFiles(x86)}\Charles",
        "$env:LOCALAPPDATA\Programs\Charles", "$env:LOCALAPPDATA\Programs\Charles-CN",
        "$env:LOCALAPPDATA\Charles", "$env:APPDATA\Charles")
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $roots += @((Join-Path $d.Root 'Charles'), (Join-Path $d.Root 'Charles-CN'))
    }
    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { continue }
        $bk = Join-Path $r 'lib\charles.jar.orig'
        if (Test-Path $bk) {
            try { $full = (Resolve-Path $r).Path } catch { continue }
            if (-not ($found | Where-Object { $_.Path -eq $full })) {
                $found.Add([pscustomobject]@{ Path = $full; Backup = $bk }) | Out-Null
            }
        }
    }
    return $found
}

function Restore-Original([string]$dir, [string]$backup) {
    $target = Join-Path $dir 'lib\charles.jar'
    Report 20 '结束正在运行的 Charles…'
    if (-not (Stop-CharlesProcess)) { Log '无法结束 Charles 进程' 'ERR'; return $false }
    try { (Get-Item $target).IsReadOnly = $false } catch { }
    Report 60 '恢复原版文件…'
    Copy-Item $backup $target -Force
    Report 85 '校验…'
    if ((Get-FileHash $backup -Algorithm SHA256).Hash -ne (Get-FileHash $target -Algorithm SHA256).Hash) {
        Log '还原后哈希不一致' 'ERR'; return $false
    }
    Report 100 '已还原'
    Log "已还原：$target" 'OK'
    return $true
}