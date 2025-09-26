[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$UseTemp,
    [switch]$ZIP
)

$ErrorActionPreference = 'Stop'

# Explicit admin rights check before any operations
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Administrative privileges are required. Please run PowerShell as Administrator."
    exit 2
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] $Message"
    Add-Content -Path $Global:ActivityLogPath -Value $line -Encoding UTF8
    Write-Host $line
}

try {
    # Determine base output path
    if ($PSBoundParameters.ContainsKey('OutputPath') -and $OutputPath) {
        $baseOut = $OutputPath
    } elseif ($UseTemp) {
        $baseOut = Join-Path $env:WINDIR 'Temp'
    } else {
        $baseOut = [Environment]::GetFolderPath('MyDocuments')
    }

    # Create log root
    $timestampFolder = Get-Date -Format 'dd-MM-yyyy-HH-mm'
    $logRootName = "AppLockerLogs-$timestampFolder"
    $Global:LogRoot = Join-Path $baseOut $logRootName
    if (-not (Test-Path -LiteralPath $Global:LogRoot)) {
        New-Item -Path $Global:LogRoot -ItemType Directory -Force | Out-Null
    }

    # Activity log path
    $Global:ActivityLogPath = Join-Path $Global:LogRoot 'Get-AppLockerStatus.log'
    if (-not (Test-Path -LiteralPath $Global:ActivityLogPath)) {
        New-Item -Path $Global:ActivityLogPath -ItemType File -Force | Out-Null
    }
    Write-Log -Message "Initialized log root at '$Global:LogRoot'"

    # Helper to export an event log channel
    function Export-EventLogChannel {
        param(
            [Parameter(Mandatory=$true)][string]$Channel,
            [Parameter(Mandatory=$true)][string]$OutputFile
        )
        try {
            # Ensure target directory exists
            $dir = Split-Path -Path $OutputFile -Parent
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

            # Use wevtutil directly so we get an exit code
            & wevtutil epl "$Channel" "$OutputFile" 2>$null
            $exit = $LASTEXITCODE

            $exists = Test-Path -LiteralPath $OutputFile
            $sizeOK = $false
            if ($exists) { $sizeOK = ((Get-Item -LiteralPath $OutputFile).Length -ge 1kb) }

            if ($exit -eq 0 -and $exists -and $sizeOK) {
                Write-Log -Message "STEP: AppLocker event log export succeeded; channel='$Channel'; output='$OutputFile'"
            } else {
                Write-Log -Message "STEP: AppLocker event log export failed; reason='export failed'; exit=$exit; exists=$exists; sizeOK=$sizeOK; file='$OutputFile'"
                return $false
            }
        } catch {
            Write-Log -Message "STEP: AppLocker event log export failed; reason='exception'; channel='$Channel'; file='$OutputFile'; error='$_'"
            return $false
        }
        }

        # 1) Export AppLocker EXE and DLL channel (primary)
        $alChannel = 'Microsoft-Windows-AppLocker/EXE and DLL'
        $alEvtx = Join-Path $Global:LogRoot 'Microsoft-Windows-AppLocker-EXEandDLL.evtx'
        [void] (Export-EventLogChannel -Channel $alChannel -OutputFile $alEvtx)

        # Additional AppLocker channels
        $msiScriptEvtx = Join-Path $Global:LogRoot 'Microsoft-Windows-AppLocker-MSIandScript.evtx'
        [void] (Export-EventLogChannel -Channel 'Microsoft-Windows-AppLocker/MSI and Script' -OutputFile $msiScriptEvtx)

        $pkgDeploymentEvtx = Join-Path $Global:LogRoot 'Microsoft-Windows-AppLocker-Packagedapp-Deployment.evtx'
        [void] (Export-EventLogChannel -Channel 'Microsoft-Windows-AppLocker/Packaged app-Deployment' -OutputFile $pkgDeploymentEvtx)

        $pkgExecutionEvtx = Join-Path $Global:LogRoot 'Microsoft-Windows-AppLocker-Packagedapp-Execution.evtx'
        [void] (Export-EventLogChannel -Channel 'Microsoft-Windows-AppLocker/Packaged app-Execution' -OutputFile $pkgExecutionEvtx)

        # 2) Export Application event log
        try {
            $appEvtx = Join-Path $Global:LogRoot 'application.evtx'
            & wevtutil epl 'Application' "$appEvtx" 2>$null
            $appExit = $LASTEXITCODE
            $appExists = Test-Path -LiteralPath $appEvtx
            $appSizeOK = $false
            if ($appExists) { $appSizeOK = ((Get-Item -LiteralPath $appEvtx).Length -ge 1kb) }
            if ($appExit -eq 0 -and $appExists -and $appSizeOK) {
                Write-Log -Message "STEP: Application event log export succeeded; output='$appEvtx'"
            } else {
                Write-Log -Message "STEP: Application event log export failed; exit=$appExit; exists=$appExists; sizeOK=$appSizeOK; file='$appEvtx'"
            }
        } catch {
            Write-Log -Message "STEP: Application event log export failed; reason='exception'; error='$_'"
        }

    # 3) Export effective AppLocker policy to XML
    $policyXml = Join-Path $Global:LogRoot 'AppLockerPolicy.xml'
    try {
        Get-AppLockerPolicy -Effective -Xml | Out-File -FilePath $policyXml -Encoding UTF8
        $exists = Test-Path -LiteralPath $policyXml
        $sizeOK = $false
        if ($exists) { $sizeOK = ((Get-Item -LiteralPath $policyXml).Length -ge 1) }
        if ($exists -and $sizeOK) {
            Write-Log -Message "STEP: AppLocker policy export succeeded; output='$policyXml'"
        } else {
            Write-Log -Message "STEP: AppLocker policy export failed; reason='empty or missing file'; file='$policyXml'"
        }
    } catch {
        Write-Log -Message "STEP: AppLocker policy export failed; reason='exception'; file='$policyXml'; error='$_'"
    }

    # 4) Optional ZIP of entire output folder
    if ($ZIP) {
        try {
            $parent = Split-Path -Path $Global:LogRoot -Parent
            $zipName = "${env:COMPUTERNAME}-AppLockerLogs-$timestampFolder.zip"
            $zipPath = Join-Path $parent $zipName

            if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue }
            Compress-Archive -Path (Join-Path $Global:LogRoot '*') -DestinationPath $zipPath -Force

            $zipExists = Test-Path -LiteralPath $zipPath
            $zipSizeOK = $false
            if ($zipExists) { $zipSizeOK = ((Get-Item -LiteralPath $zipPath).Length -ge 1kb) }
            if ($zipExists -and $zipSizeOK) {
                Write-Log -Message "STEP: ZIP archive succeeded; output='$zipPath'"
            } else {
                Write-Log -Message "STEP: ZIP archive failed; reason='empty or missing zip'; file='$zipPath'"
            }
        } catch {
            Write-Log -Message "STEP: ZIP archive failed; reason='exception'; error='$_'"
        }
    }

    Write-Log -Message "Collection completed. Log root: '$Global:LogRoot'"
} catch {
    Write-Log -Message "Unhandled exception: $_"
    throw
}
