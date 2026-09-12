# WindowsCare core. Compatible with Windows PowerShell 5.1.
Set-StrictMode -Version 2
$script:AppRoot = Split-Path $PSScriptRoot -Parent
$script:JobDir = $null
$script:HadWarning = $false
function Write-CareLog([string]$Message) {
    if ($script:JobDir) { Add-Content -LiteralPath (Join-Path $script:JobDir 'operation.log') -Value ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8 }
}
function Write-CareWarning([string]$Message) { $script:HadWarning = $true; Write-CareLog ('WARNING: ' + $Message) }
function Test-Cancel {
    if ($script:JobDir -and (Test-Path -LiteralPath (Join-Path $script:JobDir 'cancel'))) { throw [OperationCanceledException]::new('توقف در مرز امن عملیات انجام شد.') }
}
function Save-Json($Value, [string]$Path) {
    $temp = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    ConvertTo-Json -InputObject $Value -Depth 14 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}
function Set-CareStatus([string]$State, [string]$Message) {
    if ($script:JobDir) { Save-Json @{ State=$State; Message=$Message; Time=(Get-Date).ToString('o') } (Join-Path $script:JobDir 'status.json') }
    Write-CareLog $Message
}
function New-Row([string]$Name, [string]$Detail, [string]$Path = '') {
    [pscustomobject]@{ Selected=$false; Name=$Name; Detail=$Detail; Path=$Path }
}
function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'این عملیات به دسترسی Administrator نیاز دارد.' }
}
function Test-RebootPending {
    $paths = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
    foreach ($p in $paths) { if (Test-Path $p) { return $true } }
    $v = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    return ($null -ne $v)
}
function Invoke-Preflight([bool]$RequireRestore, [bool]$AllowNoRestore) {
    Assert-Admin
    if (Test-RebootPending) { throw 'راه‌اندازی مجدد معلق است. ابتدا ویندوز را Restart کنید؛ سپس عملیات را دوباره انتخاب کنید.' }
    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($env:SystemDrive)'" -ErrorAction Stop
    if ($drive.FreeSpace -lt 5GB) { throw 'پیش از این عملیات حداقل ۵ گیگابایت فضای آزاد روی درایو ویندوز لازم است.' }
    Add-Type -AssemblyName System.Windows.Forms
    if ([Windows.Forms.SystemInformation]::PowerStatus.PowerLineStatus -eq 'Offline') { throw 'لپ‌تاپ را به برق متصل کنید و دوباره تلاش کنید.' }
    if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        try { $b = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop; Write-CareLog ('BitLocker protection: ' + $b.ProtectionStatus) }
        catch { Write-CareWarning 'وضعیت BitLocker قابل خواندن نبود؛ هیچ تغییری در رمزگذاری انجام نشد.' }
    }
    if ($RequireRestore) {
        try {
            $desc = 'WindowsCare ' + (Get-Date -Format 'yyyyMMdd-HHmmss')
            Checkpoint-Computer -Description $desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction Stop
            $point = Get-ComputerRestorePoint -ErrorAction Stop | Where-Object Description -eq $desc | Select-Object -First 1
            if (-not $point) { throw 'ساخت نقطه بازیابی تأیید نشد.' }
            Write-CareLog ('Restore point created: ' + $point.SequenceNumber)
        } catch {
            if (-not $AllowNoRestore) { throw ('نقطه بازیابی ساخته نشد: ' + $_.Exception.Message + ' اگر پشتیبان مستقل دارید، گزینه ادامه بدون نقطه بازیابی را آگاهانه انتخاب کنید.') }
            Write-CareWarning ('ادامه بدون نقطه بازیابی با انتخاب کاربر: ' + $_.Exception.Message)
        }
    }
}
function ConvertTo-NativeArgument([string]$Value) {
    if ($Value.IndexOf([char]0) -ge 0 -or $Value -match '[\r\n]') { throw 'آرگومان نامعتبر.' }
    # Windows CommandLineToArgvW escaping, including quotes and trailing slashes.
    '"' + [regex]::Replace([regex]::Replace($Value, '(\\*)"', '$1$1\"'), '(\\+)$', '$1$1') + '"'
}
function Invoke-Native([string]$File, [string[]]$Arguments, [int[]]$SuccessCodes = @(0)) {
    Test-Cancel
    if (-not [IO.Path]::IsPathRooted($File) -or -not (Test-Path -LiteralPath $File -PathType Leaf)) { throw ('اجرایی معتبر یافت نشد: ' + $File) }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=$File; $psi.Arguments=($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' '
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    if ([IO.Path]::GetFileName($File) -ieq 'sfc.exe') { $psi.StandardOutputEncoding=[Text.Encoding]::Unicode }
    Write-CareLog ($File + ' ' + $psi.Arguments)
    $proc=New-Object Diagnostics.Process; $proc.StartInfo=$psi
    try {
        [void]$proc.Start()
        $out=$proc.StandardOutput.ReadToEndAsync(); $err=$proc.StandardError.ReadToEndAsync()
        # Do not terminate DISM, installers or disk operations mid-write.
        $proc.WaitForExit()
        $output=$out.GetAwaiter().GetResult(); $errors=$err.GetAwaiter().GetResult(); $code=$proc.ExitCode
        Write-CareLog $output; if ($errors) { Write-CareLog $errors }; Write-CareLog ('ExitCode: ' + $code)
        if ($code -notin $SuccessCodes) { throw ('عملیات با کد ' + $code + ' پایان یافت. جزئیات در گزارش است.') }
        if ($code -in @(3010,1641)) { Write-CareWarning 'برای تکمیل عملیات، راه‌اندازی مجدد لازم است؛ برنامه خودکار Restart نمی‌کند.' }
        return [pscustomobject]@{ Code=$code; Output=$output; Errors=$errors }
    } finally { $proc.Dispose() }
}
function Assert-MicrosoftSignature([string]$Path) {
    $s = Get-AuthenticodeSignature -LiteralPath $Path
    if ($s.Status -ne 'Valid' -or $s.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') { throw 'امضای معتبر Microsoft برای فایل دریافت‌شده تأیید نشد.' }
}
function Expand-SafeZip([string]$Archive, [string]$Destination, [long]$MaxBytes = 21474836480) {
    Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $Destination) { throw 'پوشه استخراج باید جدید باشد.' }
    $root=[IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    $zip=[IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        [long]$total=0; $names=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $zip.Entries) {
            $n=$entry.FullName.Replace('/','\')
            if ([IO.Path]::IsPathRooted($n) -or $n.Contains(':') -or $n -match '(^|\\)\.\.(\\|$)' -or $n -match '(^|\\)(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|\\|$)' -or $n -match '[ .](\\|$)') { throw 'مسیر نامعتبر در ZIP.' }
            $target=[IO.Path]::GetFullPath((Join-Path $root $n))
            if (-not $target.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or -not $names.Add($target)) { throw 'مسیر تکراری یا خارج از پوشه در ZIP.' }
            $total += $entry.Length
            if ($total -gt $MaxBytes -or $zip.Entries.Count -gt 100000) { throw 'حجم یا تعداد فایل‌های ZIP از سقف مجاز بیشتر است.' }
            if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'پیوند نمادین در ZIP پذیرفته نیست.' }
        }
        [void][IO.Directory]::CreateDirectory($root)
        foreach ($entry in $zip.Entries) {
            Test-Cancel
            $target=[IO.Path]::GetFullPath((Join-Path $root $entry.FullName.Replace('/','\')))
            if ($entry.FullName.EndsWith('/')) { [void][IO.Directory]::CreateDirectory($target); continue }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$false)
        }
    } finally { $zip.Dispose() }
}
function Export-CareReport([string]$Directory, $Request, $Rows, [string]$State) {
    $report=@{ Version='0.1.0'; Time=(Get-Date).ToString('o'); Action=$Request.Action; State=$State; Rows=@($Rows) }
    Save-Json $report (Join-Path $Directory 'report.json')
    $log = if (Test-Path -LiteralPath (Join-Path $Directory 'operation.log')) { Get-Content -LiteralPath (Join-Path $Directory 'operation.log') -Raw } else { '' }
    $body=[Net.WebUtility]::HtmlEncode(($report | ConvertTo-Json -Depth 12))
    $safeLog=[Net.WebUtility]::HtmlEncode($log)
    "<!doctype html><html lang='fa' dir='rtl'><meta charset='utf-8'><title>WindowsCare Report</title><style>body{font:16px Tahoma;max-width:1100px;margin:40px auto;background:#f3f6fb;color:#172942}pre{direction:ltr;text-align:left;white-space:pre-wrap;background:white;padding:24px;border-radius:12px}</style><h1>گزارش WindowsCare</h1><pre>$body</pre><h2>رویدادها</h2><pre>$safeLog</pre></html>" | Set-Content -LiteralPath (Join-Path $Directory 'report.html') -Encoding UTF8
    @($Rows) | ForEach-Object {
        $record=[ordered]@{}
        foreach ($key in @('Name','Detail','Path')) { $value=[string]$_.$key; if ($value -match '^[\s]*[=+@-]' -or $value -match '^[\t\r\n]') { $value="'"+$value }; $record[$key]=$value }
        [pscustomobject]$record
    } | Export-Csv -LiteralPath (Join-Path $Directory 'report.csv') -NoTypeInformation -Encoding UTF8
}
