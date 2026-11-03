# 图形界面入口只打开窗口，等待用户点击“开始”。
$ErrorActionPreference = 'Stop'
try {
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -WindowStyle Hidden -ArgumentList ('-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"')
        exit
    }
    Import-Module (Join-Path $PSScriptRoot 'RepairWindow.psm1') -Force
    [Windows.Forms.Application]::EnableVisualStyles()
    $window = New-RepairWindow
    [void]$window.Form.ShowDialog()
    $window.Form.Dispose()
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, '无法打开启动修复窗口', 'OK', 'Error')
    exit 1
}
