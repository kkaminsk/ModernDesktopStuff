#requires -version 5.1
<#!
.SYNOPSIS
Collects BitLocker state information and related logs.

.DESCRIPTION
Implements the application specification in "Collect-BitLockerState.ps1 App Specification.md".
Run this script in an elevated PowerShell session (Run as Administrator).

.OUTPUTS
Creates a timestamped folder under either the user's Documents or C:\Windows\Temp, containing:
- Get-BitLockerVolume.txt
- Manage-BDE_Status.txt
- Get-TPM.txt
- Reagentc.txt
- Microsoft-Windows-BitLocker-API_Management.evtx
- system.evtx
- Get-BitLockerState.log (activity log)
!#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Test-IsAdministrator {
    try {
        $current = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($current)
        return $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch {
        return $false
    }
}

if (-not (Test-IsAdministrator)) {
    Write-Error "This script must be run with Administrator privileges. Please re-launch PowerShell as Administrator."
    exit 1
}

# Prompt for output directory location
$documentsDir = [Environment]::GetFolderPath('MyDocuments')
$tempDir = Join-Path $env:WINDIR 'Temp'

Write-Host "Select output directory for logs:" -ForegroundColor Cyan
Write-Host "  1) Documents: $documentsDir"
Write-Host "  2) Windows Temp: $tempDir"
$selection = Read-Host "Enter 1 or 2 [default: 1]"

switch ($selection) {
    '2' { $baseDir = $tempDir }
    default { $baseDir = $documentsDir }
}

# Create folder structure: BitLockerLogs-DD-MM-YYYY-HH-MM
$timestamp = Get-Date -Format 'dd-MM-yyyy-HH-mm'
$folderName = "BitLockerLogs-{0}" -f $timestamp
$logRoot = Join-Path $baseDir $folderName
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

$logFile = Join-Path $logRoot 'Get-BitLockerState.log'

function Write-Log {
    param(
        [Parameter(Mandatory)] [string] $Message,
        [ValidateSet('INFO','WARN','ERROR')] [string] $Level = 'INFO'
    )
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[{0}] [{1}] {2}" -f $ts, $Level, $Message
    Add-Content -Path $logFile -Value $entry -Encoding UTF8
    Write-Host $entry
}

Write-Log "Collect-BitLockerState started."
Write-Log "PowerShell version: $($PSVersionTable.PSVersion.ToString())"
Write-Log "Running elevated: $([bool](Test-IsAdministrator))"
Write-Log "Log root: $logRoot"

function Get-WevtutilPath {
    # Ensure we use the 64-bit wevtutil on 64-bit systems, even if running a 32-bit PowerShell host
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        return (Join-Path $env:WINDIR 'Sysnative\wevtutil.exe')
    }
    return (Join-Path $env:WINDIR 'System32\wevtutil.exe')
}

function Invoke-External {
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter()] [string[]] $Arguments = @(),
        [Parameter(Mandatory)] [string] $OutputCaptureFile
    )
    Write-Log ("Running external command: {0} {1}" -f $FilePath, ($Arguments -join ' '))
    # Invoke the external process, capture stdout+stderr to a file, and return the exit code
    & $FilePath @Arguments 2>&1 | Tee-Object -FilePath $OutputCaptureFile | Out-Null
    $exit = $LASTEXITCODE
    Write-Log ("Exit code: {0}" -f $exit)
    return $exit
}

function Invoke-Step {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Action
    )
    Write-Log "$Name..."
    try {
        & $Action
        Write-Log "$Name completed."
    } catch {
        Write-Log "$Name failed: $($_.Exception.Message)" 'ERROR'
    }
}

# 1) BitLocker Volume Information: Get-BitLockerVolume -> Get-BitLockerVolume.txt
Invoke-Step -Name 'Collect BitLocker Volume Information (Get-BitLockerVolume)' -Action {
    $outfile = Join-Path $logRoot 'Get-BitLockerVolume.txt'
    $cmd = Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        Write-Log "Get-BitLockerVolume cmdlet not found. Skipping." 'WARN'
        return
    }
    Get-BitLockerVolume | Format-List * | Out-File -FilePath $outfile -Encoding UTF8
}

