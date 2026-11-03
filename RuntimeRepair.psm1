Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-RepairProgress {
    param([scriptblock]$OnProgress, [string]$Stage, [string]$Message, [int]$Completed = 0, [int]$Total = 0)
    if ($OnProgress) {
        # 进度独立于返回值，供命令行和图形界面共同使用。
        $null = & $OnProgress ([pscustomobject]@{ Stage = $Stage; Message = $Message; Completed = $Completed; Total = $Total })
    }
}

function Get-RuntimeFileHash {
    param([Parameter(Mandatory)][string]$Path)
    # 快捷方式启动的 PowerShell 模块环境可能不同，直接使用 .NET 流计算哈希。
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}

function Get-RuntimeId {
    param([Parameter(Mandatory)][string]$Source)
    # 与当前桌面端一致：依次拼接相对路径、空字符和核心文件的 SHA256。
    $builder = [Text.StringBuilder]::new()
    foreach ($relative in @('manifest.json', 'bin/node.exe', 'bin/node_repl.exe')) {
        $digest = Get-RuntimeFileHash -Path (Join-Path $Source $relative)
        [void]$builder.Append($relative).Append([char]0).Append($digest).Append([char]0)
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($builder.ToString()))
        return ([BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()).Substring(0, 16)
    } finally { $sha.Dispose() }
}

function Get-RuntimeFiles {
    param([Parameter(Mandatory)][string]$Root)
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    foreach ($item in Get-ChildItem -LiteralPath $Root -Recurse -Force) {
        # 安装包结构改变时明确停止，避免意外跟随目录链接。
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "运行时包含链接，需要适配新结构：$($item.FullName)"
        }
        if (!$item.PSIsContainer) {
            [pscustomobject]@{
                Relative = $item.FullName.Substring($prefix.Length)
                Path = $item.FullName
                Length = $item.Length
                Ticks = $item.LastWriteTimeUtc.Ticks.ToString()
            }
        }
    }
}

function Test-RuntimeTree {
    param([array]$SourceFiles, [string]$Target, [switch]$Hash, [scriptblock]$OnProgress, [string]$Stage = 'FullCheck')
    if (!(Test-Path -LiteralPath $Target -PathType Container)) { return $false }
    $targetFiles = @(Get-RuntimeFiles -Root $Target)
    if ($targetFiles.Count -ne $SourceFiles.Count) { return $false }
    $index = @{}
    foreach ($file in $targetFiles) { $index[$file.Relative] = $file }
    $completed = 0
    Write-RepairProgress $OnProgress $Stage '正在逐文件校验 SHA256' 0 $SourceFiles.Count
    foreach ($file in $SourceFiles) {
        $other = $index[$file.Relative]
        if ($null -eq $other -or $other.Length -ne $file.Length) { return $false }
        if ($Hash) {
            $a = Get-RuntimeFileHash -Path $file.Path
            $b = Get-RuntimeFileHash -Path $other.Path
            if ($a -ne $b) { return $false }
        }
        $completed++
        Write-RepairProgress $OnProgress $Stage '正在逐文件校验 SHA256' $completed $SourceFiles.Count
    }
    return $true
}

function Copy-RuntimeStream {
    param([array]$Files, [string]$Destination, [scriptblock]$OnProgress)
    $completed = 0
    Write-RepairProgress $OnProgress 'Copy' '正在复制运行时文件' 0 $Files.Count
    foreach ($file in $Files) {
        $path = Join-Path $Destination $file.Relative
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        # 从一开始采用流式复制，避开 WindowsApps 加密属性的复制失败。
        $inputStream = [IO.File]::OpenRead($file.Path)
        try {
            $outputStream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $inputStream.CopyTo($outputStream) }
            finally { $outputStream.Dispose() }
        } finally { $inputStream.Dispose() }
        $completed++
        Write-RepairProgress $OnProgress 'Copy' '正在复制运行时文件' $completed $Files.Count
    }
}

function Save-RuntimeReceipt {
    param([string]$File, [string]$Source, [string]$RuntimeId, [string]$Target)
    if (!$File) { return }
    $receipt = [ordered]@{
        Source = $Source
        RuntimeId = $RuntimeId
        VerifiedUtc = [DateTime]::UtcNow.ToString('o')
        Files = @(Get-RuntimeFiles -Root $Target | Select-Object Relative, Length, Ticks)
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($File))
    $receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $File -Encoding UTF8
}

