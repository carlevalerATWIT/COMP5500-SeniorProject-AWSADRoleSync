<#
.SYNOPSIS
    Manages logging session initialization, cleanup, and retrieval for the AWS-AD Role Sync system.

.DESCRIPTION
    This module provides comprehensive logging session management functionality for the AWS-AD Role Sync system.
    It handles the creation, tracking, and cleanup of log sessions based on user, host, and date combinations.
    
    Key features include:
    - Automatic log session creation with unique UUIDs
    - Session tracking by username, hostname, and date
    - Automatic cleanup of old log sessions based on configurable retention periods
    - Session reuse for same user/host/date combinations
    - JSON-based session persistence
    - Configurable log file naming conventions
    
    The module ensures that each unique combination of user, host, and date gets its own log session,
    while reusing existing sessions for the same combination within a day.

.EXAMPLE
    $currentLogPath = Get-CurrentLogSession
    Gets the log file path for the current user's session today.

.EXAMPLE
    Clean-SessionData
    Removes old log sessions based on the configured cleanup time.
#>


# ===== [ IMPORTS ] =====

# Helper function to get the directory where this script is located
function Get-ScriptDirectory { Split-Path $MyInvocation.ScriptName }

# Configuration file paths
$sessionsJSON = Join-Path (Get-ScriptDirectory) './../../LOGS/sessions.json'        # Log session tracking data
$logconfigJSON = Join-Path (Get-ScriptDirectory) './../../CONFIG/logconfig.json'   # Logging configuration settings


# ===== [ FUNCTIONS ] =====

function Clean-SessionData {
    <#
    .SYNOPSIS
        Removes old log sessions that exceed the configured retention period.

    .DESCRIPTION
        This function performs automatic cleanup of old log sessions based on the cleanup time
        configured in the log configuration file. It removes sessions older than the specified
        number of days to prevent the sessions file from growing indefinitely.
        
        The function performs the following steps:
        1. Reads the cleanup time in days from the log configuration
        2. Calculates the cutoff date for session removal
        3. Iterates through all sessions to identify those older than the cutoff date
        4. Removes the old sessions from the JSON structure
        5. Saves the updated sessions back to the file
        
        This function should be called periodically to maintain system performance and
        prevent excessive disk usage from old session data.

    .EXAMPLE
        Clean-SessionData
        Removes all log sessions older than the configured cleanup time.

    .EXAMPLE
        # Typically called as part of system maintenance
        Clean-SessionData
        Write-Host "Old log sessions have been cleaned up."
    #>

    # Grabs JSON Content.
    $logconfigContent = Get-Content -Path $logconfigJSON -Raw | ConvertFrom-Json
    $sessionsContent = Get-Content -Path $sessionsJSON -Raw | ConvertFrom-Json

    # Gets the cleanup time in days from the logconfig.
    $cleanupTimeInDays = $logconfigContent.log_session_settings.cleanup_time_indays

    $currentDate = Get-Date
    $cleanupDate = $currentDate.AddDays(-$cleanupTimeInDays)

    $sessionsToRemove = @()

    # Iterates through each session and checks if the record date is older than the cleanup date.
    foreach ($session in $sessionsContent.sessions.PSObject.Properties) {
        $sessionDate = [datetime]::ParseExact($session.Value.recorddate, "yyyy-MM-dd", $null)
        if ($sessionDate -lt $cleanupDate) {
            $sessionsToRemove += $session.Name
        }
    }

    foreach ($sessionName in $sessionsToRemove) {
        $sessionsContent.sessions.PSObject.Properties.Remove($sessionName)
    }

    # Applies the changes to the JSON file.
    $sessionsContent | ConvertTo-Json -Depth 32 | Set-Content -Path $sessionsJSON
}


function New-SessionData {
    <#
    .SYNOPSIS
        # TODO: Write this.

    .DESCRIPTION
        # TODO: Write this.

    .EXAMPLE
        # TODO: Write this.
    #>

    # Grabs JSON Content.
    $logconfigContent = Get-Content -Path $logconfigJSON -Raw | ConvertFrom-Json
    $sessionsContent = Get-Content -Path $sessionsJSON -Raw | ConvertFrom-Json

    # Generates a new UUID for the session and creates a new log session object.
    $newUUID = [guid]::NewGuid().ToString()
    $newLogSession = @{
        envuser = $ENV:USERNAME
        envhost = $ENV:COMPUTERNAME
        recorddate = (Get-Date).ToString("yyyy-MM-dd")
        logpath = $logconfigContent.logfilename.basename + "_$ENV:USERNAME" + "_$((Get-Date).ToString("yyyy-MM-dd"))" + "_$newUUID" + $logconfigContent.logfilename.extension
    }

    # Ensures the sessions object exists in the JSON file and is hastable type.
    if (-not $sessionsContent.PSObject.Properties['sessions']) {
        $sessionsContent | Add-Member -MemberType NoteProperty -Name 'sessions' -Value @{}
    }

    # Converts sessions property to a hashtable if it is not already.
    if (-not ($sessionsContent.sessions -is [hashtable])) {
        $sessionsTable = @{}
        $sessionsContent.sessions.PSObject.Properties | ForEach-Object {
            $sessionsTable[$_.Name] = $_.Value
        }
        $sessionsContent.sessions = $sessionsTable
    }

    # Adds the new session to the existing sessions.
    $sessionsContent.sessions[$newUUID] = $newLogSession

    # Converts back to JSON and saves the new session to the log file.
    $sessionsContent | ConvertTo-Json -Depth 32 | Set-Content -Path $sessionsJSON

    return $newUUID
}


function Search-ForSessionUUID {
    <#
    .SYNOPSIS
        # TODO: Write this.

    .DESCRIPTION
        # TODO: Write this.

    .EXAMPLE
        # TODO: Write this.
    #>

    # Grabs JSON Content.
    $sessionsContent = Get-Content -Path $sessionsJSON -Raw | ConvertFrom-Json

    foreach ($session in $sessionsContent.sessions.PSObject.Properties) {
        if ($session.Value.envhost -eq $ENV:COMPUTERNAME -and $session.Value.envuser -eq $ENV:USERNAME -and $session.Value.recorddate -eq $((Get-Date).ToString("yyyy-MM-dd"))) {
            return $session.Name
        }
    }

    $newUUID = New-SessionData
    return $newUUID
}

function Get-CurrentLogSession {
    <#
    .SYNOPSIS
        # TODO: Write this.

    .DESCRIPTION
        # TODO: Write this.

    .EXAMPLE
        # TODO: Write this.
    #>

    # Gets the current UUID of the working log. This MUST be called before the JSON content is grabbed.
    $logUUID = Search-ForSessionUUID  

    # Grabs JSON Content.
    $sessionsContent = Get-Content -Path $sessionsJSON -Raw | ConvertFrom-Json      

    # Convert sessions property to a hashtable
    $sessionsTable = @{}
    
    $sessionsContent.sessions.PSObject.Properties | ForEach-Object {
        $sessionsTable[$_.Name] = $_.Value
    }

    # Returns the log path for the current session and if it does not exist, returns null.
    if ($sessionsTable[$logUUID]) {
        return $sessionsTable[$logUUID].logpath
    } else {
        return $null
    }
}
