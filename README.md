# WindowsCare

Persian, right-to-left Windows maintenance GUI for Windows PowerShell 5.1 x64. **Preview — not yet validated for production maintenance.**

Read the complete [Persian guide](README.fa.md) for functionality, limitations, safety controls and test coverage.

## اجرای برنامه با یک دستور

نسخه عمومی آزمایشی **0.1.0-preview.1** منتشر شده است. در Windows PowerShell ویندوز ۱۰ یا ۱۱ نسخه ۶۴ بیتی، تمام خط زیر را کپی و اجرا کنید. برنامه پس از دانلود و تطبیق SHA256 باز می‌شود؛ هیچ نصب یا تعمیری صرفاً با بازشدن پنجره آغاز نمی‌شود.

```powershell
& { $ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; $d=Join-Path $env:LOCALAPPDATA ('WindowsCare\Downloads\'+[guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($d); $z=Join-Path $d 'app.zip'; Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/miladVR/WindowsCare/releases/download/v0.1.0-preview.1/WindowsCare-0.1.0-preview.1.zip' -OutFile $z; if ((Get-FileHash -LiteralPath $z -Algorithm SHA256).Hash -ne '005CFB3F9E95928A905B73D6313111DD7108DEAAF8F8061AC25146E26FB24C77') { throw 'Package verification failed' }; Expand-Archive -LiteralPath $z -DestinationPath (Join-Path $d 'app'); & (Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $d 'app\WindowsCare.ps1') }
```

[دانلود فایل دستور](https://github.com/miladVR/WindowsCare/releases/download/v0.1.0-preview.1/Run-WindowsCare.txt) · [دانلود ZIP](https://github.com/miladVR/WindowsCare/releases/download/v0.1.0-preview.1/WindowsCare-0.1.0-preview.1.zip) · [جزئیات نسخه](https://github.com/miladVR/WindowsCare/releases/tag/v0.1.0-preview.1) · [آزمون و ساخت موفق در GitHub](https://github.com/miladVR/WindowsCare/actions/runs/34693370327)

این نسخه بدون امضای ناشر است. ۸۹ بررسی خودکار و دانلود عمومی تأیید شده‌اند؛ نصب و تعمیر واقعی روی همه سیستم‌ها هنوز تأیید نشده است. اگر سیاست سازمان اجرای اسکریپت را مسدود می‌کند، با مدیر سیستم هماهنگ کنید.

Download a versioned ZIP, extract it and run `Start-WindowsCare.cmd`. Opening the GUI does not start repairs or installations. Administrator elevation is requested for specific operations. Internet launch commands are generated per release with a pinned SHA256; unsigned code remains subject to Windows and organizational application-control policies.

Features: Windows Update and driver selection, Office Deployment Tool configuration/installation, Defender scans, verified third-party antivirus installer launch, DISM/SFC, targeted service/network repair, disk inspection and optimization, selected-file recycling, hash-based duplicate search, driver ZIP backup/restore, HTML/JSON/CSV logs.

Source layout: `WindowsCare.ps1` (WPF controller), `Worker.ps1` (isolated job runner), `Modules/` (operations), `UI/` (XAML), `Tests/` (non-destructive tests), `Tools/` (release packaging).

No credentials, licenses, activation keys, telemetry or personal test reports belong in this repository. Read [PUBLISHING.fa.md](PUBLISHING.fa.md) before publishing. No open-source license has been selected yet; public visibility alone does not grant reuse rights beyond applicable platform terms.
