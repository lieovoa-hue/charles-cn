#Requires -Version 5.1
<#
  Charles 汉化版 - 卸载 / 清理工具
  · 三种模式：仅还原汉化（保留 Charles）/ 卸载便携版并删除目录 / 卸载商店(MSIX)版
  · 可选清理：系统代理、桌面快捷方式、Charles 根证书、配置数据
#>
param(
    [switch]$NoElevate,
    [string]$Target,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'core.ps1')

$script:UninstallLog = Join-Path $PSScriptRoot 'uninstall.log'
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

function ULog([string]$msg, [string]$level = 'INFO') {
    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $level, $msg
    try { Add-Content -Path $script:UninstallLog -Value $line -Encoding UTF8 } catch { }
    if ($script:LogSink) { try { & $script:LogSink $line $level } catch { } } else { Write-Host $msg }
}

function Get-Targets {
    $list = New-Object System.Collections.Generic.List[object]
    $cands = Get-CharlesCandidates
    foreach ($c in $cands) {
        $kind = if ($c.Msix) { '商店版 (MSIX)' }
                elseif ($c.Path -like '*\AppData\*') { '便携版（用户目录）' }
                else { '便携版 / 安装版' }
        $size = 0
        try { $size = (Get-ChildItem $c.Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } catch { }
        $list.Add([pscustomobject]@{
            Path = $c.Path; Kind = $kind; Msix = $c.Msix
            HasBackup = $c.HasJar; Writable = $c.Writable
            SizeMB = [math]::Round($size / 1MB, 1)
            Rank = if ($c.Msix) { 9 } elseif ($c.Path -like '*\AppData\*') { 5 } else { 1 }
        }) | Out-Null
    }
    # 商店版单独补充（Get-CharlesCandidates 已含，但排除无效路径）
    return @($list | Sort-Object Rank, Path)
}

function Clear-SystemProxy {
    $p = Get-ItemProperty $key -ErrorAction SilentlyContinue
    if ($p.ProxyEnable -eq 1 -and $p.ProxyServer -match '127\.0\.0\.1:8888') {
        Set-ItemProperty $key -Name ProxyEnable -Value 0
        & rundll32.exe user32.dll,UpdatePerUserSystemParameters 2>&1 | Out-Null
        ULog '已关闭系统代理（原先指向 Charles 8888）' 'OK'
        return $true
    }
    ULog '系统代理未指向 Charles，无需处理'
    return $false
}

function Remove-Shortcuts([string]$dir) {
    $removed = 0
    $shell = New-Object -ComObject WScript.Shell
    $places = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'),
                (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))
    foreach ($place in $places) {
        if (-not (Test-Path $place)) { continue }
        Get-ChildItem $place -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $sc = $shell.CreateShortcut($_.FullName)
                if ($sc.TargetPath -and $sc.TargetPath.StartsWith($dir, 'OrdinalIgnoreCase')) {
                    Remove-Item $_.FullName -Force
                    $removed++
                }
            } catch { }
        }
    }
    if ($removed) { ULog ("已删除 {0} 个快捷方式" -f $removed) 'OK' } else { ULog '没有需要删除的快捷方式' }
}

function Remove-CharlesCertificate {
    $certs = @()
    foreach ($store in @('Cert:\CurrentUser\Root', 'Cert:\LocalMachine\Root')) {
        try {
            $certs += Get-ChildItem $store -ErrorAction SilentlyContinue |
                Where-Object { $_.Subject -match 'Charles' -and $_.Subject -match 'Proxy' }
        } catch { }
    }
    if (-not $certs) { ULog '没有找到 Charles 根证书'; return }
    foreach ($c in $certs) {
        try {
            Remove-Item -Path $c.PSPath -Force -ErrorAction Stop
            ULog ("已移除根证书：{0}" -f $c.Subject) 'OK'
        } catch {
            ULog ("移除根证书失败（可能需要管理员）：{0}" -f $c.Subject) 'WARN'
        }
    }
}

function Remove-CharlesData([string]$dir) {
    $dataDirs = @()
    $local = Join-Path $dir 'data'
    if (Test-Path $local) { $dataDirs += $local }
    if (Test-Path "$env:APPDATA\Charles") { $dataDirs += "$env:APPDATA\Charles" }
    if (Test-Path "$env:LOCALAPPDATA\Charles") { $dataDirs += "$env:LOCALAPPDATA\Charles" }
    $appx = Get-AppxPackage -Name 'XK72.Charles' -ErrorAction SilentlyContinue
    if ($appx) {
        $p = Join-Path $env:LOCALAPPDATA ("Packages\{0}\RoamingState" -f $appx.PackageFamilyName)
        if (Test-Path $p) { $dataDirs += $p }
    }
    foreach ($d in $dataDirs) {
        try {
            Remove-Item $d -Recurse -Force -ErrorAction Stop
            ULog "已删除数据目录：$d" 'OK'
        } catch { ULog "删除数据目录失败：$d（可能被占用）" 'WARN' }
    }
    if (-not $dataDirs) { ULog '没有找到需要清理的数据目录' }
}

