Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RuntimeRepair.psm1') -Force

function Invoke-RepairSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StateRoot,
        [switch]$Launch, [switch]$CheckOnly, [switch]$VerifyAll,
        [scriptblock]$OnProgress,
        [string]$RuntimeRoot = (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\runtimes\cua_node'),
        [scriptblock]$GetPackage = { Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1 },
        [scriptblock]$GetProcesses = { Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" },
        [scriptblock]$StartApp = {
            param($Package)
            Start-Process -FilePath explorer.exe -ArgumentList ('shell:AppsFolder\' + $Package.PackageFamilyName + '!App')
        }
    )
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $lock = $null
    $events = [Collections.Generic.List[object]]::new()
    $progressState = @{ Stage = ''; LastReport = -1000.0 }
    $record = [ordered]@{
        Time = (Get-Date).ToString('o'); Status = 'Failed'; RuntimeStatus = 'Unknown'
        AppVersion = $null; RuntimeId = $null; Files = 0; CheckMode = $null
        Target = $null; Backup = $null; LaunchStatus = 'NotRequested'
        Message = ''; Error = $null; Stage = 'Initialize'; FailureStage = $null; Seconds = 0.0; ExitCode = 1
        LogPath = $null; Events = $events
    }
    # 阶段切换立即报告，文件进度最多每 125 毫秒报告一次。
    $report = {
        param($event)
        $record.Stage = $event.Stage
        $now = $timer.Elapsed.TotalMilliseconds
        $changed = $progressState.Stage -ne $event.Stage
        if (!$changed -and $now - $progressState.LastReport -lt 125 -and
            !($event.Total -gt 0 -and $event.Completed -eq $event.Total)) { return }
        $progressState.Stage = $event.Stage
        $progressState.LastReport = $now
        $item = [pscustomobject]@{
            Time = (Get-Date).ToString('o'); Stage = $event.Stage; Message = $event.Message
            Completed = $event.Completed; Total = $event.Total; AppVersion = $record.AppVersion
        }
        $events.Add($item)
        if ($OnProgress) { $null = & $OnProgress $item }
    }.GetNewClosure()
    $log = Join-Path $StateRoot ('run-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $PID + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.log')
    try {
        [void][IO.Directory]::CreateDirectory($StateRoot)
        try { $lock = [IO.File]::Open((Join-Path $StateRoot 'repair.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
        catch [IO.IOException] {
            if (($_.Exception.HResult -band 65535) -in @(32, 33)) {
                $record.Status = 'Busy'
                throw '已有修复任务正在执行，请等待该任务完成后重试。'
            }
            throw
        }
        $null = & $report ([pscustomobject]@{ Stage = 'DetectPackage'; Message = '正在检测已安装的 ChatGPT'; Completed = 0; Total = 0 })
        $pkg = & $GetPackage
        if (!$pkg) { throw '未找到当前用户安装的 OpenAI.Codex 正式版，请先安装应用。' }
        $record.AppVersion = "$($pkg.Version)"
        $null = & $report ([pscustomobject]@{ Stage = 'PackageDetected'; Message = "已检测到应用版本 $($pkg.Version)"; Completed = 0; Total = 0 })
        $source = Join-Path $pkg.InstallLocation 'app\resources\cua_node'
        $expectedPackage = $pkg.PackageFullName
        $beforeDeploy = {
            $current = & $GetPackage
            if (!$current -or $current.PackageFullName -ne $expectedPackage) { throw '应用正在升级，请升级完成后重试。' }
            $running = @(& $GetProcesses | Where-Object {
                $_.ExecutablePath -and $_.ExecutablePath -match '\\OpenAI\.Codex_[^\\]+\\app\\ChatGPT\.exe$'
            })
            if ($running.Count -gt 0) { throw '需要修复运行时。请从托盘完全退出 ChatGPT，再点击“重试”。' }
        }.GetNewClosure()
        $result = Invoke-VerifiedRuntime -Source $source -RuntimeRoot $RuntimeRoot -ReceiptFile (Join-Path $StateRoot 'verified.json') `
            -CheckOnly:$CheckOnly -VerifyAll:$VerifyAll -BeforeDeploy $beforeDeploy -OnProgress $report
        $record.Status = $result.Status
        $record.RuntimeStatus = $result.Status
        $record.RuntimeId = $result.RuntimeId
        $record.Files = $result.FileCount
        $record.CheckMode = $result.CheckMode
        $record.Target = $result.Target
        $record.Backup = $result.Backup
        $record.ExitCode = 0
        switch ($result.Status) {
            'Healthy' { $record.Message = '运行时正常，无需修复。' }
            'Repaired' { $record.Message = '修复完成，完整校验通过。' }
            'NeedsRepair' { $record.Message = '检查完成，运行时需要修复。'; $record.ExitCode = 2 }
        }
        if ($Launch -and !$CheckOnly -and $result.Status -ne 'NeedsRepair') {
            $null = & $report ([pscustomobject]@{ Stage = 'Launch'; Message = '正在发送 ChatGPT 启动请求'; Completed = 0; Total = 0 })
            try {
                $null = & $StartApp $pkg
                $record.LaunchStatus = 'Requested'
                $record.Message += ' 已发送 ChatGPT 启动请求。'
            } catch {
                $record.Status = 'LaunchFailed'; $record.LaunchStatus = 'Failed'; $record.ExitCode = 1
                $record.FailureStage = 'Launch'
                $record.Error = $_.Exception.Message
                $record.Message += ' 启动请求失败，可查看日志后重试。'
            }
        }
        $null = & $report ([pscustomobject]@{ Stage = 'Completed'; Message = $record.Message; Completed = 0; Total = 0 })
    } catch {
        $record.FailureStage = $record.Stage
        $record.Error = $_.Exception.Message
        $record.Message = $_.Exception.Message
        if ($record.Status -ne 'Busy') { $record.Status = 'Failed' }
        $record.ExitCode = 1
    } finally {
        $timer.Stop()
        $record.Seconds = [math]::Round($timer.Elapsed.TotalSeconds, 2)
        try {
            $record.LogPath = $log
            $record | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $log -Encoding UTF8
            Get-ChildItem -LiteralPath $StateRoot -Filter 'run-*.log' -File | Sort-Object LastWriteTime -Descending |
                Select-Object -Skip 10 | Remove-Item -Force -ErrorAction SilentlyContinue
        } catch {
            $record.LogPath = $null
            $record.Message += " 日志写入失败：$($_.Exception.Message)"
        }
        if ($null -ne $lock) { $lock.Dispose() }
    }
    return [pscustomobject]$record
}

Export-ModuleMember -Function Invoke-RepairSession
