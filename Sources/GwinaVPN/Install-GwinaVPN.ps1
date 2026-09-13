<#
.SYNOPSIS
Installation routine for GwinaVPN
#>

$Logpath = $env:ProgramData + "\astang0\GwinaVPN\Logs\"
$Logfile = $Logpath + "Install-GwinaVPNLog.txt"

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

    # Update scheduled task "Update-GwinaVPN-Connections"
    Write-Log -Message "Creating scheduled task 'Update-GwinaVPN-Connections'..." -Level 'Info'
    $actions = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe -ExecutionPolicy Bypass -File '$PsScriptRoot\Set-GwinaVPN.ps1'"
    $trigger = New-ScheduledTaskTrigger -Daily -At '9:00 AM' -RandomDelay (New-TimeSpan -Minutes 60)
    $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -Runlevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit 00:30:00 -MultipleInstances IgnoreNew -AllowStartIfOnBatteries
    $task = New-ScheduledTask -Action $actions -Principal $principal -Trigger $trigger -Settings $settings 
    $task.Author = 'astang0'

    Register-ScheduledTask -TaskName 'Update-GwinaVPN-Connections' -InputObject $task -TaskPath "\GwinaVPN" -Force | Out-Null

    
    # Update scheduled task "Update-GwinaVPN-Tasks"
    Write-Log -Message "Creating scheduled task 'Update-GwinaVPN-Tasks'..." -Level 'Info'
    $actions = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe -ExecutionPolicy Bypass -File '$PsScriptRoot\Update-GwinaVpnTasks.ps1'"
    $trigger = New-ScheduledTaskTrigger -Daily -At '00:00 AM'
    $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -Runlevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit 00:30:00 -MultipleInstances IgnoreNew -AllowStartIfOnBatteries
    $task = New-ScheduledTask -Action $actions -Principal $principal -Trigger $trigger -Settings $settings 
    $task.Author = 'astang0'
    
    Register-ScheduledTask -TaskName 'Update-GwinaVPN-Tasks' -InputObject $task -TaskPath "\GwinaVPN" -Force | Out-Null

    # Run the "Update-GwinaVPN-Tasks" task immediately after installation
    Start-ScheduledTask -TaskName 'Update-GwinaVPN-Tasks' -TaskPath "\GwinaVPN" | Out-Null

    Write-Log -Message "GwinaVPN successfully installed." -Level 'Info'
}
catch {
    Write-Log -Message $_.Exception -Level 'Error'
    exit 1
}
