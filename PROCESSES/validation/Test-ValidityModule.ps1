
<#
.SYNOPSIS
    Checks if an Active Directory (AD) username is valid.

.DESCRIPTION
    This script takes an AD username as input and verifies if the user exists in the Active Directory.
    It uses the Get-ADUser cmdlet to perform the validation and outputs whether the user is valid or not.

.PARAMETER Username
    The AD username to be validated.

.EXAMPLE
    .\Test-UserValidity.ps1 -Username "jdoe"
    This command checks if the user 'jdoe' exists in the Active Directory.
#>


# ===== [ IMPORTS ] =====

# Helper function to get the directory where this script is located
function Get-ScriptDirectory { Split-Path $MyInvocation.ScriptName }

# Configuration file path for miscellaneous settings including validation bypass options
$miscconfigJSON = Join-Path (Get-ScriptDirectory) './../../CONFIG/miscconfig.json'

# Import the logging module for audit and debugging purposes
$WriteLogIMPORT = Join-Path (Get-ScriptDirectory) './../../PROCESSES/logging/Write-Log.ps1'

# Import (dot-source) the logging module
. $WriteLogIMPORT

# ===== [ FUNCTIONS ] =====

function Test-UserValidity {
    <#
    .SYNOPSIS
        Validates whether a specified Active Directory user exists and is accessible.

    .DESCRIPTION
        This function checks if a given username exists in Active Directory by attempting
        to retrieve the user object. It includes support for validation bypass functionality
        through configuration settings, which can be useful for testing environments.
        
        The function performs the following steps:
        1. Checks the miscellaneous configuration for user validation bypass setting
        2. If bypass is disabled, attempts to retrieve the AD user object
        3. Returns true if the user exists and is accessible, false otherwise
        4. Logs all validation attempts and results for audit purposes
        
        The bypass functionality allows administrators to disable user validation checks
        during testing or in environments where AD connectivity may be limited.

    .PARAMETER user
        The username (SamAccountName) of the Active Directory user to validate.

    .OUTPUTS
        System.Boolean
        Returns $true if the user exists and is valid, $false otherwise.
        Returns $true if validation bypass is enabled in configuration.

    .EXAMPLE
        Test-UserValidity -user "john.doe"
        Checks if the user "john.doe" exists in Active Directory.

    .EXAMPLE
        if (Test-UserValidity -user "contractor.smith") {
            Write-Host "User is valid, proceeding with role assignment"
        }
        Validates a user before performing operations on their account.

    .EXAMPLE
        $users = @("alice", "bob", "charlie")
        $validUsers = $users | Where-Object { Test-UserValidity -user $_ }
        Filters a list of usernames to only include valid AD users.
    #>

    param (
        [Parameter(Mandatory=$true)]
        [string]$user
    )

    Write-Log -logType "CALL" -logMSG "$($MyInvocation.MyCommand.Name) (user: $user)"

    # Grabs JSON Content.
    $miscconfigContent = Get-Content -Path $miscconfigJSON -Raw | ConvertFrom-Json
    $userTestBypass = $miscconfigContent.validitytests.User

    if (-not $userTestBypass) {
        try {
            Get-ADUser -Identity $user -ErrorAction Stop
            Write-Log -logType "INFO" -logMSG "User validity test has given TRUE on user '$user'."
            return $true
        } catch {
            Write-Log -logType "WARN" -logMSG "User validity test has given FALSE on user '$user'. $_"
            return $false
        }
    } else {
        Write-Log -logType "WARN" -logMSG "User validity bypass is either true or there is a boolean error."
        return $true
    }
    
}

