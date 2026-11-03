Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function New-RepairWindow {
    [CmdletBinding()]
    param(
        [string]$StateRoot = (Join-Path $PSScriptRoot 'state'),
        [hashtable]$SessionOptions = @{},
        [scriptblock]$WorkerScript = {
            param($ModulePath, $Options, $Queue)
            Import-Module $ModulePath -Force
            $callback = { param($item) $Queue.Enqueue($item) }.GetNewClosure()
            Invoke-RepairSession @Options -OnProgress $callback
        }
    )
    $form = [Windows.Forms.Form]::new()
    $form.Text = 'ChatGPT 启动修复'
    $versionPath = Join-Path $PSScriptRoot 'VERSION'
    if (Test-Path -LiteralPath $versionPath) {
        $form.Text += ' v' + [IO.File]::ReadAllText($versionPath).Trim()
    }
    $form.ClientSize = [Drawing.Size]::new(660, 530)
    $form.MinimumSize = $form.Size
    $form.StartPosition = 'CenterScreen'
    $form.BackColor = [Drawing.Color]::White
    $form.Font = [Drawing.Font]::new('Microsoft YaHei UI', 9.5)
    $form.AutoScaleMode = 'Font'
    $form.MaximizeBox = $false
    $form.FormBorderStyle = 'FixedSingle'
    $iconPath = Join-Path $PSScriptRoot 'chatgpt.ico'
    if (Test-Path -LiteralPath $iconPath) { $form.Icon = [Drawing.Icon]::new($iconPath) }

    $heading = [Windows.Forms.Label]::new()
    $heading.Text = 'ChatGPT 启动修复'
    $heading.Font = [Drawing.Font]::new($form.Font.FontFamily, 19, [Drawing.FontStyle]::Bold)
    $heading.SetBounds(28, 22, 600, 38)
    $heading.ForeColor = [Drawing.ColorTranslator]::FromHtml('#172033')
    $form.Controls.Add($heading)
    $subtitle = [Windows.Forms.Label]::new()
    $subtitle.Text = '检查当前版本，并在需要时修复启动运行时。'
    $subtitle.SetBounds(30, 67, 600, 24)
    $subtitle.ForeColor = [Drawing.ColorTranslator]::FromHtml('#64748B')
    $form.Controls.Add($subtitle)

    $card = [Windows.Forms.Panel]::new()
    $card.SetBounds(28, 108, 604, 174)
    $card.Anchor = 'Top, Left, Right'
    $card.BackColor = [Drawing.ColorTranslator]::FromHtml('#F1F5F9')
    $form.Controls.Add($card)
    $status = [Windows.Forms.Label]::new()
    $status.Text = '准备就绪'
    $status.Font = [Drawing.Font]::new($form.Font.FontFamily, 12, [Drawing.FontStyle]::Bold)
    $status.SetBounds(18, 14, 568, 26)
    $card.Controls.Add($status)
    $version = [Windows.Forms.Label]::new()
    $version.Text = '应用版本：待检测'
    $version.SetBounds(18, 45, 568, 22)
    $version.ForeColor = [Drawing.ColorTranslator]::FromHtml('#475569')
    $card.Controls.Add($version)
    $detail = [Windows.Forms.Label]::new()
    $detail.Text = '点击“开始”执行检查，结果会保留在此窗口。'
    $detail.SetBounds(18, 73, 568, 44)
    $card.Controls.Add($detail)
    $progress = [Windows.Forms.ProgressBar]::new()
    $progress.SetBounds(18, 122, 568, 9)
    $progress.Style = 'Continuous'
    $card.Controls.Add($progress)
    $count = [Windows.Forms.Label]::new()
    $count.Text = '等待开始'
    $count.SetBounds(18, 139, 370, 24)
    $count.ForeColor = [Drawing.ColorTranslator]::FromHtml('#64748B')
    $card.Controls.Add($count)
    $elapsed = [Windows.Forms.Label]::new()
    $elapsed.Text = '耗时 0 秒'
    $elapsed.TextAlign = 'TopRight'
    $elapsed.SetBounds(388, 139, 198, 24)
    $elapsed.ForeColor = $count.ForeColor
    $card.Controls.Add($elapsed)

    $messagesTitle = [Windows.Forms.Label]::new()
    $messagesTitle.Text = '重要信息'
    $messagesTitle.SetBounds(28, 300, 600, 24)
    $form.Controls.Add($messagesTitle)
    $messages = [Windows.Forms.TextBox]::new()
    $messages.SetBounds(28, 328, 604, 90)
    $messages.Multiline = $true
    $messages.ReadOnly = $true
    $messages.TabStop = $false
    $messages.ScrollBars = 'Vertical'
    $messages.BackColor = [Drawing.Color]::White
    $messages.BorderStyle = 'FixedSingle'
    $messages.Text = '尚未执行检查。'
    $form.Controls.Add($messages)
    $launch = [Windows.Forms.CheckBox]::new()
    $launch.Text = '完成后打开 ChatGPT'
    $launch.Checked = $true
    $launch.SetBounds(28, 432, 320, 26)
    $form.Controls.Add($launch)
    $start = [Windows.Forms.Button]::new()
    $start.Text = '开始'
    $start.SetBounds(28, 475, 148, 36)
    $start.FlatStyle = 'Flat'
    $start.FlatAppearance.BorderSize = 0
    $start.BackColor = [Drawing.ColorTranslator]::FromHtml('#2563EB')
    $start.ForeColor = [Drawing.Color]::White
    $form.Controls.Add($start)
    $logButton = [Windows.Forms.Button]::new()
    $logButton.Text = '查看日志'
    $logButton.SetBounds(420, 475, 100, 36)
    $logButton.Enabled = $false
    $form.Controls.Add($logButton)
    $close = [Windows.Forms.Button]::new()
    $close.Text = '关闭'
    $close.SetBounds(532, 475, 100, 36)
    $form.Controls.Add($close)
    $form.AcceptButton = $start
    $form.ActiveControl = $start

    $ui = [pscustomobject]@{
        Form = $form; StartButton = $start; LaunchCheckbox = $launch; LogButton = $logButton
        StatusLabel = $status; DetailLabel = $detail; ProgressBar = $progress; CountLabel = $count
        VersionLabel = $version; ElapsedLabel = $elapsed; Messages = $messages
        Busy = $false; Result = $null; Queue = [Collections.Concurrent.ConcurrentQueue[object]]::new()
        PowerShell = $null; Handle = $null; Runspace = $null; Clock = [Diagnostics.Stopwatch]::new()
        ObservedStages = [Collections.Generic.List[string]]::new(); TickCount = 0; LastMessageStage = ''
    }
    $timer = [Windows.Forms.Timer]::new()
    $timer.Interval = 100
    $modulePath = Join-Path $PSScriptRoot 'RepairSession.psm1'
    $appendMessage = {
        param([string]$text)
        if ($messages.Text.Length -gt 0) { $messages.AppendText([Environment]::NewLine) }
        $messages.AppendText($text)
    }.GetNewClosure()
    $applyEvent = {
        param($item)
        $ui.ObservedStages.Add($item.Stage)
        if ($item.AppVersion) { $version.Text = '应用版本：' + $item.AppVersion }
        $detail.Text = $item.Message
        if ($item.Total -gt 0) {
            $progress.Style = 'Continuous'
            $progress.Value = [math]::Min(100, [int](100.0 * $item.Completed / $item.Total))
            $count.Text = "当前阶段：$($item.Completed) / $($item.Total) 个文件"
        } else {
            $progress.Style = 'Marquee'
            $count.Text = '正在处理，请稍候'
        }
        if ($ui.LastMessageStage -ne $item.Stage) {
            $ui.LastMessageStage = $item.Stage
            # 主界面只保留重要阶段，路径和逐文件细节留在日志中。
            if ($item.Stage -in @('PackageDetected', 'QuickCheck', 'FullCheck', 'RepairRequired', 'Copy', 'Verify', 'Publish', 'Launch')) {
                $null = & $appendMessage $item.Message
            }
        }
    }.GetNewClosure()
    $finish = {
        param($result)
        $timer.Stop()
        $ui.Clock.Stop()
        $ui.Result = $result
        $ui.Busy = $false
        $start.Enabled = $true
        $launch.Enabled = $true
        $close.Enabled = $true
        $progress.Style = 'Continuous'
        $detail.Text = $result.Message
        $elapsed.Text = '耗时 ' + [math]::Round($ui.Clock.Elapsed.TotalSeconds, 1) + ' 秒'
        $count.Text = if ($result.Files -gt 0) { '运行时文件：' + $result.Files + ' 个' } else { '本次执行已结束' }
        if ($result.AppVersion) { $version.Text = '应用版本：' + $result.AppVersion }
        $logButton.Enabled = [bool]($result.LogPath -and (Test-Path -LiteralPath $result.LogPath))
        $success = $result.Status -in @('Healthy', 'Repaired')
        $status.ForeColor = [Drawing.ColorTranslator]::FromHtml('#B45309')
        if ($success) {
            $status.ForeColor = [Drawing.ColorTranslator]::FromHtml('#15803D')
            $status.Text = if ($result.Status -eq 'Repaired') { '修复完成' } else { '运行时正常，无需修复' }
            $progress.Value = 100
            $start.Text = '重新检查'
        } else {
            $progress.Value = 0
            $start.Text = '重试'
            $status.Text = switch ($result.Status) {
                'Busy' { '已有任务正在执行' }
                'LaunchFailed' { '运行时已就绪，启动请求失败' }
                'NeedsRepair' { '运行时需要修复' }
                default { '本次未能完成' }
            }
            if ($result.Status -eq 'LaunchFailed') { $progress.Value = 100 }
        }
        $null = & $appendMessage $result.Message
        if ($null -ne $ui.PowerShell) { $ui.PowerShell.Dispose(); $ui.PowerShell = $null }
        if ($null -ne $ui.Runspace) { $ui.Runspace.Dispose(); $ui.Runspace = $null }
        $ui.Handle = $null
    }.GetNewClosure()
    $timer.Add_Tick({
        $ui.TickCount++
        $elapsed.Text = '耗时 ' + [math]::Round($ui.Clock.Elapsed.TotalSeconds, 1) + ' 秒'
        $item = $null
        while ($ui.Queue.TryDequeue([ref]$item)) { $null = & $applyEvent $item }
        if ($null -ne $ui.Handle -and $ui.Handle.IsCompleted) {
            try {
                $output = @($ui.PowerShell.EndInvoke($ui.Handle))
                # 后台结束后再取一次队列，保留最后一次计时器读取之后到达的阶段消息。
                $item = $null
                while ($ui.Queue.TryDequeue([ref]$item)) { $null = & $applyEvent $item }
                if ($ui.PowerShell.HadErrors) { throw ($ui.PowerShell.Streams.Error | Out-String) }
                if ($output.Count -ne 1) { throw '后台执行未返回有效结果。' }
                $null = & $finish $output[0]
            } catch {
                $null = & $finish ([pscustomobject]@{ Status = 'Failed'; Message = $_.Exception.Message; Files = 0; AppVersion = $null; LogPath = $null })
            }
        }
    }.GetNewClosure())
    $start.Add_Click({
        if ($ui.Busy) { return }
        $ui.Busy = $true
        $ui.Result = $null
        $ui.LastMessageStage = ''
        $ui.ObservedStages.Clear()
        $start.Enabled = $false
        $launch.Enabled = $false
        $close.Enabled = $false
        $logButton.Enabled = $false
        $status.Text = '正在执行'
        $status.ForeColor = [Drawing.ColorTranslator]::FromHtml('#172033')
        $detail.Text = '正在准备检查当前版本。'
        $progress.Style = 'Marquee'
        $messages.Clear()
        $ui.Clock.Restart()
        try {
            $options = $SessionOptions.Clone()
            $options.StateRoot = $StateRoot
            $options.Launch = $launch.Checked
            # 后台 PowerShell runspace 执行任务，消息队列由界面计时器读取。
            $ui.Runspace = [RunspaceFactory]::CreateRunspace()
            $ui.Runspace.Open()
            $ui.PowerShell = [PowerShell]::Create()
            $ui.PowerShell.Runspace = $ui.Runspace
            [void]$ui.PowerShell.AddScript($WorkerScript.ToString()).AddArgument($modulePath).AddArgument($options).AddArgument($ui.Queue)
            $ui.Handle = $ui.PowerShell.BeginInvoke()
            $timer.Start()
        } catch {
            $null = & $finish ([pscustomobject]@{ Status = 'Failed'; Message = $_.Exception.Message; Files = 0; AppVersion = $null; LogPath = $null })
        }
    }.GetNewClosure())
    $logButton.Add_Click({
        if ($ui.Result -and $ui.Result.LogPath) {
            Start-Process -FilePath notepad.exe -ArgumentList ('"' + $ui.Result.LogPath + '"')
        }
    }.GetNewClosure())
    $close.Add_Click({ $form.Close() }.GetNewClosure())
    $form.Add_FormClosing({
        param($sender, $eventArgs)
        if ($ui.Busy) {
            $eventArgs.Cancel = $true
            $null = & $appendMessage '任务正在执行，完成后即可关闭窗口。'
        }
    }.GetNewClosure())
    $form.Add_FormClosed({ $timer.Dispose() }.GetNewClosure())
    return $ui
}

Export-ModuleMember -Function New-RepairWindow
