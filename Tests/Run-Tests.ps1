param([string]$WorkDirectory=(Join-Path $env:TEMP ('WindowsCare-tests-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
foreach($m in @('Core','Catalog','Files','Install')){. (Join-Path $root ('Modules\'+$m+'.ps1'))}
[void][IO.Directory]::CreateDirectory($WorkDirectory)
$script:Passed=0
Add-Type -Path (Join-Path $root 'Modules\Recycle.cs')
function Assert-True([bool]$Condition,[string]$Name){if(-not $Condition){throw ('TEST FAILED: '+$Name)};$script:Passed++;Write-Output ('PASS '+$Name)}
function Assert-Throws([scriptblock]$Body,[string]$Name){$threw=$false;try{& $Body | Out-Null}catch{$threw=$true};Assert-True $threw $Name}
function New-TestZip([string]$Path,[string[]]$Names){
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $z=[IO.Compression.ZipFile]::Open($Path,[IO.Compression.ZipArchiveMode]::Create)
    try{foreach($n in $Names){$e=$z.CreateEntry($n);$s=New-Object IO.StreamWriter ($e.Open());try{$s.Write('fixture')}finally{$s.Dispose()}}}finally{$z.Dispose()}
}
foreach($f in (Get-ChildItem -LiteralPath $root -Filter '*.ps1' -Recurse)){
    $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)
    Assert-True (@($errors).Count -eq 0) ('PowerShell parser '+$f.Name)
    $bytes=[IO.File]::ReadAllBytes($f.FullName)
    Assert-True ($bytes.Length -gt 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) ('UTF8 BOM '+$f.Name)
}
Assert-True (Test-Inside 'C:\Data\File.txt' 'C:\Data') 'path inside'
Assert-True (-not (Test-Inside 'C:\Database\File.txt' 'C:\Data')) 'prefix collision blocked'
Assert-True (-not (Test-Inside 'C:\Data\..\Other\File.txt' 'C:\Data')) 'canonical traversal blocked'
Assert-Throws {Assert-CleanupPath $env:windir} 'Windows folder protected'
Assert-Throws {Assert-CleanupPath $root} 'program folder protected'
Assert-Throws {Assert-RegularPath '\\server\share\file.txt'} 'UNC rejected'
Assert-Throws {Assert-RegularPath 'C:\file.txt:payload'} 'alternate data stream rejected'
$fixtures=Join-Path $WorkDirectory 'files';[void][IO.Directory]::CreateDirectory($fixtures)
[IO.File]::WriteAllText((Join-Path $fixtures 'a.txt'),'same content')
[IO.File]::WriteAllText((Join-Path $fixtures 'b.txt'),'same content')
[IO.File]::WriteAllText((Join-Path $fixtures 'c.txt'),'different contents')
$large=@(Get-ScanFiles $fixtures 0);Assert-True ($large.Count -eq 3) 'file scan results'
Assert-True (@($large | Where-Object Selected).Count -eq 0) 'nothing selected by default'
$dupes=@(Find-Duplicates $fixtures 0);Assert-True ($dupes.Count -eq 2) 'duplicate hash groups'
Assert-True ($dupes[0].Hash -eq $dupes[1].Hash) 'duplicate contents verified'
Assert-DuplicateKeepers @($dupes[0]) @($dupes[1]); Assert-True $true 'one verified duplicate retained'
Assert-Throws {Assert-DuplicateKeepers $dupes @()} 'all duplicates cannot be removed'
Assert-Throws {Assert-DuplicateKeepers $dupes $dupes} 'selected duplicate cannot be its own keeper'
[IO.File]::AppendAllText((Join-Path $fixtures 'a.txt'),' changed')
Assert-Throws {Assert-DuplicateKeepers @($dupes[1]) @($dupes[0])} 'changed keeper rejected'
Assert-Throws {Move-SelectedToRecycle @($large | Where-Object Name -eq 'a.txt')} 'changed file rejected before delete'
Assert-True (Test-Path -LiteralPath (Join-Path $fixtures 'a.txt')) 'changed file remains present'
Assert-Throws {Get-ScanFiles ([IO.Path]::GetPathRoot($fixtures))} 'drive-root scan rejected'
$safe=Join-Path $WorkDirectory 'safe.zip';New-TestZip $safe @('nested/a.txt','b.txt')
$expanded=Join-Path $WorkDirectory 'safe-expanded';Expand-SafeZip $safe $expanded
Assert-True (Test-Path -LiteralPath (Join-Path $expanded 'nested\a.txt')) 'normal zip extracted'
$idx=0
foreach($name in @('../escape.txt','/rooted.txt','C:/absolute.txt','file.txt:stream','nested/../../escape.txt','CON.txt','folder./file.txt')){
    $idx++;$zip=Join-Path $WorkDirectory ('bad-'+$idx+'.zip');New-TestZip $zip @($name)
    Assert-Throws {Expand-SafeZip $zip (Join-Path $WorkDirectory ('bad-out-'+$idx))} ('zip rejected '+$name)
}
$dupZip=Join-Path $WorkDirectory 'duplicate.zip';New-TestZip $dupZip @('a.txt','A.txt')
Assert-Throws {Expand-SafeZip $dupZip (Join-Path $WorkDirectory 'duplicate-out')} 'zip case collision rejected'
Assert-Throws {Expand-SafeZip $safe (Join-Path $WorkDirectory 'size-out') 1} 'zip expansion size limit'
foreach($name in $script:OfficeProducts.Keys){
    $opts=@{Product=$name;Bits='64';Language='en-us';Apps=@('Word','Excel')}
    $path=Join-Path $WorkDirectory ([guid]::NewGuid().ToString('N')+'.xml');[void](New-OfficeConfiguration $opts $path);$x=[xml](Get-Content -LiteralPath $path -Raw)
    Assert-True ($x.Configuration.Add.Product.ID -eq $script:OfficeProducts[$name].Id) ('Office product '+$name)
    Assert-True ('Word' -notin @($x.Configuration.Add.Product.ExcludeApp | ForEach-Object ID)) 'selected Word retained'
    Assert-True ('PowerPoint' -in @($x.Configuration.Add.Product.ExcludeApp | ForEach-Object ID)) 'unselected PowerPoint excluded'
    Assert-True ($x.Configuration.Display.AcceptEULA -eq 'FALSE') 'Office interactive EULA'
}
Assert-Throws {New-OfficeConfiguration @{Product='Injected';Bits='64';Language='en-us';Apps=@('Word')} (Join-Path $WorkDirectory 'bad.xml')} 'unknown Office product rejected'
Assert-Throws {New-OfficeConfiguration @{Product='Office 2024 Home & Business';Bits='64';Language='en-us';Apps=@('Access')} (Join-Path $WorkDirectory 'bad.xml')} 'unavailable Office component rejected'
Assert-Throws {New-OfficeConfiguration @{Product='Microsoft 365 Enterprise';Bits='64';Language='en-us';Apps=@()} (Join-Path $WorkDirectory 'bad.xml')} 'empty Office selection rejected'
Assert-True ((ConvertTo-NativeArgument 'C:\folder with spaces\') -eq '"C:\folder with spaces\\"') 'trailing slash escaping'
Assert-True ((ConvertTo-NativeArgument 'a"b') -eq '"a\"b"') 'embedded quote escaping'
Assert-Throws {ConvertTo-NativeArgument "a`nb"} 'newline argument rejected'
$script:JobDir=Join-Path $WorkDirectory 'cancel-job';[void][IO.Directory]::CreateDirectory($script:JobDir);[IO.File]::WriteAllText((Join-Path $script:JobDir 'cancel'),'yes')
Assert-Throws {Test-Cancel} 'safe cancellation token'
$script:JobDir=$null
$testRows=@((New-Row '<script>alert(1)</script>' '"&<>'))
Export-CareReport $WorkDirectory @{Action='test'} $testRows 'Completed'
$html=Get-Content -LiteralPath (Join-Path $WorkDirectory 'report.html') -Raw
Assert-True (-not $html.Contains('<script>alert')) 'HTML report escapes user content'
Assert-Throws {[WindowsCare.Recycle]::FileOnly((Join-Path $WorkDirectory 'does-not-exist.txt'))} 'recycle rejects missing file without shell operation'
Assert-True (Test-Path -LiteralPath (Join-Path $WorkDirectory 'report.csv')) 'CSV report created'
$native=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
foreach($action in @('LargeFiles','OfficeConfig','SystemInfo')){
    $job=Join-Path $WorkDirectory ('worker '+$action);[void][IO.Directory]::CreateDirectory($job)
    $options=switch($action){LargeFiles {@{Root=$fixtures;MinBytes=0}} OfficeConfig {@{Product='Microsoft 365 Enterprise';Bits='64';Language='en-us';Apps=@('Word');SetupPath=''}} default {@{}}}
    Save-Json @{Action=$action;Confirmed=$false;AllowNoRestore=$false;Rows=@();Options=$options} (Join-Path $job 'request.json')
    [void](Invoke-Native $native @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'Worker.ps1'),'-JobDirectory',$job))
    $state=Get-Content -LiteralPath (Join-Path $job 'status.json') -Raw | ConvertFrom-Json
    Assert-True ($state.State -eq 'Completed' -or ($action -eq 'SystemInfo' -and $state.State -eq 'Warning')) ('worker end-to-end '+$action)
    $result=@(Get-Content -LiteralPath (Join-Path $job 'result.json') -Raw | ConvertFrom-Json)
    Assert-True ($result.Count -gt 0) ('worker result '+$action)
    Assert-True (Test-Path -LiteralPath (Join-Path $job 'report.html')) ('worker report '+$action)
}
& (Join-Path $root 'WindowsCare.ps1') -SelfTest
Write-Output ('ALL PASSED: '+$script:Passed+' assertions. No system repair, install or delete was executed.')
