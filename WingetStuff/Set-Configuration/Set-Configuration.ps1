<#
.SYNOPSIS
  Set-Configuration - GUI tool to select and apply a WinGet configuration YAML from GitHub.

.DESCRIPTION
  Implements the application behavior defined in Application-Specification.md:
  - PowerShell 5.1, requires Administrator (self-elevates if not)
  - Ensures WinGet is installed (using InstallWinget-V2 helper)
  - Discovers and downloads YAML files from GitHub repo path
  - Presents a WinForms GUI listing base names (extension hidden)
  - Applies the selected YAML via `winget configure --file <path>`
  - Logs to %USERPROFILE%\Documents\Set-Configuration-%COMPUTERNAME%-YYYY-MM-DD-HH-MM.log
  - Optional config.xml in same folder overrides defaults

.NOTES
  Repository defaults:
    Owner: kkaminsk
    Repo : ModernDesktopStuff
    Branch: main
    Path: WingetStuff/Config_YAML_Examples

#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Utilities & Logging
function Get-ScriptDirectory {
  if ($PSCommandPath) { return (Split-Path -Parent $PSCommandPath) }
  if ($MyInvocation.MyCommand.Path) { return (Split-Path -Parent $MyInvocation.MyCommand.Path) }
  return (Get-Location).Path
}

$Script:ScriptDir = Get-ScriptDirectory
$Script:TimeStamp = Get-Date -Format 'yyyy-MM-dd-HH-mm'
$Script:LogPath = Join-Path -Path $env:USERPROFILE -ChildPath ("Documents/Set-Configuration-$($env:COMPUTERNAME)-$TimeStamp.log")

function Add-LogLine {
  param([Parameter(Mandatory=$true)][string]$Text)
  try {
    $dir = Split-Path -Parent $Script:LogPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text + [Environment]::NewLine)
    $fs = New-Object System.IO.FileStream($Script:LogPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
  } catch {}
}

function Write-Log {
  param(
    [Parameter(Mandatory=$true)][string]$Message,
    [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
  )
  $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ssK'
  $line = "{0}  {1}  {2}" -f $ts, $Level.PadRight(5), $Message
  Add-LogLine -Text $line
  Write-Host $line
}

# Start transcript to capture console output as well
try {
  Start-Transcript -Path $Script:LogPath -Append -ErrorAction Stop | Out-Null
} catch {
  Write-Host "WARN: Failed to start transcript: $($_.Exception.Message)"
}

function Enable-ModernTls {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor ([Enum]::Parse([Net.SecurityProtocolType], 'Tls13')) } catch {}
    Write-Log "Enabled TLS 1.2/1.3 (if available)." 'INFO'
  } catch {
    Write-Log "Failed to enable modern TLS: $($_.Exception.Message)" 'WARN'
  }
}
#endregion

#region Admin/Version Checks
function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = [Security.Principal.WindowsPrincipal]::new($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ensure-Admin {
  if (Test-IsAdmin) { return }
  Write-Log "Not elevated. Re-launching with Administrator privileges..." 'WARN'
  $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $PSCommandPath + '"'))
  try {
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -Verb RunAs -PassThru -WindowStyle Normal
    if ($p) { Write-Log "Elevated instance started (PID: $($p.Id)). Exiting current instance." 'INFO' }
  } catch {
    Write-Log "Failed to self-elevate: $($_.Exception.Message)" 'ERROR'
    try { Stop-Transcript | Out-Null } catch {}
    exit 2
  }
  try { Stop-Transcript | Out-Null } catch {}
  exit 0
}

function Ensure-PowerShell51 {
  $v = $PSVersionTable.PSVersion
  if (!($v.Major -eq 5 -and $v.Minor -ge 1)) {
    $msg = "PowerShell 5.1 is required. Current version: $v"
    Write-Log $msg 'ERROR'
    try { Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop } catch {}
    try { [System.Windows.Forms.MessageBox]::Show($msg, 'Set-Configuration', 'OK', 'Error') | Out-Null } catch {}
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
  }
}
#endregion

