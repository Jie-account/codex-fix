param([switch]$Visible)
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
Import-Module (Join-Path $PSScriptRoot '..\RepairWindow.psm1') -Force
[Windows.Forms.Application]::EnableVisualStyles()
$fixture = New-TestFixture
$worker = {
    param($ModulePath, $Options, $Queue)
    Import-Module $ModulePath -Force
    $fixtureRoot = $Options.FixtureRoot
    $pkg = [pscustomobject]@{ Version = '1.0.0.0'; InstallLocation = (Join-Path $fixtureRoot 'install'); PackageFullName = 'OpenAI.Codex_test'; PackageFamilyName = 'OpenAI.Codex_test' }
    $provider = { $pkg }.GetNewClosure()
    $callback = { param($item) $Queue.Enqueue($item) }.GetNewClosure()
    # 延迟由测试制造，用于验证界面在后台任务期间持续处理消息。
    Start-Sleep -Milliseconds 700
    Invoke-RepairSession -StateRoot $Options.StateRoot -RuntimeRoot (Join-Path $fixtureRoot 'runtimes') `
        -GetPackage $provider -GetProcesses { @() } -Launch:$Options.Launch -StartApp { throw '模拟启动请求失败' } -OnProgress $callback
}
$ui = New-RepairWindow -StateRoot $fixture.StateRoot -SessionOptions @{ FixtureRoot = $fixture.Base } -WorkerScript $worker
if (!$Visible) { $ui.Form.Opacity = 0; $ui.Form.ShowInTaskbar = $false }
function Wait-Window {
    param($Window)
    $deadline = [DateTime]::UtcNow.AddSeconds(25)
    while ($Window.Busy -and [DateTime]::UtcNow -lt $deadline) {
        [Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 20
    }
    if ($Window.Busy) { throw '界面后台任务超时' }
}
function Save-WindowImage {
    param($Window, [string]$Name)
    $bitmap = [Drawing.Bitmap]::new($Window.Form.Width, $Window.Form.Height)
    try {
        $Window.Form.DrawToBitmap($bitmap, [Drawing.Rectangle]::new(0, 0, $bitmap.Width, $bitmap.Height))
        $bitmap.Save((Join-Path $PSScriptRoot ('..\work\' + $Name)))
    } finally { $bitmap.Dispose() }
}
try {
    $ui.Form.Show()
    [Windows.Forms.Application]::DoEvents()
    Assert-Test (!$ui.Busy -and $ui.StartButton.Enabled -and $ui.LaunchCheckbox.Checked) '窗口初始准备就绪且默认勾选启动'
    Assert-Test (!(Test-Path -LiteralPath $fixture.StateRoot)) '打开窗口不自动执行检查'
    Save-WindowImage $ui 'gui-ready.png'
    $ui.LaunchCheckbox.Checked = $false
    $ui.StartButton.PerformClick()
    Assert-Test ($ui.Busy -and !$ui.StartButton.Enabled -and !$ui.LaunchCheckbox.Enabled) '点击开始后禁用重复执行和选项修改'
    $ui.Form.Close()
    Assert-Test ($ui.Form.Visible -and $ui.Busy) '执行中关闭窗口不会中断修复'
    Wait-Window $ui
    Assert-Test ($ui.Result.Status -eq 'Repaired' -and $ui.StatusLabel.Text -eq '修复完成') '窗口显示真实隔离目录修复结果'
    Assert-Test ($ui.TickCount -ge 4) '后台任务期间界面计时器持续响应'
    Assert-Test ($ui.ProgressBar.Value -eq 100 -and $ui.LogButton.Enabled) '成功后进度完成且可以查看日志'
    Assert-Test ($ui.StartButton.Text -eq '重新检查' -and $ui.Form.Visible) '成功结果保留在窗口且可以重新检查'
    Assert-Test ($ui.ObservedStages.Contains('Copy') -and $ui.ObservedStages.Contains('Verify')) '窗口收到复制与校验阶段通知'
    Assert-Test ($ui.VersionLabel.Text -like '*1.0.0.0*' -and $ui.CountLabel.Text -like '*4*') '界面显示检测版本和文件数量'
    Save-WindowImage $ui 'gui-success.png'
    $ui.LaunchCheckbox.Checked = $true
    $ui.StartButton.PerformClick()
    Wait-Window $ui
    Assert-Test ($ui.Result.Status -eq 'LaunchFailed' -and $ui.Result.RuntimeStatus -eq 'Healthy') '启动失败保留运行时健康结果'
    Assert-Test ($ui.StatusLabel.Text -like '*启动请求失败*' -and $ui.StartButton.Text -eq '重试') '启动请求失败明确反馈并提供重试'
    Assert-Test ($ui.ProgressBar.Value -eq 100) '启动失败后仍显示运行时检查已完成'
    Save-WindowImage $ui 'gui-launch-failed.png'
    $manifestPath = Join-Path $fixture.Source 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw
    '{"platform":"linux"}' | Set-Content -LiteralPath $manifestPath
    $ui.LaunchCheckbox.Checked = $false
    $ui.StartButton.PerformClick()
    Wait-Window $ui
    Assert-Test ($ui.Result.Status -eq 'Failed' -and $ui.DetailLabel.Text -like '*结构*') '修复错误在窗口中保留具体原因'
    Assert-Test ($ui.LogButton.Enabled -and $ui.StartButton.Enabled) '失败后可查看日志并再次执行'
    Save-WindowImage $ui 'gui-failed.png'
    $manifest | Set-Content -LiteralPath $manifestPath -Encoding UTF8 -NoNewline
    $ui.StartButton.PerformClick()
    Wait-Window $ui
    Assert-Test ($ui.Result.Status -eq 'Healthy' -and $ui.StatusLabel.Text -like '*正常*') '修复原因解除后可以成功重试'
} finally {
    if (!$ui.Busy) { $ui.Form.Close(); $ui.Form.Dispose() }
}
Write-Output "图形界面测试通过：$script:AssertionCount 项断言"
