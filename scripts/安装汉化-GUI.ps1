#Requires -Version 5.1
<#
  Charles 5.2.2 简体中文语言包 - 图形界面安装器
  双击「安装汉化.bat」即进入本界面。
#>
param(
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
. (Join-Path $PSScriptRoot 'core.ps1')

$jarPath = Join-Path $PSScriptRoot 'charles-zh.jar'
if (-not (Test-Path $jarPath)) {
    [System.Windows.Forms.MessageBox]::Show("找不到 charles-zh.jar，请确保它和本程序在同一目录。", '缺少文件', 'OK', 'Error') | Out-Null
    exit 1
}

# ---------------- 界面 ----------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Charles 5.2.2 简体中文语言包 · 安装器'
$form.Size = New-Object System.Drawing.Size(800, 660)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'Charles 5.2.2 简体中文语言包'
$lblTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 15, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(20, 14)
$lblTitle.Size = New-Object System.Drawing.Size(560, 34)
$form.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = '自动查找 Charles 安装目录，结束运行中的进程，备份原版后写入汉化文件。'
$lblSub.ForeColor = [System.Drawing.Color]::DimGray
$lblSub.Location = New-Object System.Drawing.Point(22, 50)
$lblSub.Size = New-Object System.Drawing.Size(740, 20)
$form.Controls.Add($lblSub)

$lv = New-Object System.Windows.Forms.ListView
$lv.Location = New-Object System.Drawing.Point(20, 78)
$lv.Size = New-Object System.Drawing.Size(745, 190)
$lv.View = 'Details'
$lv.FullRowSelect = $true
$lv.MultiSelect = $false
$lv.HideSelection = $false
$lv.GridLines = $false
[void]$lv.Columns.Add('安装目录', 420)
[void]$lv.Columns.Add('来源', 190)
[void]$lv.Columns.Add('状态', 120)
$form.Controls.Add($lv)

$btnRescan = New-Object System.Windows.Forms.Button
$btnRescan.Text = '重新扫描'
$btnRescan.Location = New-Object System.Drawing.Point(20, 280)
$btnRescan.Size = New-Object System.Drawing.Size(96, 30)
$form.Controls.Add($btnRescan)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = '手动选择…'
$btnBrowse.Location = New-Object System.Drawing.Point(124, 280)
$btnBrowse.Size = New-Object System.Drawing.Size(96, 30)
$form.Controls.Add($btnBrowse)

$chkLaunch = New-Object System.Windows.Forms.CheckBox
$chkLaunch.Text = '安装后启动 Charles'
$chkLaunch.Checked = $true
$chkLaunch.Location = New-Object System.Drawing.Point(236, 285)
$chkLaunch.Size = New-Object System.Drawing.Size(180, 22)
$form.Controls.Add($chkLaunch)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text = '开始安装'
$btnInstall.Location = New-Object System.Drawing.Point(600, 274)
$btnInstall.Size = New-Object System.Drawing.Size(165, 38)
$btnInstall.BackColor = [System.Drawing.Color]::FromArgb(46, 139, 87)
$btnInstall.ForeColor = [System.Drawing.Color]::White
$btnInstall.FlatStyle = 'Flat'
$btnInstall.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnInstall)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Location = New-Object System.Drawing.Point(20, 324)
$bar.Size = New-Object System.Drawing.Size(745, 16)
$bar.Minimum = 0; $bar.Maximum = 100
$form.Controls.Add($bar)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = '就绪'
$lblStatus.Location = New-Object System.Drawing.Point(20, 344)
$lblStatus.Size = New-Object System.Drawing.Size(745, 20)
$lblStatus.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblStatus)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location = New-Object System.Drawing.Point(20, 368)
$txtLog.Size = New-Object System.Drawing.Size(745, 200)
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$txtLog.BackColor = [System.Drawing.Color]::WhiteSmoke
$form.Controls.Add($txtLog)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = '还原原版'
$btnRestore.Location = New-Object System.Drawing.Point(20, 578)
$btnRestore.Size = New-Object System.Drawing.Size(96, 30)
$form.Controls.Add($btnRestore)

$btnOpenLog = New-Object System.Windows.Forms.Button
$btnOpenLog.Text = '打开日志'
$btnOpenLog.Location = New-Object System.Drawing.Point(124, 578)
$btnOpenLog.Size = New-Object System.Drawing.Size(96, 30)
$form.Controls.Add($btnOpenLog)

$lblFoot = New-Object System.Windows.Forms.Label
$lblFoot.Text = '适配 Charles 5.2.2 · 写入系统目录需要管理员权限'
$lblFoot.ForeColor = [System.Drawing.Color]::Gray
$lblFoot.Location = New-Object System.Drawing.Point(236, 584)
$lblFoot.Size = New-Object System.Drawing.Size(530, 20)
$form.Controls.Add($lblFoot)