function Remove-Directory([string]$dir) {
    if (-not (Stop-CharlesProcess)) { ULog '无法结束 Charles 进程' 'ERR'; return $false }
    for ($i = 1; $i -le 3; $i++) {
        try {
            Remove-Item $dir -Recurse -Force -ErrorAction Stop
            ULog "已删除目录：$dir" 'OK'
            return $true
        } catch {
            ULog ("删除失败（第 {0} 次）：{1}" -f $i, $_.Exception.Message) 'WARN'
            Start-Sleep -Seconds 2
        }
    }
    # 兜底：清空目录内容再删
    try {
        Get-ChildItem $dir -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $dir -Force -ErrorAction Stop
        ULog "已删除目录（清理模式）：$dir" 'OK'
        return $true
    } catch {
        ULog '目录仍无法删除，可能被占用或权限不足' 'ERR'
        return $false
    }
}

function Uninstall-Appx {
    $pkg = Get-AppxPackage -Name 'XK72.Charles' -ErrorAction SilentlyContinue
    if (-not $pkg) { ULog '没有找到已安装的商店版 Charles' 'WARN'; return $false }
    if (-not (Stop-CharlesProcess)) { return $false }
    try {
        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
        ULog ("已卸载商店版 Charles：{0}" -f $pkg.PackageFullName) 'OK'
        return $true
    } catch {
        ULog ("卸载商店版失败：{0}" -f $_.Exception.Message) 'ERR'
        return $false
    }
}

# ================== 界面 ==================
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Charles 汉化版 · 卸载 / 清理'
$form.Size = New-Object System.Drawing.Size(820, 700)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = '卸载 / 清理 Charles'
$lblTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 15, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(20, 12)
$lblTitle.Size = New-Object System.Drawing.Size(400, 34)
$form.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = '选择要处理的目标，按需勾选清理项。删除后无法恢复（原版备份会一并删除）。'
$lblSub.ForeColor = [System.Drawing.Color]::DimGray
$lblSub.Location = New-Object System.Drawing.Point(22, 48)
$lblSub.Size = New-Object System.Drawing.Size(760, 20)
$form.Controls.Add($lblSub)

$lv = New-Object System.Windows.Forms.ListView
$lv.Location = New-Object System.Drawing.Point(20, 76)
$lv.Size = New-Object System.Drawing.Size(765, 150)
$lv.View = 'Details'
$lv.FullRowSelect = $true
$lv.MultiSelect = $false
[void]$lv.Columns.Add('路径', 430)
[void]$lv.Columns.Add('类型', 160)
[void]$lv.Columns.Add('大小', 90)
[void]$lv.Columns.Add('原版备份', 80)
$form.Controls.Add($lv)

$grpMode = New-Object System.Windows.Forms.GroupBox
$grpMode.Text = '操作'
$grpMode.Location = New-Object System.Drawing.Point(20, 236)
$grpMode.Size = New-Object System.Drawing.Size(765, 96)
$form.Controls.Add($grpMode)

$rbRestore = New-Object System.Windows.Forms.RadioButton
$rbRestore.Text = '仅还原汉化（保留 Charles 程序，回到官方原版）'
$rbRestore.Location = New-Object System.Drawing.Point(14, 20)
$rbRestore.Size = New-Object System.Drawing.Size(430, 22)
$rbRestore.Checked = $true
$grpMode.Controls.Add($rbRestore)

$rbDelete = New-Object System.Windows.Forms.RadioButton
$rbDelete.Text = '彻底卸载：删除该 Charles 目录（便携版会连同程序一起删除）'
$rbDelete.Location = New-Object System.Drawing.Point(14, 46)
$rbDelete.Size = New-Object System.Drawing.Size(500, 22)
$grpMode.Controls.Add($rbDelete)

$rbAppx = New-Object System.Windows.Forms.RadioButton
$rbAppx.Text = '卸载 Microsoft Store 商店版（从系统移除该应用）'
$rbAppx.Location = New-Object System.Drawing.Point(14, 70)
$rbAppx.Size = New-Object System.Drawing.Size(430, 22)
$grpMode.Controls.Add($rbAppx)

$grpOpt = New-Object System.Windows.Forms.GroupBox
$grpOpt.Text = '同时清理（仅“彻底卸载”时生效）'
$grpOpt.Location = New-Object System.Drawing.Point(20, 340)
$grpOpt.Size = New-Object System.Drawing.Size(765, 86)
$form.Controls.Add($grpOpt)

