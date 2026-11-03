param([Parameter(Mandatory)][string]$Archive)
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archivePath = (Resolve-Path -LiteralPath $Archive).Path
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$version = [IO.File]::ReadAllText((Join-Path $root 'VERSION')).Trim()
$extract = Join-Path $root ('work\release-test-' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $archivePath -DestinationPath $extract
$packageRoot = Join-Path $extract "codex-fix-v$version"
$manifest = Get-Content -LiteralPath (Join-Path $packageRoot 'release-info.json') -Raw | ConvertFrom-Json
Assert-Test ($manifest.Version -eq $version -and $manifest.SourceCommit -eq (git -C $root rev-parse HEAD)) '安装包版本与源码提交一致'
$expected = @($manifest.Files | ForEach-Object Path) + @('release-info.json')
$actual = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File)
Assert-Test ($actual.Count -eq $expected.Count -and @(Get-ChildItem -LiteralPath $packageRoot -Directory).Count -eq 0) '安装包只包含声明的发布文件'
foreach ($entry in $manifest.Files) {
    $filePath = Join-Path $packageRoot $entry.Path
    Assert-Test ((Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant() -eq $entry.Sha256) "文件内容完整：$($entry.Path)"
    if ([IO.Path]::GetExtension($filePath) -in @('.ps1', '.psm1')) {
        $bytes = [IO.File]::ReadAllBytes($filePath)
        Assert-Test ($bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) "PowerShell 5.1 中文编码完整：$($entry.Path)"
    }
}
$checksum = [IO.File]::ReadAllText((Join-Path (Split-Path $archivePath -Parent) 'SHA256SUMS.txt')).Trim()
Assert-Test ($checksum.StartsWith((Get-FileHash -LiteralPath $archivePath).Hash.ToLowerInvariant() + '  ')) 'ZIP 的 SHA256 与校验文件一致'
Import-Module (Join-Path $packageRoot 'RepairWindow.psm1') -Force
$window = New-RepairWindow -StateRoot (Join-Path $extract 'test-state')
try {
    Assert-Test ($window.Form.Text -eq "ChatGPT 启动修复 v$version") '解压后的独立界面显示发布版本'
    Assert-Test (!$window.Busy -and $window.StartButton.Enabled -and !(Test-Path -LiteralPath (Join-Path $extract 'test-state'))) '解压后的窗口等待开始且不会自动执行'
} finally { $window.Form.Dispose() }
$privacy = & (Join-Path $PSScriptRoot '..\tools\Test-PublicationPrivacy.ps1') -RepositoryRoot $root -IncludeHistory -Archive $archivePath
Assert-Test $privacy.Passed '源码、可达历史和解压发布包通过公开内容检查'
Write-Output "发布包测试通过：$script:AssertionCount 项断言"
Write-Output "解压目录：$packageRoot"
