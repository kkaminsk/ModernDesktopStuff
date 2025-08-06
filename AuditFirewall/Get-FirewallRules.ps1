# Define the path for the output CSV file on your desktop
$filePath = "$env:USERPROFILE\Desktop\FirewallRules.csv"

# Get all firewall rules and select the most useful properties for the report
Get-NetFirewallRule | Select-Object -Property `
    DisplayName, `
    Enabled, `
    Direction, `
    Action, `
    Profile, `
    Protocol, `
    LocalPort, `
    RemotePort, `
    Program, `
    Service | `
# Export the collected data to a CSV file
Export-Csv -Path $filePath -NoTypeInformation

# Display a confirmation message in the console
Write-Host "✅ Firewall rules successfully exported to: $filePath"