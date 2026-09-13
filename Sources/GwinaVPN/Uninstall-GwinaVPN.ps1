<#
.SYNOPSIS
    Uninstall routine for GwinaVPN
#>


$Logpath = $env:ProgramData + "\astang0\GwinaVPN\Logs\"
$Logfile = $Logpath + "Uninstall-GwinaVPNLog.txt"

if (-not (Test-Path -Path $Logpath)) {
    New-Item -ItemType Directory -Path $Logpath -Force | Out-Null
}

function Write-Log {
    <#
    .SYNOPSIS
    Writes a message to the log file and console.

    .DESCRIPTION
    This function writes a message to the log file and console with a timestamp and log level.

    .PARAMETER Message
    The message to write to the log.

    .PARAMETER Level
    The log level of the message.
    #>

    param(
        [string]$Message, 
        [string]$Level = 'Info'  
    )

    $Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $LogEntry = "[$Timestamp] [$Level] $Message"
    Write-Host $LogEntry
    Add-Content -Path $Logfile -Value $LogEntry
}

try {
    # Check if the script is running with administrative privileges
    $IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $IsSystem = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).Identities.IsSystem

    If (-NOT ($IsAdmin -or $IsSystem)) {
        throw "This installer must be run as an administrator. Please run it in with elevated permissions." 
    }

    # Remove Scheduled tasks
    Write-Log -Message "Removing scheduled tasks..." -Level 'Info'
    Get-ScheduledTask -TaskPath "\GwinaVPN\" | Unregister-ScheduledTask -Confirm:$false
    
    # Remove GwinaVPN directory
    $scheduleObject = New-Object -ComObject Schedule.Service
    $scheduleObject.connect()
    $rootFolder = $scheduleObject.GetFolder("\")
    $rootFolder.DeleteFolder("GwinaVPN",$null)

    Write-Log -Message "GwinaVPN successfully uninstalled." -Level 'Info'
}
catch {
    Write-Log -Message $_.Exception -Level 'Error'
    exit 1
}
