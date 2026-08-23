<#
    run_watcher.ps1
    Optional wrapper to run 03_ai_n_plus_1_watcher.sql on a schedule
    (SQL Agent job step, or Windows Task Scheduler calling this script)
    and surface newly-flagged candidates to a log/alert channel.

    Requires the SqlServer PowerShell module:
        Install-Module SqlServer -Scope CurrentUser

    Usage:
        .\run_watcher.ps1 -ServerInstance "localhost" -Database "NPlus1Demo"
#>
param(
    [Parameter(Mandatory = $true)] [string] $ServerInstance,
    [Parameter(Mandatory = $true)] [string] $Database,
    [string] $ScriptPath = (Join-Path $PSScriptRoot "03_ai_n_plus_1_watcher.sql"),
    [string] $LogPath = (Join-Path $PSScriptRoot "n_plus_1_watcher.log")
)

Import-Module SqlServer -ErrorAction Stop

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
try {
    $results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database `
        -InputFile $ScriptPath -QueryTimeout 120 -ErrorAction Stop

    $pendingCount = ($results | Where-Object { $_.ReviewStatus -eq 'pending' }).Count

    "$timestamp - Watcher ran OK. $pendingCount pending candidate(s) awaiting review." |
        Out-File -FilePath $LogPath -Append

    if ($pendingCount -gt 0) {
        Write-Warning "$pendingCount new N+1 candidate(s) logged to dbo.NPlus1CandidateLog on $Database. Review before approving any fix."
    }
}
catch {
    "$timestamp - Watcher FAILED: $($_.Exception.Message)" | Out-File -FilePath $LogPath -Append
    throw
}
