#Requires -Version 5.1
<#
  Charles 5.2.2 简体中文语言包 - 自动安装器
  · 自动查找本机 Charles 安装目录（注册表 / 常见路径 / 运行进程 / MSIX 包 / 全盘浅层扫描）
  · 自动结束正在运行的 Charles
  · 自动备份原版 jar，安装后校验哈希
  · 若只找到商店(MSIX)版（目录只读），可自动创建便携副本再打补丁
  · 全程日志：install.log

  用法：
    安装汉化.bat                        图形化一键安装
    powershell -File 安装汉化.ps1 -DryRun          仅扫描并列出找到的 Charles
    powershell -File 安装汉化.ps1 -Target "D:\Charles"   指定目录安装
    powershell -File 安装汉化.ps1 -Portable       没有可写目录时自动创建便携副本
#>
param(
    [string]$Target,
    [switch]$DryRun,
    [switch]$Portable,
    [switch]$NoLaunch,
    [switch]$NoElevate,
    [string]$Jar
)

$ErrorActionPreference = 'Stop'
$script:LogPath = Join-Path $PSScriptRoot 'install.log'
$script:BackupName = 'charles.jar.orig'

function Log([string]$msg, [string]$level = 'INFO') {
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $level, $msg
    switch ($level) {
        'OK'    { Write-Host $msg -ForegroundColor Green }
        'WARN'  { Write-Host $msg -ForegroundColor Yellow }
        'ERR'   { Write-Host $msg -ForegroundColor Red }
        'STEP'  { Write-Host ''; Write-Host "== $msg" -ForegroundColor Cyan }
        default { Write-Host $msg }
    }
    try { Add-Content -Path $script:LogPath -Value $line -Encoding UTF8 } catch { }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Admin {
    if (Test-Admin) { return }
    Log '需要管理员权限（写入 Program Files 或读取商店应用目录），正在请求提权…' 'WARN'
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Target)   { $args += @('-Target', "`"$Target`"") }
    if ($DryRun)   { $args += '-DryRun' }
    if ($Portable) { $args += '-Portable' }
    if ($NoLaunch) { $args += '-NoLaunch' }
    if ($Jar)      { $args += @('-Jar', "`"$Jar`"") }
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $args | Out-Null
    exit
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
    $full = (Resolve-Path $path).Path
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

function Get-CharlesCandidates {
    $list = New-Object System.Collections.Generic.List[object]

    # 1) 卸载注册表
    $regRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in $regRoots) {
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

    # 2) 常见安装位置
    $roots = @(
        "$env:ProgramFiles\Charles",
        "${env:ProgramFiles(x86)}\Charles",
        "$env:LOCALAPPDATA\Programs\Charles",
        "$env:LOCALAPPDATA\Charles",
        "$env:APPDATA\Charles",
        "$env:ProgramData\Charles"
    )
    foreach ($r in $roots) { if (Test-Path $r) { Add-Candidate $list $r '常见安装路径' } }

    # 3) 各盘符根目录下的 Charles / Charles-CN
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($name in @('Charles', 'Charles-CN', 'Charles-CN', 'CharlesProxy')) {
            $p = Join-Path $d.Root $name
            if (Test-Path $p) { Add-Candidate $list $p '磁盘根目录' }
        }
    }

    # 4) 正在运行的进程
    Get-Process -Name 'Charles' -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Path) { Add-Candidate $list (Split-Path $_.Path) '运行中的进程' }
    }

    # 5) MSIX / 商店版
    $appx = Get-AppxPackage -Name 'XK72.Charles' -ErrorAction SilentlyContinue
    if ($appx) {
        $p = Join-Path $appx.InstallLocation 'VFS\ProgramFilesX64\Charles'
        if (Test-Path $p) { Add-Candidate $list $p 'Microsoft Store (MSIX)' }
    }

    # 6) 浅层全盘扫描兜底（深度 3，最多 15 秒）
    $deadline = (Get-Date).AddSeconds(15)
    $scanRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA, 'D:\', 'E:\') |
        Where-Object { $_ -and (Test-Path $_) }
    foreach ($root in $scanRoots) {
        if ((Get-Date) -gt $deadline) { break }
        Get-ChildItem -Path $root -Directory -Filter 'Charles*' -Recurse -Depth 2 -ErrorAction SilentlyContinue |
            ForEach-Object { Add-Candidate $list $_.FullName '目录扫描' }
    }

    return $list
}

