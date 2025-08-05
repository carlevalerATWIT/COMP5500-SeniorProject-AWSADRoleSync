<#
.SYNOPSIS
    Provides functions for retrieving AWS IAM users and groups for synchronization operations.

.DESCRIPTION
    This module contains functions for interfacing with AWS Identity and Access Management (IAM)
    to retrieve user and group information. It includes functionality for:
    - Retrieving all IAM group names from AWS
    - Retrieving all IAM user names from AWS
    - Error handling and logging for all AWS API operations
    - Using temporary session profiles for secure API access
    
    The module is designed to work with AWS temporary sessions and provides comprehensive
    logging for audit and troubleshooting purposes. All functions return arrays of names
    for easy processing in synchronization workflows.

.EXAMPLE
    $groups = Get-AllIAMGroupNames
    Retrieves all IAM group names from AWS for synchronization processing.

.EXAMPLE
    $users = Get-AllIAMUsers
    Retrieves all IAM user names from AWS for synchronization processing.
#>


# ===== [ IMPORTS ] =====

# Import required AWS PowerShell modules for IAM operations
Import-Module AWS.Tools.Common -ErrorAction SilentlyContinue              # Core AWS functionality
Import-Module AWS.Tools.IdentityStore -ErrorAction SilentlyContinue       # AWS Identity Store operations
Import-Module AWS.Tools.IdentityManagement -ErrorAction SilentlyContinue  # AWS IAM operations

# Helper function to get the directory where this script is located
function Get-ScriptDirectory { Split-Path $MyInvocation.ScriptName }

# Import paths for required modules
$WriteLogIMPORT = Join-Path (Get-ScriptDirectory) './../../PROCESSES/logging/Write-Log.ps1'                        # Logging functionality
$AWSCredSetupIMPORT = Join-Path (Get-ScriptDirectory) './../../PROCESSES/awsinstance/AWS-CredentialSetup.ps1'     # AWS credential setup

# Import (dot-source) the required modules
. $WriteLogIMPORT
. $AWSCredSetupIMPORT


# ===== [ PRE-VALS ] =====


# ===== [ FUNCTIONS ] =====

function Get-AllIAMGroupNames {
    <#
    .SYNOPSIS
        Retrieves all IAM group names from AWS for synchronization operations.

    .DESCRIPTION
        This function connects to AWS IAM and retrieves a list of all group names in the account.
        It uses the temporary session profile for secure authentication and includes comprehensive
        error handling and logging.
        
        The function performs the following steps:
        1. Connects to AWS IAM using the TempSession profile
        2. Retrieves all IAM groups from the us-east-1 region
        3. Extracts and returns only the group names
        4. Logs all operations and any errors that occur
        
        If an error occurs, an empty array is returned to prevent downstream processing issues.

    .OUTPUTS
        System.String[]
        Returns an array of IAM group names, or an empty array if an error occurs.

    .EXAMPLE
        $groups = Get-AllIAMGroupNames
        Retrieves all IAM group names from AWS.

    .EXAMPLE
        $groupList = Get-AllIAMGroupNames
        if ($groupList.Count -gt 0) {
            Write-Host "Found $($groupList.Count) IAM groups"
        }
        Retrieves IAM groups and checks if any were found.
    #>

    Write-Log -logType "CALL" -logMSG "Retrieving all IAM group names."

    try {
        # Connect to AWS IAM and retrieve all groups using the temporary session profile
        $groups = Get-IAMGroupList -Region us-east-1 -ProfileName "TempSession"
        $groupNames = $groups | Select-Object -ExpandProperty GroupName

        Write-Log -logType "INFO" -logMSG "Successfully retrieved IAM group names."

        return $groupNames
    } catch {
        # Log any errors and return empty array to prevent downstream issues
        Write-Log -logType "ERROR" -logMSG "Failed to retrieve IAM group names: $($_.Exception.Message)"
        return @()
    }
}

function Get-AllIAMUsers {
    <#
    .SYNOPSIS
        Retrieves all IAM user names from AWS for synchronization operations.

    .DESCRIPTION
        This function connects to AWS IAM and retrieves a list of all user names in the account.
        It uses the temporary session profile for secure authentication and includes comprehensive
        error handling and logging.
        
        The function performs the following steps:
        1. Connects to AWS IAM using the TempSession profile
        2. Retrieves all IAM users from the us-east-1 region
        3. Extracts and returns only the user names
        4. Logs all operations and any errors that occur
        
        If an error occurs, an empty array is returned to prevent downstream processing issues.
        This function is commonly used to identify which AWS users need synchronization with
        Active Directory.

    .OUTPUTS
        System.String[]
        Returns an array of IAM user names, or an empty array if an error occurs.

    .EXAMPLE
        $users = Get-AllIAMUsers
        Retrieves all IAM user names from AWS.

    .EXAMPLE
        $userList = Get-AllIAMUsers
        $adUsers = Get-ADUser -Filter * | Select-Object -ExpandProperty SamAccountName
        $commonUsers = $userList | Where-Object { $adUsers -contains $_ }
        Retrieves AWS users and finds which ones also exist in Active Directory.
    #>

    Write-Log -logType "CALL" -logMSG "Retrieving all IAM user names."

    try {
        # Connect to AWS IAM and retrieve all users using the temporary session profile
        $users = Get-IAMUserList -Region us-east-1 -ProfileName "TempSession"
        $usernames = $users | Select-Object -ExpandProperty UserName

        Write-Log -logType "INFO" -logMSG "Successfully retrieved IAM user names."

        return $usernames
    } catch {
        # Log any errors and return empty array to prevent downstream issues
        Write-Log -logType "ERROR" -logMSG "Failed to retrieve IAM user names: $($_.Exception.Message)"
        return @()
    }
}


# ===== [ FILE TESTS ] =====

# Example usage for testing (commented out for safety):
<#
$groupsiam = Get-AllIAMGroupNames
Write-Host "Found IAM Groups: $groupsiam"

$usersiam = Get-AllIAMUsers  
Write-Host "Found IAM Users: $usersiam"
#>