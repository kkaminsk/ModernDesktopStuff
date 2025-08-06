# Define the path for the output CSV file on your desktop
$filePath = "$env:USERPROFILE\Desktop\FirewallRules.csv"

# Get all firewall rules and collect comprehensive information
Write-Host "🔍 Collecting firewall rules and associated filters..."
$firewallData = Get-NetFirewallRule | ForEach-Object {
    $rule = $_
    
    # Get associated filter information
    $appFilter = $rule | Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue
    $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
    $serviceFilter = $rule | Get-NetFirewallServiceFilter -ErrorAction SilentlyContinue
    
    # Create a custom object with all the information
    [PSCustomObject]@{
        Name = $rule.Name
        DisplayName = $rule.DisplayName
        Description = $rule.Description
        Enabled = $rule.Enabled
        Direction = $rule.Direction
        Action = $rule.Action
        Profile = $rule.Profile -join ', '
        ApplicationName = if ($appFilter.Program) { $appFilter.Program } else { "Any" }
        Package = if ($appFilter.Package) { $appFilter.Package } else { "Any" }
        ServiceName = if ($serviceFilter.Service) { $serviceFilter.Service } else { "Any" }
        Protocol = if ($portFilter.Protocol) { $portFilter.Protocol } else { "Any" }
        LocalPort = if ($portFilter.LocalPort) { $portFilter.LocalPort -join ', ' } else { "Any" }
        RemotePort = if ($portFilter.RemotePort) { $portFilter.RemotePort -join ', ' } else { "Any" }
        IcmpType = if ($portFilter.IcmpType) { $portFilter.IcmpType } else { "Any" }
    }
}

# Export the collected data to a CSV file
$firewallData | Export-Csv -Path $filePath -NoTypeInformation

# Display a confirmation message in the console
Write-Host "✅ Firewall rules successfully exported to: $filePath"
Write-Host "📊 Total rules exported: $($firewallData.Count)"