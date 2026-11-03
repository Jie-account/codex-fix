. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$checker = Join-Path $PSScriptRoot '..\tools\Test-PublicationPrivacy.ps1'
$fixture = Join-Path (Join-Path $PSScriptRoot '..\work') ('privacy-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
'Public test document.' | Set-Content -LiteralPath (Join-Path $fixture 'README.md')
$result = & $checker -RepositoryRoot $fixture
Assert-Test $result.Passed '干净文件通过公开检查'
$samples = [ordered]@{
    Email = ('private' + '@' + 'example.test')
    Conversation = ('chatgpt-conver' + 'sation://' + [guid]::NewGuid().ToString())
    UserPath = ('C:' + '\Users\' + 'example\file.txt')
    Workspace = ('D:' + '\workspace\' + 'example')
    Token = ('gh' + 'p_' + ('x' * 36))
}
foreach ($sample in $samples.GetEnumerator()) {
    $path = Join-Path $fixture 'private.txt'
    $sample.Value | Set-Content -LiteralPath $path
    $blocked = $false
    try { & $checker -RepositoryRoot $fixture | Out-Null } catch { $blocked = $_.Exception.Message -like '*检查未通过*' }
    Assert-Test $blocked ("检测合成的私人信息：$($sample.Key)")
    Remove-Item -LiteralPath $path
}
git -C $fixture init -b main | Out-Null
git -C $fixture config user.name 'codex-fix contributors'
git -C $fixture config user.email 'noreply@users.noreply.github.com'
git -C $fixture add README.md
git -C $fixture commit -m 'Public fixture' | Out-Null
$result = & $checker -RepositoryRoot $fixture -IncludeHistory
Assert-Test $result.Passed '匿名身份和干净历史通过检查'
$samples.Email | Set-Content -LiteralPath (Join-Path $fixture 'private.txt')
git -C $fixture add private.txt
git -C $fixture commit -m 'Synthetic private fixture' | Out-Null
git -C $fixture rm private.txt | Out-Null
git -C $fixture commit -m 'Remove fixture' | Out-Null
$blocked = $false
try { & $checker -RepositoryRoot $fixture -IncludeHistory | Out-Null } catch { $blocked = $_.Exception.Message -like '*检查未通过*' }
Assert-Test $blocked '当前文件删除后仍能检测历史中的私人信息'
$archiveRoot = Join-Path $fixture 'work\archive-data'
[void][IO.Directory]::CreateDirectory($archiveRoot)
$samples.UserPath | Set-Content -LiteralPath (Join-Path $archiveRoot 'private.txt')
$archive = Join-Path $fixture 'work\test.zip'
Compress-Archive -LiteralPath $archiveRoot -DestinationPath $archive
$blocked = $false
try { & $checker -RepositoryRoot $fixture -Archive $archive | Out-Null } catch { $blocked = $_.Exception.Message -like '*检查未通过*' }
Assert-Test $blocked '解压发布包后检测内部私人信息'
Write-Output "公开内容检查测试通过：$script:AssertionCount 项断言"
