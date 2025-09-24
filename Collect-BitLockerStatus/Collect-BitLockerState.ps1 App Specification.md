### **Collect-BitLockerState.ps1 Application Specification**

**1\. Scripting Environment and Prerequisites**

* **PowerShell Version**: The script must be written for PowerShell 5.1 or a newer version.

* **Execution Context**: The script must be run with administrator privileges.

---

### **2\. Output and Logging**

* **Log Location**: The script must prompt the user to choose a directory for the output logs, either their Documents folder or C:\\Windows\\temp.

* **Folder Structure**: A new subfolder must be created within the chosen location with a name formatted as BitLockerLogs-DD-MM-YYYY-HH-MM.

* **Activity Log**: A log file named Get-BitLockerState.log should be created within the new folder to record the script's activities.

---

### **3\. Data Collection Commands and Output Files**

The script will collect the following information and save it to individual files within the created log folder:

* **BitLocker Volume Information**:  
  * **Command**: Get-BitLockerVolume.

  * **Output File**: The output will be saved to a text file named Get-BitLockerVolume.txt.

* **manage-bde Status**:  
  * **Command**: manage-bde \-status.

  * **Output File**: The output will be saved to a text file named Manage-BDE_Status.txt.

* **TPM Status**:  
  * **Command**: Get-Tpm.

  * **Output File**: The output will be saved to a text file named Get-TPM.txt.

* **Windows Recovery Environment (WinRE) Status**:  
  * **Command**: reagentc /info.

  * **Output File**: The output will be saved to a text file named Reagentc.txt.

* **BitLocker Event Logs**:  
  * **Log Source**: Microsoft-Windows-BitLocker-API/Management.

  * **Output File**: The exported log will be saved to an Event Viewer file (.evtx) named Microsoft-Windows-BitLocker-API\_Management.evtx.

* **System Event Logs**:  
  * **Log Source**: System.

  * **Output File**: The exported log will be saved to an Event Viewer file (.evtx) named system.evtx.

---

### **4\. Purpose**

The purpose of this script is to help troubleshoot BitLocker issues by collecting key information into a single, organized report18. The gathered data includes the BitLocker status of volumes, key protector details, TPM status, and relevant event logs.

---

### **5\. Additional Information**

This script combines several PowerShell cmdlets and command-line tools to provide a comprehensive overview of a system's BitLocker configuration and state.