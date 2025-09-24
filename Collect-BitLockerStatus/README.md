# Collect-BitLockerState.ps1

## Overview
`Collect-BitLockerState.ps1` gathers BitLocker configuration and diagnostic information from a Windows device and exports it into a timestamped folder. Use this when troubleshooting BitLocker encryption, TPM, or Windows Recovery Environment issues.

## Requirements
- PowerShell 5.1 or newer
- Run in an elevated PowerShell session (Run as Administrator)
- Windows environment with access to:
  - `Get-BitLockerVolume` (BitLocker cmdlet)
  - `manage-bde.exe`
  - `Get-Tpm`
  - `reagentc.exe`
  - `wevtutil.exe`

## What the script does
- Prompts you to choose an output base location:
  - Your Documents folder, or
  - `C:\Windows\Temp`
- Creates a new subfolder named:
  - `BitLockerLogs-DD-MM-YYYY-HH-MM`
- Writes an activity log named `Get-BitLockerState.log`
- Collects the following outputs:
  - BitLocker volumes via `Get-BitLockerVolume` → `Get-BitLockerVolume.txt`
  - BitLocker status via `manage-bde -status` → `Manage-BDE_Status.txt`
  - TPM status via `Get-Tpm` → `Get-TPM.txt`
  - WinRE status via `reagentc /info` → `Reagentc.txt`
- Exports event logs (EVTX):
  - `Microsoft-Windows-BitLocker-API/Management` → `Microsoft-Windows-BitLocker-API_Management.evtx`
  - `System` → `system.evtx`

All operations are logged to `Get-BitLockerState.log`. If any tool/cmdlet is unavailable, the script logs a warning and continues.

## Usage
1) Open PowerShell as Administrator.
2) Navigate to the script directory:
```
cd "c:\Users\KevinKaminski\Documents\GitHub\ModernDesktopStuff\Collect-BitLockerStatus"
```
3) Run the script (allowing execution for the current session if needed):
```
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\Collect-BitLockerState.ps1
```
4. When prompted, choose `1` (Documents) or `2` (Windows Temp) for the output location.

   ![1](.\images\1.png)

5. Upon completion, the console will show the output folder path and activity log file.

   ![2](.\images\2.png)

## Output structure (example)
```
<Documents or C:\Windows\Temp>\BitLockerLogs-DD-MM-YYYY-HH-MM\
  Get-BitLockerVolume.txt
  Manage-BDE_Status.txt
  Get-TPM.txt
  Reagentc.txt
  Microsoft-Windows-BitLocker-API_Management.evtx
  system.evtx
  Get-BitLockerState.log
```

## Notes
- The script is read-only with respect to your BitLocker/TPM/WinRE configuration; it only collects state and exports logs.
- EVTX files can be opened in Event Viewer (File → Open Saved Log...).
- If running on systems without BitLocker or TPM support, related sections will be skipped with warnings in the activity log.

## Troubleshooting
- "This script must be run with Administrator privileges":
  - Close PowerShell and re-open as Administrator.
- Execution policy errors:
  - Use the provided `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force` for the current session.
- `Get-BitLockerVolume` or `Get-Tpm` not found:
  - Ensure you are on a Windows edition that includes these cmdlets (typically Client/Server with BitLocker/TPM modules available).
- `manage-bde.exe`, `reagentc.exe`, or `wevtutil.exe` not found:
  - These should be available in `C:\Windows\System32`. Verify the OS installation and PATH.
- EVTX export fails:
  - Ensure the event logs exist and you have sufficient permissions. The script uses `wevtutil epl` with overwrite enabled.

## Privacy
The output may include sensitive system information and logs. Share the resulting folder only with trusted parties for support or troubleshooting.

## License
MIT, use it, but at your own peril. :)
