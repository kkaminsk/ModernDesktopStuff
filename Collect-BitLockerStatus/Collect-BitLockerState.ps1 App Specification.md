### **Collect-BitLockerState.ps1 Application Specification**

**1\. Scripting Environment and Prerequisites**

* **PowerShell Version**: The script must be written for PowerShell 5.1 or a newer version.
* **Execution Context**: The script must be run with administrator privileges.

### **2\. Output and Logging**

* **Log Location (non-interactive)**: The base output folder is determined as follows:
  * If `-OutputPath <path>` is provided, use that path.
  * Else if `-UseTemp` is provided, use `C:\\Windows\\Temp`.
  * Else, default to the user's Documents folder.
* **Folder Structure**: A new subfolder must be created within the chosen location with a name formatted as BitLockerLogs-DD-MM-YYYY-HH-MM.
* **Activity Log**: A log file named Get-BitLockerState.log should be created within the new folder to record the script's activities.

### **3\. Data Collection Commands and Output Files**
{{ ... }}
| Microsoft-Windows-BitLocker-API_Management.evtx` | Always | `wevtutil epl 'Microsoft-Windows-BitLocker-API/Management'` (falls back to alternate channel if needed) |
| application.evtx` | Always | `wevtutil epl Application'` |
  | `<COMPUTERNAME>-BitLockerLogs-<date>-<time>.zip` | With `-ZIP` | ZIP archive of the entire output folder (created in the parent of the log root) |
  | `Get-BitLockerState.log` | Always | Activity log with timestamps |

---

### **6\. Parameters**
{{ ... }}
{{ ... }}
* `-OutputPath <path>` (string, optional):
  - Fully qualified base folder into which the timestamped `AppLockerLogs-<date>-<time>` folder is created. If omitted, the script uses the user's Documents folder unless `-UseTemp` is set.

* `-UseTemp` (switch, optional):

 * `-ZIP` (switch, optional):
  - When present, the script creates a ZIP archive named `<COMPUTERNAME>-AppLockerLogs-<date>-<time>.zip` in the parent folder of the log root once all collection steps complete.

Example usages:

* Default (Documents):
  - `...\Collect-AppLockerState.ps1`
  {{ ... }}
  - `...\Collect-AppLockerState.ps1 -UseTemp -MDM`
 * Custom folder and MDM:
  - `...\Collect-AppLockerState.ps1 -OutputPath "D:\\Support\\Logs" -MDM`

---

### **8\. Log markers (STEP) for quick triage**

Use these markers in the activity log (`Get-AppLockerState.log`) to quickly determine outcomes.

- 