# 2) manage-bde -status -> Manage-BDE_Status.txt
Invoke-Step -Name 'Collect manage-bde -status output' -Action {
    $outfile = Join-Path $logRoot 'Manage-BDE_Status.txt'
    $exe = Join-Path $env:WINDIR 'System32\manage-bde.exe'
    if (-not (Test-Path $exe)) {
        Write-Log "manage-bde.exe not found at $exe. Skipping." 'WARN'
        return
    }
    & $exe -status 2>&1 | Out-File -FilePath $outfile -Encoding UTF8
}

# 3) TPM Status: Get-Tpm -> Get-TPM.txt
Invoke-Step -Name 'Collect TPM status (Get-Tpm)' -Action {
    $outfile = Join-Path $logRoot 'Get-TPM.txt'
    $cmd = Get-Command -Name Get-Tpm -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        Write-Log "Get-Tpm cmdlet not found. Skipping." 'WARN'
        return
    }
    Get-Tpm | Format-List * | Out-File -FilePath $outfile -Encoding UTF8
}

# 4) WinRE Status: reagentc /info -> Reagentc.txt
Invoke-Step -Name 'Collect WinRE status (reagentc /info)' -Action {
    $outfile = Join-Path $logRoot 'Reagentc.txt'
    $exe = Join-Path $env:WINDIR 'System32\reagentc.exe'
    if (-not (Test-Path $exe)) {
        Write-Log "reagentc.exe not found at $exe. Skipping." 'WARN'
        return
    }
    & $exe /info 2>&1 | Out-File -FilePath $outfile -Encoding UTF8
}

# 5) Export BitLocker Event Logs -> Microsoft-Windows-BitLocker-API_Management.evtx
Invoke-Step -Name 'Export BitLocker-API/Management event log' -Action {
    $outfile = Join-Path $logRoot 'Microsoft-Windows-BitLocker-API_Management.evtx'
    $wevtutil = Get-WevtutilPath
    if (-not (Test-Path $wevtutil)) {
        Write-Log "wevtutil.exe not found at $wevtutil. Skipping." 'WARN'
        return
    }

    $channelsToTry = @(
        'Microsoft-Windows-BitLocker-API/Management',
        'Microsoft-Windows-BitLocker/BitLocker Management'
    )
    $exported = $false

    foreach ($channel in $channelsToTry) {
        Write-Log "Trying channel: $channel"
        # Verify the channel exists
        & $wevtutil gl $channel | Out-Null
        $glExit = $LASTEXITCODE
        if ($glExit -ne 0) {
            Write-Log "Channel not found or inaccessible: $channel (exit $glExit)" 'WARN'
            continue
        }

        if (Test-Path $outfile) { Remove-Item -Path $outfile -Force -ErrorAction SilentlyContinue }
        & $wevtutil epl $channel $outfile /ow:true
        $eplExit = $LASTEXITCODE
        $sizeOK = (Test-Path $outfile) -and ((Get-Item $outfile).Length -gt 0)
        if ($eplExit -eq 0 -and $sizeOK) {
            Write-Log "Export succeeded from '$channel' to '$outfile'"
            $exported = $true
            break
        } else {
            Write-Log "Export failed from '$channel' (exit $eplExit, exists=$((Test-Path $outfile)), sizeOK=$sizeOK)" 'ERROR'
        }
    }

    if (-not $exported) {
        Write-Log "Failed to export BitLocker event log from known channels." 'ERROR'
    }
}

# 6) Export System Event Logs -> system.evtx
Invoke-Step -Name 'Export System event log' -Action {
    $outfile = Join-Path $logRoot 'system.evtx'
    $wevtutil = Get-WevtutilPath
    if (-not (Test-Path $wevtutil)) {
        Write-Log "wevtutil.exe not found at $wevtutil. Skipping." 'WARN'
        return
    }
    & $wevtutil epl 'System' $outfile /ow:true
}

Write-Log "All steps completed."
Write-Host ""; Write-Host "Output folder: $logRoot" -ForegroundColor Green
Write-Host "Activity log: $logFile" -ForegroundColor Green
