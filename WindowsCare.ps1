[CmdletBinding()]
param([switch]$SelfTest, [string]$RenderDirectory)
$ErrorActionPreference='Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'این برنامه را با Start-WindowsCare.cmd و Windows PowerShell 5.1 x64 اجرا کنید.' }
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
foreach ($m in @('Core','Catalog','Files')) { . (Join-Path $PSScriptRoot ('Modules\'+$m+'.ps1')) }
$xml=[xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'UI\Main.xaml') -Raw -Encoding UTF8)
$reader=New-Object Xml.XmlNodeReader $xml
$script:Window=[Windows.Markup.XamlReader]::Load($reader)
$script:UI=@{}
foreach ($n in $xml.SelectNodes('//*[@*[local-name()="Name"]]')) { $name=$n.GetAttribute('Name','http://schemas.microsoft.com/winfx/2006/xaml'); $script:UI[$name]=$script:Window.FindName($name) }
$script:Active=$null; $script:LastDirectory=$null; $script:LastAction=''; $script:Displayed=@(); $script:DriverHash=''; $script:DriverPath=''
$script:DataRoot=Join-Path $env:LOCALAPPDATA 'WindowsCare\Jobs'
foreach ($p in $script:OfficeProducts.Keys) { [void]$script:UI.OfficeProduct.Items.Add($p) }; $script:UI.OfficeProduct.SelectedIndex=0
foreach ($v in $script:Vendors.Keys) { [void]$script:UI.AntivirusVendor.Items.Add($v) }; $script:UI.AntivirusVendor.SelectedIndex=0
foreach ($d in [IO.DriveInfo]::GetDrives() | Where-Object DriveType -eq 'Fixed') { [void]$script:UI.Drive.Items.Add($d.Name.Substring(0,1)) }; $script:UI.Drive.SelectedIndex=0
$script:UI.ScanRoot.Text=Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
$pathStyle=[Windows.Style]::new([Windows.Controls.TextBlock])
$pathStyle.Setters.Add([Windows.Setter]::new([Windows.FrameworkElement]::FlowDirectionProperty,[Windows.FlowDirection]::LeftToRight))
$pathStyle.Setters.Add([Windows.Setter]::new([Windows.Controls.TextBlock]::TextAlignmentProperty,[Windows.TextAlignment]::Left))
$script:UI.Results.Columns[3].ElementStyle=$pathStyle
if (-not (Test-Path -LiteralPath $script:UI.ScanRoot.Text)) { $script:UI.ScanRoot.Text=[Environment]::GetFolderPath('MyDocuments') }
function Show-Message([string]$Text, [string]$Title='WindowsCare') { [void][Windows.MessageBox]::Show($script:Window,$Text,$Title,'OK','Information') }
function Get-Choice($Control) { if ($Control.SelectedItem -is [Windows.Controls.ComboBoxItem]) { return [string]$Control.SelectedItem.Content }; return [string]$Control.SelectedItem }
function Pick-File([string]$Filter) { $dialog=New-Object Microsoft.Win32.OpenFileDialog; $dialog.Filter=$Filter; if ($dialog.ShowDialog($script:Window)) { return $dialog.FileName }; return '' }
function Open-Official([string]$Uri) {
    $u=[uri]$Uri
    if ($u.Scheme -ne 'https' -and $u.Scheme -notin @('ms-settings','windowsdefender')) { throw 'نشانی مجاز نیست.' }
    Start-Process -FilePath $Uri
}
function Show-TextDialog([string]$Title, [string]$Text, [bool]$Confirm=$false) {
    $dlg=New-Object Windows.Window; $dlg.Title=$Title; $dlg.Width=790; $dlg.Height=580; $dlg.Owner=$script:Window; $dlg.WindowStartupLocation='CenterOwner'; $dlg.FlowDirection='RightToLeft'
    $panel=New-Object Windows.Controls.DockPanel; $panel.Margin='16'; $dlg.Content=$panel
    $bar=New-Object Windows.Controls.StackPanel; $bar.Orientation='Horizontal'; [Windows.Controls.DockPanel]::SetDock($bar,'Bottom'); [void]$panel.Children.Add($bar)
    $close=New-Object Windows.Controls.Button; $close.Content='بستن / انصراف'; $close.Padding='16,8'; $close.Margin='4'; [void]$bar.Children.Add($close)
    $close.Add_Click({ $this.Tag.DialogResult=$false }); $close.Tag=$dlg
    if ($Confirm) { $ok=New-Object Windows.Controls.Button; $ok.Content='تأیید و اجرا'; $ok.Padding='16,8'; $ok.Margin='4'; $ok.Tag=$dlg; $ok.Add_Click({$this.Tag.DialogResult=$true}); [void]$bar.Children.Add($ok) }
    $box=New-Object Windows.Controls.TextBox; $box.Text=$Text; $box.IsReadOnly=$true; $box.TextWrapping='Wrap'; $box.VerticalScrollBarVisibility='Auto'; $box.FontFamily='Segoe UI'; $box.FontSize=14; $box.Padding='12'; [void]$panel.Children.Add($box)
    return $dlg.ShowDialog()
}
function Get-SelectedRows {
    [void]$script:UI.Results.CommitEdit([Windows.Controls.DataGridEditingUnit]::Cell,$true)
    [void]$script:UI.Results.CommitEdit([Windows.Controls.DataGridEditingUnit]::Row,$true)
    return @($script:Displayed | Where-Object Selected)
}
function Get-ActionOptions([string]$Action) {
    $o=@{}
    switch ($Action) {
        {$_ -in @('DiskScan','DiskRepair','DiskOptimize')} { $o.Drive=Get-Choice $script:UI.Drive }
        {$_ -in @('LargeFiles','DuplicateFiles')} {
            [long]$min=0
            if (-not [long]::TryParse($script:UI.MinSize.Text,[ref]$min) -or $min -lt 0 -or $min -gt 1048576) { throw 'حداقل حجم باید بین صفر و ۱۰۴۸۵۷۶ مگابایت باشد.' }
            $o.Root=$script:UI.ScanRoot.Text; $o.MinBytes=$min*1MB
        }
        {$_ -in @('DriverInspect','DriverRestore')} {
            $o.Archive=$script:UI.DriverArchive.Text; $o.ArchiveHash=$script:DriverHash
            if ($Action -eq 'DriverRestore' -and (-not $script:DriverHash -or $script:DriverPath -ne $o.Archive)) { throw 'ابتدا همین فایل پشتیبان را با دکمه بررسی بسته بازبینی کنید.' }
        }
        {$_ -in @('OfficeConfig','OfficeInstall')} {
            $o.Product=Get-Choice $script:UI.OfficeProduct; $o.Bits=Get-Choice $script:UI.OfficeBits; $o.Language=Get-Choice $script:UI.OfficeLanguage; $o.SetupPath=$script:UI.OdtPath.Text
            $o.Apps=@('Word','Excel','PowerPoint','Outlook','OneNote','Access') | Where-Object { $script:UI['App'+$_].IsChecked -and $script:UI['App'+$_].IsEnabled }
            if (-not @($o.Apps).Count) { throw 'حداقل یک جزء Office انتخاب کنید.' }
        }
        AntivirusInstall { $o.Vendor=Get-Choice $script:UI.AntivirusVendor; $o.Installer=$script:UI.AntivirusPath.Text; if (-not $o.Installer) { throw 'ابتدا نصب‌کننده رسمی را انتخاب کنید.' } }
        RecycleFiles { $o.DuplicateScan=($script:LastAction -eq 'DuplicateFiles'); $o.Keepers=@($script:Displayed | Where-Object { -not $_.Selected }) }
    }
    return $o
}
function Start-CareAction([string]$Action) {
    if ($script:Active) { Show-Message 'عملیات فعلی هنوز در حال اجرا است.'; return }
    try {
        $meta=$script:Actions[$Action]; $rows=@()
        if ($Action -in @('UpdateInstall','RecycleFiles')) {
            if ($Action -eq 'UpdateInstall' -and $script:LastAction -notin @('UpdateScan','DriverScan')) { throw 'ابتدا آپدیت‌ها را جست‌وجو کنید.' }
            if ($Action -eq 'RecycleFiles' -and $script:LastAction -notin @('LargeFiles','DuplicateFiles','TempFiles')) { throw 'ابتدا فایل‌ها را اسکن کنید.' }
            $rows=@(Get-SelectedRows); if (-not $rows.Count) { throw 'حداقل یک مورد را از ستون انتخاب علامت بزنید.' }
        }
        $o=Get-ActionOptions $Action
        if ($meta.Change) {
            $summary=$meta.Title+"`r`n`r`n"
            if ($rows.Count) { $summary += ('تعداد انتخاب: '+$rows.Count+"`r`n"+ (($rows | ForEach-Object {$_.Name+' | '+$_.Path+' | '+$_.Detail}) -join "`r`n")+"`r`n`r`n") }
            if ($o.Count) { $brief=@{}; foreach ($k in $o.Keys) { if ($k -ne 'Keepers') {$brief[$k]=$o[$k]} }; $summary+=($brief | ConvertTo-Json -Depth 6)+"`r`n`r`n" }
            if ($Action -eq 'UpdateInstall') { $summary+='با تأیید، دریافت و نصب موارد انتخابی و پذیرش مجوز آن‌ها انجام می‌شود. مجوز هر مورد پیش از این مرحله از دکمه نمایش مجوز قابل خواندن است.'+"`r`n" }
            if ($Action -eq 'RecycleFiles') { $summary+='فایل‌های بالا به سطل بازیافت منتقل می‌شوند. اگر ویندوز به دلیل محدودیت سطل بازیافت حذف دائمی پیشنهاد کرد، آن را لغو کنید.'+"`r`n" }
            if ($Action -eq 'DiskRepair') { $summary+='درایو داده برای تعمیر از دسترس خارج می‌شود. برنامه‌های استفاده‌کننده را ببندید و پشتیبان مستقل داشته باشید.'+"`r`n" }
            if ($Action -eq 'DiskScan') { $summary+='CHKDSK /scan ممکن است اصلاحات آنلاین فایل‌سیستم انجام دهد؛ این مرحله صرفاً نمایش اطلاعات نیست.'+"`r`n" }
            if ($Action -eq 'DriverRestore') { $summary+='درایورهای منطبق ممکن است تغییر کنند. کلید بازیابی BitLocker و پشتیبان را در دسترس داشته باشید.'+"`r`n" }
            if ($meta.Restore) { $summary+='ساخت نقطه بازیابی: فعال. ادامه در صورت شکست: '+[string][bool]$script:UI.AllowNoRestore.IsChecked+"`r`n" }
            if (-not (Show-TextDialog 'پیش‌نمایش عملیات — تأیید لازم است' $summary $true)) { return }
        }
        $job=Join-Path $script:DataRoot ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($job)
        $request=@{Action=$Action; Options=$o; Rows=$rows; Confirmed=[bool]$meta.Change; AllowNoRestore=[bool]$script:UI.AllowNoRestore.IsChecked}
        Save-Json $request (Join-Path $job 'request.json')
        $exe=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $args=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Worker.ps1'),'-JobDirectory',$job)
        $params=@{FilePath=$exe; ArgumentList=(($args | ForEach-Object {ConvertTo-NativeArgument $_}) -join ' '); WindowStyle='Hidden'; PassThru=$true}
        if ($meta.Admin) { $params.Verb='RunAs' }
        $p=Start-Process @params
        $script:Active=@{Process=$p; Directory=$job; Action=$Action; Options=$o; Started=Get-Date}
        $script:LastDirectory=$job; $script:UI.Tabs.IsEnabled=$false; $script:UI.AllowNoRestore.IsEnabled=$false; $script:UI.Cancel.IsEnabled=$true; $script:UI.Progress.IsIndeterminate=$true
        $script:UI.Status.Text='در حال اجرا: '+$meta.Title; $script:UI.Log.Text='در انتظار گزارش عملیات…'
    } catch { Show-Message $_.Exception.Message }
}
foreach ($action in $script:Actions.Keys) { if ($script:UI.ContainsKey($action)) { $script:UI[$action].Tag=$action; $script:UI[$action].Add_Click({Start-CareAction ([string]$this.Tag)}) } }
$script:UI.OfficeProduct.Add_SelectionChanged({$product=$script:OfficeProducts[(Get-Choice $script:UI.OfficeProduct)]; foreach($a in @('Word','Excel','PowerPoint','Outlook','OneNote','Access')) {$script:UI['App'+$a].IsEnabled=($a -in $product.Apps)}})
$script:UI.PickFolder.Add_Click({$d=New-Object Windows.Forms.FolderBrowserDialog; try {if($d.ShowDialog() -eq 'OK'){$script:UI.ScanRoot.Text=$d.SelectedPath}}finally{$d.Dispose()}})
$script:UI.PickOdt.Add_Click({$p=Pick-File 'Office setup|setup.exe'; if($p){$script:UI.OdtPath.Text=$p}})
$script:UI.PickAntivirus.Add_Click({$p=Pick-File 'Installer|*.exe'; if($p){$script:UI.AntivirusPath.Text=$p}})
$script:UI.PickArchive.Add_Click({$p=Pick-File 'Driver backup|*.zip'; if($p){$script:UI.DriverArchive.Text=$p; $script:DriverHash=''}})
$script:UI.Cancel.Add_Click({if($script:Active){[IO.File]::WriteAllText((Join-Path $script:Active.Directory 'cancel'),'cancel'); $script:UI.Status.Text='درخواست توقف ثبت شد؛ فرمان جاری به‌زور بسته نمی‌شود.'; $script:UI.Cancel.IsEnabled=$false}})
$script:UI.SelectAll.Add_Click({foreach($r in $script:Displayed){$r.Selected=$true}; $script:UI.Results.Items.Refresh()})
$script:UI.SelectNone.Add_Click({foreach($r in $script:Displayed){$r.Selected=$false}; $script:UI.Results.Items.Refresh()})
$script:UI.ShowDetails.Add_Click({if($script:UI.Results.SelectedItem){[void](Show-TextDialog 'جزئیات' ($script:UI.Results.SelectedItem | ConvertTo-Json -Depth 8))}})
$script:UI.ShowEula.Add_Click({$r=$script:UI.Results.SelectedItem; if($r -and $r.PSObject.Properties['Eula']){[void](Show-TextDialog 'مجوز آپدیت' ([string]$r.Eula))}else{Show-Message 'یک آپدیت را انتخاب کنید.'}})
$links=@{OpenSettings='ms-settings:'; OpenUpdate='ms-settings:windowsupdate'; OpenSecurity='windowsdefender:'; OpenTroubleshoot='ms-settings:troubleshoot'; OpenOdt='https://www.microsoft.com/en-us/download/details.aspx?id=49117'; OpenOffice='https://account.microsoft.com/services'}
foreach($k in $links.Keys){$script:UI[$k].Tag=$links[$k];$script:UI[$k].Add_Click({try{Open-Official ([string]$this.Tag)}catch{Show-Message $_.Exception.Message}})}
$script:UI.OpenVendor.Add_Click({Open-Official $script:Vendors[(Get-Choice $script:UI.AntivirusVendor)].Url})
$script:UI.OpenRestore.Add_Click({Start-Process -FilePath (Join-Path $env:windir 'System32\SystemPropertiesProtection.exe')})
$script:UI.OpenDeviceManager.Add_Click({Start-Process -FilePath (Join-Path $env:windir 'System32\mmc.exe') -ArgumentList 'devmgmt.msc'})
$script:UI.OpenGuide.Add_Click({[void](Show-TextDialog 'راهنمای WindowsCare' (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'README.fa.md') -Raw -Encoding UTF8))})
$script:UI.OpenHistory.Add_Click({[void][IO.Directory]::CreateDirectory($script:DataRoot);Start-Process -FilePath explorer.exe -ArgumentList (ConvertTo-NativeArgument $script:DataRoot)})
$script:UI.OpenReport.Add_Click({if($script:LastDirectory -and (Test-Path -LiteralPath (Join-Path $script:LastDirectory 'report.html'))){Start-Process -FilePath (Join-Path $script:LastDirectory 'report.html')}else{Show-Message 'هنوز گزارشی وجود ندارد.'}})
$script:Timer=New-Object Windows.Threading.DispatcherTimer; $script:Timer.Interval=[timespan]::FromMilliseconds(750)
$script:Timer.Add_Tick({
    if (-not $script:Active) { return }
    try {
        $job=$script:Active.Directory; $statusPath=Join-Path $job 'status.json'; $s=$null
        if(Test-Path -LiteralPath $statusPath){$s=Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json;$script:UI.Status.Text=$s.Message}
        $logPath=Join-Path $job 'operation.log'
        if(Test-Path -LiteralPath $logPath){$script:UI.Log.Text=(Get-Content -LiteralPath $logPath -Tail 55) -join "`r`n"; $script:UI.Log.ScrollToEnd()}
        $exited=$false
        try { $script:Active.Process.Refresh(); $exited=$script:Active.Process.HasExited } catch { }
        $finished=$s -and $s.State -in @('Completed','Warning','Failed','Cancelled')
        if ($finished -or $exited) {
            $results=Join-Path $job 'result.json'; $script:Displayed=@()
            if(Test-Path -LiteralPath $results){$loaded=Get-Content -LiteralPath $results -Raw | ConvertFrom-Json; if($null -ne $loaded){$script:Displayed=@($loaded)}}
            $script:UI.Results.ItemsSource=$script:Displayed; $script:LastAction=$script:Active.Action
            $script:UI.ResultTitle.Text=$script:Actions[$script:LastAction].Title+' | '+$script:Displayed.Count+' نتیجه'
            if($script:LastAction -eq 'DriverInspect' -and $script:Displayed.Count){$script:DriverHash=$script:Displayed[0].ArchiveHash;$script:DriverPath=$script:Active.Options.Archive}
            if(-not (Test-Path -LiteralPath $statusPath) -or $s.State -eq 'Running'){$script:UI.Status.Text='پردازش متوقف شد یا شروع نشد؛ گزارش را بررسی کنید. عملیات خودکار تکرار نمی‌شود.'}
            $script:Active.Process.Dispose();$script:Active=$null;$script:UI.Tabs.IsEnabled=$true;$script:UI.AllowNoRestore.IsEnabled=$true;$script:UI.Cancel.IsEnabled=$false;$script:UI.Progress.IsIndeterminate=$false
        }
    } catch { $script:UI.Status.Text='خواندن گزارش موقتاً ممکن نبود: '+$_.Exception.Message }
})
$script:Window.Add_Closing({param($sender,$e);if($script:Active){$e.Cancel=$true;Show-Message 'عملیات هنوز فعال است. تا پایان یا توقف در مرز امن صبر کنید.'}})
if ($SelfTest -or $RenderDirectory) {
    foreach($a in $script:Actions.Keys){if(-not $script:UI.ContainsKey($a)){throw ('دکمه عملیات یافت نشد: '+$a)}}
    if ($RenderDirectory) {
        [void][IO.Directory]::CreateDirectory($RenderDirectory)
        $script:Window.WindowStartupLocation='Manual'; $script:Window.Left=-20000; $script:Window.Top=-20000
        $script:Window.ShowActivated=$false; $script:Window.ShowInTaskbar=$false; $script:Window.Show()
        $script:Displayed=@((New-Row 'Windows 11 Pro' 'نمونه نمایشی برای آزمون رابط — داده واقعی دستگاه نیست'),(New-Row 'فضای ذخیره‌سازی' '125 GB free / 512 GB | NTFS' 'C:\'),(New-Row 'نتیجه بررسی' 'آماده برای انتخاب و بررسی گزارش'))
        $script:UI.Results.ItemsSource=$script:Displayed
        foreach($idx in @(0,2,6,7)) {
            $script:UI.Tabs.SelectedIndex=$idx
            $script:Window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
            $script:Window.UpdateLayout()
            $bmp=[Windows.Media.Imaging.RenderTargetBitmap]::new(1180,900,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bmp.Render($script:Window)
            $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
            $stream=[IO.File]::Create((Join-Path $RenderDirectory ('tab-'+$idx+'.png')));try{$encoder.Save($stream)}finally{$stream.Dispose()}
        }
        $script:Window.Close()
    }
    Write-Output ('UI smoke test passed: '+$script:UI.Count+' controls, '+$script:Actions.Count+' actions.'); return
}
$sessionLock=[Threading.Mutex]::new($false,'Local\WindowsCare-GUI')
$sessionHeld=$false
try {
    try { $sessionHeld=$sessionLock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $sessionHeld=$true }
    if (-not $sessionHeld) { [void][Windows.MessageBox]::Show('یک پنجره WindowsCare از قبل باز است.','WindowsCare'); return }
    $script:Timer.Start()
    [void]$script:Window.ShowDialog()
} finally { $script:Timer.Stop(); if ($sessionHeld) { $sessionLock.ReleaseMutex() }; $sessionLock.Dispose() }
