#Requires -Version 5.1
<#
  Charles 汉化包 - 还原工具
  · 自动查找带有 charles.jar.orig 备份的 Charles 目录
  · 结束正在运行的 Charles，恢复原版 jar 并校验
#>
param(
    [string]$Target,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$script:LogPath = Join-Path $PSScriptRoot 'restore.log'

function Log([string]$msg, [string]$level = 'INFO') {
    switch ($level) {
        'OK'   { Write-Host $msg -ForegroundColor Green }
        'WARN' { Write-Host $msg -ForegroundColor Yellow }
        'ERR'  { Write-Host $msg -ForegroundColor Red }
        'STEP' { Write-Host ''; Write-Host "== $msg" -ForegroundColor Cyan }
        default { Write-Host $msg }
    }
    try { Add-Content -Path $script:LogPath -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg) -Encoding UTF8 } catch { }
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Ensure-Admin {
    if (Test-Admin) { return }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Target) { $a += @('-Target', "`"$Target`"") }
    if ($DryRun) { $a += '-DryRun' }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $a | Out-Null
    exit
}

function Stop-CharlesProcess {
    $procs = Get-Process -Name 'Charles' -ErrorAction SilentlyContinue
    if (-not $procs) { return $true }
    Log 'Charles 正在运行，正在退出…' 'WARN'
    foreach ($p in $procs) { try { $p.CloseMainWindow() | Out-Null } catch { } }
    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 500
        if (-not (Get-Process -Name 'Charles' -ErrorAction SilentlyContinue)) { return $true }
    }
    Get-Process -Name 'Charles' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    return (-not (Get-Process -Name 'Charles' -ErrorAction SilentlyContinue))
}

function Find-Backups {
    $found = New-Object System.Collections.Generic.List[object]
    $roots = @("$env:ProgramFiles\Charles", "${env:ProgramFiles(x86)}\Charles",
               "$env:LOCALAPPDATA\Programs\Charles", "$env:LOCALAPPDATA\Programs\Charles-CN",
               "$env:LOCALAPPDATA\Charles", "$env:APPDATA\Charles")
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $roots += @((Join-Path $d.Root 'Charles'), (Join-Path $d.Root 'Charles-CN'))
    }
    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { continue }
        $backup = Join-Path $r 'lib\charles.jar.orig'
        if (Test-Path $backup) {
            if (-not ($found | Where-Object { $_.Path -eq $r })) {
                $found.Add([pscustomobject]@{ Path = (Resolve-Path $r).Path; Backup = $backup }) | Out-Null
            }
        }
    }
    return $found
}

function Restore-One([string]$dir, [string]$backup) {
    $target = Join-Path $dir 'lib\charles.jar'
    if (-not (Stop-CharlesProcess)) { Log '无法结束 Charles 进程' 'ERR'; return $false }
    try { (Get-Item $target).IsReadOnly = $false } catch { }
    Copy-Item $backup $target -Force
    $a = (Get-FileHash $backup -Algorithm SHA256).Hash
    $b = (Get-FileHash $target -Algorithm SHA256).Hash
    if ($a -ne $b) { Log '还原后哈希不一致' 'ERR'; return $false }
    Log "已还原：$target" 'OK'
    return $true
}

Write-Host '  Charles 汉化包 · 还原原版' -ForegroundColor Cyan
Write-Host ''

if ($Target) {
    $bk = Join-Path $Target 'lib\charles.jar.orig'
    if (-not (Test-Path $bk)) { Log "没有备份文件：$bk" 'ERR'; Read-Host '按回车退出'; exit 1 }
    if ($DryRun) { Log "（DryRun）将用 $bk 还原" 'WARN'; Read-Host '按回车退出'; exit 0 }
    Ensure-Admin
    if (Restore-One (Resolve-Path $Target).Path $bk) { Log '还原完成' 'OK' }
    Read-Host '按回车退出'
    exit 0
}

$list = Find-Backups
if (-not $list -or $list.Count -eq 0) {
    Log '没有找到任何带 charles.jar.orig 备份的 Charles 目录' 'ERR'
    Log '（如果从未安装过汉化补丁，不需要还原）' 'WARN'
    Read-Host '按回车退出'
    exit 1
}

Write-Host '找到以下可还原的安装：' -ForegroundColor White
for ($i = 0; $i -lt $list.Count; $i++) { Write-Host ("  {0}) {1}" -f ($i + 1), $list[$i].Path) }
$sel = Read-Host '请选择序号（直接回车 = 1）'
if ([string]::IsNullOrWhiteSpace($sel)) { $sel = '1' }
$idx = [int]$sel - 1
if ($idx -lt 0 -or $idx -ge $list.Count) { $idx = 0 }

if ($DryRun) { Log "（DryRun）将还原：$($list[$idx].Path)" 'WARN'; Read-Host '按回车退出'; exit 0 }
Ensure-Admin
if (Restore-One $list[$idx].Path $list[$idx].Backup) {
    Log '还原完成，重新启动 Charles 即为原版' 'OK'
} else {
    Log '还原失败，请查看 restore.log' 'ERR'
}
Read-Host '按回车退出'