function Test-RuntimeReceipt {
    param([string]$ReceiptPath, [string]$Source, [string]$RuntimeId, [string]$Target, [int]$Count)
    if (!$ReceiptPath -or !(Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) { return $false }
    try {
        $receipt = Get-Content -LiteralPath $ReceiptPath -Raw | ConvertFrom-Json
        if ($receipt.Source -ne $Source -or $receipt.RuntimeId -ne $RuntimeId) { return $false }
        $files = @(Get-RuntimeFiles -Root $Target)
        if ($files.Count -ne $Count -or @($receipt.Files).Count -ne $Count) { return $false }
        $index = @{}
        foreach ($file in $files) { $index[$file.Relative] = $file }
        foreach ($old in $receipt.Files) {
            $current = $index[$old.Relative]
            if ($null -eq $current -or $old.Length -ne $current.Length -or $old.Ticks -ne $current.Ticks) { return $false }
        }
        # 核心文件每次重新核验；完整内容校验可通过 -VerifyAll 强制执行。
        foreach ($relative in @('manifest.json', 'bin/node.exe', 'bin/node_repl.exe')) {
            if ((Get-RuntimeFileHash -Path (Join-Path $Source $relative)) -ne
                (Get-RuntimeFileHash -Path (Join-Path $Target $relative))) { return $false }
        }
        return $true
    } catch { return $false }
}

function Invoke-VerifiedRuntime {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$RuntimeRoot,
        [string]$ReceiptFile,
        [switch]$CheckOnly,
        [switch]$VerifyAll,
        [scriptblock]$BeforeDeploy = {},
        [scriptblock]$OnProgress
    )
    $Source = [IO.Path]::GetFullPath($Source).TrimEnd('\')
    $RuntimeRoot = [IO.Path]::GetFullPath($RuntimeRoot).TrimEnd('\')
    Write-RepairProgress $OnProgress 'Prepare' '正在读取运行时配置'
    $manifest = Get-Content -LiteralPath (Join-Path $Source 'manifest.json') -Raw | ConvertFrom-Json
    if ($manifest.platform -ne 'windows' -or $manifest.node_path -ne 'bin/node.exe' -or
        $manifest.node_repl_path -ne 'bin/node_repl.exe') {
        throw '新版运行时结构与当前修复器不兼容，请保留日志后更新修复器。'
    }
    Write-RepairProgress $OnProgress 'Identify' '正在识别当前版本的运行时'
    $runtimeId = Get-RuntimeId -Source $Source
    $target = Join-Path $RuntimeRoot $runtimeId
    if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($target)) -ne $RuntimeRoot) {
        throw '目标目录超出预期运行时根目录。'
    }
    if (!(Test-Path -LiteralPath (Join-Path $Source 'bin\node_modules') -PathType Container)) {
        throw '安装包缺少 bin\node_modules，请先修复应用安装。'
    }
    Write-RepairProgress $OnProgress 'Enumerate' '正在统计运行时文件'
    $files = @(Get-RuntimeFiles -Root $Source)
    if ($files.Count -lt 3) { throw '安装包的运行时文件不完整。' }
    $healthy = $false
    $checkMode = 'Full'
    if (!$VerifyAll) {
        Write-RepairProgress $OnProgress 'QuickCheck' '正在进行快速检查'
        $healthy = Test-RuntimeReceipt -ReceiptPath $ReceiptFile -Source $Source -RuntimeId $runtimeId -Target $target -Count $files.Count
        if ($healthy) { $checkMode = 'Quick' }
    }
    if (!$healthy) {
        Write-RepairProgress $OnProgress 'FullCheck' '正在进行完整校验'
        $healthy = Test-RuntimeTree -SourceFiles $files -Target $target -Hash -OnProgress $OnProgress
    }
    $status = 'Healthy'
    $backup = $null
    if (!$healthy) {
        $status = 'NeedsRepair'
        Write-RepairProgress $OnProgress 'RepairRequired' '检测到运行时缺失或不完整，需要修复'
        if (!$CheckOnly) {
            Write-RepairProgress $OnProgress 'Preflight' '正在确认应用已退出并检查安装版本'
            & $BeforeDeploy
            [void][IO.Directory]::CreateDirectory($RuntimeRoot)
            $stage = Join-Path $RuntimeRoot ('.manual-verified-' + [guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($stage)
            Write-Verbose "流式复制 $($files.Count) 个文件至 $stage"
            Copy-RuntimeStream -Files $files -Destination $stage -OnProgress $OnProgress
            Write-RepairProgress $OnProgress 'Verify' '正在完整校验复制结果'
            if (!(Test-RuntimeTree -SourceFiles $files -Target $stage -Hash -OnProgress $OnProgress -Stage 'Verify')) {
                throw "完整 SHA256 校验失败，暂存目录保留于：$stage"
            }
            if ((Get-RuntimeId -Source $Source) -ne $runtimeId) { throw '复制期间安装包发生变化，请重新运行。' }
            # 临近替换再次检查应用状态；只移动本次推导出的精确目标目录。
            Write-RepairProgress $OnProgress 'Publish' '正在部署已通过校验的运行时'
            & $BeforeDeploy
            if (Test-Path -LiteralPath $target) {
                $backup = Join-Path $RuntimeRoot ('.repair-backup-' + $runtimeId + '-' + [guid]::NewGuid().ToString('N'))
                [IO.Directory]::Move($target, $backup)
            }
            try { [IO.Directory]::Move($stage, $target) }
            catch {
                if ($backup -and !(Test-Path -LiteralPath $target)) { [IO.Directory]::Move($backup, $target) }
                throw
            }
            $status = 'Repaired'
        }
    }
    if (!$CheckOnly -and $status -ne 'NeedsRepair') {
        Write-RepairProgress $OnProgress 'Receipt' '正在保存校验记录'
        Save-RuntimeReceipt -File $ReceiptFile -Source $Source -RuntimeId $runtimeId -Target $target
    }
    [pscustomobject]@{ Status = $status; RuntimeId = $runtimeId; FileCount = $files.Count; Target = $target; Backup = $backup; CheckMode = $checkMode }
}

Export-ModuleMember -Function Get-RuntimeId, Invoke-VerifiedRuntime