# ---------------- 日志 / 进度挂接 ----------------
$script:LogSink = {
    param($line, $level)
    $txtLog.AppendText($line + "`r`n")
    $txtLog.SelectionStart = $txtLog.Text.Length
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}
$script:ProgressSink = {
    param($percent, $text)
    $bar.Value = [Math]::Min(100, [Math]::Max(0, $percent))
    if ($text) { $lblStatus.Text = $text }
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Busy([bool]$busy) {
    foreach ($c in @($btnRescan, $btnBrowse, $btnInstall, $btnRestore)) { $c.Enabled = -not $busy }
    $form.Cursor = if ($busy) { [System.Windows.Forms.Cursors]::WaitCursor } else { [System.Windows.Forms.Cursors]::Default }
    [System.Windows.Forms.Application]::DoEvents()
}

$script:cands = @()

function Get-CandidateRank($c) {
    $p = $c.Path.ToLower()
    if ($c.Msix -or -not $c.Writable) { return 90 }
    if ($p -like '*\program files\charles*') { return 0 }
    if ($p -like '*\program files (x86)\charles*') { return 1 }
    if ($p -like '*\appdata\local\programs\charles-cn*') { return 40 }   # 安装器生成的便携副本
    if ($p -like '*\appdata\*') { return 50 }
    return 10                                                                 # 其它磁盘/自定义便携版
}

function Show-Candidates {
    $lv.Items.Clear()
    $script:cands = @($script:cands | Sort-Object { Get-CandidateRank $_ }, { $_.Path })
    foreach ($c in $script:cands) {
        $state = if ($c.Msix) { '商店版·只读' } elseif ($c.Writable) { '可写' } else { '只读' }
        if ($c.HasJar) { $state += ' · 有备份' }
        $item = New-Object System.Windows.Forms.ListViewItem($c.Path)
        [void]$item.SubItems.Add($c.Source)
        [void]$item.SubItems.Add($state)
        $item.Tag = $c
        if ($c.Writable -and -not $c.Msix) { $item.ForeColor = [System.Drawing.Color]::FromArgb(0, 100, 0) }
        else { $item.ForeColor = [System.Drawing.Color]::FromArgb(150, 80, 0) }
        [void]$lv.Items.Add($item)
    }
    $first = $lv.Items | Where-Object { $_.Tag.Writable -and -not $_.Tag.Msix } |
        Sort-Object { Get-CandidateRank $_.Tag } | Select-Object -First 1
    if (-not $first) { $first = $lv.Items | Select-Object -First 1 }
    if ($first) {
        foreach ($it in $lv.Items) { $it.Selected = $false }
        $first.Selected = $true
        $first.Focused = $true
        $lv.EnsureVisible($first.Index)
        $lv.Select()
    }
}

function Invoke-Scan {
    Set-Busy $true
    $lv.Items.Clear()
    $lblStatus.Text = '正在扫描…'
    $txtLog.AppendText("`r`n")
    try {
        $script:cands = Get-CharlesCandidates -OnProgress {
            param($m)
            $lblStatus.Text = $m
            [System.Windows.Forms.Application]::DoEvents()
        }
    } catch {
        Log ("扫描出错：{0}" -f $_.Exception.Message) 'ERR'
    }
    Show-Candidates
    $lblStatus.Text = ("扫描完成，找到 {0} 个安装" -f $script:cands.Count)
    if ($script:cands.Count -eq 0) {
        $lblStatus.Text = '没有找到 Charles，请点「手动选择…」或先安装官方 5.2.2'
    }
    Set-Busy $false
}

# ---------------- 事件 ----------------
$btnRescan.Add_Click({ Invoke-Scan })

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = '请选择 Charles 安装目录（该目录下应有 lib\charles.jar）'
    if ($dlg.ShowDialog() -eq 'OK') {
        if (-not (Test-CharlesDir $dlg.SelectedPath)) {
            [System.Windows.Forms.MessageBox]::Show("这个目录里没有 lib\charles.jar，不是 Charles 安装目录。", '目录无效', 'OK', 'Warning') | Out-Null
            return
        }
        $full = (Resolve-Path $dlg.SelectedPath).Path
        $c = [pscustomobject]@{
            Path = $full; Source = '手动选择'
            Writable = (Test-Writable $full)
            Msix = ($full -like '*\WindowsApps\*')
            HasJar = (Test-Path (Join-Path $full 'lib\charles.jar.orig'))
        }
        $script:cands = @($c) + @($script:cands)
        Show-Candidates
        $lv.Items[0].Selected = $true
        $lblStatus.Text = "已选择：$full"
    }
})

