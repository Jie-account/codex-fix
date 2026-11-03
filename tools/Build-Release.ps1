[CmdletBinding()]
param([string]$OutputDirectory, [switch]$Force)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$version = [IO.File]::ReadAllText((Join-Path $root 'VERSION')).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'VERSION 应为三段式正式版本号。' }
$status = @(git -C $root status --porcelain)
if ($LASTEXITCODE -ne 0) { throw '读取 Git 状态失败。' }
if ($status.Count -gt 0) { throw '请先提交源码，再生成对应提交的正式发布包。' }
$commit = git -C $root rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw '读取发布提交失败。' }
$privacy = & (Join-Path $PSScriptRoot 'Test-PublicationPrivacy.ps1') -RepositoryRoot $root -IncludeHistory
if (!$privacy.Passed) { throw '公开内容检查未通过。' }
if (!$OutputDirectory) { $OutputDirectory = Join-Path $root 'dist' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$archiveName = "codex-fix-v$version-windows.zip"
$archivePath = Join-Path $OutputDirectory $archiveName
if ((Test-Path -LiteralPath $archivePath) -and !$Force) { throw '发布包已存在；使用 -Force 可重新生成本地文件。' }
$stage = Join-Path $root ('work\release-' + [guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $stage "codex-fix-v$version"
[void][IO.Directory]::CreateDirectory($packageRoot)
# 明确发布文件清单，运行状态、日志、测试和诊断副本留在本机。
$files = @('Install.ps1', 'Uninstall.ps1', 'RuntimeRepair.psm1', 'RepairSession.psm1', 'RepairWindow.psm1',
    'Start-RepairGui.ps1', 'Repair-And-Launch.ps1', 'README.md', 'CHANGELOG.md', '安装自动修复.cmd', '修复并启动.cmd', 'VERSION')
function Get-ReleaseHash([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}
$entries = foreach ($name in $files) {
    $source = Join-Path $root $name
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "缺少发布文件：$name" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $packageRoot $name)
    [pscustomobject]@{ Path = $name; Sha256 = Get-ReleaseHash $source }
}
$manifest = [ordered]@{
    Version = $version; SourceCommit = $commit; Repository = 'https://github.com/Jie-account/codex-fix'
    Platform = 'Windows'; PowerShell = 'Windows PowerShell 5.1'; TargetPackage = 'OpenAI.Codex'
    Files = @($entries)
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $packageRoot 'release-info.json') -Encoding UTF8
Compress-Archive -LiteralPath $packageRoot -DestinationPath $archivePath -Force:$Force
$digest = Get-ReleaseHash $archivePath
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS.txt'), "$digest  $archiveName`r`n", [Text.Encoding]::ASCII)
[pscustomobject]@{ Version = $version; Commit = $commit; Archive = $archivePath; Sha256 = $digest; PackageRoot = $packageRoot }
