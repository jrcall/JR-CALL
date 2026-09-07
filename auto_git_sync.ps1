$Repo = "E:\AndroidStudioProjects\jr_call"
Set-Location $Repo

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $Repo
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true
$watcher.NotifyFilter = [IO.NotifyFilters]::LastWrite, [IO.NotifyFilters]::FileName, [IO.NotifyFilters]::DirectoryName, [IO.NotifyFilters]::Size

$script:LastSync = [datetime]::MinValue
$script:SyncRunning = $false

function Sync-Git {
    if ($script:SyncRunning) { return }

    $now = Get-Date
    if (($now - $script:LastSync).TotalSeconds -lt 8) { return }

    $script:SyncRunning = $true

    try {
        Start-Sleep -Seconds 5

        Set-Location $Repo

        $status = git status --porcelain 2>$null

        if ($status) {
            git add .
            git commit -m "Auto sync JR CALL $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" 2>$null
            git push origin main 2>$null
            $script:LastSync = Get-Date
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] JR CALL synced to GitHub."
        }
    }
    finally {
        $script:SyncRunning = $false
    }
}

$action = {
    Sync-Git
}

Register-ObjectEvent $watcher Changed -Action $action | Out-Null
Register-ObjectEvent $watcher Created -Action $action | Out-Null
Register-ObjectEvent $watcher Deleted -Action $action | Out-Null
Register-ObjectEvent $watcher Renamed -Action $action | Out-Null

Write-Host "JR CALL Auto Git Sync is RUNNING..."
Write-Host "Changes will automatically commit and push to GitHub."
Write-Host "Keep this window running."

while ($true) {
    Start-Sleep -Seconds 10
}