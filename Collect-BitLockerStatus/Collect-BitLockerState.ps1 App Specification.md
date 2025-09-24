### **Collect-BitLockerState.ps1 Application Specification**

**1\. Scripting Environment and Prerequisites**

* **PowerShell Version**: The script must be written for PowerShell 5.1 or a newer version1.

* **Execution Context**: The script must be run with administrator privileges2.

---

### **2\. Output and Logging**

* **Log Location**: The script must prompt the user to choose a directory for the output logs, either their Documents folder or C:\\Windows\\temp3.

* **Folder Structure**: A new subfolder must be created within the chosen location with a name formatted as BitLockerLogs-DD-MM-YYYY-HH-MM4.

* **Activity Log**: A log file named Get-BitLockerState.log should be created within the new folder to record the script's activities5.

---

### **3\. Data Collection Commands and Output Files**

The script will collect the following information and save it to individual files within the created log folder:

* **BitLocker Volume Information**:  
  * **Command**: Get-BitLockerVolume6.

  * **Output File**: The output will be saved to a text file named Get-BitLockerVolme.txt7.

* **manage-bde Status**:  
  * **Command**: manage-bde \-status8.

  * **Output File**: The output will be saved to a text file named Manage-BDE-Status.txt9.

* **TPM Status**:  
  * **Command**: Get-Tpm10.

  * **Output File**: The output will be saved to a text file named Get-TPM.txt11.

* **Windows Recovery Environment (WinRE) Status**:  
  * **Command**: reagentc /info12.

  * **Output File**: The output will be saved to a text file named Reagentc.txt13.

* **BitLocker Event Logs**:  
  * **Log Source**: Microsoft-Windows-BitLocker-API/Management14.

  * **Output File**: The exported log will be saved to an Event Viewer file (.evt) named Microsoft-Windows-BitLocker-API\_Management.evt15.

* **System Event Logs**:  
  * **Log Source**: System16.

  * **Output File**: The exported log will be saved to an Event Viewer file (.evt) named system.evt17.

---

### **4\. Purpose**

The purpose of this script is to help troubleshoot BitLocker issues by collecting key information into a single, organized report18. The gathered data includes the BitLocker status of volumes, key protector details, TPM status, and relevant event logs191919191919191919.

---

### **5\. Additional Information**

This script combines several PowerShell cmdlets and command-line tools to provide a comprehensive overview of a system's BitLocker configuration and state20.

I can draft the PowerShell script Collect-BitLockerState.ps1 based on this specification. Would you like me to proceed with that?