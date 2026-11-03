[CmdletBinding()]
param([switch]$Launch, [switch]$Interactive, [switch]$CheckOnly, [switch]$VerifyAll, [switch]$Json)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RepairSession.psm1') -Force
$progress = {
    param($event)
    if (!$Json) {
        $percent = -1
        if ($event.Total -gt 0) { $percent = [int](100.0 * $event.Completed / $event.Total) }
        Write-Progress -Activity 'ChatGPT 启动修复' -Status $event.Message -PercentComplete $percent
    }
}.GetNewClosure()
$result = Invoke-RepairSession -StateRoot (Join-Path $PSScriptRoot 'state') -Launch:$Launch `
    -CheckOnly:$CheckOnly -VerifyAll:$VerifyAll -OnProgress $progress
Write-Progress -Activity 'ChatGPT 启动修复' -Completed
if ($Json) { $result | ConvertTo-Json -Depth 7 } else { Write-Output $result }
# 保留原命令行错误弹窗；图形界面使用独立入口。
if ($Interactive -and $result.ExitCode -eq 1) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show($result.Message, 'ChatGPT 启动修复', 'OK', 'Warning')
}
exit $result.ExitCode
