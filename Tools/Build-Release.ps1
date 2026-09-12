param(
 [string]$Version='0.1.0-preview.1',
 [string]$Owner='',
 [string]$Repository='WindowsCare',
 [string]$OutputDirectory=(Join-Path (Split-Path $PSScriptRoot -Parent) 'dist')
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
if($Version -notmatch '^\d+\.\d+\.\d+(?:-[a-zA-Z0-9.]+)?$'){throw 'Invalid version'}
if($Owner -and ($Owner -notmatch '^[A-Za-z0-9-]+$' -or $Repository -notmatch '^[A-Za-z0-9_.-]+$')){throw 'Invalid GitHub owner/repository'}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$out=[IO.Path]::GetFullPath($OutputDirectory)
$archive=Join-Path $out ('WindowsCare-'+$Version+'.zip')
if(Test-Path -LiteralPath $archive){throw 'Release already exists. Use a new version or a new output directory; never replace published assets.'}
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$z=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
try {
    $files=@(Get-ChildItem -LiteralPath $root -File | Where-Object Extension -in @('.ps1','.cmd','.md','.json'))
    foreach($dir in @('Modules','UI','Tests','Tools')){$files+=@(Get-ChildItem -LiteralPath (Join-Path $root $dir) -File -Recurse)}
    foreach($file in $files){$relative=$file.FullName.Substring($root.Length+1).Replace('\','/');[void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($z,$file.FullName,$relative,[IO.Compression.CompressionLevel]::Optimal)}
} finally {$z.Dispose()}
$hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
($hash+'  '+[IO.Path]::GetFileName($archive)) | Set-Content -LiteralPath (Join-Path $out 'SHA256SUMS.txt') -Encoding ASCII
@{Version=$Version;File=[IO.Path]::GetFileName($archive);SHA256=$hash;BuiltAt=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $out 'release.json') -Encoding UTF8
if($Owner){
    $url="https://github.com/$Owner/$Repository/releases/download/v$Version/WindowsCare-$Version.zip"
    # Trust anchor is the SHA256 embedded in this reviewed command, not a remote checksum fetched alongside the ZIP.
    # ZIP content is authenticated before extraction. Use a unique directory to avoid cache poisoning/overwrites.
    $command='& { $ErrorActionPreference=''Stop''; [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; $d=Join-Path $env:LOCALAPPDATA (''WindowsCare\Downloads\''+[guid]::NewGuid().ToString(''N'')); [void][IO.Directory]::CreateDirectory($d); $z=Join-Path $d ''app.zip''; Invoke-WebRequest -UseBasicParsing -Uri ''__URL__'' -OutFile $z; if ((Get-FileHash -LiteralPath $z -Algorithm SHA256).Hash -ne ''__HASH__'') { throw ''Package verification failed'' }; Expand-Archive -LiteralPath $z -DestinationPath (Join-Path $d ''app''); & (Join-Path $env:windir ''System32\WindowsPowerShell\v1.0\powershell.exe'') -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $d ''app\WindowsCare.ps1'') }'
    $command=$command.Replace('__URL__',$url).Replace('__HASH__',$hash)
    $command | Set-Content -LiteralPath (Join-Path $out 'Run-WindowsCare.txt') -Encoding UTF8
    "# WindowsCare $Version`n`nPreview build; see README for test coverage and limitations.`n`nSHA256: $hash`n`nCopy the single line in Run-WindowsCare.txt into Windows PowerShell on x64 Windows. It checks the pinned package hash before execution. Do not use an untrusted copy of that command.`n`nThis release is unsigned. A checksum verifies the package against the reviewed command, not the publisher identity. Enterprise policy may prevent execution." | Set-Content -LiteralPath (Join-Path $out 'release-notes.md') -Encoding UTF8
}
Write-Output ('Archive: '+$archive)
Write-Output ('SHA256: '+$hash)
