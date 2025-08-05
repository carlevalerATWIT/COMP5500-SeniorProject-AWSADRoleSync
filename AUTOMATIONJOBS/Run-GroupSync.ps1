<#
.SYNOPSIS
    Synchronizes user group memberships between Active Directory and AWS IAM based on configured mappings.

.DESCRIPTION
    This script provides bidirectional synchronization between Active Directory groups and AWS IAM groups.
    It can operate in two modes:
    - "ad" mode: Syncs AWS group memberships based on AD group membership (AD is the source of truth)
    - "aws" mode: Syncs AD group memberships based on AWS group membership (AWS is the source of truth)
    
    The script reads configuration files to determine group mappings, AWS credentials, and synchronization direction.
    It processes all AWS users that also exist in Active Directory and ensures their group memberships
    are consistent between both systems according to the defined mappings.

.EXAMPLE
    .\Run-GroupSync.ps1
    Runs the group synchronization process using the configured controller mode and group mappings.
#>


# ===== [ IMPORTS ] =====

# Import required PowerShell modules for Active Directory and AWS operations
Import-Module ActiveDirectory -ErrorAction SilentlyContinue
Import-Module AWS.Tools.Common

# Helper function to get the directory where this script is located
function Get-ScriptDirectory { Split-Path $MyInvocation.ScriptName }

# Define paths to configuration files relative to the script location
$groupmapJSON = Join-Path (Get-ScriptDirectory) './../CONFIG/awssync/groupmappings.json'     # AD to AWS group mappings
$awsapiconfigJSON = Join-Path (Get-ScriptDirectory) './../CONFIG/awsapikeys.json'           # AWS API credentials
$awsinstanceJSON = Join-Path (Get-ScriptDirectory) './../CONFIG/awsinstance.json'           # AWS instance configuration

# Define paths to required PowerShell module files
$AWSCredentialIMPORT = Join-Path (Get-ScriptDirectory) './../PROCESSES/logging/Write-Log.ps1'
$AWSGetIAMIMPORT = Join-Path (Get-ScriptDirectory) './../PROCESSES/awssync/AWS-GetIAM.ps1'
$AWSRoleSyncIMPORT = Join-Path (Get-ScriptDirectory) './../PROCESSES/awssync/AWS-RoleSync.ps1'
$AssignRoleIMPORT = Join-Path (Get-ScriptDirectory) './../PROCESSES/adfm/Assign-Role.ps1'
$RemoveRoleIMPORT = Join-Path (Get-ScriptDirectory) './../PROCESSES/adfm/Remove-Role.ps1'
$WriteLogIMPORT = Join-Path (Get-ScriptDirectory) './../PROCESSES/logging/Write-Log.ps1'

# Import (dot-source) all required PowerShell modules
. $AWSCredentialIMPORT
. $AWSGetIAMIMPORT
. $AWSRoleSyncIMPORT
. $AssignRoleIMPORT
. $RemoveRoleIMPORT
. $WriteLogIMPORT


# ===== [ PRE-VALS ] =====

# Load configuration data from JSON files
$awsConfig = Get-Content -Raw -Path $awsapiconfigJSON | ConvertFrom-Json      # AWS API credentials and settings
$awsInstance = Get-Content -Raw -Path $awsinstanceJSON | ConvertFrom-Json     # AWS instance configuration including controller mode
$groupMap = Get-Content -Raw -Path $groupmapJSON | ConvertFrom-Json           # Mappings between AD groups and AWS groups


# ===== [ FUNCTIONS ] =====

