# WindowsCare

Persian, right-to-left Windows maintenance GUI for Windows PowerShell 5.1 x64. **Preview — not yet validated for production maintenance.**

Read the complete [Persian guide](README.fa.md) for functionality, limitations, safety controls and test coverage.

Download a versioned ZIP, extract it and run `Start-WindowsCare.cmd`. Opening the GUI does not start repairs or installations. Administrator elevation is requested for specific operations. Internet launch commands are generated per release with a pinned SHA256; unsigned code remains subject to Windows and organizational application-control policies.

Features: Windows Update and driver selection, Office Deployment Tool configuration/installation, Defender scans, verified third-party antivirus installer launch, DISM/SFC, targeted service/network repair, disk inspection and optimization, selected-file recycling, hash-based duplicate search, driver ZIP backup/restore, HTML/JSON/CSV logs.

Source layout: `WindowsCare.ps1` (WPF controller), `Worker.ps1` (isolated job runner), `Modules/` (operations), `UI/` (XAML), `Tests/` (non-destructive tests), `Tools/` (release packaging).

No credentials, licenses, activation keys, telemetry or personal test reports belong in this repository. Read [PUBLISHING.fa.md](PUBLISHING.fa.md) before publishing. No open-source license has been selected yet; public visibility alone does not grant reuse rights beyond applicable platform terms.
