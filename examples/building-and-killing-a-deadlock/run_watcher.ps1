<#
    run_watcher.ps1
    Companion code for "Building and Killing a Deadlock With Your Own Hands"

    Optional wrapper to run 03_ai_deadlock_watcher.sql on a schedule (SQL
    Agent job step, or Windows Task Scheduler calling this script directly).
    It only ever reads deadlock graphs and logs a report -- it never
    modifies a stored procedure or application code.

    Requires the SqlServer PowerShell module:
        Install-Module SqlServer -Scope CurrentUser
#>

param(
    [string]$ServerInstance = "localhost",
    [string]$Database       = "DeadlockDemo",
    [string]$WatcherScript  = "$PSScriptRoot\03_ai_deadlock_watcher.sql",
    [int]$AlertThreshold    = 2   # occurrences of the same object pair in 7 days
)

Import-Module SqlServer -ErrorAction Stop

$results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database `
    -InputFile $WatcherScript -ErrorAction Stop

$flagged = $results | Where-Object { $_.OccurrenceCount -ge $AlertThreshold }

if ($flagged) {
    foreach ($row in $flagged) {
        Write-Warning ("Recurring deadlock pattern: {0} -- {1} occurrences between {2} and {3} (status: {4})" -f `
            $row.PatternKey, $row.OccurrenceCount, $row.FirstSeen, $row.LastSeen, $row.ReviewStatus)
    }
    # Wire this into whatever Ivan's team already uses for alerting --
    # e.g. Send-MailMessage, a Teams/Slack webhook, or a ticket-creation
    # API call. Intentionally left as a report, not an auto-remediation:
    # a human decides the actual code fix.
}
else {
    Write-Output "No recurring deadlock patterns above threshold ($AlertThreshold) in the last 7 days."
}