function Start-AutomationLoopRun {
    <#
    .SYNOPSIS
        Executes the main synchronization loop for AD and AWS group memberships.

    .DESCRIPTION
        This function performs the core synchronization logic between Active Directory and AWS IAM groups.
        It operates in two modes based on the controller configuration:
        - "ad" mode: Uses AD group membership to determine AWS group assignments
        - "aws" mode: Uses AWS group membership to determine AD group assignments
        
        The function processes all AWS users that exist in AD and ensures their group memberships
        are synchronized according to the configured mappings.

    .EXAMPLE
        Start-AutomationLoopRun
        Starts the synchronization process using the configured controller mode.
    #>

    Write-Log -logType "CALL" -logMSG "Starting main automation loop."

    # Initialize AWS credentials using the configured access and secret keys
    Setup-AWSCredentials -AccessKey $awsConfig.awsaccesskey -SecretKey $awsConfig.awssecretkey

    # Retrieve all AWS IAM users and filter to only include those that exist in Active Directory
    $awsUsers = Get-AllIAMUsers
    $adUsers = Get-ADUser -Filter * | Select-Object -ExpandProperty SamAccountName
    $awsUsers = $awsUsers | Where-Object { $adUsers -contains $_ }

    Write-Log -logType "INFO" -logMSG "Found $($awsUsers.Count) AWS users that are also in AD."

    # Get the synchronization controller mode from configuration
    $syncval = $awsInstance.controller
    $controller = $awsInstance.controller

    Write-Host $syncval


    # OLD VERSION THAT JUST DID AD SYNCING
    # This commented section shows the original implementation that only synchronized from AD to AWS
    <#foreach ($username in $awsUsers) {
        foreach ($mapping in $groupMap.groupMappings) {
            $adGroup = $mapping.ad
            $awsGroup = $mapping.aws

            # Get AD groups for the user
            $userGroups = (Get-ADUser -Identity $username -Properties MemberOf).MemberOf
            $isMember = $false
            if ($userGroups) {
                $isMember = $userGroups | ForEach-Object { (Get-ADGroup $_).Name } | Where-Object { $_ -eq $adGroup }
            }

            if ($isMember) {
                # Assign user to AWS group if they are missing it.
                Add-SyncAWSUserToGroup -GroupName $awsGroup -UserName $username
            } else {
                # Remove user from AWS group if not in AD group
                Remove-SyncAWSUserFromGroup -groupname $awsGroup -username $username
            }
        }
    }#>

    # Process synchronization based on the configured controller mode
    # The controller determines which system (AD or AWS) is the source of truth
    if ($controller -eq "ad") {
        # AD Controller Mode: Active Directory is the source of truth
        # AWS group memberships are updated to match AD group memberships
        Write-Log -logType "INFO" -logMSG "Controller set to 'ad'. Syncing AWS roles based on AD group membership."
        
        foreach ($username in $awsUsers) {
            foreach ($mapping in $groupMap.groupMappings) {
                $adGroup = $mapping.ad
                $awsGroup = $mapping.aws

                # Retrieve all AD groups that the user is currently a member of
                $userGroups = (Get-ADUser -Identity $username -Properties MemberOf).MemberOf
                $adGroupNames = @()
                if ($userGroups) {
                    $adGroupNames = $userGroups | ForEach-Object { (Get-ADGroup $_).Name }
                }

                # Synchronize AWS group membership based on AD group membership
                if ($adGroupNames -contains $adGroup) {
                    # User is in the AD group, ensure they are also in the corresponding AWS group
                    Add-SyncAWSUserToGroup -groupname $awsGroup -username $username
                } else {
                    # User is not in the AD group, ensure they are removed from the corresponding AWS group
                    Remove-SyncAWSUserFromGroup -groupname $awsGroup -username $username
                }
            }
        }
    }
    elseif ($controller -eq "aws") {
        # AWS Controller Mode: AWS is the source of truth  
        # AD group memberships are updated to match AWS group memberships
        Write-Log -logType "INFO" -logMSG "Controller set to 'aws'. Syncing AD roles based on AWS group membership."
        
        foreach ($username in $awsUsers) {
            # Retrieve all AWS IAM groups that the user is currently a member of
            $userAwsGroups = @()
            try {
                $userAwsGroups = Get-IAMGroupForUser -username $username -Region us-east-1 -ProfileName "TempSession" | Select-Object -ExpandProperty GroupName
            } catch {
                Write-Log -logType "ERROR" -logMSG "Failed to get AWS groups for user '$username': $($_.Exception.Message)"
            }

            # Process each defined group mapping
            foreach ($mapping in $groupMap.groupMappings) {
                $adGroup = $mapping.ad
                $awsGroup = $mapping.aws

                # Retrieve current AD groups for the user
                $userGroups = (Get-ADUser -Identity $username -Properties MemberOf).MemberOf
                $adGroupNames = @()
                if ($userGroups) {
                    $adGroupNames = $userGroups | ForEach-Object { (Get-ADGroup $_).Name }
                }

                # Synchronize AD group membership based on AWS group membership
                if ($userAwsGroups -contains $awsGroup) {
                    # User is in the AWS group, ensure they are also in the corresponding AD group
                    if (-not ($adGroupNames -contains $adGroup)) {
                        try {
                            Add-ADRolesToUser -user $username -roles @($adGroup) -ErrorAction Stop
    
                            Write-Log -logType "INFO" -logMSG "Added user '$username' to AD group '$adGroup'."
                        } catch {
                            Write-Log -logType "ERROR" -logMSG "Failed to add user '$username' to AD group '$adGroup': $($_.Exception.Message)"
                        }
                    }
                } else {
                    # User is not in the AWS group, ensure they are removed from the corresponding AD group
                    if ($adGroupNames -contains $adGroup) {
                        try {
                            Remove-ADRolesFromUser -user $username -roles @($adGroup) -ErrorAction Stop
                            Write-Log -logType "INFO" -logMSG "Removed user '$username' from AD group '$adGroup'."
                        } catch {
                            Write-Log -logType "ERROR" -logMSG "Failed to remove user '$username' from AD group '$adGroup': $($_.Exception.Message)"
                        }
                    }
                }
            }
        }
    }
    else {
        # Invalid controller value - log error and throw exception
        Write-Log -logType "ERROR" -logMSG "Unknown controller value '$controller'."
        throw "Unknown controller value: $controller"
    }
}


# ===== [ FILE RUNS ] =====

# Execute the main synchronization process
Start-AutomationLoopRun

# ===== [ FILE TESTS ] =====
# This section can be used for testing and validation code