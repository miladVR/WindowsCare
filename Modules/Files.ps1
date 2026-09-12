function Test-Inside([string]$Path, [string]$Root) {
    $p=[IO.Path]::GetFullPath($Path).TrimEnd('\'); $r=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    return ($p.Equals($r,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r+'\',[StringComparison]::OrdinalIgnoreCase))
}
function Assert-RegularPath([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\') -or $Path.Substring(2).Contains(':')) { throw 'فقط مسیر محلی معمولی پذیرفته است.' }
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    $cursor=$item
    while ($cursor) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('پیوند، Junction یا فایل ابری پذیرفته نیست: '+$Path) }
        if ($cursor -is [IO.DirectoryInfo]) { $cursor=$cursor.Parent } else { $cursor=$cursor.Directory }
    }
    return $item
}
function Assert-CleanupPath([string]$Path) {
    $item=Assert-RegularPath $Path
    $protected=@($env:windir,$env:ProgramFiles,${env:ProgramFiles(x86)},$env:ProgramData,$script:AppRoot,(Join-Path $env:LOCALAPPDATA 'WindowsCare')) | Where-Object { $_ }
    foreach ($r in $protected) { if (Test-Inside $item.FullName $r) { throw ('این مسیر برای پاکسازی محافظت شده است: '+$item.FullName) } }
    if ($item.FullName -match '(?i)\\(\$Recycle\.Bin|System Volume Information|Recovery)(\\|$)') { throw 'مسیر محافظت‌شده است.' }
    if (($item.Attributes -band [IO.FileAttributes]::System) -ne 0) { throw 'فایل سیستمی از پاکسازی مستثنا است.' }
    return $item
}
function Get-ScanFiles([string]$Root, [long]$MinBytes=0, [datetime]$OlderThan=[datetime]::MaxValue) {
    $start=Assert-CleanupPath $Root
    if (-not $start.PSIsContainer) { throw 'پوشه انتخاب کنید.' }
    if ($start.FullName.TrimEnd('\') -eq $start.PSDrive.Root.TrimEnd('\')) { throw 'برای اسکن، پوشه مشخص انتخاب کنید؛ کل درایو پذیرفته نیست.' }
    $stack=New-Object 'Collections.Generic.Stack[string]'; $stack.Push($start.FullName)
    $found=New-Object 'Collections.Generic.List[object]'; $skipped=0; $seen=0
    while ($stack.Count) {
        Test-Cancel; $dir=$stack.Pop()
        try { $children=@(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop) } catch { $skipped++; continue }
        foreach ($f in $children) {
            $seen++
            if ($seen % 250 -eq 0) { Test-Cancel }
            if (($f.Attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::System)) -ne 0) { $skipped++; continue }
            if ($f.PSIsContainer) {
                try { [void](Assert-CleanupPath $f.FullName); $stack.Push($f.FullName) } catch { $skipped++ }
            } elseif ($f.Length -ge $MinBytes -and $f.LastWriteTimeUtc -lt $OlderThan) {
                try { [void](Assert-CleanupPath $f.FullName) } catch { $skipped++; continue }
                $found.Add([pscustomobject]@{Selected=$false; Name=$f.Name; Detail=('{0:N2} MB | {1}' -f ($f.Length/1MB),$f.LastWriteTime); Path=$f.FullName; Bytes=$f.Length; ModifiedUtc=$f.LastWriteTimeUtc.ToString('o'); Hash=''; Group=''})
                if ($found.Count -ge 20000) { Write-CareWarning 'سقف ۲۰ هزار نتیجه رسید؛ پوشه محدودتری انتخاب کنید.'; return $found.ToArray() }
            }
        }
        if ($seen % 1000 -lt 100) { Set-CareStatus 'Running' ('بررسی فایل‌ها: '+$seen+' | نتیجه: '+$found.Count) }
    }
    if ($skipped) { Write-CareWarning ("$skipped مسیر محافظت‌شده، ابری یا غیرقابل‌خواندن کنار گذاشته شد.") }
    $found.ToArray()
}
function Find-Duplicates([string]$Root, [long]$MinBytes) {
    $files=@(Get-ScanFiles $Root $MinBytes)
    $answer=New-Object 'Collections.Generic.List[object]'; $groupNumber=0
    foreach ($sizeGroup in ($files | Group-Object Bytes | Where-Object Count -gt 1)) {
        foreach ($f in $sizeGroup.Group) {
            Test-Cancel
            try { $f.Hash=(Get-FileHash -LiteralPath $f.Path -Algorithm SHA256 -ErrorAction Stop).Hash }
            catch { Write-CareWarning ('فایل قابل هش نبود: '+$f.Path) }
        }
        foreach ($group in ($sizeGroup.Group | Where-Object Hash | Group-Object Hash | Where-Object Count -gt 1)) {
            $groupNumber++
            foreach ($f in $group.Group) { $f.Group=[string]$groupNumber; $f.Detail=('گروه '+$groupNumber+' | '+$f.Detail); $answer.Add($f) }
        }
    }
    $answer.ToArray()
}
function Assert-DuplicateKeepers($Rows, $Keepers) {
    $selectedPaths=@($Rows | ForEach-Object { [IO.Path]::GetFullPath([string]$_.Path) })
    foreach ($g in ($Rows | Group-Object Hash)) {
        if ($g.Name -notmatch '^[A-Fa-f0-9]{64}$') { throw 'هش گروه تکراری معتبر نیست.' }
        $verified=$false
        foreach ($k in @($Keepers | Where-Object Hash -eq $g.Name)) {
            if ([IO.Path]::GetFullPath([string]$k.Path) -in $selectedPaths) { continue }
            try {
                $f=Assert-CleanupPath ([string]$k.Path)
                if (-not $f.PSIsContainer -and (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash -eq $g.Name) { $verified=$true; break }
            } catch {}
        }
        if (-not $verified) { throw 'حداقل یک نسخه تأییدشده از هر گروه تکراری باید خارج از انتخاب حذف باقی بماند.' }
    }
}
function Move-SelectedToRecycle($Rows, $Keepers=@(), [bool]$DuplicateScan=$false) {
    if (@($Rows).Count -eq 0 -or @($Rows).Count -gt 20000) { throw 'تعداد فایل انتخابی نامعتبر است.' }
    if ($DuplicateScan) { Assert-DuplicateKeepers $Rows $Keepers }
    # Validate the ENTIRE set before touching a file. Never delete the last known duplicate.
    foreach ($r in $Rows) {
        $f=Assert-CleanupPath ([string]$r.Path)
        if ($f.PSIsContainer -or $f.Length -ne [long]$r.Bytes -or $f.LastWriteTimeUtc.ToString('o') -ne [string]$r.ModifiedUtc) { throw ('فایل از زمان اسکن تغییر کرده است؛ دوباره اسکن کنید: '+$r.Path) }
        if ($r.Hash -and (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash -ne $r.Hash) { throw 'محتوای فایل تکراری تغییر کرده است.' }
    }
    foreach ($r in $Rows) {
        Test-Cancel
        if ($DuplicateScan) { Assert-DuplicateKeepers @($r) $Keepers }
        $f=Assert-CleanupPath ([string]$r.Path)
        if ($f.Length -ne [long]$r.Bytes -or $f.LastWriteTimeUtc.ToString('o') -ne [string]$r.ModifiedUtc) { throw 'فایل پس از پیش‌نمایش تغییر کرده است.' }
        # Refuse potential hard links (a single file can have multiple names).
        $links=Invoke-Native (Join-Path $env:windir 'System32\fsutil.exe') @('hardlink','list',$f.FullName)
        if (@($links.Output -split '\r?\n' | Where-Object { $_.Trim().StartsWith('\') }).Count -gt 1) { throw ('فایل دارای Hard Link است: '+$f.FullName) }
        if (-not ('WindowsCare.Recycle' -as [type])) { Add-Type -Path (Join-Path $script:AppRoot 'Modules\Recycle.cs') }
        [WindowsCare.Recycle]::FileOnly($f.FullName)
        if (Test-Path -LiteralPath $f.FullName) { throw ('انتقال تأیید نشد: '+$f.FullName) }
        Write-CareLog ('RECYCLED: '+$f.FullName)
        New-Row $f.Name 'به سطل بازیافت منتقل شد.' $f.FullName
    }
}
function Backup-Drivers {
    $dest=Join-Path $script:JobDir 'drivers'; [void][IO.Directory]::CreateDirectory($dest)
    [void](Invoke-Native (Join-Path $env:windir 'System32\pnputil.exe') @('/export-driver','*',$dest))
    $files=@(Get-ChildItem -LiteralPath $dest -Recurse -File)
    if (-not @($files | Where-Object Extension -eq '.inf').Count) { throw 'بسته درایور قابل‌صدور یافت نشد.' }
    $records=@($files | ForEach-Object { @{Path=$_.FullName.Substring($dest.Length+1); Bytes=$_.Length; SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash} })
    Save-Json @{Format=1; Created=(Get-Date).ToString('o'); Architecture=$env:PROCESSOR_ARCHITECTURE; Files=$records} (Join-Path $dest 'manifest.json')
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    $archive=Join-Path $script:JobDir 'WindowsCare-Drivers.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($dest,$archive)
    New-Row 'پشتیبان درایورها' ('SHA256: '+(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash) $archive
}
function Read-DriverArchive([string]$Archive) {
    $file=Assert-RegularPath $Archive
    if ($file.PSIsContainer -or $file.Extension -ne '.zip') { throw 'فایل ZIP پشتیبان WindowsCare را انتخاب کنید.' }
    $dest=Join-Path $script:JobDir ('driver-import-'+[guid]::NewGuid().ToString('N'))
    Expand-SafeZip $file.FullName $dest
    $manifestPath=Join-Path $dest 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'manifest.json در بسته موجود نیست؛ از خروجی WindowsCare استفاده کنید.' }
    $m=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($m.Format -ne 1 -or $m.Architecture -ne $env:PROCESSOR_ARCHITECTURE) { throw 'نسخه بسته یا معماری درایورها با این دستگاه سازگار نیست.' }
    $expected=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in $m.Files) {
        Test-Cancel
        $p=[IO.Path]::GetFullPath((Join-Path $dest ([string]$f.Path)))
        if (-not (Test-Inside $p $dest) -or [string]$f.Path -match ':' -or -not $expected.Add($p)) { throw 'مسیر نامعتبر در فهرست بسته.' }
        $item=Assert-RegularPath $p
        if ($item.PSIsContainer -or $item.Length -ne [long]$f.Bytes -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne $f.SHA256) { throw 'صحت محتوای بسته درایورها تأیید نشد.' }
    }
    foreach ($f in (Get-ChildItem -LiteralPath $dest -Recurse -File)) { if ($f.FullName -ne $manifestPath -and -not $expected.Contains($f.FullName)) { throw 'فایل ثبت‌نشده در بسته وجود دارد.' } }
    $infs=@(Get-ChildItem -LiteralPath $dest -Recurse -Filter '*.inf' -File)
    if (-not $infs.Count) { throw 'فایل INF یافت نشد.' }
    return [pscustomobject]@{Root=$dest; Infs=$infs; ArchiveHash=(Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash}
}
function Install-DriverArchive([string]$Archive, [string]$ExpectedHash) {
    if ($ExpectedHash -notmatch '^[A-Fa-f0-9]{64}$' -or (Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $ExpectedHash) { throw 'ابتدا بسته را بررسی کنید؛ بسته پس از بررسی نباید تغییر کند.' }
    $bundle=Read-DriverArchive $Archive
    foreach ($f in $bundle.Infs) {
        Test-Cancel
        $r=Invoke-Native (Join-Path $env:windir 'System32\pnputil.exe') @('/add-driver',$f.FullName,'/install') @(0,3010)
        New-Row $f.Name 'پردازش توسط PnPUtil؛ نصب فقط برای سخت‌افزار منطبق و مطابق رتبه‌بندی ویندوز است. متن گزارش را بررسی کنید.' $f.FullName
    }
}