#region Config
$Script:Config = [pscustomobject]@{
  RepoOwner       = 'kkaminsk'
  RepoName        = 'ModernDesktopStuff'
  Branch          = 'main'
  Path            = 'WingetStuff/Config_YAML_Examples'
  ContentsApiUrl  = $null
  LocalCacheRoot  = [Environment]::ExpandEnvironmentVariables("$env:USERPROFILE\\Documents\\Set-Configuration\\Configs")
  WingetCommand   = 'winget'
  WingetArgs      = 'configure --file "{YamlPath}"'
  AdditionalArgs  = ''
  GitHubToken     = $null
}

# Prefer WinGet PowerShell module when available
$Script:UseWinGetModule = $false

function Load-ConfigXml {
  $cfgPath = Join-Path $Script:ScriptDir 'config.xml'
  if (-not (Test-Path -LiteralPath $cfgPath)) { return }
  try {
    [xml]$xml = Get-Content -LiteralPath $cfgPath -Raw -ErrorAction Stop
    Write-Log "Loaded config.xml from $cfgPath" 'INFO'

    $source = $xml.Configuration.Source
    if ($source) {
      if ($source.RepoOwner)      { $Script:Config.RepoOwner = [string]$source.RepoOwner }
      if ($source.RepoName)       { $Script:Config.RepoName  = [string]$source.RepoName }
      if ($source.Branch)         { $Script:Config.Branch    = [string]$source.Branch }
      if ($source.Path)           { $Script:Config.Path      = [string]$source.Path }
      if ($source.ContentsApiUrl) { $val = [string]$source.ContentsApiUrl; if ($val) { $Script:Config.ContentsApiUrl = $val } }
    }
    if ($xml.Configuration.LocalCacheRoot) {
      $Script:Config.LocalCacheRoot = [Environment]::ExpandEnvironmentVariables([string]$xml.Configuration.LocalCacheRoot)
    }
    if ($xml.Configuration.WingetCommand) { $Script:Config.WingetCommand = [string]$xml.Configuration.WingetCommand }
    if ($xml.Configuration.WingetArgs)    { $Script:Config.WingetArgs    = [string]$xml.Configuration.WingetArgs }
    if ($xml.Configuration.AdditionalArgs) { $Script:Config.AdditionalArgs = [string]$xml.Configuration.AdditionalArgs }
    if ($xml.Configuration.GitHubToken)    { $tok = [string]$xml.Configuration.GitHubToken; if ($tok) { $Script:Config.GitHubToken = $tok } }
  } catch {
    Write-Log "Failed to parse config.xml: $($_.Exception.Message)" 'WARN'
  }
}

function Get-ContentsApiUrl {
  if ($Script:Config.ContentsApiUrl) { return $Script:Config.ContentsApiUrl }
  $owner = $Script:Config.RepoOwner
  $repo  = $Script:Config.RepoName
  $path  = $Script:Config.Path.TrimStart('/')
  $br    = $Script:Config.Branch
  return ("https://api.github.com/repos/{0}/{1}/contents/{2}?ref={3}" -f $owner, $repo, $path, $br)
}
#endregion

#region WinGet
function Try-ImportWinGetModule {
  try {
    Import-Module -Name Microsoft.WinGet.Client -ErrorAction Stop
    Write-Log 'Imported Microsoft.WinGet.Client module.' 'INFO'
    return $true
  } catch {
    Write-Log ("WinGet module not available: {0}" -f $_.Exception.Message) 'WARN'
    return $false
  }
}

function Ensure-WinGetModule {
  if (Try-ImportWinGetModule) { $Script:UseWinGetModule = $true; return }
  Enable-ModernTls
  try {
    # Ensure NuGet and PSGallery trust (best-effort on PS 5.1)
    Install-PackageProvider -Name NuGet -Force -Scope AllUsers -ErrorAction SilentlyContinue | Out-Null
  } catch {}
  try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch {}
  try {
    Write-Log 'Attempting to install Microsoft.WinGet.Client module from PSGallery...' 'INFO'
    Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Scope AllUsers -Force -ErrorAction Stop
    if (Try-ImportWinGetModule) { $Script:UseWinGetModule = $true }
  } catch {
    Write-Log ("Failed to install Microsoft.WinGet.Client: {0}" -f $_.Exception.Message) 'WARN'
  }
}

