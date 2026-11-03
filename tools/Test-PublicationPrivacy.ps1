[CmdletBinding()]
param(
    [string]$RepositoryRoot = ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))),
    [switch]$IncludeHistory,
    [string]$Archive,
    [string]$PolicyFile
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
$findings = [Collections.Generic.List[object]]::new()
$scanned = @{ Files = 0; Objects = 0 }
$privateTerms = @()
if ($PolicyFile) { $privateTerms = @((Get-Content -LiteralPath $PolicyFile -Raw | ConvertFrom-Json).PrivateTerms) }
# 规则只报告类别和位置，避免将命中的敏感值再次写入终端。
$rules = [ordered]@{
    '私人聊天链接' = ('(?i)chatgpt-conver' + 'sation://')
    '会话标识' = '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
    '本机用户目录' = '(?i)\b[A-Z]:[\\/]+Users[\\/]+[^\\/\s"<>]+'
    '本机工作目录' = '(?i)\b[A-Z]:[\\/]+workspace[\\/]'
    'GitHub 令牌' = ('\bgh' + '[pousr]_[A-Za-z0-9]{20,}\b')
    'GitHub 细粒度令牌' = ('\bgithub' + '_pat_[A-Za-z0-9_]{20,}\b')
    'API 密钥' = ('\bs' + 'k-[A-Za-z0-9_-]{20,}\b')
    '云访问密钥' = '\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'
    '私钥内容' = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
}
function Test-PrivacyText([string]$Text, [string]$Location) {
    foreach ($rule in $rules.GetEnumerator()) {
        if ([regex]::IsMatch($Text, $rule.Value)) {
            $findings.Add([pscustomobject]@{ Category = $rule.Key; Location = $Location })
        }
    }
    foreach ($match in [regex]::Matches($Text, '[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}')) {
        # 匿名提交地址和 GitHub SSH 用户是固定公共标识。
        if ($match.Value -notin @('noreply@users.noreply.github.com', 'git@github.com')) {
            $findings.Add([pscustomobject]@{ Category = '邮箱地址'; Location = $Location })
        }
    }
    foreach ($term in $privateTerms) {
        if ($term -and $Text.IndexOf($term, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $findings.Add([pscustomobject]@{ Category = '本机私有策略命中'; Location = $Location })
            break
        }
    }
}
function Test-PrivacyFiles([string]$Directory, [string]$Scope, [bool]$SkipGenerated) {
    $prefix = [IO.Path]::GetFullPath($Directory).TrimEnd('\') + '\'
    foreach ($file in Get-ChildItem -LiteralPath $Directory -Recurse -File -Force) {
        $relative = $file.FullName.Substring($prefix.Length).Replace('\', '/')
        if ($SkipGenerated -and $relative -match '^(?:\.git|work|state|dist|\.playwright-mcp|\.vscode|\.idea)(?:/|$)') { continue }
        $location = "${Scope}:$relative"
        if ($file.Name -match '^\.env(?:\.|$)|\.(?:pem|key|pfx|p12)$') {
            $findings.Add([pscustomobject]@{ Category = '私人配置或密钥文件'; Location = $location })
        }
        $text = [IO.File]::ReadAllText($file.FullName)
        if ($text.IndexOf([char]0) -ge 0) {
            $findings.Add([pscustomobject]@{ Category = '需要人工审查的非文本文件'; Location = $location })
        }
        Test-PrivacyText $text $location
        $scanned.Files++
    }
}
Test-PrivacyFiles $root 'source' $true
if ($IncludeHistory) {
    $ids = @(git -C $root rev-list --objects --all --no-object-names)
    if ($LASTEXITCODE -ne 0) { throw '读取 Git 历史失败。' }
    foreach ($id in $ids) {
        $type = git -C $root cat-file -t $id
        if ($LASTEXITCODE -ne 0) { throw '读取 Git 对象类型失败。' }
        if ($type -in @('blob', 'commit', 'tag')) {
            $content = (git -C $root cat-file $type $id) -join "`n"
            if ($LASTEXITCODE -ne 0) { throw '读取 Git 对象失败。' }
            Test-PrivacyText $content "git:$id"
            $scanned.Objects++
        }
    }
}
if ($Archive) {
    $extract = Join-Path $root ('work\privacy-archive-' + [guid]::NewGuid().ToString('N'))
    Expand-Archive -LiteralPath ([IO.Path]::GetFullPath($Archive)) -DestinationPath $extract
    Test-PrivacyFiles $extract 'archive' $false
}
if ($findings.Count -gt 0) {
    foreach ($finding in $findings | Select-Object -First 20) {
        Write-Host ($finding.Category + '：' + $finding.Location)
    }
    throw "公开内容检查未通过：$($findings.Count) 个命中。请处理来源后重新检查。"
}
[pscustomobject]@{ Passed = $true; FilesScanned = $scanned.Files; GitObjectsScanned = $scanned.Objects; ArchiveChecked = [bool]$Archive }
