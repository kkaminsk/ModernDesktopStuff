<#
.SYNOPSIS
    Deletes specified local user accounts from a Windows machine.
.DESCRIPTION
    This script removes one or more local user accounts. You must specify the usernames in the 
    $UsernamesToDelete array below. The script must be run with administrative privileges.
.NOTES
    Author: Gemini
    Last Modified: 2025-07-30
.EXAMPLE
    1. Open this .ps1 file in a text editor (like Notepad or VS Code).
    2. Modify the $UsernamesToDelete array with the exact usernames you want to delete.
       e.g., $UsernamesToDelete = @("TempUser1", "TestAccount")
    3. Save the script file.
    4. Right-click the .ps1 file and select "Run with PowerShell". 
       You must have administrative rights.
#>

#Requires -RunAsAdministrator

# --- Configuration ---
# Add the exact usernames you want to delete into this array.
$UsernamesToDelete = @(
    "TempUser",
    "OldAccount",
    "TestUser1"
)
# --- End of Configuration ---

# Verify the script is running with elevated (Administrator) privileges.
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script requires Administrator privileges!"
    Write-Warning "Please right-click the script and select 'Run as Administrator'."
    # Pause for 5 seconds before exiting to allow the user to read the message.
    Start-Sleep -Seconds 5
    Exit
}

Write-Host "Starting user deletion process..." -ForegroundColor Cyan
Write-Host "--------------------------------"

# Loop through each username specified in the array.
foreach ($username in $UsernamesToDelete) {
    try {
        # Check if the user account actually exists before trying to delete it.
        $user = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
        
        if ($user) {
            # If the user exists, proceed with deletion.
            # The -Confirm:$false parameter prevents PowerShell from prompting for confirmation.
            Remove-LocalUser -Name $username -Confirm:$false
            Write-Host "✔️ Successfully deleted user: '$($username)'" -ForegroundColor Green
        }
        else {
            # If the user does not exist, report it and move on.
            Write-Host "⚠️  User '$($username)' not found. Skipping." -ForegroundColor Yellow
        }
    }
    catch {
        # Catch any unexpected errors during the process.
        Write-Host "❌ ERROR deleting user: '$($username)'." -ForegroundColor Red
        Write-Host "   Error details: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "--------------------------------"
Write-Host "Script execution finished." -ForegroundColor Cyan