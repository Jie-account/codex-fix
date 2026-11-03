# 保留已修复运行时和日志，只移除两个自动修复入口。
$ErrorActionPreference = 'Stop'
foreach ($folder in @([Environment]::GetFolderPath('DesktopDirectory'), [Environment]::GetFolderPath('Programs'))) {
    $path = Join-Path $folder 'ChatGPT（自动修复）.lnk'
    if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
}
Write-Output '已移除自动修复快捷方式。程序文件和日志仍保留于本脚本所在目录。'
