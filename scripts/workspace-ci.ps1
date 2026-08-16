[CmdletBinding()]
param(
    [switch]$SkipDocker
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$workspaceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$startedAt = Get-Date
$results = [System.Collections.Generic.List[object]]::new()

function Invoke-CiStep {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [string]$WorkingDirectory,
        [Parameter(Mandatory)] [scriptblock]$Command
    )

    $stepStartedAt = Get-Date
    Write-Host ""
    Write-Host "==> $Name" -ForegroundColor Cyan
    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $Command
        if ($LASTEXITCODE -ne 0) {
            throw "$Name failed with exit code $LASTEXITCODE"
        }
        $duration = [math]::Round(((Get-Date) - $stepStartedAt).TotalSeconds, 1)
        $results.Add([pscustomobject]@{ Step = $Name; Result = "PASS"; Seconds = $duration })
        Write-Host "PASS: $Name ($duration s)" -ForegroundColor Green
    }
    catch {
        $duration = [math]::Round(((Get-Date) - $stepStartedAt).TotalSeconds, 1)
        $results.Add([pscustomobject]@{ Step = $Name; Result = "FAIL"; Seconds = $duration })
        Write-Host "FAIL: $Name ($duration s)" -ForegroundColor Red
        throw
    }
    finally {
        Pop-Location
    }
}

foreach ($commandName in @("git", "npm.cmd", "forge")) {
    if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
        throw "Required command is unavailable: $commandName"
    }
}

$repositories = @(
    "autoloop",
    "autoloop-dashboard-v2",
    "autoloop-mcp",
    "autoloop-sdk",
    "autoloop-site",
    "autoloop-worker"
)

Invoke-CiStep -Name "Repository diff integrity" -WorkingDirectory $workspaceRoot -Command {
    foreach ($repository in $repositories) {
        git -C $repository diff --check
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
}

Invoke-CiStep -Name "Core contracts" -WorkingDirectory (Join-Path $workspaceRoot "autoloop") -Command {
    npm.cmd run check
}

Invoke-CiStep -Name "Dashboard and mock API" -WorkingDirectory (Join-Path $workspaceRoot "autoloop-dashboard-v2") -Command {
    npm.cmd run check
}

Invoke-CiStep -Name "MCP server" -WorkingDirectory (Join-Path $workspaceRoot "autoloop-mcp") -Command {
    npm.cmd run check
}

Invoke-CiStep -Name "SDK" -WorkingDirectory (Join-Path $workspaceRoot "autoloop-sdk") -Command {
    npm.cmd run check
}

Invoke-CiStep -Name "Site" -WorkingDirectory (Join-Path $workspaceRoot "autoloop-site") -Command {
    npm.cmd run check
}

Invoke-CiStep -Name "Worker" -WorkingDirectory (Join-Path $workspaceRoot "autoloop-worker") -Command {
    npm.cmd run check
}

if (-not $SkipDocker) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw "Docker is unavailable. Install/start Docker or run local CI with -SkipDocker."
    }
    Invoke-CiStep -Name "Worker container" -WorkingDirectory (Join-Path $workspaceRoot "autoloop-worker") -Command {
        docker build --tag autoloop-worker:ci .
    }
}

Write-Host ""
$results | Format-Table -AutoSize
$totalDuration = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 1)
Write-Host "Local CI passed in $totalDuration seconds." -ForegroundColor Green