$btnInstall.Add_Click({
    $item = $lv.SelectedItems | Select-Object -First 1
    if (-not $item) {
        [System.Windows.Forms.MessageBox]::Show('请先在列表中选择一个 Charles 安装目录。', '未选择', 'OK', 'Information') | Out-Null
        return
    }
    $c = $item.Tag

    # 若选中的是只读项（商店版），但列表里存在可写安装，自动切换到可写项
    if ($c.Msix -or -not $c.Writable) {
        $w = $lv.Items | Where-Object { $_.Tag.Writable -and -not $_.Tag.Msix } |
            Sort-Object { Get-CandidateRank $_.Tag } | Select-Object -First 1
        if ($w) {
            $c = $w.Tag
            foreach ($it in $lv.Items) { $it.Selected = $false }
            $w.Selected = $true
            $w.Focused = $true
            $lv.Select()
            Log ("已自动切换到可写的安装：{0}" -f $c.Path) 'INFO'
        }
    }

    if (-not (Test-Admin) -and -not $NoElevate) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "写入 $($c.Path) 需要管理员权限。`r`n`r`n是否以管理员身份重新打开安装器？",
            '需要管理员权限', 'YesNo', 'Warning')
        if ($r -eq 'Yes') {
            Start-Process powershell.exe -Verb RunAs -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") | Out-Null
            $form.Close()
        }
        return
    }

    Set-Busy $true
    $bar.Value = 0
    $ok = $false
    $installedTo = $c.Path

    if ($c.Msix -or -not $c.Writable) {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "检测到这是只读的 Charles（通常是 Microsoft Store 版）：`r`n$($c.Path)`r`n`r`n" +
            "商店版目录受系统保护，无法直接替换文件。`r`n" +
            "是否把它复制成便携版（%LOCALAPPDATA%\Programs\Charles-CN）后再安装汉化？",
            '商店版 / 只读目录', 'YesNo', 'Question')
        if ($r -ne 'Yes') { Set-Busy $false; return }
        $created = New-PortableCopy $c.Path $jarPath
        if ($created) { $ok = $true; $installedTo = $created }
    } else {
        $ok = Install-Patch $c.Path $jarPath
    }

    Set-Busy $false
    if ($ok) {
        $lblStatus.Text = "安装完成：$installedTo"
        $msg = "安装完成！`r`n`r`n$installedTo`r`n`r`n界面应为中文，帮助菜单显示「注册给 Charles CN」。"
        if ($chkLaunch.Checked) {
            $exe = Join-Path $installedTo 'Charles.exe'
            if (Test-Path $exe) {
                try { Unblock-File -Path $exe -ErrorAction SilentlyContinue } catch { }
                Start-Process -FilePath $exe -WorkingDirectory $installedTo
                $msg += "`r`n`r`n已启动 Charles。"
            }
        }
        [System.Windows.Forms.MessageBox]::Show($msg, '成功', 'OK', 'Information') | Out-Null
        Invoke-Scan
    } else {
        $lblStatus.Text = '安装失败，请查看下方日志'
        [System.Windows.Forms.MessageBox]::Show(
            "安装失败。`r`n`r`n常见原因：`r`n· Charles 仍被占用（已尝试自动结束，可重试）`r`n· 杀毒软件锁定了 jar 文件`r`n· 权限不足（请用管理员身份运行）`r`n`r`n详细日志见下方或 install.log。",
            '失败', 'OK', 'Error') | Out-Null
    }
})

$btnRestore.Add_Click({
    $item = $lv.SelectedItems | Select-Object -First 1
    $target = $null
    if ($item -and (Test-Path (Join-Path $item.Tag.Path 'lib\charles.jar.orig'))) {
        $target = [pscustomobject]@{ Path = $item.Tag.Path; Backup = (Join-Path $item.Tag.Path 'lib\charles.jar.orig') }
    } else {
        $found = Find-RestoreTargets
        if (-not $found -or $found.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('没有找到任何带 charles.jar.orig 备份的目录（可能从未安装过汉化）。', '无备份', 'OK', 'Information') | Out-Null
            return
        }
        $target = $found[0]
    }
    $r = [System.Windows.Forms.MessageBox]::Show("将用备份还原：`r`n$($target.Path)`r`n`r`n继续？", '还原原版', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    Set-Busy $true
    $bar.Value = 0
    $ok = Restore-Original $target.Path $target.Backup
    Set-Busy $false
    if ($ok) {
        [System.Windows.Forms.MessageBox]::Show('已还原为原版，重新启动 Charles 即生效。', '完成', 'OK', 'Information') | Out-Null
        Invoke-Scan
    } else {
        [System.Windows.Forms.MessageBox]::Show('还原失败，详见日志。', '失败', 'OK', 'Error') | Out-Null
    }
})

$btnOpenLog.Add_Click({
    if (Test-Path $script:LogPath) { Start-Process notepad.exe $script:LogPath }
    else { [System.Windows.Forms.MessageBox]::Show('还没有日志。', '提示', 'OK', 'Information') | Out-Null }
})

$form.Add_Shown({
    Log ("汉化包：{0}（{1:N1} MB）" -f (Split-Path $jarPath -Leaf), ((Get-Item $jarPath).Length / 1MB)) 'INFO'
    Invoke-Scan
})

[void]$form.ShowDialog()