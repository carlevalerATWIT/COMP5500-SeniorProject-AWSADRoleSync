<#
.SYNOPSIS
    Provides functions for assigning Active Directory roles/groups to users with validation and logging.

.DESCRIPTION
    This module contains functions for managing Active Directory group membership assignments.
    It includes functionality for:
    - Adding individual users to multiple AD groups with comprehensive validation
    - Ensuring data integrity by validating both users and groups before making changes
    - Comprehensive logging of all operations for audit and troubleshooting purposes
    
    The module uses imported validation functions to verify that users and groups exist
    and are valid before attempting any modifications, preventing errors and maintaining
    Active Directory integrity.

.EXAMPLE
    Add-ADRolesToUser -user "john.doe" -roles @("HR-Managers", "Finance-ReadOnly")
    Adds the user john.doe to both the HR-Managers and Finance-ReadOnly groups after validation.
#>


# ===== [ IMPORTS ] =====

function Get-ScriptDirectory { Split-Path $MyInvocation.ScriptName }

$WriteLogIMPORT = Join-Path (Get-ScriptDirectory) './../../PROCESSES/logging/Write-Log.ps1'
$TestValidityModuleIMPORT = Join-Path (Get-ScriptDirectory) './../../PROCESSES/validation/Test-ValidityModule.ps1'

. $WriteLogIMPORT
. $TestValidityModuleIMPORT

# ===== [ FUNCTIONS ] =====

function Add-ADRolesToUser {
    <#
    .SYNOPSIS
        Adds one or more Active Directory groups/roles to a specified user with validation.

    .DESCRIPTION
        This function safely adds a user to multiple Active Directory groups by performing
        comprehensive validation before making any changes. It validates both the user
        account and all specified groups before attempting to add the user to any group.
        
        The function performs the following steps:
        1. Validates that the specified user exists and is valid
        2. Validates that all specified groups exist and are valid
        3. Attempts to add the user to each group
        4. Logs all operations and any errors that occur
        
        If any validation fails, the entire operation is cancelled to prevent partial updates.

    .PARAMETER user
        The username (SamAccountName) of the user to add to the groups.

    .PARAMETER roles
        An array of group names to add the user to. All groups must exist and be valid.

    .EXAMPLE
        Add-ADRolesToUser -user "john.doe" -roles @("HR-Managers")
        Adds john.doe to the HR-Managers group after validation.

    .EXAMPLE
        Add-ADRolesToUser -user "jane.smith" -roles @("Finance-ReadOnly", "Accounting-Basic", "Reports-Viewer")
        Adds jane.smith to multiple groups in a single operation after validating all groups.
    #>

    param(
        [Parameter(Mandatory=$true)]
        [String]$user,
        [Parameter(Mandatory=$true)]
        [String[]]$roles
    )

    Write-Log -logType "CALL" -logMSG "$($MyInvocation.MyCommand.Name) (user: $user) (roles: $roles)"

    # User verification.
    Write-Log -logType "INFO" -logMSG "Calling user validity test on object '$user'."
    if (-not (Test-UserValidity -user $user)) {
        Write-Log -logType "ERROR" -logMSG "Test user validity function has returned that the user is not valid."
        Write-Log -logType "FATAL" -logMSG "Canceling action due to called validity test failure. $_"
        exit
    }

    # Role verification.
    foreach ($role in $roles) {
        if (-not (Test-GroupValidity -group $role)) {
            Write-Log -logType "ERROR" -logMSG "Test group validity function has returned that the group is not valid."
            Write-Log -logType "FATAL" -logMSG "Canceling action due to called validity test failure. $_"
            exit
        }
    }

    # Assigns the roles.
    foreach ($role in $roles) {
        try {
            Write-Log -logType "INFO" -logMSG "Attempting to add role '$role' to user '$user'."
            Add-ADGroupMember -Identity $role -Members $user 
        } catch {
            Write-Log -logType "FATAL" -logMSG "Role '$role' could not be assigned to user '$user' due to the following error. $_"
        }
    }

    Write-Log -logType "INFO" -logMSG "Role assignment finished. If there were any errors during the assignment process, they have been given above."
}

