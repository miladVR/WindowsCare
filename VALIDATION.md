# Validation record — 2026-09-12

Local preview build, not a production certification.

- Windows PowerShell 5.1 x64 / STA: **89 assertions passed**.
- WPF: **75 named controls / 31 operation buttons** loaded successfully.
- The System, Office, Cleanup and Drivers screens were rendered with fixture data and visually inspected. Paths are explicitly left-to-right inside the Persian interface.
- Non-mutating worker integration passed for file discovery, Office XML generation and system information, including saved results and HTML reports.
- CIM hardware queries were denied by the test environment. The fallback path returned basic information with an explicit warning; complete hardware discovery was not validated here.
- Negative tests cover ZIP traversal/absolute paths/ADS/reserved names/case collisions/expansion limits, protected cleanup paths, modified files, selected duplicate keepers, invalid Office configurations and argument quoting.
- The recycle helper compiled successfully and rejected a nonexistent file. No actual file was recycled during validation.

Not executed on the host: Windows Update downloads/installations, Defender scans, Restore Point creation, Office or antivirus installation, driver export/install, DISM/SFC repair, network/service reset, CHKDSK, volume repair or optimization. These need a disposable VM and relevant hardware test matrix before a stable release.

No public GitHub release and no trusted publisher code-signing certificate were created as part of this local validation. Publishing remains a separate observable step. The built launcher pins a package SHA256; it does not assert publisher identity.
