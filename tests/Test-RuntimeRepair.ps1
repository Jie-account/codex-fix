$ErrorActionPreference='Stop'
$base=Join-Path (Join-Path $PSScriptRoot '..\work') ('fixture-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($base)
$source=Join-Path $base 'source'
$root=Join-Path $base 'runtimes'
$receipt=Join-Path $base 'state\verified.json'
[void][IO.Directory]::CreateDirectory((Join-Path $source 'bin\node_modules\example'))
'{"platform":"windows","node_path":"bin/node.exe","node_repl_path":"bin/node_repl.exe"}' | Set-Content -LiteralPath (Join-Path $source 'manifest.json') -Encoding UTF8
'node-v1' | Set-Content -LiteralPath (Join-Path $source 'bin\node.exe')
'repl-v1' | Set-Content -LiteralPath (Join-Path $source 'bin\node_repl.exe')
'AAAA' | Set-Content -LiteralPath (Join-Path $source 'bin\node_modules\example\index.js')
Import-Module (Join-Path $PSScriptRoot '..\RuntimeRepair.psm1') -Force
function Assert($condition,$message) { if (!$condition) { throw $message }; Write-Output "PASS $message" }
$r=Invoke-VerifiedRuntime -Source $source -RuntimeRoot $root -ReceiptFile $receipt -CheckOnly
Assert ($r.Status -eq 'NeedsRepair' -and !(Test-Path $root)) '仅检查缺失目标，不创建运行时'
$r=Invoke-VerifiedRuntime -Source $source -RuntimeRoot $root -ReceiptFile $receipt
Assert ($r.Status -eq 'Repaired' -and $r.FileCount -eq 4) '缺失运行时自动部署'
$id=$r.RuntimeId; $target=$r.Target
$r=Invoke-VerifiedRuntime -Source $source -RuntimeRoot $root -ReceiptFile $receipt
Assert ($r.Status -eq 'Healthy') '重复运行保持健康状态'
$moduleFile=Join-Path $target 'bin\node_modules\example\index.js'
'BBBB' | Set-Content -LiteralPath $moduleFile
$r=Invoke-VerifiedRuntime -Source $source -RuntimeRoot $root -ReceiptFile $receipt -CheckOnly -VerifyAll
Assert ($r.Status -eq 'NeedsRepair') '完整校验发现等长内容损坏'
$r=Invoke-VerifiedRuntime -Source $source -RuntimeRoot $root -ReceiptFile $receipt
Assert ($r.Status -eq 'Repaired' -and (Test-Path $r.Backup)) '损坏目标备份后恢复'
Remove-Item -LiteralPath (Join-Path $target 'bin\node_modules\example\index.js')
$blocked=$false
try { Invoke-VerifiedRuntime -Source $source -RuntimeRoot $root -ReceiptFile $receipt -BeforeDeploy { throw '模拟应用正在运行' } | Out-Null }
catch { $blocked=$_.Exception.Message -eq '模拟应用正在运行' }
Assert $blocked '修复前检查可阻止正在运行时替换'
$r=Invoke-VerifiedRuntime -Source $source -RuntimeRoot $root -ReceiptFile $receipt
Assert ($r.Status -eq 'Repaired') '缺文件自动恢复'
'node-v2' | Set-Content -LiteralPath (Join-Path $source 'bin\node.exe')
$r=Invoke-VerifiedRuntime -Source $source -RuntimeRoot $root -ReceiptFile $receipt
Assert ($r.RuntimeId -ne $id -and $r.Status -eq 'Repaired') '核心文件变化生成新运行时 ID'
Assert (Test-Path $target) '保留旧版本目录'
'EXTRA' | Set-Content -LiteralPath (Join-Path $r.Target 'extra.txt')
$r=Invoke-VerifiedRuntime -Source $source -RuntimeRoot $root -ReceiptFile $receipt -CheckOnly
Assert ($r.Status -eq 'NeedsRepair') '发现额外文件'
$beforeSource=(Get-FileHash -LiteralPath (Join-Path $source 'manifest.json')).Hash
'{"platform":"linux"}' | Set-Content -LiteralPath (Join-Path $source 'manifest.json')
$unsupported=$false
try { Invoke-VerifiedRuntime -Source $source -RuntimeRoot $root | Out-Null } catch { $unsupported=$_.Exception.Message -like '*结构*' }
Assert $unsupported '不兼容清单清楚报错'