function Test-GroupValidity {
    <#
    .SYNOPSIS
        Validates whether a specified Active Directory group exists and is accessible.

    .DESCRIPTION
        This function checks if a given group name exists in Active Directory by attempting
        to retrieve the group object. It provides essential validation before performing
        group membership operations to prevent errors and ensure data integrity.
        
        The function performs the following steps:
        1. Attempts to retrieve the AD group object using Get-ADGroup
        2. Returns true if the group exists and is accessible
        3. Returns false if the group doesn't exist or is inaccessible
        4. Logs all validation attempts and results for audit purposes
        
        This validation is critical for preventing errors during group membership
        operations and maintaining Active Directory integrity.

    .PARAMETER group
        The name of the Active Directory group to validate.

    .OUTPUTS
        System.Boolean
        Returns $true if the group exists and is valid, $false otherwise.

    .EXAMPLE
        Test-GroupValidity -group "HR-Managers"
        Checks if the group "HR-Managers" exists in Active Directory.

    .EXAMPLE
        if (Test-GroupValidity -group "Finance-ReadOnly") {
            Add-ADGroupMember -Identity "Finance-ReadOnly" -Members $user
        }
        Validates a group exists before adding a user to it.

    .EXAMPLE
        $groups = @("IT-Admin", "HR-Staff", "Finance-Users")
        $validGroups = $groups | Where-Object { Test-GroupValidity -group $_ }
        Filters a list of group names to only include valid AD groups.
    #>

    param (
        [Parameter(Mandatory=$true)]
        [string]$group
    )

    Write-Log -logType "CALL" -logMSG "$($MyInvocation.MyCommand.Name) (group: $group)"

    try {
        Get-ADGroup -Identity $group -ErrorAction Stop
        Write-Log -logType "INFO" -logMSG "Group validity test has given TRUE on group '$group'."
        return $true
    } catch {
        Write-Log -logType "WARN" -logMSG "Group validity test has given FALSE on group '$group'.  $_"
        return $false
    }
}

function Test-OUValidity {
    <#
    .SYNOPSIS
        Validates whether a specified Active Directory Organizational Unit (OU) exists and is accessible.

    .DESCRIPTION
        This function checks if a given OU distinguished name exists in Active Directory by
        attempting to retrieve the OU object. It provides essential validation for operations
        that target specific organizational units, such as user filtering or OU-based processing.
        
        The function performs the following steps:
        1. Attempts to retrieve the AD OU object using Get-ADOrganizationalUnit
        2. Returns true if the OU exists and is accessible
        3. Returns false if the OU doesn't exist or is inaccessible
        4. Logs all validation attempts and results for audit purposes
        
        This validation is important for preventing errors during OU-based operations
        and ensuring that organizational unit references are valid before processing.

    .PARAMETER ou
        The distinguished name of the Active Directory Organizational Unit to validate.
        Should be in the format: "OU=UnitName,DC=domain,DC=com"

    .OUTPUTS
        System.Boolean
        Returns $true if the OU exists and is valid, $false otherwise.

    .EXAMPLE
        Test-OUValidity -ou "OU=Employees,DC=contoso,DC=com"
        Checks if the Employees OU exists in the contoso.com domain.

    .EXAMPLE
        if (Test-OUValidity -ou "OU=Contractors,OU=External,DC=company,DC=local") {
            # Process users in the Contractors OU
        }
        Validates an OU exists before performing operations on users within it.

    .EXAMPLE
        $targetOU = "OU=IT Department,DC=corp,DC=example"
        if (Test-OUValidity -ou $targetOU) {
            $users = Get-ADUser -SearchBase $targetOU -Filter *
        }
        Validates an OU before using it as a search base for user queries.
    #>

    param (
        [Parameter(Mandatory=$true)]
        [string]$ou
    )

    Write-Log -logType "CALL" -logMSG "$($MyInvocation.MyCommand.Name) (ou: $ou)"

    try {
        Get-ADOrganizationalUnit -Identity $ou -ErrorAction Stop
        Write-Log -logType "INFO" -logMSG "OU validity test has given TRUE on OU '$ou'."
        return $true
    } catch {
        Write-Log -logType "WARN" -logMSG "OU validity test has given FALSE on OU '$ou'. $_"
        return $false
    }
}


# ===== [ FILE TESTS ] =====
# WARNING: KEEP COMMENTED OUT UNLESS TESTING.

# Example usage for testing the validation functions:
<#
# Test user validation
Test-UserValidity -user "rcarlevale"

# Test group validation
Test-GroupValidity -group "Domain Admins"

# Test OU validation  
Test-OUValidity -ou "OU=Users,DC=contoso,DC=com"

# Test with invalid objects
Test-UserValidity -user "nonexistentuser"
Test-GroupValidity -group "NonExistentGroup"
Test-OUValidity -ou "OU=InvalidOU,DC=invalid,DC=com"
#>
