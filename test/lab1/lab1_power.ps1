<# =====================================================================
  lab1_power.ps1
  Purpose  : First-boot provisioning for CloudLabs jump VM
  Notes    : - Prefers Service Principal auth if provided
             - Falls back to user credential auth
             - Downloads common helpers & lab files
             - Leaves clear breadcrumbs in transcript
  ===================================================================== #>

Param (
    [Parameter(Mandatory = $true)]
    [string] $AzureUserName,

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

    [string] $spAppId,
    
    [string] $spAppSecret
)

# =========================
#   Section: Prep & Logging
# =========================
$ErrorActionPreference = 'Stop'

# Ensure log folder exists BEFORE transcript
$newLogDir = 'C:\WindowsAzure\Logs'
if (-not (Test-Path $newLogDir)) { New-Item -ItemType Directory -Path $newLogDir -Force | Out-Null }
Start-Transcript -Path "$newLogDir\CloudLabsCustomScriptExtension.txt" -Append

Function Write-Section([string]$msg) {
    Write-Host ""
    Write-Host "========== $msg ==========" -ForegroundColor Cyan
}

Function Invoke-Retry {
    param(
        [Parameter(Mandatory=$true)][ScriptBlock]$Script,
        [int]$Retries = 3,
        [int]$DelaySeconds = 3
    )
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            return & $Script
        } catch {
            if ($i -ge $Retries) { throw }
            Write-Warning "Attempt $i failed: $($_.Exception.Message). Retrying in $DelaySeconds sec…"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

# Force TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Ensure base folders exist up-front
Write-Section "Create base folders"
$pathsToEnsure = @(
    'C:\LabFiles',
    'C:\CloudLabs',
    'C:\AllFiles',
    'C:\CloudLabs\Common',
    'C:\Users\Public\Documents'
)
foreach ($p in $pathsToEnsure) { New-Item -ItemType Directory -Path $p -Force | Out-Null }

# ==================================
#   Section: AzureCreds file & PS1
# ==================================
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

# ================================
#   Section: Common helper import
# ================================
Write-Section "Fetch & import CloudLabs common functions"

$commonScript = "C:\CloudLabs\Common\cloudlabs-windows-functions.ps1"
if (-not (Test-Path $commonScript)) {
    Invoke-Retry -Script {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile("https://experienceazure.blob.core.windows.net/templates/cloudlabs-common/cloudlabs-windows-functions.ps1", $commonScript)
    }
}

. $commonScript

# Base server hygiene + tooling
Write-Section "Apply WindowsServerCommon; install Az PowerShell & Azure CLI"
WindowsServerCommon
InstallAzPowerShellModule
InstallAzCLI

# ================================
#   Section: Download Lab Content
# ================================
Write-Section "Download lab content (mslearn-openai repo)"
$labsZip = "C:\AllFiles\AllFiles.zip"
Invoke-Retry -Script {
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile("https://github.com/CloudLabs-MOC/mslearn-openai/archive/refs/heads/main.zip", $labsZip)
}

Function Expand-ZIPFile($file, $destination) {
    try {
        # Primary: COM Shell (fast)
        $shell = New-Object -ComObject shell.application
        $zip   = $shell.NameSpace($file)
        foreach ($item in $zip.items()) {
            $shell.Namespace($destination).copyhere($item, 16)  # 16 = No UI
        }
    } catch {
        # Fallback: .NET ZipFile
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($file, $destination)
    }
}
Expand-ZIPFile -file $labsZip -destination "C:\AllFiles"
Start-Sleep -Seconds 5

# =========================
#   Section: Auth to Azure
# =========================
Write-Section "Authenticate to Azure (SPN preferred)"
. $credsPs1

$effectiveAppId     = if ($spAppId)     { $spAppId }     elseif ($env:AppID)    { $env:AppID }    else { $null }
$effectiveAppSecret = if ($spAppSecret) { $spAppSecret } elseif ($env:AppSecret){ $env:AppSecret} else { $null }
$effectiveTenantId  = if ($AzureTenantID){ $AzureTenantID}elseif ($env:TenantID){ $env:TenantID } else { $null }

try {
    if ($effectiveAppId -and $effectiveAppSecret -and $effectiveTenantId) {
        Write-Host "Using Service Principal authentication…"
        $spnSecure = $effectiveAppSecret | ConvertTo-SecureString -AsPlainText -Force
        $spnCred   = New-Object System.Management.Automation.PSCredential ($effectiveAppId, $spnSecure)
        Connect-AzAccount -ServicePrincipal -Credential $spnCred -Tenant $effectiveTenantId | Out-Null
        if ($AzureSubscriptionID) { Set-AzContext -Subscription $AzureSubscriptionID | Out-Null }
    } else {
        Write-Warning "SPN not provided; falling back to user credential auth."
        $securePassword = $AzurePassword | ConvertTo-SecureString -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($AzureUserName, $securePassword)
        Connect-AzAccount -Credential $cred | Out-Null
        if ($AzureSubscriptionID) { Set-AzContext -Subscription $AzureSubscriptionID | Out-Null }
    }
}
catch {
    Write-Error "Azure authentication failed: $($_.Exception.Message)"
    throw
}

# ============================
#   Section: Lab-specific ops
# ============================
Write-Section "Lookup ODL user (soft-fail)"
try {
    $ODLuser = Get-AzADUser -DisplayName "ODL_User $DeploymentID" -ErrorAction Stop
    $ODLuserID = $ODLuser.Id
    Write-Host "Found ODL user: $($ODLuser.UserPrincipalName)"
} catch {
    Write-Warning "ODL user not found for DeploymentID '$DeploymentID'. Continuing…"
}

Write-Section "Update Shadow script (if present) & trainer password"
$shadowPath = "C:\Users\Public\Documents\Shadow.ps1"
if (Test-Path $shadowPath) {
    (Get-Content $shadowPath).Replace("vmAdminUsernameValue", $vmAdminUsername) | Set-Content $shadowPath
    Write-Host "Patched Shadow.ps1 with vmAdminUsername."
} else {
    Write-Warning "Shadow.ps1 not found; skipping patch."
}

if ($trainerUserName -and $trainerUserPassword) {
    try {
        net user $trainerUserName $trainerUserPassword | Out-Null
        Write-Host "Trainer account password updated."
    } catch {
        Write-Warning "Failed to set trainer password: $($_.Exception.Message)"
    }
}

# ==================================================
#   Section: Start CloudLabs VM Agent (if available)
# ==================================================
Write-Section "Start CloudLabs VM Agent (if present)"
$vmAgentPath = "C:\CloudLabs\Validator\VMAgent\Spektra.CloudLabs.VMAgent.exe"
$svcName     = "Spektra CloudLabs VM Agent"

if (Test-Path $vmAgentPath) {
    try {
        cmd.exe --% /c sc create "$svcName" BinPath="$vmAgentPath" start= auto
    } catch {
        Write-Warning "Service may already exist: $($_.Exception.Message)"
    }
    try {
        cmd.exe --% /c sc start "$svcName"
        Write-Host "CloudLabs VM Agent service started."
    } catch {
        Write-Warning "Unable to start VM Agent service: $($_.Exception.Message)"
    }
} else {
    Write-Warning "VM Agent binary not found at $vmAgentPath; skipping service creation."
}

# =========================================
#   Section: Finalize & disable runuserdata
# =========================================
Write-Section "Finalize and disable runuserdata"
try { Disable-ScheduledTask -TaskName "runuserdata" -ErrorAction SilentlyContinue } catch {}
try { Stop-ScheduledTask    -TaskName "runuserdata" -ErrorAction SilentlyContinue } catch {}

Write-Section "Provisioning completed"
Stop-Transcript
