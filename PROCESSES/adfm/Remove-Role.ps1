<#
.SYNOPSIS
    Provides functions for removing Active Directory roles/groups from users with validation and logging.

.DESCRIPTION
    This module contains functions for managing Active Directory group membership removals.
    It includes functionality for:
    - Removing individual users from multiple AD groups with comprehensive validation
    - Ensuring data integrity by validating both users and groups before making changes
    - Comprehensive logging of all operations for audit and troubleshooting purposes
    
    The module uses imported validation functions to verify that users and groups exist
    and are valid before attempting any modifications, preventing errors and maintaining
    Active Directory integrity. All removal operations are logged for security and audit purposes.

.EXAMPLE
    Remove-ADRolesFromUser -user "john.doe" -roles @("HR-Managers", "Finance-ReadOnly")
    Removes the user john.doe from both the HR-Managers and Finance-ReadOnly groups after validation.
#>


# ===== [ IMPORTS ] =====

# Helper function to get the directory where this script is located
function Get-ScriptDirectory { Split-Path $MyInvocation.ScriptName }

# Import paths for required modules
$WriteLogIMPORT = Join-Path (Get-ScriptDirectory) './../../PROCESSES/logging/Write-Log.ps1'           # Logging functionality
$TestValidityModuleIMPORT = Join-Path (Get-ScriptDirectory) './../../PROCESSES/validation/Test-ValidityModule.ps1'  # User and group validation

# Import (dot-source) the required modules
. $WriteLogIMPORT
. $TestValidityModuleIMPORT

# ===== [ FUNCTIONS ] =====

function Remove-ADRolesFromUser {
    <#
    .SYNOPSIS
        Removes one or more Active Directory groups/roles from a specified user with validation.

    .DESCRIPTION
        This function safely removes a user from multiple Active Directory groups by performing
        comprehensive validation before making any changes. It validates both the user
        account and all specified groups before attempting to remove the user from any group.
        
        The function performs the following steps:
        1. Validates that the specified user exists and is valid
        2. Validates that all specified groups exist and are valid
        3. Attempts to remove the user from each group
        4. Logs all operations and any errors that occur
        
        If any validation fails, the entire operation is cancelled to prevent partial updates.
        All removal operations are performed without confirmation prompts for automation compatibility.

    .PARAMETER user
        The username (SamAccountName) of the user to remove from the groups.

    .PARAMETER roles
        An array of group names to remove the user from. All groups must exist and be valid.

    .EXAMPLE
        Remove-ADRolesFromUser -user "john.doe" -roles @("HR-Managers")
        Removes john.doe from the HR-Managers group after validation.

    .EXAMPLE
        Remove-ADRolesFromUser -user "jane.smith" -roles @("Finance-ReadOnly", "Accounting-Basic", "Reports-Viewer")
        Removes jane.smith from multiple groups in a single operation after validating all groups.

    .EXAMPLE
        Remove-ADRolesFromUser -user "contractor.user" -roles @("Temp-Access", "Project-Alpha")
        Removes a contractor from temporary access groups, useful for offboarding processes.
    #>

    param(
        [Parameter(Mandatory=$true)]
        [String]$user,
        [Parameter(Mandatory=$true)]
        [String[]]$roles
    )

    Write-Log -logType "CALL" -logMSG "$($MyInvocation.MyCommand.Name) (user: $user) (roles: $roles)"

    # User validation - verify the user exists and is valid before proceeding
    Write-Log -logType "INFO" -logMSG "Calling user validity test on object '$user'."
    if (-not (Test-UserValidity -user $user)) {
        Write-Log -logType "ERROR" -logMSG "Test user validity function has returned that the user is not valid."
        Write-Log -logType "FATAL" -logMSG "Canceling action due to called validity test failure. $_"
        exit
    }

    # Group validation - verify all groups exist and are valid before making any changes
    foreach ($role in $roles) {
        if (-not (Test-GroupValidity -group $role)) {
            Write-Log -logType "ERROR" -logMSG "Test group validity function has returned that the group is not valid."
            Write-Log -logType "FATAL" -logMSG "Canceling action due to called validity test failure. $_"
            exit
        }
    }

    # Perform the role removals - remove user from each validated group
    foreach ($role in $roles) {
        try {
            Write-Log -logType "INFO" -logMSG "Attempting to remove role '$role' from user '$user'."
            Remove-ADGroupMember -Identity $role -Members $user -Confirm:$False
        } catch {
            Write-Log -logType "FATAL" -logMSG "Role '$role' could not be removed from user '$user' due to the following error. $_"
        }
    }

    Write-Log -logType "INFO" -logMSG "Role removal finished. If there were any errors during the removal process, they have been given above."
}

# ===== [ FILE TESTS ] =====

# Example usage (commented out for safety):
#Remove-ADRolesFromUser -user "testuser" -roles @("TEMP-ACCESS", "PROJECT-ALPHA")
#Remove-ADRolesFromUser -user "contractor.doe" -roles @("External-ReadOnly")