Param (
    [Parameter(Mandatory = $true)][string] $AzureUserName,
    [string] $AzurePassword,
    [string] $AzureTenantID,
    [string] $AzureSubscriptionID,
    [string] $ODLID,
    [string] $InstallCloudLabsShadow,
    [string] $DeploymentID,
    [string] $vmAdminUsername,
    [string] $vmAdminPassword,
    [string] $trainerUserName,
    [string] $trainerUserPassword,
    [Parameter(Mandatory = $true)][string] $spAppId,
    [Parameter(Mandatory = $true)][string] $spAppSecret
)

$ErrorActionPreference = 'Stop'
$newLogDir = 'C:\WindowsAzure\Logs'
if (-not (Test-Path $newLogDir)) { New-Item -ItemType Directory -Path $newLogDir -Force | Out-Null }
Start-Transcript -Path "$newLogDir\CloudLabsCustomScriptExtension.txt" -Append

Function Write-Section([string]$msg) { Write-Host ""; Write-Host "========== $msg ==========" -ForegroundColor Cyan }

Function Invoke-Retry {
    param([Parameter(Mandatory=$true)][ScriptBlock]$Script,[int]$Retries = 3,[int]$DelaySeconds = 3)
    for ($i = 1; $i -le $Retries; $i++) {
        try { return & $Script } catch { if ($i -ge $Retries) { throw }; Write-Warning "Attempt $i failed: $($_.Exception.Message). Retrying in $DelaySeconds sec…"; Start-Sleep -Seconds $DelaySeconds }
    }
}

[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

Write-Section "Create base folders"
$pathsToEnsure = @('C:\LabFiles','C:\CloudLabs','C:\AllFiles','C:\CloudLabs\Common','C:\Users\Public\Documents')
foreach ($p in $pathsToEnsure) { New-Item -ItemType Directory -Path $p -Force | Out-Null }

Write-Section "Create AzureCreds files"
$credsTxt = 'C:\LabFiles\AzureCreds.txt'
$credsPs1 = 'C:\LabFiles\AzureCreds.ps1'
Invoke-Retry -Script {
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/AzureCreds.txt", $credsTxt)
    $wc.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/AzureCreds.ps1", $credsPs1)
}
(Get-Content $credsTxt).
    Replace("AzureUserNameValue",   $AzureUserName).
    Replace("AzurePasswordValue",   $AzurePassword).
    Replace("AzureTenantIDValue",   $AzureTenantID).
    Replace("AzureSubscriptionIDValue", $AzureSubscriptionID).
    Replace("DeploymentIDValue",    $DeploymentID) | Set-Content $credsTxt
(Get-Content $credsPs1).
    Replace("AzureUserNameValue",   $AzureUserName).
    Replace("AzurePasswordValue",   $AzurePassword).
    Replace("AzureTenantIDValue",   $AzureTenantID).
    Replace("AzureSubscriptionIDValue", $AzureSubscriptionID).
    Replace("DeploymentIDValue",    $DeploymentID) | Set-Content $credsPs1
Copy-Item $credsTxt -Destination "C:\Users\Public\Desktop" -Force

Write-Section "Fetch & import CloudLabs common functions"
$commonScript = "C:\CloudLabs\Common\cloudlabs-windows-functions.ps1"
if (-not (Test-Path $commonScript)) {
    Invoke-Retry -Script {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/cloudlabs-windows-functions.ps1", $commonScript)
    }
}
. $commonScript

Write-Section "Apply WindowsServerCommon; install Az PowerShell & Azure CLI"
WindowsServerCommon
InstallAzPowerShellModule
InstallAzCLI

Write-Section "Download lab content (mslearn-openai repo)"
$labsZip = "C:\AllFiles\AllFiles.zip"
Invoke-Retry -Script {
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile("https://github.com/CloudLabs-MOC/mslearn-openai/archive/refs/heads/main.zip", $labsZip)
}
Function Expand-ZIPFile($file, $destination) {
    try { $shell = New-Object -ComObject shell.application; $zip = $shell.NameSpace($file); foreach ($item in $zip.items()) { $shell.Namespace($destination).copyhere($item, 16) } }
    catch { Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::ExtractToDirectory($file, $destination) }
}
Expand-ZIPFile -file $labsZip -destination "C:\AllFiles"
Start-Sleep -Seconds 5

Write-Section "Authenticate to Azure (Service Principal only)"
if ([string]::IsNullOrWhiteSpace($spAppId) -or $spAppId -match '^GET-|^PUT-' -or [string]::IsNullOrWhiteSpace($spAppSecret) -or [string]::IsNullOrWhiteSpace($AzureTenantID)) {
    throw "Missing or placeholder Service Principal parameters. Provide valid spAppId, spAppSecret, and AzureTenantID."
}
$spnSecure = $spAppSecret | ConvertTo-SecureString -AsPlainText -Force
$spnCred   = New-Object System.Management.Automation.PSCredential ($spAppId, $spnSecure)
Connect-AzAccount -ServicePrincipal -Credential $spnCred -Tenant $AzureTenantID | Out-Null
if ($AzureSubscriptionID) { Set-AzContext -Subscription $AzureSubscriptionID | Out-Null }

Write-Section "Lookup ODL user (soft-fail)"
try { $ODLuser = Get-AzADUser -DisplayName "ODL_User $DeploymentID" -ErrorAction Stop; $ODLuserID = $ODLuser.Id; Write-Host "Found ODL user: $($ODLuser.UserPrincipalName)" } catch { Write-Warning "ODL user not found for DeploymentID '$DeploymentID'. Continuing…" }

Write-Section "Update Shadow script (if present) & trainer password"
$shadowPath = "C:\Users\Public\Documents\Shadow.ps1"
if (Test-Path $shadowPath) { (Get-Content $shadowPath).Replace("vmAdminUsernameValue", $vmAdminUsername) | Set-Content $shadowPath } else { Write-Warning "Shadow.ps1 not found; skipping patch." }
if ($trainerUserName -and $trainerUserPassword) {
    try {
        $user = $null
        try { $user = Get-LocalUser -Name $trainerUserName -ErrorAction Stop } catch {}
        if (-not $user) { cmd.exe /c "net user $trainerUserName $trainerUserPassword /add /y" | Out-Null } else { cmd.exe /c "net user $trainerUserName $trainerUserPassword" | Out-Null }
        cmd.exe /c "net localgroup Administrators $trainerUserName /add" | Out-Null
    } catch { Write-Warning "Failed to ensure trainer account: $($_.Exception.Message)" }
}

Write-Section "Start CloudLabs VM Agent (if present)"
$vmAgentPath = "C:\CloudLabs\Validator\VMAgent\Spektra.CloudLabs.VMAgent.exe"
$svcName     = "Spektra CloudLabs VM Agent"
if (Test-Path $vmAgentPath) {
    try { cmd.exe --% /c sc create "$svcName" BinPath="$vmAgentPath" start= auto } catch {}
    try { cmd.exe --% /c sc start "$svcName" } catch {}
} else { Write-Warning "VM Agent binary not found at $vmAgentPath; skipping service creation." }

Write-Section "Finalize and disable runuserdata"
try { Disable-ScheduledTask -TaskName "runuserdata" -ErrorAction SilentlyContinue } catch {}
try { Stop-ScheduledTask    -TaskName "runuserdata" -ErrorAction SilentlyContinue } catch {}

Write-Section "Provisioning completed"
Stop-Transcript
