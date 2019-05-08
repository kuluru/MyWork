Import-Module "$PSScriptRoot\Deployment\Retryable-WebRequest.psm1"

Function PowershellModuleUpgradeRequired($Name, $MinimumVersion, $MaximumVersion)
{
    $FoundModules = (Get-Module -ListAvailable -Name $Name)
    if ($FoundModules.Count -gt 0)
    {
        $LatestVersion = ($FoundModules | Sort-Object Version -Descending)[0].Version
        Write-Host "Found $LatestVersion of $Name"
        $MinimumPowershellVersion = New-Object System.Version($MinimumVersion)
        $MaximumPowershellVersion = New-Object System.Version($MaximumVersion)
        if ($LatestVersion.CompareTo($MinimumPowershellVersion) -ge 0)
        {
            if ($LatestVersion.CompareTo($MaximumPowershellVersion) -lt 0)
            {
                Write-Host "Optional Azure Powershell update available at https://github.com/Azure/azure-powershell/releases/download/v6.2.1-June2018/azure-powershell.6.2.1.msi." -Foreground Yellow
            }
            elseif ($LatestVersion.CompareTo($MaximumPowershellVersion) -gt 0)
            {
                Write-Host "Your version ($LatestVersion) is not yet supported, please downgrade to $MaximumVersion."
                return $true
            }

            return $false
        }
        else
        {
            return $true
        }
    }
    else
    {
        return $true
    }
}

function InstallAzurePowershell()
{
    trap [System.Net.WebException]
    {
        Write-Host "Retrying due to network transient exception..."
        Start-Sleep -Seconds 2
        InstallAzurePowershell
        return
    }

    $Name = "AzureRm"
    $MinimumVersion = "6.2.1"
    $MaximumVersion = "6.2.1"

    Write-Host "Checking for version $($MinimumVersion) of $($Name) Powershell module..."
    if (-not (PowershellModuleUpgradeRequired $Name $MinimumVersion $MaximumVersion))
    {
        Write-Host "Azure Powershell installed. Skipping installation." -ForegroundColor Green
        return
    }

    Set ErrorActionPreference Stop
    Write-Host "Installing Azure Powershell..."
    $installer = ".\azure-powershell.6.2.1.msi" | Resolve-Path

    Write-Host "Installing $($installer)..."
    $msiArgs = "/i `"$installer`" /quiet /norestart"
    Start-Process -FilePath "$env:systemroot\System32\msiexec.exe" -ArgumentList $msiArgs -Wait -LoadUserProfile -PassThru

    Write-Host "Refreshing PSModulePath variable"
    $env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", "Machine")

    Write-Host "Disabling AzureDataCollection"
    Disable-AzureDataCollection

    Write-Host "Reloading module..."
    Import-Module Azure -Force
}


function InstallWPI()
{
    $script:WebPICmdExe = "$env:ProgramFiles\Microsoft\Web Platform Installer\WebpiCmd.exe"
    if (Test-Path "$env:ProgramFiles\Microsoft\Web Platform Installer\WebpiCmd.exe")
    {
        Write-Host "Web Platform Installer exists. Skipping installation." -ForegroundColor Green
        return
    }

    $TmpFolder = $env:TEMP | Resolve-Path
    $tempMsiPath = "$TmpFolder\CloudTestServiceFabric"
    $installerUri = "http://download.microsoft.com/download/C/F/F/CFF3A0B8-99D4-41A2-AE1A-496C08BEB904/WebPlatformInstaller_amd64_en-US.msi"
    New-Item -ItemType Directory $tempMsiPath -ErrorAction Ignore | Out-Null
    Write-Host "Downloading WebPlatformInstaller to $tempMsiPath\wpi.msi from $installerUri" -ForegroundColor Green
    Invoke-WebRequestWithRetry -Uri $installerUri -OutFile "$tempMsiPath\wpi.msi"

    Write-Host "Installing $tempMsiPath\wpi.msi" -ForegroundColor Green
    $msiArgs = "/i `"$tempMsiPath\wpi.msi`" /quiet"
    Start-Process -FilePath "$env:systemroot\System32\msiexec.exe" -ArgumentList $msiArgs -Wait -LoadUserProfile -PassThru
}

