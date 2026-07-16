param([int]$Port = 8765)

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Error 'Python was not found. Install Python 3, then run this script again.'
    exit 1
}

$root = Split-Path -Parent $PSScriptRoot
$url = "http://localhost:$Port/apps/shiren6-identification/"
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listener) {
    Write-Error "Port $Port is already in use. Stop the process using it or specify another port with -Port."
    exit 1
}

$server = Start-Process -FilePath $python.Source -ArgumentList @('-m', 'http.server', $Port, '--directory', "`"$root`"") -NoNewWindow -PassThru
$deadline = (Get-Date).AddSeconds(5)
do {
    Start-Sleep -Milliseconds 100
    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
} until ($listener -or $server.HasExited -or (Get-Date) -ge $deadline)

if (-not $listener) {
    if (-not $server.HasExited) { Stop-Process -Id $server.Id }
    Write-Error "Could not start the local server on port $Port."
    exit 1
}

Write-Host "Starting Shiren 6 identification tool: $url"
Start-Process $url
try {
    Wait-Process -Id $server.Id
} finally {
    if (-not $server.HasExited) { Stop-Process -Id $server.Id }
}
