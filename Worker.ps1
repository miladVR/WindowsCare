param([Parameter(Mandatory=$true)][string]$JobDirectory)
$ErrorActionPreference='Stop'
foreach ($module in @('Core','Catalog','Files','System','Install')) { . (Join-Path $PSScriptRoot ('Modules\'+$module+'.ps1')) }
$script:JobDir=[IO.Path]::GetFullPath($JobDirectory)
$script:Rows=New-Object 'Collections.Generic.List[object]'
$request=$null; $state='Failed'; $message='عملیات شروع نشد.'; $maintenanceLock=$null; $lockHeld=$false
try {
    $request=Get-Content -LiteralPath (Join-Path $script:JobDir 'request.json') -Raw | ConvertFrom-Json
    if (-not $script:Actions.ContainsKey([string]$request.Action)) { throw 'عملیات در فهرست مجاز نیست.' }
    $meta=$script:Actions[[string]$request.Action]
    Write-CareLog ('WindowsCare 0.1.0 | User: '+[Security.Principal.WindowsIdentity]::GetCurrent().Name+' | Action: '+$request.Action)
    Set-CareStatus 'Running' $meta.Title
    if ($meta.Admin) { Assert-Admin }
    if ($meta.Admin) {
        $maintenanceLock=New-Object Threading.Mutex($false,'Global\WindowsCare-Maintenance')
        try { $lockHeld=$maintenanceLock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $lockHeld=$true; Write-CareWarning 'اجرای قبلی ناگهانی متوقف شده است؛ گزارش‌های قبلی را نیز بررسی کنید.' }
        if (-not $lockHeld) { throw 'عملیات مدیریتی دیگری از WindowsCare فعال است.' }
    }
    if ($meta.Change -and -not $request.Confirmed) { throw 'تأیید اجرای عملیات موجود نیست.' }
    if ($meta.Change -and $meta.Admin -and $request.Action -notin @('RestorePoint','DefenderUpdate','DefenderQuick','DefenderFull')) { Invoke-Preflight ([bool]$meta.Restore) ([bool]$request.AllowNoRestore) }
    function Invoke-SelectedAction {
        switch ([string]$request.Action) {
            SystemInfo { Get-SystemRows }
            UpdateScan { Search-CareUpdates 'Software' }
            DriverScan { Search-CareUpdates 'Driver' }
            UpdateInstall { Install-CareUpdates $request.Rows }
            DiskInfo { Get-DiskRows }
            {$_ -in @('DiskScan','DiskRepair','DiskOptimize')} { Invoke-DiskAction $_ ([string]$request.Options.Drive) }
            LargeFiles { Get-ScanFiles ([string]$request.Options.Root) ([long]$request.Options.MinBytes) | Sort-Object Bytes -Descending }
            DuplicateFiles { Find-Duplicates ([string]$request.Options.Root) ([long]$request.Options.MinBytes) }
            TempFiles { Get-ScanFiles ([IO.Path]::GetTempPath()) 0 ([datetime]::UtcNow.AddDays(-7)) | Sort-Object Bytes -Descending }
            RecycleFiles {
                Move-SelectedToRecycle $request.Rows $request.Options.Keepers ([bool]$request.Options.DuplicateScan)
            }
            DriverList { Get-DriverRows }
            DriverBackup { Backup-Drivers }
            DriverInspect { $b=Read-DriverArchive ([string]$request.Options.Archive); foreach ($inf in $b.Infs) { [pscustomobject]@{Selected=$false; Name=$inf.Name; Detail='بسته از نظر هش و ساختار بررسی شد؛ سازگاری سخت‌افزار هنگام نصب توسط ویندوز تعیین می‌شود.'; Path=$inf.FullName; ArchiveHash=$b.ArchiveHash} } }
            DriverRestore { Install-DriverArchive ([string]$request.Options.Archive) ([string]$request.Options.ArchiveHash) }
            SecurityInfo { Get-SecurityRows }
            {$_ -in @('DefenderUpdate','DefenderQuick','DefenderFull')} { Invoke-DefenderAction $_ }
            AntivirusInstall { Install-Antivirus ([string]$request.Options.Vendor) ([string]$request.Options.Installer) }
            NetworkInfo { Get-NetworkRows }
            {$_ -in @('WindowsCheck','WindowsRepair','NetworkRepair','UpdateRepair','AudioRepair','PrintRepair','RestorePoint')} { Invoke-WindowsRepair $_ }
            OfficeConfig { $path=New-OfficeConfiguration $request.Options (Join-Path $script:JobDir 'Office-configuration.xml'); New-Row 'تنظیمات Office' 'فایل XML ساخته شد؛ هنوز نصب انجام نشده است.' $path }
            OfficeInstall { Invoke-OfficeInstall $request.Options }
        }
    }
    Invoke-SelectedAction | ForEach-Object {
        $script:Rows.Add($_)
        if ($script:Rows.Count -eq 1 -or $script:Rows.Count % 100 -eq 0 -or $request.Action -in @('UpdateInstall','DriverRestore','OfficeInstall')) { Save-Json @($script:Rows.ToArray()) (Join-Path $script:JobDir 'result.json') }
    }
    $state=if ($script:HadWarning) {'Warning'} else {'Completed'}
    $message=if ($script:HadWarning) {'عملیات پایان یافت؛ هشدارهای گزارش را بررسی کنید.'} else {'عملیات پایان یافت. نتیجه و گزارش را بررسی کنید.'}
} catch [OperationCanceledException] { $state='Cancelled'; $message=$_.Exception.Message; Write-CareLog $message }
catch { $state='Failed'; $message=$_.Exception.Message; Write-CareLog ($_ | Out-String) }
finally {
    Save-Json @($script:Rows.ToArray()) (Join-Path $script:JobDir 'result.json')
    try { Export-CareReport $script:JobDir $request @($script:Rows.ToArray()) $state } catch { Write-CareLog ('Report error: '+$_.Exception.Message) }
    Set-CareStatus $state $message
    if ($maintenanceLock) { if ($lockHeld) { $maintenanceLock.ReleaseMutex() }; $maintenanceLock.Dispose() }
}
if ($state -eq 'Failed') { exit 1 }
