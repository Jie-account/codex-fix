. (Join-Path $PSScriptRoot 'TestSupport.ps1')
Import-Module (Join-Path $PSScriptRoot '..\RepairSession.psm1') -Force
$fixture = New-TestFixture
$package = $fixture.Package
$getPackage = { $package }.GetNewClosure()
$options = @{ StateRoot = $fixture.StateRoot; RuntimeRoot = $fixture.RuntimeRoot; GetPackage = $getPackage; GetProcesses = { @() } }
$observed = [Collections.Generic.List[object]]::new()
$callback = { param($event) $observed.Add($event) }.GetNewClosure()
$result = Invoke-RepairSession @options -OnProgress $callback
Assert-Test ($result.Status -eq 'Repaired' -and $result.ExitCode -eq 0) '编排完成真实隔离目录修复'
Assert-Test ($result.RuntimeStatus -eq 'Repaired' -and $result.LaunchStatus -eq 'NotRequested') '修复结果与启动结果分开记录'
Assert-Test (@($observed | Where-Object { $_.Stage -eq 'Copy' -and $_.Completed -eq 4 -and $_.Total -eq 4 }).Count -eq 1) '复制进度报告真实完成文件数'
Assert-Test (@($observed | Where-Object { $_.Stage -eq 'Verify' -and $_.Completed -eq 4 }).Count -eq 1) '完整校验报告完成进度'
$stages = @($observed | ForEach-Object Stage)
Assert-Test ([array]::IndexOf($stages, 'Copy') -lt [array]::IndexOf($stages, 'Verify') -and [array]::IndexOf($stages, 'Verify') -lt [array]::IndexOf($stages, 'Publish')) '校验通过后才报告部署阶段'
$logged = Get-Content -LiteralPath $result.LogPath -Raw | ConvertFrom-Json
Assert-Test ($logged.Status -eq 'Repaired' -and $logged.Events.Count -gt 0) '成功日志包含最终结果和阶段记录'
$options.GetProcesses = { throw '健康目录不应要求退出应用' }
$result = Invoke-RepairSession @options
Assert-Test ($result.Status -eq 'Healthy' -and $result.CheckMode -eq 'Quick') '健康运行时快速检查无需替换或退出应用'
$launchCalls = [Collections.Generic.List[string]]::new()
$launchAction = { param($pkg) $launchCalls.Add($pkg.PackageFamilyName) }.GetNewClosure()
$result = Invoke-RepairSession @options -Launch -StartApp $launchAction
Assert-Test ($result.Status -eq 'Healthy' -and $result.LaunchStatus -eq 'Requested' -and $launchCalls.Count -eq 1) '勾选启动后发出一次启动请求'
Assert-Test ($result.Message -like '*启动请求*' -and $result.Message -notlike '*成功启动*') '启动文案只陈述已发出请求'
$result = Invoke-RepairSession @options -Launch -StartApp { throw '模拟启动器不可用' }
Assert-Test ($result.Status -eq 'LaunchFailed' -and $result.RuntimeStatus -eq 'Healthy' -and $result.ExitCode -eq 1) '启动失败保留健康运行时结果'
$logged = Get-Content -LiteralPath $result.LogPath -Raw | ConvertFrom-Json
Assert-Test ($logged.LaunchStatus -eq 'Failed' -and $logged.Error -eq '模拟启动器不可用' -and $logged.FailureStage -eq 'Launch') '日志在启动结束后记录真实失败阶段和原因'
$result = Invoke-RepairSession -StateRoot (Join-Path $fixture.Base 'missing-state') -GetPackage { $null }
Assert-Test ($result.Status -eq 'Failed' -and $result.Stage -eq 'DetectPackage' -and $result.Message -like '*请先安装*') '未安装应用返回可操作的失败说明'
$newFixture = New-TestFixture
$newPackage = $newFixture.Package
$newOptions = @{ StateRoot = $newFixture.StateRoot; RuntimeRoot = $newFixture.RuntimeRoot; GetPackage = { $newPackage }.GetNewClosure(); GetProcesses = { @() } }
$result = Invoke-RepairSession @newOptions -CheckOnly -Launch
Assert-Test ($result.Status -eq 'NeedsRepair' -and $result.ExitCode -eq 2 -and !(Test-Path -LiteralPath $newFixture.RuntimeRoot)) '只检查模式保留退出码且不部署或启动'
$newOptions.GetProcesses = { [pscustomobject]@{ ExecutablePath = 'C:\Program Files\WindowsApps\OpenAI.Codex_test\app\ChatGPT.exe' } }
$result = Invoke-RepairSession @newOptions
Assert-Test ($result.Status -eq 'Failed' -and $result.Stage -eq 'Preflight' -and $result.Message -like '*托盘*') '需修复且应用仍运行时提示退出并重试'
Assert-Test (!(Test-Path -LiteralPath $newFixture.RuntimeRoot)) '退出检查失败时不替换运行时'
[void][IO.Directory]::CreateDirectory($newFixture.StateRoot)
$lock = [IO.File]::Open((Join-Path $newFixture.StateRoot 'repair.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try { $result = Invoke-RepairSession @newOptions } finally { $lock.Dispose() }
Assert-Test ($result.Status -eq 'Busy' -and $result.Message -like '*已有修复任务*') '并发任务返回明确的占用说明'
$counter = @{ Count = 0 }
$newOptions.GetProcesses = { @() }
$newOptions.GetPackage = {
    $counter.Count++
    if ($counter.Count -eq 1) { return $newPackage }
    return [pscustomobject]@{ PackageFullName = 'different-package' }
}.GetNewClosure()
$result = Invoke-RepairSession @newOptions
Assert-Test ($result.Status -eq 'Failed' -and $result.Message -like '*升级*') '检测到升级时提示稍后重试'
Write-Output "执行编排测试通过：$script:AssertionCount 项断言"
