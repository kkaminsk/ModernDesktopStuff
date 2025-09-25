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

* **Conditional Output (MDM)**: When the `-MDM` switch is used:
  * MDM diagnostics will be saved to a subfolder named `MDM` inside the selected log folder.
  * BitLocker Area entries parsed from `MDMDiagReport.xml` will be saved as `MDM\\BitlockerMDM.xml` in the `MDM` folder.

---

### **3\. Data Collection Commands and Output Files**
{{ ... }}
| `Reagentc.txt` | Always | `reagentc /info` |
| `Microsoft-Windows-BitLocker-API_Management.evtx` | Always | `wevtutil epl 'Microsoft-Windows-BitLocker-API/Management'` (falls back to alternate channel if needed) |
| `system.evtx` | Always | `wevtutil epl 'System'` |
| `FVE_Policies.reg` | Always | `reg.exe export HKLM\Software\Policies\Microsoft\FVE FVE_Policies.reg /y` (may be empty/missing if key not present) |
| `MDM\` (folder) | With `-MDM` | Output of `mdmdiagnosticstool.exe -out "<LOG_ROOT>\MDM"`  | `MDM\\MDMDiagReport.html` | With `-MDM` | MDM diagnostics report (generated or reused) |
  | `MDM\\BitlockerMDM.xml` | With `-MDM` and BitLocker Area entries found | Extracted `<Area>` nodes (PolicyAreaName = BitLocker) from `MDMDiagReport.xml` |
  | `<COMPUTERNAME>-BitLockerLogs-<date>-<time>.zip` | With `-ZIP` | ZIP archive of the entire output folder (created in the parent of the log root) |
  | `Get-BitLockerState.log` | Always | Activity log with timestamps |

---

### **6\. Parameters**
{{ ... }}
{{ ... }}
* `-OutputPath <path>` (string, optional):
  - Fully qualified base folder into which the timestamped `BitLockerLogs-<date>-<time>` folder is created. If omitted, the script uses the user's Documents folder unless `-UseTemp` is set.

* `-UseTemp` (switch, optional):

 * `-ZIP` (switch, optional):
  - When present, the script creates a ZIP archive named `<COMPUTERNAME>-BitLockerLogs-<date>-<time>.zip` in the parent folder of the log root once all collection steps complete.

Example usages:

* Default (Documents):
  - `...\Collect-BitLockerState.ps1`
{{ ... }}
  - `...\Collect-BitLockerState.ps1 -UseTemp -MDM`
 * Custom folder and MDM:
  - `...\Collect-BitLockerState.ps1 -OutputPath "D:\\Support\\Logs" -MDM`
 
---

### **8\. Log markers (STEP) for quick triage**

Use these markers in the activity log (`Get-BitLockerState.log`) to quickly determine outcomes.

Quick search example:

```powershell
Select-String -Path "<LOG_ROOT>\Get-BitLockerState.log" -Pattern "STEP: MDM .* parsing|STEP: .* event log export|STEP: FVE registry export|STEP: ZIP archive"
```

Markers:

- XML success: `STEP: MDM XML parsing succeeded; output='<full path>'; count=<Area nodes>`
- XML failure (not found): `STEP: MDM XML parsing failed; reason='MDMDiagReport.xml not found'; folder='<MDM folder>'`
- XML failure (no areas): `STEP: MDM XML parsing failed; reason='no BitLocker Area nodes'; file='<xml path>'`
- XML failure (exception): `STEP: MDM XML parsing failed; reason='exception'; file='<xml path>'; error='<message>'`
- BitLocker event log export success: `STEP: BitLocker event log export succeeded; channel='<channel>'; output='<full path>'`
- BitLocker event log export failure: `STEP: BitLocker event log export failed; reason='no channel succeeded'; attempted='<channel list>'`
- System event log export success: `STEP: System event log export succeeded; output='<full path>'`
- System event log export failure: `STEP: System event log export failed; exit=<code>; exists=<bool>; sizeOK=<bool>; file='<full path>'`
- FVE registry export success: `STEP: FVE registry export succeeded; output='<full path>'`
- FVE registry export failure: `STEP: FVE registry export failed; exit=<code>; exists=<bool>; sizeOK=<bool>; file='<full path>'`