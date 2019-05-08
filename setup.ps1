function EnsureFeatureEnabled($featureName)
{
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName;
    if ($feature.State -ne "Enabled")
    {
        Enable-WindowsOptionalFeature -NoRestart -All -Online -FeatureName $featureName | Out-Null;
    }
    else
    {
        Write-Host "Feature `"$featureName`" is already installed.";
    }
}


EnsureFeatureEnabled "Microsoft-Hyper-V"
EnsureFeatureEnabled "Microsoft-Hyper-V-Management-PowerShell"
EnsureFeatureEnabled "Microsoft-Hyper-V-Management-Clients"




$DynamicRangeStartPort = 52000

#Get the current settings:
$current = Get-NetUDPSetting
Write-Output "Current DynamicPortRangeStartPort: $($current.DynamicPortRangeStartPort), DynamicPortRangeNumberOfPorts: $($current.DynamicPortRangeNumberOfPorts)"

if($current.DynamicPortRangeStartPort -ne $DynamicRangeStartPort) {
    $portRange = [UInt16]::MaxValue - $DynamicRangeStartPort + 1 # +1 here since DynamicRangeStartPort is inclusive
    Set-NetUDPSetting -DynamicPortRangeStartPort $DynamicRangeStartPort -DynamicPortRangeNumberOfPorts $portRange
    $new = Get-NetUDPSetting
    Write-Output "New DynamicPortRangeStartPort: $($new.DynamicPortRangeStartPort), DynamicPortRangeNumberOfPorts: $($new.DynamicPortRangeNumberOfPorts)"
}
