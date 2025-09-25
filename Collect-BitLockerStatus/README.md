# Collect-BitLockerState.ps1

## Overview
`Collect-BitLockerState.ps1` gathers BitLocker configuration and diagnostic information from a Windows device and exports it into a timestamped folder. Use this when troubleshooting BitLocker encryption, TPM, Windows Recovery Environment (WinRE) issues, Group Policy BitLocker settings (FVE), and optionally MDM diagnostics.

## Requirements
- PowerShell 5.1 or newer
- Run in an elevated PowerShell session (Run as Administrator)
- Windows environment with access to:
  - `Get-BitLockerVolume` (BitLocker cmdlet)
  - `manage-bde.exe`
  - `Get-Tpm`
  - `reagentc.exe`
  - `wevtutil.exe`
  - `reg.exe`
  - (Optional) `mdmdiagnosticstool.exe` for MDM diagnostics

## What the script does
- Determines a non-interactive output base location (in this order):
  - `-OutputPath <path>` if specified
  - else `-UseTemp` uses `C:\Windows\Temp`
  - else defaults to the current user's Documents folder
- Creates a new subfolder named:
  - `BitLockerLogs-DD-MM-YYYY-HH-MM`
- Writes an activity log named `Get-BitLockerState.log`
- Collects the following outputs:
  - BitLocker volumes via `Get-BitLockerVolume` → `Get-BitLockerVolume.txt`
  - TPM status via `Get-Tpm` → `Get-TPM.txt`
  - WinRE status via `reagentc /info` → `Reagentc.txt`
- Exports event logs (EVTX):
  - `Microsoft-Windows-BitLocker-API/Management` → `Microsoft-Windows-BitLocker-API_Management.evtx`
  - `System` → `system.evtx`
  - Exports BitLocker policy registry (FVE):
    - `HKLM\Software\Policies\Microsoft\FVE` → `FVE_Policies.reg`
  - (Optional) With `-MDM`:
    - Generates (or reuses existing) MDM diagnostics under `MDM\` via `mdmdiagnosticstool.exe -out "<LogRoot>\\MDM"`
    - Parses `MDMDiagReport.xml` for BitLocker Area nodes and saves them to `MDM\\BitlockerMDM.xml`

## Usage

1) Open PowerShell as Administrator.
2) Optional: allow script execution for the current session:

## Output structure (example)
Without `-MDM`:
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```
  Run one of the following PowerShell 5.1 examples:
  
  # Default (Logs to My Documents)
  .\Collect-BitLockerState.ps1
  
  # Uses Windows Temp
  .\Collect-BitLockerState.ps1 -UseTemp
  
  # Custom log folder
  .\Collect-BitLockerState.ps1 -OutputPath "D:\Support\Logs"
  
  # Include MDM diagnostics and use Windows temp folder
  .\Collect-BitLockerState.ps1 -MDM -UseTemp
```

  ## Output structure (example)
  Without `-MDM`:
  ```
  <Documents or C:\Windows\Temp or OutputPath>\BitLockerLogs-DD-MM-YYYY-HH-MM\
    Get-BitLockerVolume.txt
    Manage-BDE_Status.txt
    Get-TPM.txt
    Reagentc.txt
    Microsoft-Windows-BitLocker-API_Management.evtx
    system.evtx
    FVE_Policies.reg
    Get-BitLockerState.log
  ```

  With `-MDM` (additional items):
  ```
  <...>\BitLockerLogs-DD-MM-YYYY-HH-MM\
    MDM\
      ... MDM artifacts ...
      DeviceManagement-Enterprise-Diagnostics-Provider.evtx
      MDMDiagReport.html
      MDMDiagReport.xml
      Microsoft-Windows-AAD.evtx
      Microsoft-Windows-Shell-Core.evtx
      ... Custom report ...
      BitlockerMDM.xml - BitLocker MDM configuration.
  
  ## Testing MDM XML extraction

To validate XML extraction without generating full diagnostics, place an `MDMDiagReport.xml` in the `MDM` folder and run with `-MDM`.

  Example:

  ```powershell
  New-Item -ItemType Directory -Path "<LogRoot>\MDM" -Force | Out-Null
  Copy-Item "<path>\MDMDiagReport.xml" "<LogRoot>\MDM\MDMDiagReport.xml" -Force
  .\Collect-BitLockerState.ps1 -OutputPath "<LogRootParent>" -MDM
  ```

## Troubleshooting
- "This script must be run with Administrator privileges":
  - Close PowerShell and re-open as Administrator.
- Execution policy errors:
- `Get-BitLockerVolume` or `Get-Tpm` not found:
  - Ensure you are on a Windows edition that includes these cmdlets (typically Client/Server with BitLocker/TPM modules available).
- `manage-bde.exe`, `reagentc.exe`, or `wevtutil.exe` not found:
  - These should be available in `C:\Windows\System32`. Verify the OS installation and PATH.
- EVTX export fails:
  - Ensure the event logs exist and you have sufficient permissions. The script uses `wevtutil epl` with overwrite enabled.
- `MDMDiagReport.xml` not found (with `-MDM`):
  - Verify MDM logs were generated under `<LogRoot>\MDM` or manually place an XML report in that folder.
  - Confirm `mdmdiagnosticstool.exe` exists (usually `%WINDIR%\System32` or `%WINDIR%\Sysnative`).
  
### Log markers (STEP) for quick triage

Use these markers to quickly determine outcomes in `Get-BitLockerState.log`.

Quick search example:

```powershell
Select-String -Path "<LogRoot>\Get-BitLockerState.log" -Pattern "STEP: MDM XML parsing|STEP: .* event log export|STEP: FVE registry export"
```

Markers:

- XML success: `STEP: MDM XML parsing succeeded; output='<full path>'; count=<Area nodes>`
- XML failure (not found): `STEP: MDM XML parsing failed; reason='MDMDiagReport.xml not found'; folder='<MDM folder>'`
- XML failure (no areas): `STEP: MDM XML parsing failed; reason='no BitLocker Area nodes'; file='<xml path>'`
- XML failure (exception): `STEP: MDM XML parsing failed; reason='exception'; file='<xml path>'; error='<message>'`

### Log markers (STEP) for quick triage

Use these markers to quickly determine MDM parsing outcomes in the activity log (`Get-BitLockerState.log`).

Quick search example:

```powershell
Select-String -Path "<LogRoot>\Get-BitLockerState.log" -Pattern "STEP: MDM .* parsing"
```

Markers:

- HTML success: `STEP: MDM HTML parsing succeeded; output='<full path>'`
- HTML failure (not found): `STEP: MDM HTML parsing failed; reason='MDMDiagReport.html not found'; folder='<MDM folder>'`
- HTML failure (no section): `STEP: MDM HTML parsing failed; reason='BitLocker section not found'; file='<report path>'`
- HTML failure (unreadable): `STEP: MDM HTML parsing failed; reason='file unreadable or empty'; file='<report path>'`
- XML success: `STEP: MDM XML parsing succeeded; output='<full path>'; count=<Area nodes>`
- XML failure (not found): `STEP: MDM XML parsing failed; reason='MDMDiagReport.xml not found'; folder='<MDM folder>'`
- XML failure (no areas): `STEP: MDM XML parsing failed; reason='no BitLocker Area nodes'; file='<xml path>'`
- XML failure (exception): `STEP: MDM XML parsing failed; reason='exception'; file='<xml path>'; error='<message>'`

## Privacy
The output may include sensitive system information and logs. Share the resulting folder only with trusted parties for support or troubleshooting.

## License
MIT, use it, but at your own peril. :)