function InstallSDK()
{
    if (Test-Path "$env:ProgramFiles\Microsoft SDKs\Service Fabric\")
    {
      # Check service fabric version
      $SDKFabricVersion = Get-ChildItem -File -Path "$env:ProgramFiles\Microsoft SDKs\Service Fabric\packages" | Where-Object {$_.Name -match 'Microsoft.ServiceFabric.\d+.\d+.\d+.nupkg'}
      if (-not $SDKFabricVersion)
      {
        Write-Host "Could not determine installed SDK version"
      }
      else {
        $dummy, $dummy, $major, $minor, $tail = $SDKFabricVersion.Name.Split('.')
        $VersionString = "$major.$minor.$($tail[0])"
        If ($major -gt 5 -or ($major -eq 5 -and $minor -ge 7))
        {
          Write-Host "Service Fabric SDK version $VersionString present. Skipping installation." -ForegroundColor Green
          return
        }
        else
        {
          Write-Host "Service Fabric SDK version $VersionString present, but we need at least 5.7. Installing newer version"
        }
      }
    }

    if ($null -ne $env:SFRuntime -and $env:SFRuntime -ne '')
    {
        $sfRuntimeName = $env:SFRuntime
    }
    else
    {
        $sfRuntimeName = "MicrosoftAzure-ServiceFabric-CoreSDK"
    }

    Write-Host "Installing Service Fabric SDK using WebPlatform Installer" -ForegroundColor Green
    & $WebPICmdExe /Install /AcceptEULA /Products:"$sfRuntimeName"

    # Sometimes the installation randomly fails, we will download packages fron our store instead
    # When WPI works, it is faster than downloading from cloud, which is why this is a backup method
    if (-not (Test-Path "$env:ProgramFiles\Microsoft SDKs\Service Fabric\ClusterSetup\DevClusterSetup.ps1"))
    {
        Write-Host "Seems like the installation failed. Downloading from backup store." -ForegroundColor Yellow
        $packageUri = ".\ServiceFabricRuntime6.3package.zip" | Resolve-Path
        New-Item -ItemType Directory "$env:WorkingDirectory\RuntimeDL" -ErrorAction Ignore | Out-Null

        Write-Host "Extracting $packageUri" -ForegroundColor Green
        Expand-Archive "$packageUri" -DestinationPath "$env:WorkingDirectory\RuntimeDL"

        $offlineFeedPath = "$env:WorkingDirectory\RuntimeDL\feeds\latest\webproductlist.xml"
        $WebPICmdExe = Resolve-Path "$env:WorkingDirectory\RuntimeDL\bin\WebpiCmd*.exe"
        & $WebPICmdExe /Install /AcceptEULA /Products:"MicrosoftAzure-ServiceFabric-CoreSDK" /XML:"$offlineFeedPath"
    }

    Write-Host "Setting PS ExecutionPolicy to Unrestricted" -ForegroundColor Green
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Force -Scope CurrentUser

    Write-Host "Adding $env:ProgramFiles\Microsoft Service Fabric\bin\Fabric\Fabric.Code to the PATH" -ForegroundColor Green
    $env:PATH="$env:PATH;$env:ProgramFiles\Microsoft Service Fabric\bin\Fabric\Fabric.Code"
}

function SetupLocalCluster()
{
    $script:CreateOneNodeCluster = $false
    If ($env:CreateOneNodeCluster -and ($env:CreateOneNodeCluster -eq '1' -or $env:CreateOneNodeCluster -eq "true"))
    {
        Write-Host "Creating a single node cluster..."
        $script:CreateOneNodeCluster = $true
    }

    Write-Host "Modifying the cluster manifest template..."
    . $env:DeploymentDir\Set-ClusterApplicationPortRange.ps1 -StartApplicationPort 30101
    . $env:DeploymentDir\Set-ClusterReverseProxySettings.ps1
    . $env:DeploymentDir\Set-ClusterUpgradeSettings.ps1

    Install-Certificate -CertificateThumbprint $global:SSLCertificateThumbprint

    Write-Host "Setting up a local cluster." -ForegroundColor Green
    . "$env:ProgramFiles\Microsoft SDKs\Service Fabric\ClusterSetup\DevClusterSetup.ps1" `
        -Auto `
        -PathToClusterDataRoot "C:\SfDevCluster\Data" `
        -PathToClusterLogRoot "C:\SfDevCluster\Log" `
        -CreateOneNodeCluster:$script:CreateOneNodeCluster

}

function IncreaseDesktopHeapForServices()
{
    . "$env:DeploymentDir\Set-NonInteractiveDesktopHeap.ps1"
    $desktopHeapValue = 8192
    If ($env:NonInteractiveDesktopHeap)
    {
        $desktopHeapValue = $env:NonInteractiveDesktopHeap
    }
    Set-NonInteractiveDesktopHeap -NewValue $desktopHeapValue
}

try
{
    Set-Variable ErrorActionPreference Stop
    $env:DeploymentDir = ".\Deployment"
    $env:EnvironmentType = "CloudTest"

    Write-Host "Running in cluster $env:ClusterName" -ForegroundColor Green

    IncreaseDesktopHeapForServices

    InstallAzurePowershell
    InstallWPI
    InstallSDK

    # & $WebPICmdExe /Install /AcceptEULA /Products:'SQLLocalDB'
    # $env:PATH="$env:PATH;$env:ProgramFiles\Microsoft SQL Server\110\Tools\Binn"

    . "$env:DeploymentDir\Install-CosmosDBEmulator.ps1"
    . "$env:DeploymentDir\Install-AzureStorageEmulator.ps1"

    # SetupLocalCluster
}
catch
{
    Write-Error $_.Exception
    exit 1
}
