$script:Actions = @{
    SystemInfo = @{Title='بررسی وضعیت سیستم'; Admin=$false; Change=$false; Restore=$false}
    UpdateScan = @{Title='جست‌وجوی آپدیت‌های ویندوز'; Admin=$false; Change=$false; Restore=$false}
    DriverScan = @{Title='جست‌وجوی آپدیت درایورها'; Admin=$false; Change=$false; Restore=$false}
    UpdateInstall = @{Title='نصب آپدیت‌های انتخابی'; Admin=$true; Change=$true; Restore=$true}
    DiskInfo = @{Title='بررسی وضعیت دیسک'; Admin=$true; Change=$false; Restore=$false}
    DiskScan = @{Title='اسکن آنلاین فایل‌سیستم NTFS'; Admin=$true; Change=$true; Restore=$false}
    DiskRepair = @{Title='تعمیر آفلاین درایو انتخابی'; Admin=$true; Change=$true; Restore=$true}
    DiskOptimize = @{Title='بهینه‌سازی دیسک با تشخیص ویندوز'; Admin=$true; Change=$true; Restore=$false}
    LargeFiles = @{Title='یافتن فایل‌های حجیم'; Admin=$false; Change=$false; Restore=$false}
    DuplicateFiles = @{Title='یافتن فایل‌های تکراری'; Admin=$false; Change=$false; Restore=$false}
    TempFiles = @{Title='فهرست فایل‌های موقت قدیمی کاربر'; Admin=$false; Change=$false; Restore=$false}
    RecycleFiles = @{Title='انتقال فایل‌های انتخابی به سطل بازیافت'; Admin=$false; Change=$true; Restore=$false}
    DriverList = @{Title='فهرست درایورها و دستگاه‌های مشکل‌دار'; Admin=$false; Change=$false; Restore=$false}
    DriverBackup = @{Title='پشتیبان ZIP درایورها'; Admin=$true; Change=$false; Restore=$false}
    DriverInspect = @{Title='بررسی بسته پشتیبان درایور'; Admin=$false; Change=$false; Restore=$false}
    DriverRestore = @{Title='نصب بسته درایور روی دستگاه مقصد'; Admin=$true; Change=$true; Restore=$true}
    SecurityInfo = @{Title='وضعیت امنیت و آنتی‌ویروس'; Admin=$false; Change=$false; Restore=$false}
    DefenderUpdate = @{Title='به‌روزرسانی امضای Defender'; Admin=$true; Change=$true; Restore=$false}
    DefenderQuick = @{Title='اسکن سریع Defender'; Admin=$true; Change=$true; Restore=$false}
    DefenderFull = @{Title='اسکن کامل Defender'; Admin=$true; Change=$true; Restore=$false}
    AntivirusInstall = @{Title='اجرای نصب‌کننده رسمی آنتی‌ویروس'; Admin=$true; Change=$true; Restore=$true}
    WindowsCheck = @{Title='بررسی سلامت فایل‌های ویندوز'; Admin=$true; Change=$false; Restore=$false}
    WindowsRepair = @{Title='تعمیر فایل‌های ویندوز'; Admin=$true; Change=$true; Restore=$true}
    NetworkInfo = @{Title='گزارش عیب‌یابی شبکه'; Admin=$false; Change=$false; Restore=$false}
    NetworkRepair = @{Title='بازنشانی DNS و Winsock'; Admin=$true; Change=$true; Restore=$true}
    UpdateRepair = @{Title='راه‌اندازی مجدد سرویس‌های Windows Update'; Admin=$true; Change=$true; Restore=$true}
    AudioRepair = @{Title='راه‌اندازی مجدد سرویس صدای ویندوز'; Admin=$true; Change=$true; Restore=$true}
    PrintRepair = @{Title='راه‌اندازی مجدد سرویس چاپ'; Admin=$true; Change=$true; Restore=$true}
    RestorePoint = @{Title='ساخت نقطه بازیابی'; Admin=$true; Change=$true; Restore=$false}
    OfficeConfig = @{Title='ساخت تنظیمات نصب Office'; Admin=$false; Change=$false; Restore=$false}
    OfficeInstall = @{Title='نصب Office با ابزار رسمی'; Admin=$true; Change=$true; Restore=$true}
}
$script:OfficeProducts = [ordered]@{
    'Microsoft 365 Enterprise'=@{Id='O365ProPlusRetail'; Channel='Current'; Apps=@('Word','Excel','PowerPoint','Outlook','OneNote','Access')}
    'Microsoft 365 Business'=@{Id='O365BusinessRetail'; Channel='Current'; Apps=@('Word','Excel','PowerPoint','Outlook','OneNote','Access')}
    'Office 2021 Home & Business'=@{Id='HomeBusiness2021Retail'; Channel='Current'; Apps=@('Word','Excel','PowerPoint','Outlook','OneNote')}
    'Office 2024 Home & Business'=@{Id='HomeBusiness2024Retail'; Channel='Current'; Apps=@('Word','Excel','PowerPoint','Outlook','OneNote')}
    'Office LTSC 2021 Professional Plus'=@{Id='ProPlus2021Volume'; Channel='PerpetualVL2021'; Apps=@('Word','Excel','PowerPoint','Outlook','OneNote','Access')}
    'Office LTSC 2024 Professional Plus'=@{Id='ProPlus2024Volume'; Channel='PerpetualVL2024'; Apps=@('Word','Excel','PowerPoint','Outlook','OneNote','Access')}
}
$script:Vendors = [ordered]@{
    'ESET'=@{Url='https://www.eset.com/int/home/'; Publisher='ESET, spol. s r.o.'}
    'Bitdefender'=@{Url='https://www.bitdefender.com/en-us/consumer'; Publisher='Bitdefender SRL'}
    'Malwarebytes'=@{Url='https://www.malwarebytes.com/'; Publisher='Malwarebytes Inc.'}
}
