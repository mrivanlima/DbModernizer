<#
    run_watcher.ps1

    Scheduling wrapper for 03_ai_stats_drift_watcher.sql. Intended to run
    under SQL Agent (as a PowerShell/CmdExec step) or Windows Task
    Scheduler, once daily during a low-traffic window.

    It only ever runs the read-only watcher query and logs results -- it
    does not run UPDATE STATISTICS on anything. Requires the SqlServer
    PowerShell module: Install-Module -Name SqlServer -Scope CurrentUser
#>

param(
    [string]$ServerInstance = "localhost",
    [string]$Database       = "StaleStatsDemo",
    [string]$ScriptPath     = "$PSScriptRoot\03_ai_stats_drift_watcher.sql",
    [string]$LogPath        = "$PSScriptRoot\stats_drift_watcher.log"
)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

try {
    $results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database `
        -InputFile $ScriptPath -QueryTimeout 300 -ErrorAction Stop

    $updateNowCount = ($results | Where-Object { $_.RecommendedAction -eq 'UPDATE_NOW' }).Count
    $reviewCount    = ($results | Where-Object { $_.RecommendedAction -eq 'REVIEW' }).Count

    "$timestamp - Watcher ran OK. $updateNowCount stat(s) flagged UPDATE_NOW, $reviewCount flagged REVIEW." |
        Out-File -FilePath $LogPath -Append

    if ($updateNowCount -gt 0) {
        $results | Where-Object { $_.RecommendedAction -eq 'UPDATE_NOW' } |
            Format-Table TableName, StatsName, DaysSinceUpdate, PctModifiedOfLast -AutoSize |
            Out-String | Out-File -FilePath $LogPath -Append

        # Wire this into whatever alerting the team already uses --
        # email, Teams webhook, PagerDuty, etc. This is a notification,
        # not an action: a human still decides what to run and when.
        # Send-MailMessage -To "dba-team@example.com" -Subject "Statistics review needed" ...
    }
}
catch {
    "$timestamp - Watcher FAILED: $($_.Exception.Message)" | Out-File -FilePath $LogPath -Append
    throw
}
