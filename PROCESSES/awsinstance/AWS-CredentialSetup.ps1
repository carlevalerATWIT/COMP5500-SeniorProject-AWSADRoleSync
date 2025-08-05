<#
.SYNOPSIS
    Sets AWS credentials using the AWS.Tools.Common module.

.DESCRIPTION
    This script reads AWS credentials from a JSON configuration file and sets them using the AWS.Tools.Common module.

.PARAMETER awsConfig
    The JSON configuration file containing AWS credentials.

.EXAMPLE
    .\AWS-CredentialSetup.ps1
    This command sets AWS credentials from the specified JSON configuration file.
#>

# ===== [ IMPORTS ] =====

Import-Module AWS.Tools.Common -ErrorAction Stop

function Get-ScriptDirectory { Split-Path $MyInvocation.ScriptName }

$awsapiconfigJSON = Join-Path (Get-ScriptDirectory) './../../CONFIG/awsapikeys.json'

$WriteLogIMPORT = Join-Path (Get-ScriptDirectory) './../../PROCESSES/logging/Write-Log.ps1'

. $WriteLogIMPORT


# ===== [ PRE-VALS ] =====

$awsConfig = Get-Content -Raw -Path $awsapiconfigJSON | ConvertFrom-Json


# ===== [ FUNCTIONS ] =====

function Setup-AWSCredentials {

    <#
    .SYNOPSIS
        Sets AWS credentials using the AWS.Tools.Common module.

    .DESCRIPTION
        This script reads AWS credentials from a JSON configuration file and sets them using the AWS.Tools.Common module.

    .PARAMETER awsConfig
        The JSON configuration file containing AWS credentials.

    .EXAMPLE
        .\AWS-CredentialSetup.ps1
        This command sets AWS credentials from the specified JSON configuration file.
    #>

    param (
        [Parameter(Mandatory = $true)]
        [string]$accesskey,
        [Parameter(Mandatory = $true)]
        [string]$secretkey,
        [Parameter(Mandatory = $false)]
        [string]$sessiontoken,
        [Parameter(Mandatory = $false)]
        [string]$profilename = "TempSession"
    )
    
    Write-Log -logType "INFO" -logMSG "Entering Set-AWSCredentials function."
    Write-Log -logType "INFO" -logMSG "Parameters: AccessKey=$accesskey, SecretKey=$secretkey, SessionToken=$sessiontoken"

    try {
        if ($sessiontoken) {
            # Set credentials with session token
            Set-AWSCredential -AccessKey $accesskey -SecretKey $secretkey -SessionToken $sessiontoken -StoreAs $profilename
        } else {
            # Set credentials without session token
            Set-AWSCredential -AccessKey $accesskey -SecretKey $secretkey -StoreAs $profilename
        }

        Write-Log -logType "INFO" -logMSG "AWS credentials successfully set."
    } catch {
        Write-Log -logType "ERROR" -logMSG "Failed to set AWS credentials: $_"
    }

    Write-Log -logType "INFO" -logMSG "Exiting Set-AWSCredentials function."
}


# ===== [ MAIN EXECUTION ] =====

<#
# Validate that required keys exist in the configuration
Write-Log -logType "INFO" -logMSG "Validating awsConfig content: $($awsConfig | ConvertTo-Json -Depth 2)"
if (-not $awsConfig.awsaccesskey -or -not $awsConfig.awssecretkey) {
    Write-Error "AWS Access Key or Secret Key is missing in the configuration file."
    Write-Log -logType "ERROR" -logMSG "AWS Access Key or Secret Key is missing in the configuration file."
    return
}

Write-Log -logType "INFO" -logMSG "Validation passed. Proceeding to set AWS credentials."

# Set AWS credentials
Setup-AWSCredentials -AccessKey $awsConfig.awsaccesskey -SecretKey $awsConfig.awssecretkey
#>