function Add-ADRoleFromClientcodeIndex {
    <#
    .SYNOPSIS
        Performs bulk role assignments by searching for groups with a specific index and replacing it with a new index.

    .DESCRIPTION
        This function automates the process of updating Active Directory roles based on a search and replace pattern.
        It searches for all groups containing a specific string (search index), creates corresponding groups with
        a replacement string (replacement index), and then assigns users from the old groups to the new groups.
        
        The function performs the following steps:
        1. Searches for all AD groups containing the search index
        2. For each found group, creates a new group name by replacing the search index with the replacement index
        3. Validates that the new group exists and is valid
        4. Gets all users from the original group
        5. Optionally filters users based on their OU (Organizational Unit)
        6. Adds each user to the corresponding new group
        
        This is particularly useful for bulk role migrations, environment promotions (dev to prod), 
        or organizational restructuring.

    .PARAMETER sIndex
        The search string to look for in existing group names. Groups containing this string will be processed.

    .PARAMETER rIndex
        The replacement string that will replace the search index in group names to create the target groups.

    .PARAMETER userOUfilter
        Optional filter to only process users whose Distinguished Name contains this string.
        Useful for limiting the operation to specific organizational units.

    .EXAMPLE
        Add-ADRoleFromClientcodeIndex -sIndex "ENDEAVOUR-" -rIndex "ENDEAVOURPTE-"
        Finds all groups containing "ENDEAVOUR-" and assigns users to corresponding "ENDEAVOURPTE-" groups.
        For example, users in "ENDEAVOUR-DATABASE-ADMIN" would be added to "ENDEAVOURPTE-DATABASE-ADMIN".

    .EXAMPLE
        Add-ADRoleFromClientcodeIndex -sIndex "DEV-" -rIndex "PROD-" -userOUfilter "OU=Developers,DC=example,DC=com"
        Finds all groups containing "DEV-" and assigns users to corresponding "PROD-" groups,
        but only for users whose DN contains "OU=Developers,DC=example,DC=com".
    #>

    param(
        [Parameter(Mandatory=$true)]
        [String]$sIndex,
        [Parameter(Mandatory=$true)]
        [String]$rIndex,
        [Parameter(Mandatory=$false)]
        [String]$userOUfilter
    )

    Write-Log -logType "CALL" -logMSG "$($MyInvocation.MyCommand.Name) (sIndex: $sIndex) (rIndex: $rIndex) (userOUfilter: $userOUfilter)"

    # Search for groups based on the search index and validate the results
    $groups = Get-ADGroup -Filter "Name -like '*$sIndex*'" | Select-Object Name

    if ($groups.Count -gt 0) {
        Write-Log -logType "INFO" -logMSG "Retrieved list of the following groups based on the index of '$sIndex': $groups"
    } else {
        Write-Log -logType "ERROR" -logMSG "No valid groups were found using the index '$sIndex', cancelling this function."
        exit
    }

    # Process each group: replace the search index with replacement index and assign users
    foreach ($group in $groups) {
        $nGroupName = $group.Name -replace "$sIndex", "$rIndex"

        # Validate that the target group exists before proceeding
        if (-not (Test-GroupValidity -group $nGroupName)) {
            Write-Log -logType "ERROR" -logMSG "Test group validity function has returned that the group '$nGroupName' is not valid."
            Write-Log -logType "FATAL" -logMSG "Canceling action due to called validity test failure. $_"
            break
        }

        # Get all users from the original group (including nested group members)
        $users = Get-ADGroupMember -Identity $group.Name -Recursive | Where-Object { $_.objectClass -eq 'user' }
        
        # Process each user from the original group
        foreach ($user in $users) {
            $userDN = (Get-ADUser -Identity $user -Properties DistinguishedName).DistinguishedName

            # Apply OU filter if specified, otherwise process all users
            if ([string]::IsNullOrEmpty($userOUfilter) -or ($userDN -like "*$userOUfilter*")) {
                # Add the user to the new group
                Add-ADRolesToUser -user $user -roles @("$nGroupName")
                Write-Log -logType "INFO" -logMSG "Processed user '$user' for group migration from '$($group.Name)' to '$nGroupName'."
            }
        }
    }
}

# ===== [ FILE TESTS ] =====

# Example usage (commented out for safety):
#Add-ADRolesToUser -user "testad" -roles @("ALBACORE-DATABASE-TWAIN", "ALBACORE-DATABASE-JUDGE")
#Add-ADRoleFromClientcodeIndex -sIndex "ENDEAVOUR-" -rIndex "ENDEAVOURPTE-" #-userOUfilter "*OU=VMS_USER_EMPLOYEE_ACCTS*"