$chkProxy = New-Object System.Windows.Forms.CheckBox
$chkProxy.Text = '恢复系统代理（关闭指向 127.0.0.1:8888 的代理）'
$chkProxy.Location = New-Object System.Drawing.Point(14, 20)
$chkProxy.Size = New-Object System.Drawing.Size(360, 22)
$chkProxy.Checked = $true
$grpOpt.Controls.Add($chkProxy)

$chkLnk = New-Object System.Windows.Forms.CheckBox
$chkLnk.Text = '删除桌面/开始菜单快捷方式'
$chkLnk.Location = New-Object System.Drawing.Point(390, 20)
$chkLnk.Size = New-Object System.Drawing.Size(250, 22)
$chkLnk.Checked = $true
$grpOpt.Controls.Add($chkLnk)

$chkCert = New-Object System.Windows.Forms.CheckBox
$chkCert.Text = '移除 Charles 根证书（受信任根）'
$chkCert.Location = New-Object System.Drawing.Point(14, 48)
$chkCert.Size = New-Object System.Drawing.Size(360, 22)
$grpOpt.Controls.Add($chkCert)

$chkData = New-Object System.Windows.Forms.CheckBox
$chkData.Text = '删除配置与证书数据目录'
$chkData.Location = New-Object System.Drawing.Point(390, 48)
$chkData.Size = New-Object System.Drawing.Size(250, 22)
$chkData.Checked = $true
$grpOpt.Controls.Add($chkData)

$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Text = '刷新列表'
$btnRefresh.Location = New-Object System.Drawing.Point(20, 436)
$btnRefresh.Size = New-Object System.Drawing.Size(96, 30)
$form.Controls.Add($btnRefresh)

$chkElevate = New-Object System.Windows.Forms.CheckBox
$chkElevate.Text = '需要时自动请求管理员权限'
$chkElevate.Location = New-Object System.Drawing.Point(130, 441)
$chkElevate.Size = New-Object System.Drawing.Size(240, 22)
$chkElevate.Checked = $true
$form.Controls.Add($chkElevate)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = '执行'
$btnRun.Location = New-Object System.Drawing.Point(620, 432)
$btnRun.Size = New-Object System.Drawing.Size(165, 38)
$btnRun.BackColor = [System.Drawing.Color]::FromArgb(160, 60, 60)
$btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.FlatStyle = 'Flat'
$btnRun.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnRun)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(20, 480)
$txtLog.Size = New-Object System.Drawing.Size(765, 140)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$txtLog.BackColor = [System.Drawing.Color]::WhiteSmoke
$form.Controls.Add($txtLog)

$lblFoot = New-Object System.Windows.Forms.Label
$lblFoot.Text = '提示：商店版卸载后可从 Microsoft Store 重新安装；便携版删除后需重新获取官方安装包。'
$lblFoot.ForeColor = [System.Drawing.Color]::Gray
$lblFoot.Location = New-Object System.Drawing.Point(20, 626)
$lblFoot.Size = New-Object System.Drawing.Size(765, 20)
$form.Controls.Add($lblFoot)

$script:LogSink = {
    param($line, $level)
    $txtLog.AppendText($line + "`r`n")
    $txtLog.SelectionStart = $txtLog.Text.Length
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Busy([bool]$busy) {
    foreach ($c in @($btnRefresh, $btnRun)) { $c.Enabled = -not $busy }
    $form.Cursor = if ($busy) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Default }
    [System.Windows.Forms.Application]::DoEvents()
}

$script:targets = @()

function Show-Targets {
    $lv.Items.Clear()
    foreach ($t in $script:targets) {
        $item = New-Object System.Windows.Forms.ListViewItem($t.Path)
        [void]$item.SubItems.Add($t.Kind)
        [void]$item.SubItems.Add(("{0} MB" -f $t.SizeMB))
        [void]$item.SubItems.Add($(if ($t.HasBackup) { '有' } else { '无' }))
        $item.Tag = $t
        [void]$lv.Items.Add($item)
    }
    if ($lv.Items.Count -gt 0) { $lv.Items[0].Selected = $true; $lv.Select() }
}

function Refresh-Targets {
    Set-Busy $true
    $lblSub.Text = '正在扫描（便携版需要目录扫描，约 10 秒）…'
    [System.Windows.Forms.Application]::DoEvents()
    try { $script:targets = Get-Targets } catch { ULog ("扫描失败：{0}" -f $_.Exception.Message) 'ERR' }
    Show-Targets
    $lblSub.Text = ("找到 {0} 个目标。选择后点「执行」。" -f $script:targets.Count)
    Set-Busy $false
}

