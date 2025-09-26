### **Collect-AppLockerStatus.ps1 Application Specification**

**1. Scripting Environment and Prerequisites**
* **PowerShell Version**: The script must be written for PowerShell 5.1 or a newer version.
* **Execution Context**: The script must be run with administrator privileges.
### **2. Output and Logging**

* **Log Location (non-interactive)**: The base output folder is determined as follows:
  * If `-OutputPath <path>` is provided, use that path.
  * Else if `-UseTemp` is provided, use `C:\\Windows\\Temp`.
  * Else, default to the user's Documents folder.
* **Folder Structure**: A new subfolder must be created within the chosen location with a name formatted as AppLockerLogs-DD-MM-YYYY-HH-MM.
* **Activity Log**: A log file named Get-AppLockerStatus.log should be created within the new folder to record the script's activities.
 
 ---
 ### **3. Data Collection Commands and Output Files**
 
 {{ ... }}
 | `Microsoft-Windows-AppLocker-EXEandDLL.evtx` | Always | `wevtutil epl 'Microsoft-Windows-AppLocker/EXE and DLL'` |
 | `Microsoft-Windows-AppLocker-MSIandScript.evtx` | Always | `wevtutil epl 'Microsoft-Windows-AppLocker/MSI and Script'` |
 | `Microsoft-Windows-AppLocker-Packagedapp-Deployment.evtx` | Always | `wevtutil epl 'Microsoft-Windows-AppLocker/Packaged app-Deployment'` |
 | `Microsoft-Windows-AppLocker-Packagedapp-Execution.evtx` | Always | `wevtutil epl 'Microsoft-Windows-AppLocker/Packaged app-Execution'` |
 | `application.evtx` | Always | `wevtutil epl 'Application'` |
 | `<COMPUTERNAME>-AppLockerLogs-<date>-<time>.zip` | With `-ZIP` | ZIP archive of the entire output folder (created in the parent of the log root) |
  | `Get-AppLockerStatus.log` | Always | Activity log with timestamps |

---
 
 ### **8. Log markers (STEP) for quick triage**
 
 Use these markers in the activity log (`Get-AppLockerStatus.log`) to quickly determine outcomes.
 
 {{ ... }}
 
 ```powershell
 Select-String -Path "<LOG_ROOT>\Get-AppLockerStatus.log" -Pattern "STEP: .* event log export|STEP: AppLocker policy export|STEP: ZIP archive"
 ```
 
 Markers:
 
 - AppLocker event log export success: `STEP: AppLocker event log export succeeded; channel='<channel>'; output='<full path>'`
 - Application event log export success: `STEP: Application event log export succeeded; output='<full path>'`
 - Application event log export failure: `STEP: Application event log export failed; exit=<code>; exists=<bool>; sizeOK=<bool>; file='<full path>'`
 - AppLocker policy export success: `STEP: AppLocker policy export succeeded; output='<full path>'`
 - AppLocker policy export failure: `STEP: AppLocker policy export failed; reason='exception'; file='<full path>'; error='<message>'`