function Stop-CharlesProcess {
    $procs = Get-Process -Name 'Charles' -ErrorAction SilentlyContinue
    if (-not $procs) { return $true }

    Log ("检测到 Charles 正在运行（PID: {0}），正在自动退出…" -f (($procs | ForEach-Object { $_.Id }) -join ', ')) 'WARN'
    foreach ($p in $procs) {
        try { $p.CloseMainWindow() | Out-Null } catch { }
    }
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

    if (-not (Test-Writable (Join-Path $dir 'lib'))) {
        Log "目录不可写：$dir" 'ERR'
        return $false
    }

    # 结束占用
    if (-not (Stop-CharlesProcess)) { return $false }

    # 去掉只读属性
    try { (Get-Item $targetJar).IsReadOnly = $false } catch { }

    # 已是最新则跳过
    $newHash = Get-Sha256 $jarPath
    if ((Test-Path $targetJar) -and (Get-Sha256 $targetJar) -eq $newHash) {
        Log '目标 jar 已经是当前汉化版本，无需重复安装' 'OK'
        return $true
    }

    # 备份
    if (-not (Test-Path $backupJar)) {
        Copy-Item $targetJar $backupJar -Force
        Log "已备份原版：lib\$($script:BackupName)" 'OK'
    } else {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $alt = Join-Path $dir ("lib\charles.jar.bak-$stamp")
        Copy-Item $targetJar $alt -Force
        Log "已保留历史备份：lib\charles.jar.bak-$stamp" 'OK'
    }

    # 复制（带重试）
    $ok = $false
    for ($i = 1; $i -le 3; $i++) {
        try {
            Copy-Item $jarPath $targetJar -Force
            $ok = $true
            break
        } catch {
            Log ("写入失败（第 {0} 次）：{1}" -f $i, $_.Exception.Message) 'WARN'
            Start-Sleep -Seconds 1
        }
    }
    if (-not $ok) {
        Log '写入 lib\charles.jar 失败，可能仍被占用或权限不足' 'ERR'
        return $false
    }

    # 校验
    $gotHash = Get-Sha256 $targetJar
    if ($gotHash -ne $newHash) {
        Log "哈希校验失败！期望 $newHash 实际 $gotHash" 'ERR'
        return $false
    }
    Log "安装完成，SHA256 = $($gotHash.Substring(0,16))…" 'OK'
    return $true
}

