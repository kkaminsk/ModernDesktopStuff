# Collect-AppLockerStatus

PowerShell script to collect AppLocker diagnostic artifacts from a Windows device. It exports relevant AppLocker event logs, the effective AppLocker policy, and (optionally) zips the collection for easy sharing.

## Requirements

- PowerShell 5.1 or newer
- Run as Administrator (the script enforces an elevation check and exits if not elevated)
- Windows (uses built-in tools like `wevtutil` and `Compress-Archive`)

## Usage

Run from an elevated PowerShell prompt:

```powershell
# Default: writes under the current user's Documents folder
.\Collect-AppLockerStatus.ps1

# Use Windows temp folder (C:\Windows\Temp)
.\Collect-AppLockerStatus.ps1 -UseTemp

# Custom output path
.\Collect-AppLockerStatus.ps1 -OutputPath "D:\Support\Logs"

# Create a ZIP after collection (ZIP is placed next to the log root)
.\Collect-AppLockerStatus.ps1 -UseTemp -ZIP

# If your ExecutionPolicy blocks the script, you can bypass for the current session
PowerShell -NoProfile -ExecutionPolicy Bypass -File .\Collect-AppLockerStatus.ps1 -UseTemp -ZIP
```

## Parameters

- `-OutputPath <string>`
  - Base folder in which a timestamped `AppLockerLogs-<dd-MM-yyyy-HH-mm>` folder is created.
  - If omitted and `-UseTemp` is not specified, the script uses the current user's Documents folder.
- `-UseTemp`
  - If provided, the base folder will be `C:\Windows\Temp`.
- `-ZIP`
  - If provided, a ZIP archive named `<COMPUTERNAME>-AppLockerLogs-<dd-MM-yyyy-HH-mm>.zip` is created in the parent of the log root after collection completes.

## What gets collected

Inside the log root, the script produces:

- `Microsoft-Windows-AppLocker-EXEandDLL.evtx`
  - From channel: `Microsoft-Windows-AppLocker/EXE and DLL`
- `Microsoft-Windows-AppLocker-MSIandScript.evtx`
  - From channel: `Microsoft-Windows-AppLocker/MSI and Script`
- `Microsoft-Windows-AppLocker-Packagedapp-Deployment.evtx`
  - From channel: `Microsoft-Windows-AppLocker/Packaged app-Deployment`
- `Microsoft-Windows-AppLocker-Packagedapp-Execution.evtx`
  - From channel: `Microsoft-Windows-AppLocker/Packaged app-Execution`
- `application.evtx`
  - From log: `Application`
- `AppLockerPolicy.xml`
  - From: `Get-AppLockerPolicy -Effective -Xml`
- `Get-AppLockerStatus.log`
  - Activity log with timestamps and STEP markers

When `-ZIP` is used, a ZIP named `<COMPUTERNAME>-AppLockerLogs-<dd-MM-yyyy-HH-mm>.zip` is created in the parent folder of the log root and contains the entire log root.

## Output folder structure (example)

```
C:\Windows\Temp\AppLockerLogs-26-09-2025-16-32\
  Microsoft-Windows-AppLocker-EXEandDLL.evtx
  Microsoft-Windows-AppLocker-MSIandScript.evtx
  Microsoft-Windows-AppLocker-Packagedapp-Deployment.evtx
  Microsoft-Windows-AppLocker-Packagedapp-Execution.evtx
  application.evtx
  AppLockerPolicy.xml
  Get-AppLockerStatus.log

C:\Windows\Temp\<COMPUTERNAME>-AppLockerLogs-26-09-2025-16-32.zip  (when -ZIP is used)
```

## STEP log markers (quick triage)

Quick search example:

```powershell
Select-String -Path "<LOG_ROOT>\Get-AppLockerStatus.log" -Pattern "STEP: .* event log export|STEP: AppLocker policy export|STEP: ZIP archive"
```

Markers emitted by the script:

- AppLocker event log export success:
  - `STEP: AppLocker event log export succeeded; channel='<channel>'; output='<full path>'`
- AppLocker event log export failure:
  - `STEP: AppLocker event log export failed; reason='export failed'; exit=<code>; exists=<bool>; sizeOK=<bool>; file='<full path>'`
  - `STEP: AppLocker event log export failed; reason='exception'; channel='<channel>'; file='<full path>'; error='<message>'`
- Application event log export success:
  - `STEP: Application event log export succeeded; output='<full path>'`
- Application event log export failure:
  - `STEP: Application event log export failed; exit=<code>; exists=<bool>; sizeOK=<bool>; file='<full path>'`
  - `STEP: Application event log export failed; reason='exception'; error='<message>'`
- AppLocker policy export success:
  - `STEP: AppLocker policy export succeeded; output='<full path>'`
- AppLocker policy export failure:
  - `STEP: AppLocker policy export failed; reason='empty or missing file'; file='<full path>'`
  - `STEP: AppLocker policy export failed; reason='exception'; file='<full path>'; error='<message>'`
- ZIP archive:
  - `STEP: ZIP archive succeeded; output='<full path>'`
  - `STEP: ZIP archive failed; reason='empty or missing zip'; file='<full path>'`
  - `STEP: ZIP archive failed; reason='exception'; error='<message>'`

## Notes & troubleshooting

- Some channels may not exist on all systems; failures are logged with detailed reasons.
- Ensure the script is run as Administrator; otherwise it exits with code 2 and a clear message.
- If your organization restricts script execution, use a signed script or run via `-ExecutionPolicy Bypass` in a trusted administrative session.
