# Set-Configuration — Application Specification

Version: 1.0
Last updated: 2025-09-29

## Summary
- **Script title:** `Set-Configuration`
- **Purpose:** Provide a simple GUI-driven PowerShell 5.1 workflow to select and apply a WinGet configuration YAML hosted on GitHub, with robust logging and optional runtime configuration via `config.xml`.

## Table of Contents
- **[1. Objectives & Scope](#1-objectives--scope)**
- **[2. Runtime Requirements & Dependencies](#2-runtime-requirements--dependencies)**
- **[3. Configuration & Defaults](#3-configuration--defaults)**
- **[4. High-Level Flow](#4-high-level-flow)**
- **[5. Detailed Behavior](#5-detailed-behavior)**
- **[6. Files & Folders](#6-files--folders)**
- **[7. Logging](#7-logging)**
- **[8. Error Handling & Exit Codes](#8-error-handling--exit-codes)**
- **[9. Security Considerations](#9-security-considerations)**
- **[10. Testing & Validation](#10-testing--validation)**
- **[11. Future Enhancements](#11-future-enhancements)**
- **[12. Appendix (Samples)](#12-appendix-samples)**

---

## 1. Objectives & Scope
- **[objectives]**
  - Provide a PowerShell 5.1 script that can be executed by admins to apply WinGet configurations.
  - Offer a **GUI** to select one of multiple YAML configuration files hosted in GitHub.
  - Automatically **ensure WinGet is present**, installing it if missing using the provided installer script.
  - **Log** all script and WinGet output to a uniquely named file in the user’s Documents folder.

- **[in scope]**
  - Self-elevation to administrator when needed.
  - Discovering available `.yaml/.yml` files from a GitHub repository path and downloading them locally.
  - Presenting a GUI list of available configurations by file name (extension hidden) and applying the selected configuration with WinGet.
  - Optional, local `config.xml` to override defaults.

- **[out of scope]**
  - Authoring or validating the content of the YAML files beyond basic extension filtering.
  - Managing machine state beyond invoking `winget configure`.
  - Enterprise policy enforcement, telemetry, or centralized reporting.

## 2. Runtime Requirements & Dependencies
- **[os]** Windows 10/11.
- **[powershell]** Windows PowerShell 5.1.
- **[privileges]** Must run as Administrator. Script self-elevates if not.
- **[connectivity]** Internet access required to query/download from GitHub and (if needed) to install WinGet.
- **[winget]** WinGet must be installed. If not present, the script installs it using the provided helper.
- **[gui framework]** .NET Framework WinForms (via PowerShell) for maximum compatibility on PS 5.1.

## 3. Configuration & Defaults
- **[default-remote-source]**
  - Repository: `kkaminsk/ModernDesktopStuff`
  - Branch: `main`
  - Path: `WingetStuff/Config_YAML_Examples`
  - Purpose: Source location for YAML configuration files to offer to users.

- **[local-cache]** Default local download folder for YAML files:
  - `%USERPROFILE%\Documents\Set-Configuration\Configs`

- **[logging-path]**
  - `%USERPROFILE%\Documents\Set-Configuration-%COMPUTERNAME%-%yyyy%-%MM%-%dd%-%HH%-%mm%.log`

- **[optional-configxml]**
  - Location: Same folder as the script (e.g., `WingetStuff/Set-Configuration/`).
  - Purpose: Override remote source details, local cache path, and optional command arguments.
  - Suggested schema:

```xml
<?xml version="1.0" encoding="utf-8"?>
<Configuration>
  <Source>
    <RepoOwner>kkaminsk</RepoOwner>
    <RepoName>ModernDesktopStuff</RepoName>
    <Branch>main</Branch>
    <Path>WingetStuff/Config_YAML_Examples</Path>
    <!-- Optional: direct GitHub contents API URL. If provided, it overrides Owner/Name/Branch/Path. -->
    <ContentsApiUrl></ContentsApiUrl>
  </Source>
  <LocalCacheRoot>%USERPROFILE%\Documents\Set-Configuration\Configs</LocalCacheRoot>
  <!-- Winget invocation. AdditionalArgs (if any) appended literally. -->
  <WingetCommand>winget</WingetCommand>
  <WingetArgs>configure --file "{YamlPath}"</WingetArgs>
  <AdditionalArgs></AdditionalArgs>
  <!-- Optional GitHub token (not required for public repos; helps with rate limits). -->
  <GitHubToken></GitHubToken>
</Configuration>
```

## 4. High-Level Flow
```mermaid
flowchart TD
  A[Start] --> B[Self-checks: PS 5.1, Admin]
  B -->|Elevate if needed| B
  B --> C[Ensure WinGet present]
  C --> D[Load config.xml (optional)]
  D --> E[Discover YAML files from GitHub]
  E --> F[Download YAMLs to Local Cache]
  F --> G[Render GUI: list YAMLs (no extension)]
  G --> H{User selects YAML}
  H -->|Configure| I[Run: winget configure --file <selected>]
  I --> J[Log all output to Documents]
  J --> K[Show result, allow open log]
  K --> L[Exit]
```

## 5. Detailed Behavior

### 5.1 Startup Self-Checks
- **[powershell-version]** Verify `PSVersionTable.PSVersion.Major -ge 5` and `.Minor -ge 1`.
- **[admin-check]** If not elevated, re-launch self with:
  - `Start-Process -Verb RunAs -FilePath powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File', $PSCommandPath`
  - Exit original process after spawning the elevated instance.

### 5.2 Ensure WinGet
- **[presence-check]** Attempt `winget --version` to determine availability. If command not found or returns error, proceed to install.
- **[install-commands]** Use the exact helper provided:

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/kkaminsk/InstallWinget-V2/refs/heads/main/Install-WingetV2.ps1" -OutFile "Install-WinGetV2.ps1"
PowerShell.exe -NonInteractive .\Install-WinGetV2.ps1
```

- **[network-tls]** Before downloading, enable modern TLS, e.g.:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor ([Enum]::Parse([Net.SecurityProtocolType], 'Tls13')) } catch { }
```

- **[cleanup]** Delete the installer script after successful installation.

### 5.3 Discover and Download YAML Files
- **[discovery]** Use GitHub Contents API (public, no auth required) to enumerate files:
  - `https://api.github.com/repos/{Owner}/{Repo}/contents/{Path}?ref={Branch}`
  - Filter to items with `type == "file"` and names ending in `.yaml` or `.yml`.
- **[fallback]** If the API fails, optionally parse the HTML directory page as a fallback (best-effort) or prompt the user to browse for a local YAML file.
- **[download]** Download each filtered file’s `download_url` to the local cache folder, preserving file names.
- **[cache-policy]** Re-download on each refresh to ensure freshness. Optionally compare content length/ETag to skip unchanged files.

### 5.4 User Interface (WinForms)
- **[layout]**
  - Title: "Set-Configuration"
  - Controls:
    - ListBox: configuration names (file base name only; extension hidden)
    - Buttons: `Refresh`, `Configure`, `Browse Local...`, `Open Log Folder`, `Exit`
    - Status/Progress label and progress bar (indeterminate during operations)
    - Optional: read-only text area to preview selected YAML (first N lines)
- **[interactions]**
  - `Refresh`: Re-run discovery and download logic.
  - `Configure`: Enabled only when a selection is made.
  - `Browse Local...`: Allow selecting any local `.yaml/.yml` file.
  - `Open Log Folder`: Opens the Documents folder in Explorer.
  - `Exit`: Closes the application.
- **[validation]**
  - If no YAML is selected when `Configure` is clicked, show a user-friendly error.

### 5.5 Apply Configuration
- **[command]**
  - Execute: `winget configure --file "<selectedYamlPath>"`.
  - If `<AdditionalArgs>` present in `config.xml`, append them to the command line.
- **[execution]**
  - Run in a background process; surface progress and final status in the GUI.
  - Capture both stdout and stderr for logging.
- **[results]**
  - On completion, display success or failure with a short summary. Offer to open the log file.

### 5.6 Logging
- **[location]** `%USERPROFILE%\Documents` with filename pattern:
  - `Set-Configuration-%COMPUTERNAME%-YYYY-MM-DD-HH-MM.log`
- **[content]**
  - Script banner with timestamp, computer/user info, PS version.
  - Configuration source, selected YAML, and full WinGet command line (excluding secrets).
  - Full stdout/stderr from WinGet and key script steps.
  - Final status and elapsed time.
- **[mechanics]**
  - Start a transcript at script start. For external processes, pipe output through `Tee-Object -Append` to the same log file.
  - Do not log sensitive tokens (if any are provided via `config.xml`).

## 6. Files & Folders
- **[repo path]** `WingetStuff/Set-Configuration/`
  - `Application-Specification.md` (this document)
  - `Set-Configuration.ps1` (script; to be implemented)
  - `config.xml` (optional, runtime overrides; same folder as script)
- **[runtime cache]** `%USERPROFILE%\Documents\Set-Configuration\Configs`
- **[logs]** `%USERPROFILE%\Documents`

## 7. Logging
- **[rotation]** Each run generates a new file via timestamped naming.
- **[retention]** No automatic cleanup by default. Users can delete older logs manually.
- **[example entries]**

```text
2025-09-29 09:03:12Z  INFO  Launching Set-Configuration v1.0 on HOST123 (User: ACME\jdoe)
2025-09-29 09:03:12Z  INFO  PSVersion: 5.1.22621.2506, Admin: True
2025-09-29 09:03:13Z  INFO  Using source: kkaminsk/ModernDesktopStuff@main/WingetStuff/Config_YAML_Examples
2025-09-29 09:03:14Z  INFO  Discovered 2 YAML files: config.yaml, config-minimal.yaml
2025-09-29 09:03:15Z  INFO  Selected: config.yaml
2025-09-29 09:03:15Z  INFO  Running: winget configure --file "C:\\Users\\jdoe\\Documents\\Set-Configuration\\Configs\\config.yaml"
2025-09-29 09:06:40Z  INFO  Winget exited with code 0
2025-09-29 09:06:40Z  INFO  Completed in 00:03:25.412
```

## 8. Error Handling & Exit Codes
- **[codes]**
  - `0` — Success
  - `1` — General or unexpected error
  - `2` — Administrator privileges required (self-elevation failed or denied)
  - `3` — WinGet missing and installation failed
  - `4` — Failed to discover or download YAML files
  - `5` — No YAML file selected / invalid selection
  - `6` — `winget configure` failed (non-zero exit code)
  - `7` — Operation cancelled by user

- **[messaging]**
  - All user-facing errors should be actionable and reference the log file path.

## 9. Security Considerations
- **[downloaded-scripts]** WinGet installer is downloaded and executed. Source is a public GitHub URL provided in this spec. Consider validating checksum if required by policy.
- **[tls]** Force modern TLS protocols on HTTP client.
- **[input-validation]** Only `.yaml`/`.yml` files are surfaced to the user by default.
- **[secrets]** If a GitHub token is supplied via `config.xml` (optional), never write it to logs.

## 10. Testing & Validation
- **[scenarios]**
  - Fresh machine without WinGet → script installs WinGet, then proceeds.
  - Machine with WinGet present → discovery, download, GUI, configure flow.
  - GitHub unreachable → prompt for local file; applying local YAML.
  - Non-admin invocation → self-elevation path.
  - Multiple YAMLs available; selection reflects base names only.
  - Logging created with the correct file name format.
- **[manual checks]**
  - Confirm GUI responsiveness and disabled/enabled states of buttons.
  - Confirm selected YAML path and WinGet command line in the log.

## 11. Future Enhancements
- **[enhancement]** Display parsed summary of YAML (e.g., expected packages/components).
- **[enhancement]** Allow pinning a preferred configuration in `config.xml`.
- **[enhancement]** Add CLI mode (no GUI) with `-File <yaml>` argument.
- **[enhancement]** Progress details via `winget` JSON output (if/when available).

## 12. Appendix (Samples)

### 12.1 GitHub Contents API Response (excerpt)
```json
[
  {
    "name": "config.yaml",
    "path": "WingetStuff/Config_YAML_Examples/config.yaml",
    "sha": "...",
    "size": 3497,
    "url": "https://api.github.com/repos/kkaminsk/ModernDesktopStuff/contents/WingetStuff/Config_YAML_Examples/config.yaml?ref=main",
    "html_url": "https://github.com/kkaminsk/ModernDesktopStuff/blob/main/WingetStuff/Config_YAML_Examples/config.yaml",
    "git_url": "...",
    "download_url": "https://raw.githubusercontent.com/kkaminsk/ModernDesktopStuff/main/WingetStuff/Config_YAML_Examples/config.yaml",
    "type": "file"
  }
]
```

### 12.2 Sample `config.xml`
```xml
<?xml version="1.0" encoding="utf-8"?>
<Configuration>
  <Source>
    <RepoOwner>kkaminsk</RepoOwner>
    <RepoName>ModernDesktopStuff</RepoName>
    <Branch>main</Branch>
    <Path>WingetStuff/Config_YAML_Examples</Path>
  </Source>
  <LocalCacheRoot>%USERPROFILE%\Documents\Set-Configuration\Configs</LocalCacheRoot>
  <WingetCommand>winget</WingetCommand>
  <WingetArgs>configure --file "{YamlPath}"</WingetArgs>
  <AdditionalArgs></AdditionalArgs>
</Configuration>
```

### 12.3 Admin Check (PowerShell snippet)
```powershell
function Test-IsAdmin {
  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
```

### 12.4 Example WinGet Invocation
```powershell
winget configure --file "C:\\Users\\<user>\\Documents\\Set-Configuration\\Configs\\config.yaml"
```
