function Search-CareUpdates([string]$Type='Software') {
    if ($Type -notin @('Software','Driver')) { throw 'نوع آپدیت نامعتبر است.' }
    Set-CareStatus 'Running' 'در حال جست‌وجو با Windows Update Agent؛ این مرحله ممکن است چند دقیقه طول بکشد.'
    $session=New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID='WindowsCare'
    $search=$session.CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0 and Type='$Type'")
    if ([int]$search.ResultCode -ne 2) { throw ('جست‌وجوی کامل انجام نشد؛ ResultCode: '+$search.ResultCode) }
    foreach ($u in $search.Updates) {
        Test-Cancel
        [pscustomobject]@{Selected=$false; Name=$u.Title; Detail=('{0:N1} MB | {1} | Restart behavior: {2}' -f ($u.MaxDownloadSize/1MB), $(if($u.BrowseOnly){'اختیاری'}else{'قابل نصب'}),$u.InstallationBehavior.RebootBehavior); Path=$u.SupportUrl; Id=$u.Identity.UpdateID; Revision=$u.Identity.RevisionNumber; Bytes=$u.MaxDownloadSize; Type=$Type; Eula=$u.EulaText }
    }
}
function Install-CareUpdates($Rows) {
    if (@($Rows).Count -eq 0 -or @($Rows).Count -gt 200) { throw 'بین ۱ تا ۲۰۰ آپدیت انتخاب کنید.' }
    $session=New-Object -ComObject Microsoft.Update.Session; $session.ClientApplicationID='WindowsCare'
    $searcher=$session.CreateUpdateSearcher()
    foreach ($r in $Rows) {
        Test-Cancel
        $id=[guid]::Empty
        if (-not [guid]::TryParse([string]$r.Id,[ref]$id) -or [int]$r.Revision -lt 0) { throw 'شناسه آپدیت نامعتبر است.' }
        Set-CareStatus 'Running' ('بازبینی آپدیت: '+$r.Name)
        $found=$searcher.Search("UpdateID='$id' and RevisionNumber=$([int]$r.Revision) and IsInstalled=0 and IsHidden=0")
        if ([int]$found.ResultCode -ne 2 -or $found.Updates.Count -ne 1) { throw 'آپدیت انتخابی تغییر کرده یا دیگر موجود نیست؛ دوباره جست‌وجو کنید.' }
        $u=$found.Updates.Item(0)
        if ($u.InstallationBehavior.CanRequestUserInput) { throw ('این آپدیت به نصب تعاملی نیاز دارد؛ از تنظیمات Windows Update استفاده کنید: '+$u.Title) }
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        $collection=New-Object -ComObject Microsoft.Update.UpdateColl; [void]$collection.Add($u)
        Set-CareStatus 'Running' ('دریافت: '+$u.Title)
        $downloader=$session.CreateUpdateDownloader(); $downloader.Updates=$collection
        $download=$downloader.Download()
        if ([int]$download.ResultCode -ne 2 -or -not $u.IsDownloaded) { throw ('دریافت آپدیت موفق نبود: '+$download.ResultCode) }
        Test-Cancel
        Set-CareStatus 'Running' ('نصب: '+$u.Title+' — توقف پس از پایان این آپدیت اعمال می‌شود.')
        $installer=$session.CreateUpdateInstaller(); $installer.Updates=$collection; $installer.AllowSourcePrompts=$false
        $installed=$installer.Install(); $detail=$installed.GetUpdateResult(0)
        New-Row $u.Title ('ResultCode: '+$detail.ResultCode+' | HRESULT: '+$detail.HResult+' | Reboot: '+$installed.RebootRequired)
        if ([int]$detail.ResultCode -ne 2) { throw 'نصب این آپدیت کامل نشده است؛ نتایج قبلی در گزارش محفوظ است.' }
        if ($installed.RebootRequired) { Write-CareWarning 'برای ادامه، راه‌اندازی مجدد لازم است. پس از Restart دوباره جست‌وجو کنید؛ نصب‌های موفق تکرار نمی‌شوند.'; break }
    }
}
function New-OfficeConfiguration($Options, [string]$Path) {
    if (-not $script:OfficeProducts.Contains([string]$Options.Product)) { throw 'نسخه Office نامعتبر است.' }
    $product=$script:OfficeProducts[[string]$Options.Product]
    if ([string]$Options.Bits -notin @('32','64') -or [string]$Options.Language -notin @('en-us','fa-ir','ar-sa')) { throw 'معماری یا زبان نامعتبر است.' }
    $apps=@($Options.Apps)
    if (-not $apps.Count) { throw 'حداقل یک برنامه Office انتخاب کنید.' }
    foreach ($a in $apps) { if ($a -notin $product.Apps) { throw ('جزء '+$a+' در نسخه انتخابی پشتیبانی نشده است.') } }
    $xml=New-Object Xml.XmlDocument
    [void]$xml.AppendChild($xml.CreateXmlDeclaration('1.0','utf-8',$null))
    $root=$xml.CreateElement('Configuration'); [void]$xml.AppendChild($root)
    $add=$xml.CreateElement('Add'); $add.SetAttribute('OfficeClientEdition',[string]$Options.Bits); $add.SetAttribute('Channel',$product.Channel); [void]$root.AppendChild($add)
    $p=$xml.CreateElement('Product'); $p.SetAttribute('ID',$product.Id); [void]$add.AppendChild($p)
    $language=$xml.CreateElement('Language'); $language.SetAttribute('ID',[string]$Options.Language); [void]$p.AppendChild($language)
    foreach ($a in @('Word','Excel','PowerPoint','Outlook','OneNote','Access','Publisher','Groove','Lync','OneDrive','Teams','OutlookForWindows')) {
        if ($a -notin $apps) { $exclude=$xml.CreateElement('ExcludeApp'); $exclude.SetAttribute('ID',$a); [void]$p.AppendChild($exclude) }
    }
    $display=$xml.CreateElement('Display'); $display.SetAttribute('Level','Full'); $display.SetAttribute('AcceptEULA','FALSE'); [void]$root.AppendChild($display)
    $prop=$xml.CreateElement('Property'); $prop.SetAttribute('Name','FORCEAPPSHUTDOWN'); $prop.SetAttribute('Value','FALSE'); [void]$root.AppendChild($prop)
    $xml.Save($Path)
    return $Path
}
function Get-OfficialOdt([string]$LocalSetup) {
    if ($LocalSetup) {
        $f=Assert-RegularPath $LocalSetup
        if ($f.Name -ne 'setup.exe') { throw 'فایل setup.exe استخراج‌شده از Office Deployment Tool را انتخاب کنید.' }
        Assert-MicrosoftSignature $f.FullName
        if ($f.VersionInfo.FileDescription -notmatch 'Office') { throw 'فایل انتخابی نصب‌کننده Office نیست.' }
        return $f.FullName
    }
    Set-CareStatus 'Running' 'دریافت Office Deployment Tool از وب‌سایت رسمی Microsoft'
    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $page=Invoke-WebRequest -UseBasicParsing -Uri 'https://www.microsoft.com/en-us/download/details.aspx?id=49117' -TimeoutSec 60 -ErrorAction Stop
    $html=[Net.WebUtility]::HtmlDecode($page.Content).Replace('\/','/')
    $matches=[regex]::Matches($html,'https://download\.microsoft\.com/[^\s"<>]+?officedeploymenttool_[^\s"<>]+?\.exe',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $matches.Count) { throw 'لینک ODT از صفحه رسمی پیدا نشد. ابزار را از لینک رسمی داخل برنامه دریافت و setup.exe استخراج‌شده را انتخاب کنید.' }
    $uri=[uri]$matches[0].Value
    if ($uri.Scheme -ne 'https' -or $uri.Host -ne 'download.microsoft.com') { throw 'نشانی دانلود معتبر نیست.' }
    $odt=Join-Path $script:JobDir 'odt.exe'
    Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $odt -TimeoutSec 300 -ErrorAction Stop
    Assert-MicrosoftSignature $odt
    $dest=Join-Path $script:JobDir 'odt'; [void][IO.Directory]::CreateDirectory($dest)
    [void](Invoke-Native $odt @('/quiet',('/extract:'+$dest)))
    $setup=Join-Path $dest 'setup.exe'; Assert-MicrosoftSignature $setup
    return $setup
}
function Invoke-OfficeInstall($Options) {
    $installed=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if ($installed) { throw 'Office Click-to-Run از قبل نصب است. این نسخه برای جلوگیری از حذف اجزای موجود، تغییر نصب فعلی را انجام نمی‌دهد. از تنظیمات Office یا حذف نصب رسمی استفاده کنید.' }
    $config=New-OfficeConfiguration $Options (Join-Path $script:JobDir 'Office-configuration.xml')
    New-Row 'تنظیمات Office' 'نسخه و اجزای انتخاب‌شده؛ پذیرش مجوز در نصب‌کننده رسمی انجام می‌شود.' $config
    $setup=Get-OfficialOdt ([string]$Options.SetupPath)
    [void](Invoke-Native $setup @('/configure',$config) @(0,3010))
    $state=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if (-not $state) { throw 'نصب Office در رجیستری تأیید نشد؛ ممکن است نصب لغو شده باشد.' }
    $expected=$script:OfficeProducts[[string]$Options.Product].Id
    if ($expected -notin ($state.ProductReleaseIds -split ',')) { throw 'محصول نصب‌شده با انتخاب کاربر تطبیق ندارد؛ گزارش و نصب‌کننده را بررسی کنید.' }
    New-Row 'Office نصب‌شده' ($state.ProductReleaseIds+' | '+$state.VersionToReport+' | وضعیت فعال‌سازی را داخل Office بررسی کنید.')
}
function Install-Antivirus([string]$Vendor, [string]$Installer) {
    if (-not $script:Vendors.Contains($Vendor)) { throw 'ناشر انتخابی معتبر نیست.' }
    # Conservative: an existing third-party registration must be resolved by the user first.
    $others=@(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | Where-Object displayName -notmatch 'Windows Defender|Microsoft Defender')
    if ($others.Count) { throw ('آنتی‌ویروس دیگری در Security Center ثبت است: '+($others.displayName -join ', ')+'. ابتدا وضعیت آن را بررسی کنید؛ نصب هم‌زمان انجام نشد.') }
    $file=Assert-RegularPath $Installer
    if ($file.Extension -ne '.exe' -or $file.PSIsContainer) { throw 'نصب‌کننده EXE رسمی را انتخاب کنید.' }
    $sig=Get-AuthenticodeSignature -LiteralPath $file.FullName
    $publisher=$script:Vendors[$Vendor].Publisher
    $orgPattern='(?:^|,\s*)O=(?:"'+[regex]::Escape($publisher)+'"|'+[regex]::Escape($publisher)+')(?:,|$)'
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch $orgPattern) { throw 'امضای معتبر ناشر انتخاب‌شده تأیید نشد. فایل دیگری اجرا نمی‌شود.' }
    [void](Invoke-Native $file.FullName @() @(0,3010,1641))
    $registered=@(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | Where-Object displayName -match ([regex]::Escape($Vendor)))
    if (-not $registered.Count) { Write-CareWarning 'نصب‌کننده پایان یافت، اما ثبت آنتی‌ویروس تأیید نشد؛ پنجره نصب‌کننده و نیاز به Restart را بررسی کنید.' }
    Get-SecurityRows
}
