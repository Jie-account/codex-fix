$ErrorActionPreference = 'Stop'
$script:AssertionCount = 0
function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (!$Condition) { throw $Message }
    $script:AssertionCount++
    Write-Output "PASS $Message"
}
function New-TestFixture {
    $base = Join-Path (Join-Path $PSScriptRoot '..\work') ('session-' + [guid]::NewGuid().ToString('N'))
    $install = Join-Path $base 'install'
    $source = Join-Path $install 'app\resources\cua_node'
    [void][IO.Directory]::CreateDirectory((Join-Path $source 'bin\node_modules\example'))
    '{"platform":"windows","node_path":"bin/node.exe","node_repl_path":"bin/node_repl.exe"}' |
        Set-Content -LiteralPath (Join-Path $source 'manifest.json') -Encoding UTF8
    'node-v1' | Set-Content -LiteralPath (Join-Path $source 'bin\node.exe')
    'repl-v1' | Set-Content -LiteralPath (Join-Path $source 'bin\node_repl.exe')
    'AAAA' | Set-Content -LiteralPath (Join-Path $source 'bin\node_modules\example\index.js')
    [pscustomobject]@{
        Base = $base; Source = $source; RuntimeRoot = (Join-Path $base 'runtimes'); StateRoot = (Join-Path $base 'state')
        Package = [pscustomobject]@{ Version = '1.0.0.0'; InstallLocation = $install; PackageFullName = 'OpenAI.Codex_test'; PackageFamilyName = 'OpenAI.Codex_test' }
    }
}