$btnRefresh.Add_Click({ Refresh-Targets })

$btnRun.Add_Click({
    $item = $lv.SelectedItems | Select-Object -First 1
    if (-not $item) {
        [System.Windows.Forms.MessageBox]::Show('请先在列表中选择一个目标。', '未选择', 'OK', 'Information') | Out-Null
        return
    }
    $t = $item.Tag

    if ($rbAppx.Checked) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "将从系统卸载 Microsoft Store 版 Charles：`r`n$($t.Path)`r`n`r`n继续？", '确认卸载', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { return }
        Set-Busy $true
        $ok = Uninstall-Appx
        Set-Busy $false
        if ($ok) { [System.Windows.Forms.MessageBox]::Show('已卸载商店版。', '完成', 'OK', 'Information') | Out-Null }
        Refresh-Targets
        return
    }

    if ($rbRestore.Checked) {
        $bk = Join-Path $t.Path 'lib\charles.jar.orig'
        if (-not (Test-Path $bk)) {
            [System.Windows.Forms.MessageBox]::Show('该目录没有 charles.jar.orig 备份，无法还原（可能从未安装汉化）。', '无备份', 'OK', 'Warning') | Out-Null
            return
        }
        $r = [System.Windows.Forms.MessageBox]::Show("将用备份还原：`r`n$($t.Path)`r`n`r`n继续？", '还原原版', 'YesNo', 'Question')
        if ($r -ne 'Yes') { return }
        Set-Busy $true
        $ok = Restore-Original $t.Path $bk
        Set-Busy $false
        if ($ok) { [System.Windows.Forms.MessageBox]::Show('已还原为官方原版。', '完成', 'OK', 'Information') | Out-Null }
        Refresh-Targets
        return
    }

    # 彻底卸载
    $r = [System.Windows.Forms.MessageBox]::Show(
        "将彻底删除：`r`n$($t.Path)`r`n（{0} MB）`r`n`r`n此操作不可撤销，继续？" -f $t.SizeMB,
        '确认彻底卸载', 'YesNo', 'Warning')
    if ($r -ne 'Yes') { return }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "再确认一次：删除后该 Charles 及其汉化、备份、快捷方式都将消失。`r`n`r`n真的继续吗？",
        '二次确认', 'YesNo', 'Warning')
    if ($confirm -ne 'Yes') { return }

    if (-not (Test-Admin) -and $chkElevate.Checked) {
        $e = [System.Windows.Forms.MessageBox]::Show(
            '删除系统目录需要管理员权限，是否以管理员身份重新打开卸载工具？', '需要权限', 'YesNo', 'Warning')
        if ($e -eq 'Yes') {
            Start-Process powershell.exe -Verb RunAs -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") | Out-Null
            $form.Close()
        }
        return
    }

    Set-Busy $true
    ULog ("开始卸载：{0}" -f $t.Path) 'INFO'
    if ($chkProxy.Checked) { Clear-SystemProxy | Out-Null }
    if ($chkLnk.Checked) { Remove-Shortcuts $t.Path }
    if ($chkCert.Checked) { Remove-CharlesCertificate }
    if ($chkData.Checked) { Remove-CharlesData $t.Path }
    $ok = Remove-Directory $t.Path
    Set-Busy $false
    if ($ok) {
        [System.Windows.Forms.MessageBox]::Show("已删除：`r`n$($t.Path)", '完成', 'OK', 'Information') | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "删除未完全成功，可能仍被占用。`r`n`r`n建议：重启电脑后再执行一次，或手动删除该目录。", '未完成', 'OK', 'Warning') | Out-Null
    }
    Refresh-Targets
})

# ---------------- 命令行模式 ----------------
if ($Target) {
    if (-not (Test-CharlesDir $Target)) {
        ULog "不是 Charles 目录（缺少 lib\charles.jar）：$Target" 'ERR'
        exit 1
    }
    ULog ("目标：{0}" -f $Target) 'INFO'
    if ($DryRun) {
        ULog '（DryRun）将执行：恢复系统代理 → 删除快捷方式 → 移除根证书 → 删除数据目录 → 删除程序目录' 'WARN'
        exit 0
    }
    if ($chkProxy.Checked) { Clear-SystemProxy | Out-Null }
    if ($chkLnk.Checked) { Remove-Shortcuts $Target }
    if ($chkCert.Checked) { Remove-CharlesCertificate }
    if ($chkData.Checked) { Remove-CharlesData $Target }
    $ok = Remove-Directory $Target
    if ($ok) { ULog '卸载完成' 'OK'; exit 0 } else { ULog '卸载未完成' 'ERR'; exit 1 }
}

$form.Add_Shown({ Refresh-Targets })
[void]$form.ShowDialog()