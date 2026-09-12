function Get-SystemRows {
    try {
        $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $pc=Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        New-Row 'ویندوز' ($os.Caption+' | '+$os.Version+' | '+$os.OSArchitecture)
        New-Row 'سازنده و مدل' ($pc.Manufacturer+' '+$pc.Model)
        New-Row 'حافظه RAM' ('{0:N1} GB total | {1:N1} GB free' -f ($pc.TotalPhysicalMemory/1GB),($os.FreePhysicalMemory/1MB))
        foreach ($cpu in (Get-CimInstance Win32_Processor -ErrorAction Stop)) { New-Row 'پردازنده' ($cpu.Name+' | Load: '+$cpu.LoadPercentage+'%') }
        if ([int]$os.BuildNumber -lt 22000) { New-Row 'چرخه پشتیبانی' 'پشتیبانی عمومی Windows 10 پایان یافته است؛ وضعیت ESU یا LTSC را جداگانه بررسی کنید.' }
    } catch {
        Write-CareWarning ('اطلاعات کامل سخت‌افزار از CIM در دسترس نیست: '+$_.Exception.Message)
        New-Row 'ویندوز — اطلاعات پایه' ([Environment]::OSVersion.VersionString+' | 64-bit OS: '+[Environment]::Is64BitOperatingSystem)
        New-Row 'پردازنده — اطلاعات پایه' ([string]$env:PROCESSOR_IDENTIFIER)
        New-Row 'جزئیات سخت‌افزار' 'دسترسی به CIM محدود است؛ اطلاعات RAM و مدل دستگاه قابل تأیید نیست.'
    }
    New-Row 'راه‌اندازی مجدد معلق' ([string](Test-RebootPending))
    foreach ($v in ([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady })) { New-Row $v.Name ('{0:N1} GB free / {1:N1} GB | {2}' -f ($v.AvailableFreeSpace/1GB),($v.TotalSize/1GB),$v.DriveFormat) }
}
function Get-DiskRows {
    $physical=@(Get-PhysicalDisk -ErrorAction Stop)
    foreach ($d in $physical) {
        New-Row $d.FriendlyName ('Media: '+$d.MediaType+' | Health: '+$d.HealthStatus+' | '+$d.OperationalStatus)
        try { $r=$d | Get-StorageReliabilityCounter -ErrorAction Stop; New-Row 'شمارنده سلامت' ('Temperature: '+$r.Temperature+' C | Wear: '+$r.Wear+' | Read errors: '+$r.ReadErrorsUncorrected+' | Write errors: '+$r.WriteErrorsUncorrected) }
        catch { New-Row 'داده سلامت در دسترس نیست' 'کنترلر یا دستگاه این شمارنده‌ها را ارائه نکرد؛ نبود داده به معنی سلامت نیست.' }
    }
    try { foreach ($s in (Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop)) { New-Row 'SMART prediction' ($s.InstanceName+' | PredictFailure: '+$s.PredictFailure) } }
    catch { New-Row 'SMART' 'گزارش پیش‌بینی خرابی از این رابط در دسترس نیست.' }
}
function Assert-Drive([string]$Drive, [bool]$Healthy=$false) {
    if ($Drive -notmatch '^[A-Za-z]$') { throw 'حرف درایو نامعتبر است.' }
    $v=Get-Volume -DriveLetter $Drive -ErrorAction Stop
    if ($v.DriveType -ne 'Fixed') { throw 'این عملیات تنها روی دیسک محلی ثابت انجام می‌شود.' }
    if ($Healthy -and $v.HealthStatus -ne 'Healthy') { throw 'وضعیت Volume سالم نیست؛ ابتدا از داده‌ها پشتیبان بگیرید.' }
    if ($Healthy) {
        # Mapping through partition to physical disk; unknown health is not treated as healthy.
        $disks=@(Get-Partition -DriveLetter $Drive -ErrorAction Stop | Get-Disk -ErrorAction Stop)
        if (-not $disks.Count -or @($disks | Where-Object { $_.HealthStatus -ne 'Healthy' -or $_.IsOffline }).Count) { throw 'سلامت دیسک مقصد تأیید نشد.' }
        $bad=@(Get-PhysicalDisk -ErrorAction Stop | Where-Object HealthStatus -ne 'Healthy')
        if ($bad.Count) { throw 'یک دیسک وضعیت سلامت نامناسب دارد؛ ابتدا پشتیبان‌گیری و بررسی سخت‌افزاری انجام دهید.' }
        try { $pred=@(Get-CimInstance -Namespace root\wmi -ClassName MSStorageDriver_FailurePredictStatus -ErrorAction Stop); if (@($pred | Where-Object PredictFailure).Count) { throw [IO.IOException]::new('SMART خطر خرابی گزارش کرده است؛ عملیات سنگین متوقف شد.') } }
        catch [IO.IOException] { throw }
        catch { Write-CareWarning 'SMART در دسترس نیست؛ وضعیت Healthy تضمین سلامت فیزیکی نیست.' }
    }
    return $v
}
function Invoke-DiskAction([string]$Action, [string]$Drive) {
    $v=Assert-Drive $Drive $true
    if ($Action -eq 'DiskOptimize') {
        # Let the Windows storage stack choose TRIM, defrag or no-op for the actual media.
        Optimize-Volume -DriveLetter $Drive -Verbose -ErrorAction Stop 4>&1 | ForEach-Object { Write-CareLog ([string]$_) }
        New-Row $Drive 'بهینه‌سازی متناسب با نوع ذخیره‌ساز به ویندوز سپرده شد؛ درصد افزایش سرعت تضمین نمی‌شود.'
    } elseif ($Action -eq 'DiskScan') {
        if ($v.FileSystem -ne 'NTFS') { throw 'اسکن آنلاین این نسخه مخصوص NTFS است.' }
        $r=Invoke-Native (Join-Path $env:windir 'System32\chkdsk.exe') @(($Drive+':'),'/scan') @(0,1,2,3)
        if ($r.Code -ne 0) { Write-CareWarning 'CHKDSK نیاز به بررسی یا تعمیر گزارش کرده است؛ متن کامل را بخوانید.' }
        New-Row $Drive ('CHKDSK exit: '+$r.Code+' | جزئیات در گزارش عملیات')
    } else {
        if ($v.FileSystem -ne 'NTFS') { throw 'تعمیر این نسخه مخصوص NTFS است.' }
        if (($Drive+':') -eq $env:SystemDrive) { throw 'تعمیر آفلاین درایو ویندوز از این نسخه اجرا نمی‌شود. از محیط بازیابی ویندوز پس از پشتیبان‌گیری استفاده کنید.' }
        Repair-Volume -DriveLetter $Drive -OfflineScanAndFix -ErrorAction Stop | ForEach-Object { Write-CareLog ([string]$_) }
        New-Row $Drive 'عملیات تعمیر آفلاین پایان یافت؛ نتیجه Repair-Volume در گزارش ثبت شد.'
    }
}
function Get-SecurityRows {
    try { foreach ($av in (Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop)) { New-Row $av.displayName ('Security Center productState: '+$av.productState) } }
    catch { Write-CareWarning 'اطلاعات Security Center در دسترس نیست.' }
    try { $m=Get-MpComputerStatus -ErrorAction Stop; New-Row 'Microsoft Defender' ('Enabled: '+$m.AntivirusEnabled+' | Realtime: '+$m.RealTimeProtectionEnabled+' | Signatures: '+$m.AntivirusSignatureLastUpdated+' | Quick scan: '+$m.QuickScanEndTime) }
    catch { New-Row 'Defender' 'وضعیت قابل دریافت نیست؛ ممکن است آنتی‌ویروس دیگری فعال باشد.' }
}
function Invoke-DefenderAction([string]$Action) {
    $m=Get-MpComputerStatus -ErrorAction Stop
    if (-not $m.AntivirusEnabled) { throw 'Defender فعال نیست؛ وضعیت آنتی‌ویروس فعلی را در Windows Security بررسی کنید.' }
    switch ($Action) {
        DefenderUpdate { Update-MpSignature -ErrorAction Stop }
        DefenderQuick { Start-MpScan -ScanType QuickScan -ErrorAction Stop }
        DefenderFull { Start-MpScan -ScanType FullScan -ErrorAction Stop }
    }
    Get-SecurityRows
    foreach ($t in (Get-MpThreat -ErrorAction SilentlyContinue)) { New-Row 'تهدید ثبت‌شده' ($t.ThreatName+' | Active: '+$t.IsActive) }
}
function Get-NetworkRows {
    foreach ($a in (Get-NetAdapter -ErrorAction Stop)) { New-Row $a.Name ('Status: '+$a.Status+' | Link: '+$a.LinkSpeed) }
    foreach ($n in (Get-NetIPConfiguration -ErrorAction Stop)) { New-Row $n.InterfaceAlias ('IPv4: '+($n.IPv4Address.IPAddress -join ', ')+' | Gateway: '+($n.IPv4DefaultGateway.NextHop -join ', ')+' | DNS: '+($n.DNSServer.ServerAddresses -join ', ')) }
    try { $dns=Resolve-DnsName www.microsoft.com -ErrorAction Stop; New-Row 'آزمایش DNS' (($dns | Where-Object IPAddress | Select-Object -ExpandProperty IPAddress) -join ', ') } catch { New-Row 'آزمایش DNS' $_.Exception.Message }
}
function Invoke-WindowsRepair([string]$Action) {
    $sys=Join-Path $env:windir 'System32'
    switch ($Action) {
        WindowsCheck {
            $d=Invoke-Native (Join-Path $sys 'Dism.exe') @('/Online','/Cleanup-Image','/ScanHealth') @(0,3010)
            Test-Cancel
            $s=Invoke-Native (Join-Path $sys 'sfc.exe') @('/verifyonly') @(0,1,2,3)
            New-Row 'بررسی ویندوز' ('DISM: '+$d.Code+' | SFC: '+$s.Code+' | خروجی و CBS.log ملاک تشخیص هستند؛ پایان اجرا به معنی سالم بودن نیست.')
        }
        WindowsRepair {
            $d=Invoke-Native (Join-Path $sys 'Dism.exe') @('/Online','/Cleanup-Image','/RestoreHealth') @(0,3010)
            Test-Cancel
            $s=Invoke-Native (Join-Path $sys 'sfc.exe') @('/scannow') @(0,1,2,3)
            Write-CareWarning 'پایان فرمان‌ها به‌تنهایی تضمین رفع همه خطاها نیست؛ خروجی DISM، SFC و CBS.log را بررسی کنید.'
            New-Row 'فرمان‌های تعمیر پایان یافتند' ('DISM: '+$d.Code+' | SFC: '+$s.Code) (Join-Path $env:windir 'Logs\CBS\CBS.log')
        }
        NetworkRepair {
            Clear-DnsClientCache -ErrorAction Stop
            [void](Invoke-Native (Join-Path $sys 'netsh.exe') @('winsock','reset'))
            Write-CareWarning 'برای تکمیل بازنشانی Winsock، ویندوز را در زمان مناسب Restart کنید. VPN ممکن است به تنظیم مجدد نیاز داشته باشد.'
            Get-NetworkRows
        }
        UpdateRepair {
            foreach ($n in @('BITS','wuauserv')) { Restart-Service -Name $n -ErrorAction Stop; New-Row $n ([string](Get-Service $n).Status) }
        }
        AudioRepair { Restart-Service Audiosrv -ErrorAction Stop; New-Row 'Windows Audio' ([string](Get-Service Audiosrv).Status) }
        PrintRepair { Restart-Service Spooler -ErrorAction Stop; New-Row 'Print Spooler' ([string](Get-Service Spooler).Status) }
        RestorePoint {
            $desc='WindowsCare manual '+(Get-Date -Format yyyyMMdd-HHmmss)
            Checkpoint-Computer -Description $desc -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction Stop
            $point=Get-ComputerRestorePoint -ErrorAction Stop | Where-Object Description -eq $desc
            if (-not $point) { throw 'ساخت نقطه بازیابی تأیید نشد.' }
            New-Row 'نقطه بازیابی' ($desc+' | '+$point.SequenceNumber)
        }
    }
}
function Get-DriverRows {
    foreach ($d in (Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop)) { New-Row $d.DeviceName ($d.Manufacturer+' | '+$d.DriverVersion+' | Signed: '+$d.IsSigned) $d.InfName }
    foreach ($d in (Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0' -ErrorAction Stop)) { New-Row ('خطای دستگاه: '+$d.Name) ('Code: '+$d.ConfigManagerErrorCode+' | '+$d.PNPDeviceID) }
}