function Get-WinGetVersionInfo {
  if ($Script:UseWinGetModule) {
    try {
      $v = Get-WinGetVersion
      if ($null -ne $v) { return [string]$v }
    } catch {
      Write-Log ("Get-WinGetVersion via module failed: {0}" -f $_.Exception.Message) 'WARN'
    }
  }
  try { return (& $Script:Config.WingetCommand --version 2>$null) } catch { return $null }
}
function Test-WingetAvailable {
  # Prefer module if available
  if ($Script:UseWinGetModule) {
    try { $null = Get-WinGetVersion; return $true } catch {}
  }
  try {
    $cmd = Get-Command -Name $Script:Config.WingetCommand -ErrorAction Stop
    if (-not $cmd) { return $false }
    $ver = & $Script:Config.WingetCommand --version 2>$null
    return $true
  } catch { return $false }
}

function Install-WingetIfMissing {
  if (Test-WingetAvailable) { Write-Log "WinGet is present."; return }
  Write-Log "WinGet not found. Attempting installation via InstallWinget-V2 helper..." 'WARN'

  Enable-ModernTls
  $tempDir = Join-Path $env:TEMP "Set-Configuration-InstallWinget"
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
  $scriptPath = Join-Path $tempDir 'Install-WinGetV2.ps1'

  try {
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/kkaminsk/InstallWinget-V2/refs/heads/main/Install-WingetV2.ps1" -OutFile $scriptPath -UseBasicParsing
    Write-Log "Downloaded Install-WingetV2.ps1 to $scriptPath" 'INFO'
    try { Unblock-File -LiteralPath $scriptPath -ErrorAction SilentlyContinue } catch {}
  } catch {
    Write-Log "Failed to download Install-WingetV2.ps1: $($_.Exception.Message)" 'ERROR'
    throw
  }

  try {
    $proc = Start-Process -FilePath 'PowerShell.exe' -ArgumentList @('-NonInteractive','-ExecutionPolicy','Bypass', '"' + $scriptPath + '"') -PassThru -Wait -WindowStyle Normal
    Write-Log "Installer exited with code $($proc.ExitCode)" 'INFO'
  } catch {
    Write-Log "Failed to execute Install-WingetV2.ps1: $($_.Exception.Message)" 'ERROR'
    throw
  } finally {
    try { Remove-Item -LiteralPath $scriptPath -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Item -LiteralPath $tempDir -Force -Recurse -ErrorAction SilentlyContinue } catch {}
  }

  Start-Sleep -Seconds 2
  if (-not (Test-WingetAvailable)) {
    Write-Log "WinGet still not available after installation." 'ERROR'
    throw [System.Exception]::new('WinGet installation failed.')
  }
  Write-Log "WinGet installation verified." 'INFO'
}
#endregion

#region GitHub Discovery/Download
function Get-GitHubHeaders {
  $h = @{
    'User-Agent' = 'Set-Configuration-PS/1.0'
    'Accept'     = 'application/vnd.github+json'
  }
  if ($Script:Config.GitHubToken) {
    $h['Authorization'] = "Bearer $($Script:Config.GitHubToken)"
  }
  return $h
}

