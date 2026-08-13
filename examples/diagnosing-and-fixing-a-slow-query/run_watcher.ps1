<#
  run_watcher.ps1
  Scheduled wrapper for 03_ai_missing_index_watcher.sql.
  Intended to run under SQL Agent (CmdExec step) or Windows Task Scheduler
  on a jump box with the SqlServer PowerShell module installed.

  This script only ever SELECTs and INSERTs into the review-queue table
  (dbo.IndexCandidateLog). It does not, and should not be modified to,
  execute the SuggestedDDL automatically.
#>

param(
    [Parameter(Mandatory = $true)][string]$ServerInstance,
    [Parameter(Mandatory = $true)][string]$Database,
    [string]$ScriptPath = "$PSScriptRoot\03_ai_missing_index_watcher.sql",
    [string]$LogPath = "$PSScriptRoot\watcher.log"
)

Import-Module SqlServer -ErrorAction Stop

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

try {
    $results = Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database `
                              -InputFile $ScriptPath -QueryTimeout 60 -ErrorAction Stop

    $pendingCount = ($results | Measure-Object).Count
    "$timestamp - watcher ran OK - $pendingCount pending candidate(s) in review queue" |
        Out-File -Append -FilePath $LogPath

    if ($pendingCount -gt 0) {
        # Wire this to your existing alerting (Database Mail, Teams webhook, etc.)
        # instead of just logging, once you've validated the report locally.
        Write-Output "New index candidates awaiting human review: $pendingCount"
    }
}
catch {
    "$timestamp - watcher FAILED - $($_.Exception.Message)" | Out-File -Append -FilePath $LogPath
    throw
}
