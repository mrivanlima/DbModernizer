<#
    run_plan_variance_watcher.ps1
    Optional scheduling wrapper for 03_ai_plan_variance_watcher.sql.
    Run this under SQL Agent or Windows Task Scheduler on a daily cadence.
    It only reads/logs -- it never modifies a procedure or forces a plan.

    Requires the SqlServer PowerShell module:
        Install-Module -Name SqlServer -Scope CurrentUser
#>

param(
    [string]$ServerInstance = "localhost",
    [string]$Database = "ParamSniffDemo",
    [string]$ScriptPath = "$PSScriptRoot\03_ai_plan_variance_watcher.sql",
    [int]$AlertThreshold = 3   # flag if a proc appears this many times in 7 days
)

Import-Module SqlServer -ErrorAction Stop

$results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -InputFile $ScriptPath -ErrorAction Stop

$flagged = $results | Where-Object { $_.TimesFlagged -ge $AlertThreshold }

if ($flagged) {
    Write-Warning "Parameter-sniffing candidates above threshold ($AlertThreshold+ flags in 7 days):"
    $flagged | Format-Table ProcName, TimesFlagged, WorstVarianceRatio, LastFlagged -AutoSize

    # Wire this into whatever alerting the team already uses (email, Teams
    # webhook, ticket creation) -- intentionally left as a report, not an
    # automatic action. A human decides the fix per procedure.
} else {
    Write-Output "No procedures crossed the variance threshold in the last 7 days."
}