function Get-RemoteYamlList {
  param([switch]$ThrowOnError)
  $url = Get-ContentsApiUrl
  Write-Log "Querying GitHub Contents API: $url" 'INFO'
  Enable-ModernTls
  try {
    $resp = Invoke-RestMethod -Method GET -Uri $url -Headers (Get-GitHubHeaders)
    $all = @($resp)
    Write-Log ("API returned {0} item(s): {1}" -f $all.Count, (($all | ForEach-Object { $_.name }) -join ', ')) 'INFO'
    $files = @()
    foreach ($item in $all) {
      if ($item.type -eq 'file' -and ($item.name -like '*.yml' -or $item.name -like '*.yaml')) { $files += $item }
    }
    Write-Log "Discovered $($files.Count) YAML file(s)." 'INFO'
    return $files
  } catch {
    $msg = "Failed to enumerate GitHub contents: $($_.Exception.Message)"
    Write-Log $msg 'WARN'
    if ($ThrowOnError) { throw }
    return @()
  }
}

function Sync-YamlFiles {
  param([array]$RemoteFiles)
  if (-not $RemoteFiles -or $RemoteFiles.Count -eq 0) { Write-Log 'No remote YAML files to download.' 'INFO'; return @() }
  $destRoot = $Script:Config.LocalCacheRoot
  New-Item -ItemType Directory -Path $destRoot -Force | Out-Null

  $downloaded = @()
  foreach ($f in $RemoteFiles) {
    $dest = Join-Path $destRoot $f.name
    try {
      Write-Log "Downloading $($f.name) -> $dest" 'INFO'
      Invoke-WebRequest -Uri $f.download_url -OutFile $dest -UseBasicParsing
      $downloaded += $dest
    } catch {
      Write-Log "Failed to download $($f.name): $($_.Exception.Message)" 'WARN'
    }
  }
  Write-Log ("Downloaded {0} file(s)." -f $downloaded.Count) 'INFO'
  return $downloaded
}
#endregion

#region WinGet Apply
function Invoke-WingetConfigure {
  param(
    [Parameter(Mandatory=$true)][string]$YamlPath
  )
  if (-not (Test-Path -LiteralPath $YamlPath)) { throw "YAML file not found: $YamlPath" }

  $cmd  = $Script:Config.WingetCommand
  $args = $Script:Config.WingetArgs.Replace('{YamlPath}', $YamlPath)
  if ($Script:Config.AdditionalArgs) { $args = "$args $($Script:Config.AdditionalArgs)" }

  Write-Log "Running: $cmd $args" 'INFO'

  $tempOut = Join-Path $env:TEMP ("winget-configure-out-$([guid]::NewGuid().ToString()).log")
  $tempErr = Join-Path $env:TEMP ("winget-configure-err-$([guid]::NewGuid().ToString()).log")

  $exitCode = 0
  try {
    $p = Start-Process -FilePath $cmd -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tempOut -RedirectStandardError $tempErr
    $exitCode = $p.ExitCode
  } catch {
    Write-Log "Failed to start winget: $($_.Exception.Message)" 'ERROR'
    throw
  }

  # Append external outputs to our main log
  foreach ($f in @($tempOut,$tempErr)) {
    if (Test-Path -LiteralPath $f) {
      try {
        Add-Content -Path $Script:LogPath -Value (Get-Content -LiteralPath $f -Raw) -Encoding UTF8
      } catch {}
      try { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } catch {}
    }
  }

  Write-Log "winget exited with code $exitCode" 'INFO'
  return $exitCode
}
#endregion

#region GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global UI state
$Script:YamlMap = @{}
$Script:SelectedLocalYaml = $null

function Get-LocalYamlList {
  $root = $Script:Config.LocalCacheRoot
  if (-not (Test-Path -LiteralPath $root)) { return @() }
  return @(
    Get-ChildItem -LiteralPath $root -Filter *.yml  -File -ErrorAction SilentlyContinue
  ) + @(
    Get-ChildItem -LiteralPath $root -Filter *.yaml -File -ErrorAction SilentlyContinue
  )
}

function Repopulate-ListBox {
  param([System.Windows.Forms.ListBox]$ListBox,[System.Windows.Forms.TextBox]$PreviewBox)
  $ListBox.Items.Clear()
  $Script:YamlMap.Clear()

  $files = Get-LocalYamlList
  foreach ($f in $files) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    if (-not $Script:YamlMap.ContainsKey($base)) { $Script:YamlMap[$base] = $f.FullName }
  }

  foreach ($k in ($Script:YamlMap.Keys | Sort-Object)) { [void]$ListBox.Items.Add($k) }

  if ($PreviewBox) { $PreviewBox.Clear() }
}