function New-PortableCopy([string]$srcDir, [string]$jarPath) {
    $dst = Join-Path $env:LOCALAPPDATA 'Programs\Charles-CN'
    Log "正在创建便携副本：$dst" 'STEP'
    if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
    & robocopy $srcDir $dst /E /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) {
        Log "复制失败（robocopy 退出码 $LASTEXITCODE）" 'ERR'
        return $null
    }

    # 便携数据目录
    $ini = Join-Path $dst 'Charles.ini'
    if (Test-Path $ini) {
        $lines = Get-Content $ini
        $keep = $lines | Where-Object { $_ -notmatch '^-Dcharles\.(data|config)=' }
        $idx = 0
        for ($i = 0; $i -lt $keep.Count; $i++) { if ($keep[$i] -match '^vmarg\.(\d+)=') { $n = [int]$Matches[1]; if ($n -gt $idx) { $idx = $n } } }
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

function Show-Candidates($cands) {
    Log '找到以下 Charles 安装：' 'STEP'
    $i = 1
    foreach ($c in $cands) {
        $flag = if ($c.Msix) { '商店版·只读' } elseif ($c.Writable) { '可写' } else { '只读' }
        Write-Host ("  [{0}] {1}" -f $i, $c.Path) -ForegroundColor White
        Write-Host ("      来源: {0}  状态: {1}  已有备份: {2}" -f $c.Source, $flag, $c.HasJar) -ForegroundColor DarkGray
        $i++
    }
}

# ============================== 主流程 ==============================

$banner = @'
  ┌──────────────────────────────────────────────┐
  │   Charles 5.2.2 简体中文语言包 · 自动安装器   │
  └──────────────────────────────────────────────┘
'@
Write-Host $banner -ForegroundColor Cyan

$jarPath = if ($Jar) { $Jar } else { Join-Path $PSScriptRoot 'charles-zh.jar' }
if (-not (Test-Path $jarPath)) {
    Log "找不到汉化包 charles-zh.jar（应与本脚本在同一目录）：$jarPath" 'ERR'
    Read-Host '按回车退出'
    exit 1
}
$jarHash = Get-Sha256 $jarPath
Log ("汉化包：{0}  ({1:N1} MB, SHA256 {2}…)" -f (Split-Path $jarPath -Leaf), ((Get-Item $jarPath).Length / 1MB), $jarHash.Substring(0, 12)) 'INFO'

if (-not $DryRun -and -not $NoElevate) { Ensure-Admin }

# 指定目录时直接安装
if ($Target) {
    if (-not (Test-CharlesDir $Target)) {
        Log "指定目录不是 Charles 安装目录（缺少 lib\charles.jar）：$Target" 'ERR'
        Read-Host '按回车退出'
        exit 1
    }
    Log "目标目录：$Target" 'STEP'
    if ($DryRun) { Log '（DryRun 模式，不做任何修改）' 'WARN'; exit 0 }
    if (Install-Patch (Resolve-Path $Target).Path $jarPath) {
        Log '全部完成' 'OK'
        if (-not $NoLaunch) {
            Start-Process (Join-Path $Target 'Charles.exe')
            Log '已启动 Charles，请确认界面为中文' 'OK'
        }
    }
    Read-Host '按回车退出'
    exit 0
}

# 自动查找
Log '正在扫描本机 Charles 安装…' 'STEP'
$cands = Get-CharlesCandidates

if (-not $cands -or $cands.Count -eq 0) {
    Log '没有找到任何 Charles 安装。' 'ERR'
    Write-Host ''
    Write-Host '  可能原因：未安装 Charles / 安装在非常规位置 / 只有便携版放在其他盘。' -ForegroundColor Yellow
    Write-Host '  你可以：下载并安装官方 5.2.2（https://www.charlesproxy.com/download/），' -ForegroundColor Yellow
    Write-Host '          或把本汉化包放到 Charles 目录后运行：' -ForegroundColor Yellow
    Write-Host '          安装汉化.bat  （或 powershell -File 安装汉化.ps1 -Target "D:\你的Charles目录")' -ForegroundColor Yellow
    Read-Host '按回车退出'
    exit 1
}

Show-Candidates $cands

$writable = @($cands | Where-Object { $_.Writable -and -not $_.Msix })
$readonly = @($cands | Where-Object { -not $_.Writable -or $_.Msix })

$chosen = $null
if ($writable.Count -eq 1) {
    $chosen = $writable[0]
    Log ("自动选择：{0}" -f $chosen.Path) 'OK'
} elseif ($writable.Count -gt 1) {
    Write-Host ''
    Write-Host '检测到多个可写安装，请选择（直接回车 = 1）：' -ForegroundColor White
    for ($i = 0; $i -lt $writable.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $writable[$i].Path) }
    $sel = Read-Host '请输入序号'
    if ([string]::IsNullOrWhiteSpace($sel)) { $sel = '1' }
    $idx = [int]$sel - 1
    if ($idx -lt 0 -or $idx -ge $writable.Count) { $idx = 0 }
    $chosen = $writable[$idx]
} else {
    # 只有只读/商店版
    Log '只找到只读的 Charles（通常是 Microsoft Store / MSIX 版）。' 'WARN'
    Write-Host '  商店版目录受系统保护且带签名校验，不适合直接替换文件。' -ForegroundColor Yellow
    Write-Host '  可以自动创建一个便携副本（复制到 %LOCALAPPDATA%\Programs\Charles-CN 后打补丁）。' -ForegroundColor Yellow
    if (-not $Portable) {
        $ans = Read-Host '是否创建便携副本并安装汉化？(Y/n)'
        if ($ans -and $ans -notmatch '^[Yy]') { Log '已取消' 'WARN'; Read-Host '按回车退出'; exit 0 }
    }
    if ($DryRun) { Log '（DryRun 模式，不做任何修改）' 'WARN'; exit 0 }
    $created = New-PortableCopy $readonly[0].Path $jarPath
    if ($created) {
        Log "便携版已就绪：$created" 'OK'
        if (-not $NoLaunch) { Start-Process (Join-Path $created 'Charles.exe') }
    }
    Read-Host '按回车退出'
    exit 0
}

if ($DryRun) {
    Log '（DryRun 模式，不做任何修改）' 'WARN'
    Log ("将会安装到：{0}" -f $chosen.Path) 'INFO'
    Read-Host '按回车退出'
    exit 0
}

Log ("开始安装到：{0}" -f $chosen.Path) 'STEP'
if (Install-Patch $chosen.Path $jarPath) {
    Log '安装成功！界面应为中文，帮助菜单显示「注册给 Charles CN」' 'OK'
    Write-Host ''
    Write-Host '  提示：双击 Charles 时若需要抓包，请确认系统代理指向 127.0.0.1:8888' -ForegroundColor DarkGray
    Write-Host '        或使用随附的「启动 Charles 汉化版.bat」（自动设置/恢复系统代理）' -ForegroundColor DarkGray
    if (-not $NoLaunch) {
        Start-Process (Join-Path $chosen.Path 'Charles.exe')
        Log '已启动 Charles' 'OK'
    }
} else {
    Log '安装失败，请查看上方错误信息与 install.log' 'ERR'
}
Read-Host '按回车退出'