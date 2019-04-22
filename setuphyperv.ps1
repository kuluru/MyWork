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
