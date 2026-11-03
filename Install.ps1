[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$destination = Join-Path $env:LOCALAPPDATA 'OpenAI\CodexRepair'
[void][IO.Directory]::CreateDirectory($destination)
foreach ($name in @('RuntimeRepair.psm1', 'RepairSession.psm1', 'RepairWindow.psm1', 'Start-RepairGui.ps1', 'Repair-And-Launch.ps1', 'Uninstall.ps1', 'README.md', 'CHANGELOG.md', 'VERSION')) {
    $sourcePath = Join-Path $PSScriptRoot $name
    $destinationPath = Join-Path $destination $name
    if ($sourcePath -ne $destinationPath) { Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force }
}
$releaseInfo = Join-Path $PSScriptRoot 'release-info.json'
if (Test-Path -LiteralPath $releaseInfo) { Copy-Item -LiteralPath $releaseInfo -Destination (Join-Path $destination 'release-info.json') -Force }
$pkg = Get-AppxPackage -Name OpenAI.Codex
if (!$pkg) { throw '未找到 OpenAI.Codex 正式版。' }
$iconSource = Join-Path $pkg.InstallLocation 'app\resources\icon-chatgpt.ico'
$iconTarget = Join-Path $destination 'chatgpt.ico'
$inputStream = [IO.File]::OpenRead($iconSource)
try {
    $outputStream = [IO.File]::Create($iconTarget)
    try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
} finally { $inputStream.Dispose() }
$shell = New-Object -ComObject WScript.Shell
foreach ($folder in @([Environment]::GetFolderPath('DesktopDirectory'), [Environment]::GetFolderPath('Programs'))) {
    $shortcutPath = Join-Path $folder 'ChatGPT（自动修复）.lnk'
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortcut.Arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $destination 'Start-RepairGui.ps1') + '"'
    $shortcut.WorkingDirectory = $destination
    $shortcut.IconLocation = $iconTarget
    $shortcut.Description = '打开修复窗口，点击开始检查当前版本、按需修复并查看结果。'
    $shortcut.WindowStyle = 7
    $shortcut.Save()
    Write-Output "已创建：$shortcutPath"
}
Write-Output "已安装：$destination"
