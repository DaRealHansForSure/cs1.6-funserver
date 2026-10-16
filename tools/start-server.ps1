# Starts the LAN fun server together with the fast download server.
#
# Asks for the start mode, finds the LAN address of this PC, starts the small
# web server that hands out maps and sounds, then HLDS. When the HLDS window
# is closed, the download server is stopped as well.

$ErrorActionPreference = 'Stop'

# --- Settings you may want to change ---------------------------------------
$MaxPlayers = 20
$GamePort = 27015
$FastDownloadPort = 27080
# ----------------------------------------------------------------------------

$PackageRoot = Split-Path -Parent $PSScriptRoot
$ServerDir = Join-Path $PackageRoot 'server'
$CstrikeDir = Join-Path $ServerDir 'cstrike'
$HldsExe = Join-Path $ServerDir 'hlds.exe'
$FastDownloadScript = Join-Path $PSScriptRoot 'fastdl-server.ps1'
$FallbackMap = 'de_dust2'

$Modes = [ordered]@{
    '1' = @{ Id = 'classic'; Title = 'Classic Fun (Hook, Grab, Parachute, Bunnyhop)' }
    '2' = @{ Id = 'gungame'; Title = 'GunGame' }
    '3' = @{ Id = 'zombie'; Title = 'Zombie Infection' }
    '4' = @{ Id = 'deathmatch'; Title = 'Deathmatch' }
}

<#
.SYNOPSIS
Returns the IPv4 address other LAN players can reach, preferring the adapter
that has a default gateway (the one connected to the router).
#>
function Get-LanAddress {
    $configWithGateway = Get-NetIPConfiguration |
        Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' } |
        Select-Object -First 1
    if ($configWithGateway) {
        return $configWithGateway.IPv4Address[0].IPAddress
    }

    $anyAddress = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' } |
        Select-Object -First 1
    if ($anyAddress) {
        return $anyAddress.IPAddress
    }

    return '127.0.0.1'
}

function Read-StartMode {
    Write-Host ''
    Write-Host 'Which mode should the server start with?' -ForegroundColor Cyan
    foreach ($key in $Modes.Keys) {
        Write-Host "  $key) $($Modes[$key].Title)"
    }
    Write-Host '  (In game you can switch any time with /mode)'

    $choice = Read-Host 'Choice [1]'
    if ($Modes.Contains($choice)) {
        return $Modes[$choice].Id
    }
    return $Modes['1'].Id
}

function Get-FirstMapOfMode {
    param([string]$ModeId)

    $cycleFile = Join-Path $CstrikeDir "mapcycle_$ModeId.txt"
    if (-not (Test-Path $cycleFile)) {
        return $FallbackMap
    }

    foreach ($line in Get-Content $cycleFile) {
        $mapName = $line.Trim()
        if ($mapName -and (Test-Path (Join-Path $CstrikeDir "maps\$mapName.bsp"))) {
            return $mapName
        }
    }
    return $FallbackMap
}

if (-not (Test-Path $HldsExe)) {
    Write-Host 'The server is not installed yet. Please run 1_INSTALL.bat first.' -ForegroundColor Red
    exit 1
}

$startMode = Read-StartMode
$startMap = Get-FirstMapOfMode -ModeId $startMode
$lanAddress = Get-LanAddress
$fastDownloadUrl = "http://${lanAddress}:$FastDownloadPort/"

$fastDownloadProcess = Start-Process -FilePath 'powershell.exe' -PassThru -WindowStyle Minimized -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', "`"$FastDownloadScript`"",
    '-Root', "`"$CstrikeDir`"",
    '-Port', $FastDownloadPort
)

# localinfo tells fun_modes.amxx which mode to run on the very first map.
$hldsArguments = @(
    '-console', '-game', 'cstrike',
    '-port', $GamePort,
    "+ip $lanAddress",
    "+maxplayers $MaxPlayers",
    '+sv_lan 1',
    "+localinfo fun_mode $startMode",
    "+mapcyclefile mapcycle_$startMode.txt",
    "+sv_downloadurl `"$fastDownloadUrl`"",
    "+map $startMap"
)

Write-Host ''
Write-Host "Starting server: mode $startMode on $startMap" -ForegroundColor Green
Write-Host "Players join via the LAN browser or the console with:  connect ${lanAddress}:$GamePort" -ForegroundColor Green
Write-Host 'Keep this window open. To stop the server, type "quit" in the HLDS window.'

$hldsProcess = Start-Process -FilePath $HldsExe -WorkingDirectory $ServerDir -ArgumentList $hldsArguments -PassThru
$hldsProcess.WaitForExit()

if (-not $fastDownloadProcess.HasExited) {
    Stop-Process -Id $fastDownloadProcess.Id -Force
}
Write-Host 'Server stopped.'
