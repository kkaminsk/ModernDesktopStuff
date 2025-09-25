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
  - FVE_Policies.reg
  - MDM\BitlockerMDM.xml (when -MDM is used and BitLocker Area entries are found in MDMDiagReport.xml)
   - Get-BitLockerState.log (activity log)

  .PARAMETER MDM
  When specified, runs non-interactively: always runs mdmdiagnosticstool.exe to generate MDM logs into <LogRoot>\\MDM.
  Extracts BitLocker Area nodes from MDMDiagReport.xml to <LogRoot>\\MDM\\BitlockerMDM.xml.
 
  .PARAMETER OutputPath
  Optional. Fully qualified path to the base folder where the timestamped BitLockerLogs-<date>-<time> folder will be created.
  If omitted, defaults to the user's Documents folder unless -UseTemp is specified.
  .PARAMETER UseTemp
  Optional switch. When present (and -OutputPath is not supplied), uses C:\\Windows\\Temp as the base folder.
   !#>

  param(
    [switch] $MDM,
    [string] $OutputPath,
    [switch] $UseTemp
  )

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

# Resolve output directory (non-interactive)
$documentsDir = [Environment]::GetFolderPath('MyDocuments')
$tempDir = Join-Path $env:WINDIR 'Temp'

if ($PSBoundParameters.ContainsKey('OutputPath') -and -not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $baseDir = $OutputPath
} elseif ($UseTemp) {
    $baseDir = $tempDir
} else {
    $baseDir = $documentsDir
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

function Get-RegExePath {
    # Ensure we use the 64-bit reg.exe on 64-bit systems, even if running a 32-bit PowerShell host
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        return (Join-Path $env:WINDIR 'Sysnative\reg.exe')
    }
    return (Join-Path $env:WINDIR 'System32\reg.exe')
}

function Get-MdmDiagnosticsToolPath {
    # Ensure we use the 64-bit mdmdiagnosticstool.exe on 64-bit systems, even if running a 32-bit PowerShell host
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        return (Join-Path $env:WINDIR 'Sysnative\mdmdiagnosticstool.exe')
    }
    return (Join-Path $env:WINDIR 'System32\mdmdiagnosticstool.exe')
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
            Write-Log "STEP: BitLocker event log export succeeded; channel='$channel'; output='$outfile'"
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

# 7) Export BitLocker Policy Registry (FVE) -> FVE_Policies.reg
Invoke-Step -Name 'Export BitLocker policy registry (HKLM\Software\Policies\Microsoft\FVE)' -Action {
    $regFile = Join-Path $logRoot 'FVE_Policies.reg'
    $capture = Join-Path $logRoot 'FVE_Policies_export.txt'
    $regExe = Get-RegExePath
    if (-not (Test-Path $regExe)) {
        Write-Log "reg.exe not found at $regExe. Skipping." 'WARN'
        return
    }
    & $regExe export 'HKLM\Software\Policies\Microsoft\FVE' $regFile /y 2>&1 | Tee-Object -FilePath $capture | Out-Null
    $exit = $LASTEXITCODE
    $exists = Test-Path $regFile
    $sizeOK = $exists -and ((Get-Item $regFile).Length -gt 0)
    if ($exit -eq 0 -and $sizeOK) {
        Write-Log "Registry export succeeded to '$regFile'"
    } else {
        Write-Log "Registry export failed (exit $exit, exists=$exists, sizeOK=$sizeOK). The key may not exist on this system." 'WARN'
    }
}

# 8) Optionally collect MDM diagnostics using mdmdiagnosticstool.exe when -MDM is specified
if ($MDM) {
    Invoke-Step -Name 'Collect MDM diagnostics (mdmdiagnosticstool.exe)' -Action {
        $mdmDir = Join-Path $logRoot 'MDM'
        if (-not (Test-Path $mdmDir)) { New-Item -ItemType Directory -Path $mdmDir -Force | Out-Null }
        # Always generate MDM diagnostics using mdmdiagnosticstool.exe
        $tool = Get-MdmDiagnosticsToolPath
        if (-not (Test-Path $tool)) {
            Write-Log "mdmdiagnosticstool.exe not found at $tool. Skipping MDM diagnostics." 'WARN'
        } else {
            $capture = Join-Path $mdmDir 'mdmdiagnosticstool_output.txt'
            $exit = Invoke-External -FilePath $tool -Arguments @('-out', $mdmDir) -OutputCaptureFile $capture
            $fileCount = (Get-ChildItem -Path $mdmDir -Force -File | Measure-Object).Count
            if ($exit -eq 0 -and $fileCount -gt 0) {
                Write-Log "MDM diagnostics collection completed. Files saved under '$mdmDir'"
            } else {
                Write-Log "MDM diagnostics collection may have failed (exit $exit, files=$fileCount)." 'WARN'
            }
        }
        
        # HTML parsing removed; proceed with XML extraction only

        # Additionally, extract BitLocker Area entries from MDMDiagReport.xml into BitlockerMDM.xml under the MDM folder
        $xmlReport = Get-ChildItem -Path $mdmDir -Recurse -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match '^MDMDiagReport\.xml$' } |
                     Select-Object -First 1
        if ($xmlReport) {
            try {
                [xml]$xmlDoc = Get-Content -Path $xmlReport.FullName -Raw
                $xpath = "//Area[translate(PolicyAreaName/text(),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')='bitlocker']"
                $nodes = $xmlDoc.SelectNodes($xpath)
                if ($nodes -and $nodes.Count -gt 0) {
                    $outDoc = New-Object System.Xml.XmlDocument
                    $decl = $outDoc.CreateXmlDeclaration("1.0","utf-8",$null)
                    $outDoc.AppendChild($decl) | Out-Null
                    $root = $outDoc.CreateElement("BitlockerAreas")
                    $outDoc.AppendChild($root) | Out-Null
                    foreach ($n in $nodes) {
                        $imported = $outDoc.ImportNode($n, $true)
                        [void]$root.AppendChild($imported)
                    }
                    $destXml = Join-Path $mdmDir 'BitlockerMDM.xml'
                    $outDoc.Save($destXml)
                    Write-Log "Extracted $($nodes.Count) Area node(s) from '$($xmlReport.FullName)' to '$destXml'"
                    Write-Log "STEP: MDM XML parsing succeeded; output='$destXml'; count=$($nodes.Count)"
                } else {
                    Write-Log "No Area entries with PolicyAreaName='BitLocker' found in '$($xmlReport.FullName)'." 'WARN'
                    Write-Log "STEP: MDM XML parsing failed; reason='no BitLocker Area nodes'; file='$($xmlReport.FullName)'"
                }
            } catch {
                Write-Log "Failed to parse '$($xmlReport.FullName)': $($_.Exception.Message)" 'ERROR'
                Write-Log ("STEP: MDM XML parsing failed; reason='exception'; file='{0}'; error='{1}'" -f $xmlReport.FullName, $_.Exception.Message)
            }
        } else {
            Write-Log "MDMDiagReport.xml not found under '$mdmDir'." 'WARN'
            Write-Log "STEP: MDM XML parsing failed; reason='MDMDiagReport.xml not found'; folder='$mdmDir'"
        }
    }
}

Write-Log "All steps completed."
Write-Host ""
Write-Host "Output folder: $logRoot" -ForegroundColor Green
Write-Host "Activity log: $logFile" -ForegroundColor Green
