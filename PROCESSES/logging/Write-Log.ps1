<#
.SYNOPSIS
    Provides centralized logging functionality with session-based log file management.

.DESCRIPTION
    This module provides a centralized logging system for the AWS-AD Role Sync application.
    It integrates with the log session management system to automatically create and manage
    log files based on user sessions.
    
    Key features include:
    - Session-based log file creation and management
    - Multiple log levels (CALL, INFO, MSSG, WARN, ERROR, FATAL)
    - Automatic log file creation if it doesn't exist
    - Timestamped log entries with consistent formatting
    - Error handling for log write operations
    - Integration with the Initialize-LogSession module
    
    The logging system automatically determines the appropriate log file based on the current
    user session and creates new log files as needed. All log entries include timestamps,
    log levels, and the actual log message for comprehensive audit trails.

.EXAMPLE
    Write-Log -logType "INFO" -logMSG "User synchronization started"
    Writes an informational log entry to the current session's log file.

.EXAMPLE
    Write-Log -logType "ERROR" -logMSG "Failed to connect to AWS: Connection timeout"
    Writes an error log entry with details about the failure.

.EXAMPLE
    Write-Log -logType "CALL" -logMSG "Function Get-ADUsers called with parameter: Domain=contoso.com"
    Logs a function call with its parameters for debugging purposes.
#>


# ===== [ IMPORTS ] =====

# Helper function to get the directory where this script is located
function Get-ScriptDirectory { Split-Path $MyInvocation.ScriptName }

# Import the log session initialization module for session-based logging
$InitLogSessionIMPORT = Join-Path (Get-ScriptDirectory) './Initialize-LogSession.ps1'

# Import (dot-source) the log session module
. $InitLogSessionIMPORT


# ===== [ FUNCTIONS ] =====

function Write-Log {
    <#
    .SYNOPSIS
        Writes timestamped log entries to session-based log files with specified log levels.

    .DESCRIPTION
        This function provides centralized logging capabilities for the AWS-AD Role Sync system.
        It automatically determines the appropriate log file based on the current user session
        and writes formatted log entries with timestamps and log levels.
        
        The function performs the following operations:
        1. Formats the log entry with current timestamp and log level
        2. Determines the current log file from the active session
        3. Creates the log file if it doesn't exist (with initialization message)
        4. Appends the log entry to the appropriate log file
        5. Handles any errors that occur during the write operation
        
        Log levels supported:
        - CALL: Function/method calls and their parameters
        - INFO: General informational messages
        - MSSG: User messages and notifications
        - WARN: Warning conditions that don't stop execution
        - ERROR: Error conditions that may affect functionality
        - FATAL: Critical errors that may cause application termination

    .PARAMETER logType
        The severity level of the log entry. Must be one of: CALL, INFO, MSSG, WARN, ERROR, FATAL.

    .PARAMETER logMSG
        The message content to be logged. Should be descriptive and include relevant context.

    .EXAMPLE
        Write-Log -logType "INFO" -logMSG "Starting AWS credential validation"
        Writes an informational log entry about credential validation.

    .EXAMPLE
        Write-Log -logType "ERROR" -logMSG "Failed to retrieve AD groups: Access denied"
        Logs an error with specific failure details.

    .EXAMPLE
        Write-Log -logType "CALL" -logMSG "Add-ADRolesToUser called with user: john.doe, roles: @('HR-Manager', 'Finance-ReadOnly')"
        Logs a function call with its parameters for debugging.

    .EXAMPLE
        Write-Log -logType "FATAL" -logMSG "Unable to connect to AWS - invalid credentials provided"
        Logs a critical error that may cause application termination.
    #>
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("CALL", "INFO", "MSSG", "WARN", "ERROR", "FATAL")] 
        [String]$logType,
        [Parameter(Mandatory=$true)]
        [String]$logMSG
    )

    # Format the log entry with timestamp and log level
    $currDT = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logEntry = "[$currDT] $logType : $logMSG"

    # Get the current session's log file name from the session management system
    $workingLogFile = Get-CurrentLogSession    

    # Construct the full path to the log file
    $logFileIMPORT = Join-Path (Get-ScriptDirectory) "./../../LOGS/$workingLogFile"

    # Create the log file if it doesn't exist and add initialization message
    if (-not (Test-Path -Path $logFileIMPORT)) {
        New-Item -Path $logFileIMPORT -ItemType File -Force | Out-Null

        $logEntryNEW = "[$currDT] INFO : New log file initialized $logFileIMPORT from $ENV:COMPUTERNAME by $ENV:USERNAME"
        Add-Content -Path $logFileIMPORT -Value $logEntryNEW
    }

    try {
        # Write the formatted log entry to the session's log file
        Add-Content -Path $logFileIMPORT -Value $logEntry
    } catch {
        # Handle any errors that occur during log file writing
        Write-Error "Failed to write to log file: $_"
    }
}