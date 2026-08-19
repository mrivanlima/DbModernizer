<#
    run_watcher.ps1

    Scheduling wrapper for 03_ai_fragmentation_watcher.sql. Intended to run
    under SQL Agent (as a PowerShell/CmdExec step) or Windows Task
    Scheduler, once daily during a low-traffic window.

    It only ever runs the read-only watcher query and logs results -- it
    does not rebuild or reorganize any index. Requires the SqlServer
    PowerShell module: Install-Module -Name SqlServer -Scope CurrentUser
#>

param(
    [string]$ServerInstance = "localhost",
    [string]$Database       = "FragDemo",
    [string]$ScriptPath     = "$PSScriptRoot\03_ai_fragmentation_watcher.sql",
    [string]$LogPath        = "$PSScriptRoot\fragmentation_watcher.log"
)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

try {
    $results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database `
        -InputFile $ScriptPath -QueryTimeout 300 -ErrorAction Stop

    $rebuildCount   = ($results | Where-Object { $_.RecommendedAction -eq 'REBUILD' }).Count
    $reorgCount     = ($results | Where-Object { $_.RecommendedAction -eq 'REORGANIZE' }).Count

    "$timestamp - Watcher ran OK. $rebuildCount index(es) flagged REBUILD, $reorgCount flagged REORGANIZE." |
        Out-File -FilePath $LogPath -Append

    if ($rebuildCount -gt 0) {
        $results | Where-Object { $_.RecommendedAction -eq 'REBUILD' } |
            Format-Table DatabaseName, TableName, IndexName, LogicalFragPct, PageDensityPct -AutoSize |
            Out-String | Out-File -FilePath $LogPath -Append

        # Wire this into whatever alerting the team already uses --
        # email, Teams webhook, PagerDuty, etc. This is a notification,
        # not an action: a human still decides what to run and when.
        # Send-MailMessage -To "dba-team@example.com" -Subject "Fragmentation review needed" ...
    }
}
catch {
    "$timestamp - Watcher FAILED: $($_.Exception.Message)" | Out-File -FilePath $LogPath -Append
    throw
}
