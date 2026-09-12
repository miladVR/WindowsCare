@echo off
setlocal
set "CarePowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "CarePowerShell=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%CarePowerShell%" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0WindowsCare.ps1"
if errorlevel 1 pause
endlocal