function Show-Status {
  param([System.Windows.Forms.Label]$Status,[System.Windows.Forms.ProgressBar]$Prog,[string]$Text,[bool]$Busy=$false)
  $Status.Text = $Text
  if ($Busy) {
    $Prog.Style = 'Marquee'
    $Prog.MarqueeAnimationSpeed = 30
    $Prog.Visible = $true
  } else {
    $Prog.Style = 'Blocks'
    $Prog.MarqueeAnimationSpeed = 0
    $Prog.Visible = $false
  }
}

function Initialize-Form {
  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'Set-Configuration'
  $form.StartPosition = 'CenterScreen'
  $form.Size = New-Object System.Drawing.Size(720,520)
  $form.MinimizeBox = $true
  $form.MaximizeBox = $false

  $lbl = New-Object System.Windows.Forms.Label
  $lbl.Text = 'Available configurations (from GitHub cache):'
  $lbl.AutoSize = $true
  $lbl.Location = New-Object System.Drawing.Point(12,12)
  $form.Controls.Add($lbl)

  $list = New-Object System.Windows.Forms.ListBox
  $list.Location = New-Object System.Drawing.Point(12,34)
  $list.Size = New-Object System.Drawing.Size(300,360)
  $list.Anchor = 'Top,Left,Bottom'
  $form.Controls.Add($list)
  $Script:ListBox = $list

  $preview = New-Object System.Windows.Forms.TextBox
  $preview.Location = New-Object System.Drawing.Point(324,34)
  $preview.Size = New-Object System.Drawing.Size(370,360)
  $preview.Multiline = $true
  $preview.ScrollBars = 'Vertical'
  $preview.ReadOnly = $true
  $preview.Font = New-Object System.Drawing.Font('Consolas',9)
  $preview.Anchor = 'Top,Right,Bottom'
  $form.Controls.Add($preview)
  $Script:PreviewBox = $preview

  $btnRefresh = New-Object System.Windows.Forms.Button
  $btnRefresh.Text = 'Refresh'
  $btnRefresh.Location = New-Object System.Drawing.Point(12,410)
  $btnRefresh.Size = New-Object System.Drawing.Size(100,28)
  $btnConfigure = New-Object System.Windows.Forms.Button
  $btnConfigure.Text = 'Configure'
  $btnConfigure.Location = New-Object System.Drawing.Point(118,410)
  $btnConfigure.Size = New-Object System.Drawing.Size(100,28)
  $btnConfigure.Enabled = $false
  $btnBrowse = New-Object System.Windows.Forms.Button
  $btnBrowse.Text = 'Browse Local...'
  $btnBrowse.Location = New-Object System.Drawing.Point(224,410)
  $btnBrowse.Size = New-Object System.Drawing.Size(120,28)
  $btnOpenLog = New-Object System.Windows.Forms.Button
  $btnOpenLog.Text = 'Open Log Folder'
  $btnOpenLog.Location = New-Object System.Drawing.Point(350,410)
  $btnOpenLog.Size = New-Object System.Drawing.Size(130,28)
  $btnExit = New-Object System.Windows.Forms.Button
  $btnExit.Text = 'Exit'
  $btnExit.Location = New-Object System.Drawing.Point(486,410)
  $btnExit.Size = New-Object System.Drawing.Size(100,28)
  $form.Controls.AddRange(@($btnRefresh,$btnConfigure,$btnBrowse,$btnOpenLog,$btnExit))
  $Script:BtnConfigure = $btnConfigure

  $status = New-Object System.Windows.Forms.Label
  $status.AutoSize = $true
  $status.Location = New-Object System.Drawing.Point(12,448)
  $form.Controls.Add($status)
  $Script:StatusLabel = $status

  $prog = New-Object System.Windows.Forms.ProgressBar
  $prog.Location = New-Object System.Drawing.Point(12,470)
  $prog.Size = New-Object System.Drawing.Size(682,12)
  $prog.Visible = $false
  $form.Controls.Add($prog)
  $Script:ProgressBar = $prog

  # Timer for monitoring winget process without background runspace
  $Script:configureTimer = New-Object System.Windows.Forms.Timer
  $Script:configureTimer.Interval = 750
  $Script:configureProc = $null
  $Script:tempOut = $null
  $Script:tempErr = $null

  # Events
  $list.Add_SelectedIndexChanged({
    $Script:BtnConfigure.Enabled = $false
    if ($Script:ListBox.SelectedItem) {
      $name = [string]$Script:ListBox.SelectedItem
      if ($Script:YamlMap.ContainsKey($name)) {
        $path = $Script:YamlMap[$name]
        $Script:BtnConfigure.Enabled = $true
        try {
          $content = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
          if ($content.Length -gt 4096) { $content = $content.Substring(0,4096) + "`r`n..." }
          $Script:PreviewBox.Text = $content
        } catch { $Script:PreviewBox.Text = "(Failed to open $($path): $($_.Exception.Message))" }
      }
    }
  })

  $btnOpenLog.Add_Click({ Start-Process -FilePath 'explorer.exe' -ArgumentList @("`"$([IO.Path]::GetDirectoryName($Script:LogPath))`"") | Out-Null })
  $btnExit.Add_Click({ $form.Close() })

  # Background workers
  $Script:bwRefresh = New-Object System.ComponentModel.BackgroundWorker
  $Script:bwRefresh.WorkerReportsProgress = $false
  $Script:bwRefresh.WorkerSupportsCancellation = $false
  $Script:bwRefresh.add_DoWork({
    param($s, $e)
    try {
      $remote = Get-RemoteYamlList
      [void](Sync-YamlFiles -RemoteFiles $remote)
    } catch {
      Write-Log "Refresh failed: $($_.Exception.Message)" 'WARN'
    }
  })
  $Script:bwRefresh.add_RunWorkerCompleted({
    param($s, $e)
    Repopulate-ListBox -ListBox $Script:ListBox -PreviewBox $Script:PreviewBox
    $locals = Get-LocalYamlList
    if ($locals.Count -gt 0) {
      Write-Log ("Local cache has {0} YAML file(s): {1}" -f $locals.Count, (($locals | ForEach-Object { $_.Name }) -join ', ')) 'INFO'
      Show-Status $Script:StatusLabel $Script:ProgressBar 'Ready.' $false
    } else {
      Write-Log 'Local cache has 0 YAML files after refresh.' 'INFO'
      Show-Status $Script:StatusLabel $Script:ProgressBar 'No configurations found. Click Refresh or use Browse Local.' $false
    }
  })

  $Script:bwConfigure = New-Object System.ComponentModel.BackgroundWorker
  $Script:bwConfigure.WorkerReportsProgress = $false
  $Script:bwConfigure.WorkerSupportsCancellation = $false
  $Script:bwConfigure.add_DoWork({
    param($s, $e)
    try {
      $data = $e.Argument
      # PowerShell 5.1 may wrap Argument in an object[]
      if ($null -ne $data -and $data.GetType().FullName -eq 'System.Object[]' -and $data.Length -gt 0) { $data = $data[0] }
      $argType = if ($null -eq $data) { '<null>' } else { $data.GetType().FullName }
      Write-Log ("Configure DoWork invoked. ArgType={0}" -f $argType) 'INFO'
      if ($null -eq $data -or -not ($data.PSObject.Properties.Name -contains 'Yaml')) {
        Write-Log 'Configure worker missing argument Yaml. Aborting.' 'ERROR'
        $e.Result = [pscustomobject]@{ ExitCode = 9999; Error = 'Missing argument'; Path = $null; Name = $null }
        return
      }
      $yaml = $data.Yaml
      $name = $data.Name
      Write-Log ("Configure worker starting for '{0}' at '{1}'" -f $name, $yaml) 'INFO'
      try {
        $code = Invoke-WingetConfigure -YamlPath $yaml
        $e.Result = [pscustomobject]@{ ExitCode = $code; Path = $yaml; Name = $name }
      } catch {
        $e.Result = [pscustomobject]@{ ExitCode = 9999; Error = $_.Exception.Message; Path = $yaml; Name = $name }
      }
    } catch {
      Write-Log ("Unhandled exception in Configure DoWork: {0}" -f $_.Exception.Message) 'ERROR'
      try { $e.Result = [pscustomobject]@{ ExitCode = 9999; Error = $_.Exception.Message; Path = $null; Name = $null } } catch {}
    }
  })
  $Script:bwConfigure.add_RunWorkerCompleted({
    param($s, $e)
    Show-Status $Script:StatusLabel $Script:ProgressBar 'Ready.' $false
    $Script:BtnConfigure.Enabled = $true
    if ($e.Error) { Write-Log ("Configure worker error: {0}" -f $e.Error.Message) 'ERROR' }
    $res = $e.Result
    if ($null -eq $res) { return }
    $msg = "winget configure completed with code $($res.ExitCode). Log: $Script:LogPath"
    Write-Log ("Configure worker completed for '{0}' with exit code {1}" -f $res.Name, $res.ExitCode) 'INFO'
    if ($res.ExitCode -eq 0) {
      [System.Windows.Forms.MessageBox]::Show($msg, 'Set-Configuration', 'OK', 'Information') | Out-Null
    } else {
      [System.Windows.Forms.MessageBox]::Show($msg, 'Set-Configuration', 'OK', 'Warning') | Out-Null
    }
  })

  $btnRefresh.Add_Click({
    Show-Status $Script:StatusLabel $Script:ProgressBar 'Refreshing configuration list from GitHub...' $true
    try {
      $remote = Get-RemoteYamlList
      [void](Sync-YamlFiles -RemoteFiles $remote)
    } catch {
      Write-Log "Refresh failed: $($_.Exception.Message)" 'WARN'
    }
    Repopulate-ListBox -ListBox $Script:ListBox -PreviewBox $Script:PreviewBox
    $locals = Get-LocalYamlList
    if ($locals.Count -gt 0) {
      Write-Log ("Local cache has {0} YAML file(s): {1}" -f $locals.Count, (($locals | ForEach-Object { $_.Name }) -join ', ')) 'INFO'
      Show-Status $Script:StatusLabel $Script:ProgressBar 'Ready.' $false
    } else {
      Write-Log 'Local cache has 0 YAML files after refresh.' 'INFO'
      Show-Status $Script:StatusLabel $Script:ProgressBar 'No configurations found. Click Refresh or use Browse Local.' $false
    }
  })
  $btnConfigure.Add_Click({
    if (-not $Script:ListBox.SelectedItem) { Write-Log 'Configure clicked with no selection.' 'WARN'; return }
    $name = [string]$Script:ListBox.SelectedItem
    if (-not $Script:YamlMap.ContainsKey($name)) { Write-Log ("Configure clicked but selection '{0}' not found in map." -f $name) 'WARN'; return }
    if ($Script:configureTimer.Enabled) { Write-Log 'Configure already running.' 'WARN'; return }
    $yaml = $Script:YamlMap[$name]
    Show-Status $Script:StatusLabel $Script:ProgressBar "Applying configuration: $name" $true
    Write-Log ("Configure clicked: '{0}' at '{1}'" -f $name, $yaml) 'INFO'
    $Script:BtnConfigure.Enabled = $false

    # Build command
    $cmd  = $Script:Config.WingetCommand
    $args = $Script:Config.WingetArgs.Replace('{YamlPath}', $yaml)
    if ($Script:Config.AdditionalArgs) { $args = "$args $($Script:Config.AdditionalArgs)" }
    $Script:tempOut = Join-Path $env:TEMP ("winget-configure-out-{0}.log" -f ([guid]::NewGuid()))
    $Script:tempErr = Join-Path $env:TEMP ("winget-configure-err-{0}.log" -f ([guid]::NewGuid()))
    try {
      $Script:configureProc = Start-Process -FilePath $cmd -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardOutput $Script:tempOut -RedirectStandardError $Script:tempErr
      Write-Log ("Started winget (PID {0})" -f $Script:configureProc.Id) 'INFO'
      $Script:configureTimer.Start()
    } catch {
      Write-Log ("Failed to start winget: {0}" -f $_.Exception.Message) 'ERROR'
      Show-Status $Script:StatusLabel $Script:ProgressBar 'Failed to start configuration. See log.' $false
      $Script:BtnConfigure.Enabled = $true
    }
  })

  # Timer tick: check process completion, collect output, finalize UI
  $Script:configureTimer.Add_Tick({
    if ($null -eq $Script:configureProc) { return }
    if (-not $Script:configureProc.HasExited) { return }
    try {
      foreach ($f in @($Script:tempOut, $Script:tempErr)) {
        if ($f -and (Test-Path -LiteralPath $f)) {
          Add-Content -Path $Script:LogPath -Value (Get-Content -LiteralPath $f -Raw) -Encoding UTF8
          Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        }
      }
    } catch {}
    Write-Log ("winget exited with code {0}" -f $Script:configureProc.ExitCode) 'INFO'
    Show-Status $Script:StatusLabel $Script:ProgressBar 'Ready.' $false
    $Script:BtnConfigure.Enabled = $true
    try { $Script:configureTimer.Stop() } catch {}
  })

  $btnBrowse.Add_Click({
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Filter = 'YAML files (*.yml;*.yaml)|*.yml;*.yaml|All files (*.*)|*.*'
    $ofd.InitialDirectory = [IO.Path]::GetDirectoryName($Script:Config.LocalCacheRoot)
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
      $path = $ofd.FileName
      $name = [IO.Path]::GetFileNameWithoutExtension($path)
      $Script:YamlMap[$name] = $path
      if (-not $Script:ListBox.Items.Contains($name)) { [void]$Script:ListBox.Items.Add($name) }
      $Script:ListBox.SelectedItem = $name
      try {
        $content = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
        if ($content.Length -gt 4096) { $content = $content.Substring(0,4096) + "`r`n..." }
        $Script:PreviewBox.Text = $content
      } catch { $Script:PreviewBox.Text = "(Failed to open $($path): $($_.Exception.Message))" }
      $Script:BtnConfigure.Enabled = $true
    }
  })

  # Initial population
  Repopulate-ListBox -ListBox $Script:ListBox -PreviewBox $Script:PreviewBox
  Show-Status $Script:StatusLabel $Script:ProgressBar 'Ready.' $false

  # Expose controls to caller (optional)
  return [pscustomobject]@{ Form=$form; RefreshWorker=$Script:bwRefresh; ConfigureWorker=$Script:bwConfigure }
}
#endregion

#region Entry
Enable-ModernTls
Ensure-PowerShell51
Ensure-Admin
Install-WingetIfMissing
Ensure-WinGetModule
Load-ConfigXml
Write-Log "Using source: $($Script:Config.RepoOwner)/$($Script:Config.RepoName)@$($Script:Config.Branch)/$($Script:Config.Path)" 'INFO'
Write-Log "Local cache root: $($Script:Config.LocalCacheRoot)" 'INFO'

# Prepare initial cache by syncing once (best-effort)
try {
  $initial = Get-RemoteYamlList
  [void](Sync-YamlFiles -RemoteFiles $initial)
} catch {
  Write-Log "Initial sync failed: $($_.Exception.Message)" 'WARN'
}

# Launch GUI
$ui = Initialize-Form
$ui.Form.Add_Shown({ $ui.Form.Activate() })
[void]$ui.Form.ShowDialog()

Write-Log "Exiting Set-Configuration." 'INFO'
try { Stop-Transcript | Out-Null } catch {}

# Default success exit code
exit 0
#endregion
