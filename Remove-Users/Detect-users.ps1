<#
.SYNOPSIS
    Detects if specified local user accounts exist on a Windows machine.
.DESCRIPTION
    This script checks for a list of prohibited local user accounts. If any user from the list
    is found, the script will write an error and exit with a status code of 1 (failure). 
    If none of the users are found, it will exit with a status code of 0 (success).
    This is suitable for use as a detection method script in compliance and management tools.
.NOTES
    Author: Gemini
    Last Modified: 2025-07-30
.EXAMPLE
    1. Modify the $UsersToDetect array with the usernames you want to check for.
    2. Run the script in PowerShell.
    3. Check the exit code using '$LASTEXITCODE' to see the result.
       - 0 means SUCCESS (no users found).
       - 1 means FAILURE (at least one user was found).
#>

# --- Configuration ---
# Add the exact usernames you want to detect into this array.
# The script will fail detection if any of these accounts exist.
$UsersToDetect = @(
    "TempUser",
    "OldAccount",
    "TestUser1"
)
# --- End of Configuration ---

Write-Host "Starting detection for prohibited local user accounts..."
Write-Host "-----------------------------------------------------"

# This flag will be set to $true if we find any of the specified users.
$userFound = $false

# Loop through each username specified in the array.
foreach ($username in $UsersToDetect) {
    # We use SilentlyContinue because we expect that users might not exist,
    # which is the desired state. An error here is not a script failure.
    $user = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
    
    if ($null -ne $user) {
        # If $user is NOT null, it means the Get-LocalUser command found the account.
        Write-Error "DETECTION FAILED: Prohibited user account '$($username)' exists on this system."
        $userFound = $true
        # We can break the loop early since we only need to find one user to fail.
        break
    }
    else {
        # The user was not found, which is good. Continue checking the rest.
        Write-Host "✔️  OK: User '$($username)' does not exist." -ForegroundColor Green
    }
}

Write-Host "-----------------------------------------------------"

# Final determination based on the flag.
if ($userFound) {
    Write-Host "Result: At least one prohibited user account was found." -ForegroundColor Red
    # Exit with an error code to signal failure to management systems.
    exit 1
}
else {
    Write-Host "Result: Detection successful. No prohibited user accounts were found." -ForegroundColor Cyan
    # Exit with a success code.
    exit 0
}