# Installs a complete Counter-Strike 1.6 LAN fun server into the "server"
# folder next to this package.
#
# Steps: SteamCMD + HLDS, ReHLDS, ReGameDLL, Metamod-R, AMX Mod X, YaPB bots,
# the fun plugins and configs from server-files, then the map pack.
# Running it again is safe: downloads are cached and every step re-applies
# its changes, so it also works as a repair or update.
#
# -MapsOnly skips the server part and only installs maps (map pack plus the
# "custom-maps" folder) and rebuilds the map lists.

param(
    [switch]$MapsOnly
)

$ErrorActionPreference = 'Stop'
# The progress bar slows Invoke-WebRequest down by a factor of ten or more.
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PackageRoot = Split-Path -Parent $PSScriptRoot
$ServerDir = Join-Path $PackageRoot 'server'
$CstrikeDir = Join-Path $ServerDir 'cstrike'
$OverlayDir = Join-Path $PackageRoot 'server-files\cstrike'
$OwnMapsDir = Join-Path $PackageRoot 'custom-maps'
$DownloadDir = Join-Path $PSScriptRoot 'downloads'
$WorkDir = Join-Path $PSScriptRoot 'work'
$SteamCmdDir = Join-Path $PSScriptRoot 'steamcmd'
$MapListFile = Join-Path $PSScriptRoot 'maps.csv'

$BrowserUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
$HldsInstallAttempts = 3
$FunPluginsMarker = '; --- LAN Fun Server ---'

# Pinned versions, so every LAN party gets the same tested setup.
# To update, replace the URL with a newer release from the same project.
$Components = @{
    SteamCmd   = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
    ReHlds     = 'https://github.com/rehlds/ReHLDS/releases/download/3.15.0.896/rehlds-bin-3.15.0.896.zip'
    ReGameDll  = 'https://github.com/rehlds/ReGameDLL_CS/releases/download/5.30.0.814/regamedll-bin-5.30.0.814.zip'
    Metamod    = 'https://github.com/rehlds/Metamod-R/releases/download/1.3.0.149/metamod-bin-1.3.0.149.zip'
    AmxBase    = 'https://github.com/alliedmodders/amxmodx/releases/download/1.10.0.5487/amxmodx-1.10.0-git5487-base-windows.zip'
    AmxCstrike = 'https://github.com/alliedmodders/amxmodx/releases/download/1.10.0.5487/amxmodx-1.10.0-git5487-cstrike-windows.zip'
    YapbBots   = 'https://github.com/yapb/yapb/releases/download/4.4.957/yapb-4.4.957-windows.zip'
}

# Map files we copy out of downloaded archives. Anything else (exe, dll,
# readme files) stays in the archive.
$MapContentExtensions = @('.bsp', '.wad', '.res', '.txt', '.nav', '.wav', '.mp3', '.mdl', '.spr', '.tga', '.bmp')
$MapContentFolders = @('maps', 'sound', 'models', 'sprites', 'gfx', 'overviews')

$StockMaps = @(
    'as_oilrig', 'cs_747', 'cs_assault', 'cs_backalley', 'cs_estate', 'cs_havana', 'cs_italy',
    'cs_militia', 'cs_office', 'cs_siege', 'de_airstrip', 'de_aztec', 'de_cbble', 'de_chateau',
    'de_dust', 'de_dust2', 'de_inferno', 'de_nuke', 'de_piranesi', 'de_prodigy', 'de_storm',
    'de_survivor', 'de_torn', 'de_train', 'de_vertigo'
)

function Write-Step {
    param([string]$Text)

    Write-Host ''
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Write-Note {
    param([string]$Text)

    Write-Host "    $Text"
}

function Write-Problem {
    param([string]$Text)

    Write-Host "    ! $Text" -ForegroundColor Yellow
}

<#
.SYNOPSIS
Downloads a file into the cache and returns its path. Cached files are reused.
#>
function Get-CachedDownload {
    param(
        [string]$Url,
        [string]$FileName
    )

    $targetPath = Join-Path $DownloadDir $FileName
    if (Test-Path $targetPath) {
        return $targetPath
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetPath) | Out-Null

    # Download to a temporary name first, so an aborted download never
    # looks like a finished one on the next run.
    $partialPath = "$targetPath.part"
    Write-Note "Downloading $FileName ..."
    Invoke-WebRequest -Uri $Url -OutFile $partialPath -UseBasicParsing -UserAgent $BrowserUserAgent -MaximumRedirection 10
    Move-Item -Force $partialPath $targetPath

    return $targetPath
}

<#
.SYNOPSIS
Extracts an archive into a fresh folder and returns that folder.
Zip files use PowerShell itself, rar and 7z use the tar.exe built into
Windows 10/11, with an installed 7-Zip as fallback.
#>
function Expand-Download {
    param([string]$ArchivePath)

    $archiveName = [IO.Path]::GetFileNameWithoutExtension($ArchivePath)
    $destination = Join-Path $WorkDir $archiveName
    if (Test-Path $destination) {
        Remove-Item -Recurse -Force $destination
    }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null

    $extension = [IO.Path]::GetExtension($ArchivePath).ToLowerInvariant()
    if ($extension -eq '.zip') {
        Expand-Archive -Path $ArchivePath -DestinationPath $destination -Force
        return $destination
    }

    # Windows PowerShell turns any stderr line of a native tool into a
    # terminating error under "Stop", so this function relaxes it locally.
    $ErrorActionPreference = 'Continue'

    $tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path $tarExe) {
        & $tarExe -xf $ArchivePath -C $destination 2>$null
        if ($LASTEXITCODE -eq 0) {
            return $destination
        }
    }

    $sevenZipExe = Find-SevenZip
    if ($sevenZipExe) {
        & $sevenZipExe x -y "-o$destination" $ArchivePath | Out-Null
        if ($LASTEXITCODE -eq 0) {
            return $destination
        }
    }

    throw "Could not extract $([IO.Path]::GetFileName($ArchivePath)). Install 7-Zip (7-zip.org) and run the installer again."
}

function Find-SevenZip {
    $candidates = @(
        (Join-Path $env:ProgramFiles '7-Zip\7z.exe'),
        (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe')
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }
    return $null
}

function Find-FirstFile {
    param(
        [string]$Root,
        [string]$FileName
    )

    return Get-ChildItem -Path $Root -Recurse -File -Filter $FileName | Select-Object -First 1
}

function Find-FirstFolder {
    param(
        [string]$Root,
        [string]$FolderName
    )

    return Get-ChildItem -Path $Root -Recurse -Directory -Filter $FolderName | Select-Object -First 1
}

function Install-Hlds {
    Write-Step 'SteamCMD and HLDS (Counter-Strike Dedicated Server)'

    $steamCmdExe = Join-Path $SteamCmdDir 'steamcmd.exe'
    if (-not (Test-Path $steamCmdExe)) {
        $archive = Get-CachedDownload -Url $Components.SteamCmd -FileName 'steamcmd.zip'
        New-Item -ItemType Directory -Force -Path $SteamCmdDir | Out-Null
        Expand-Archive -Path $archive -DestinationPath $SteamCmdDir -Force
    }

    $hldsExe = Join-Path $ServerDir 'hlds.exe'
    $libListFile = Join-Path $CstrikeDir 'liblist.gam'

    # ReHLDS only fits the pre-anniversary engine. The current default
    # branch ships a newer steam_api.dll whose exports the ReHLDS swds.dll
    # can not find, so the server must come from the steam_legacy branch.
    # Players with the normal, current CS 1.6 can still join it.
    #
    # App 90 is known for stopping half way on the first run, so retry until
    # the files we need are really there.
    for ($attempt = 1; $attempt -le $HldsInstallAttempts; $attempt++) {
        Write-Note "SteamCMD run $attempt of $HldsInstallAttempts (takes a few minutes the first time) ..."
        & $steamCmdExe +force_install_dir "$ServerDir" +login anonymous +app_set_config 90 mod cstrike +app_update 90 -beta steam_legacy validate +quit | Out-Host

        if ((Test-Path $hldsExe) -and (Test-Path $libListFile)) {
            Write-Note 'HLDS is installed.'
            Copy-SteamClientFiles
            return
        }
    }

    throw 'HLDS could not be installed. Check the internet connection and run the installer again.'
}

<#
.SYNOPSIS
Replaces the Steam client libraries of the server with the ones SteamCMD
just updated itself to.

.DESCRIPTION
The legacy HLDS build ships an old steamclient.dll that the Steam network no
longer accepts, which ends in "Unable to initialize Steam". Leftovers from
the current branch cause the same error. SteamCMD always carries a current
32-bit Steam client, so its copies are the right ones for hlds.exe.
#>
function Copy-SteamClientFiles {
    $steamClientFiles = @('steamclient.dll', 'tier0_s.dll', 'vstdlib_s.dll', 'SDL3.dll')

    foreach ($fileName in $steamClientFiles) {
        $sourceFile = Join-Path $SteamCmdDir $fileName
        if (Test-Path $sourceFile) {
            Copy-Item -Path $sourceFile -Destination $ServerDir -Force
            Write-Note "$fileName copied from SteamCMD"
        }
    }
}

function Install-ReHlds {
    Write-Step 'ReHLDS (improved server engine)'

    $extracted = Expand-Download (Get-CachedDownload -Url $Components.ReHlds -FileName 'rehlds.zip')

    # The archive holds Linux and Windows builds, swds.dll marks the Windows one.
    $engineDll = Find-FirstFile -Root $extracted -FileName 'swds.dll'
    if (-not $engineDll) {
        throw 'swds.dll not found in the ReHLDS archive.'
    }

    Copy-Item -Path (Join-Path $engineDll.DirectoryName '*') -Destination $ServerDir -Recurse -Force
}

function Install-ReGameDll {
    Write-Step 'ReGameDLL (game logic with respawn, free-for-all and more)'

    $extracted = Expand-Download (Get-CachedDownload -Url $Components.ReGameDll -FileName 'regamedll.zip')

    $gameDll = Find-FirstFile -Root $extracted -FileName 'mp.dll'
    if (-not $gameDll) {
        throw 'mp.dll not found in the ReGameDLL archive.'
    }

    # mp.dll sits in <root>\cstrike\dlls, and <root> mirrors the server folder.
    $packageRootDir = $gameDll.Directory.Parent.Parent.FullName
    Copy-Item -Path (Join-Path $packageRootDir '*') -Destination $ServerDir -Recurse -Force
}

function Install-Metamod {
    Write-Step 'Metamod-R (plugin loader)'

    $extracted = Expand-Download (Get-CachedDownload -Url $Components.Metamod -FileName 'metamod.zip')

    $metamodDll = Find-FirstFile -Root $extracted -FileName 'metamod.dll'
    if (-not $metamodDll) {
        throw 'metamod.dll not found in the Metamod-R archive.'
    }

    $metamodDir = Join-Path $CstrikeDir 'addons\metamod'
    New-Item -ItemType Directory -Force -Path $metamodDir | Out-Null
    Copy-Item -Path $metamodDll.FullName -Destination $metamodDir -Force

    Set-GameDllToMetamod
}

function Set-GameDllToMetamod {
    $libListFile = Join-Path $CstrikeDir 'liblist.gam'
    $backupFile = "$libListFile.original"

    if (-not (Test-Path $backupFile)) {
        Copy-Item $libListFile $backupFile
    }

    $lines = Get-Content $libListFile
    $updatedLines = foreach ($line in $lines) {
        if ($line -match '^\s*gamedll\s') {
            'gamedll "addons\metamod\metamod.dll"'
        } else {
            $line
        }
    }
    Set-Content -Path $libListFile -Value $updatedLines -Encoding Ascii
}

function Install-AddonsArchive {
    param(
        [string]$Url,
        [string]$FileName,
        [string]$Title
    )

    $extracted = Expand-Download (Get-CachedDownload -Url $Url -FileName $FileName)

    $addonsFolder = Find-FirstFolder -Root $extracted -FolderName 'addons'
    if (-not $addonsFolder) {
        throw "No addons folder found in the $Title archive."
    }

    $targetAddons = Join-Path $CstrikeDir 'addons'
    New-Item -ItemType Directory -Force -Path $targetAddons | Out-Null
    Copy-Item -Path (Join-Path $addonsFolder.FullName '*') -Destination $targetAddons -Recurse -Force
}

function Install-AmxModX {
    Write-Step 'AMX Mod X (admin mod)'

    # The archives ship an empty users.ini. On a repair run that would wipe
    # the admin account, so keep the current one and put it back afterwards.
    $usersIni = Join-Path $CstrikeDir 'addons\amxmodx\configs\users.ini'
    $savedUsers = $null
    if (Test-Path $usersIni) {
        $savedUsers = Get-Content $usersIni
    }

    Install-AddonsArchive -Url $Components.AmxBase -FileName 'amxmodx-base.zip' -Title 'AMX Mod X'
    Install-AddonsArchive -Url $Components.AmxCstrike -FileName 'amxmodx-cstrike.zip' -Title 'AMX Mod X Counter-Strike'

    if ($savedUsers) {
        Set-Content -Path $usersIni -Value $savedUsers -Encoding Ascii
    }
}

function Install-Yapb {
    Write-Step 'YaPB (Bots)'

    # YaPB learns unknown maps on its own (yb_graph_analyze_auto_start), so
    # no waypoint pack is needed. The first round on a new map may lag briefly.
    Install-AddonsArchive -Url $Components.YapbBots -FileName 'yapb.zip' -Title 'YaPB'

    $yapbConfig = Join-Path $CstrikeDir 'addons\yapb\conf\yapb.cfg'
    Add-BlockOnce -FilePath $yapbConfig -Lines @(
        '// --- LAN Fun Server ---',
        'yb_quota_mode "fill"',
        'yb_autovacate "1"',
        'yb_join_after_player "1"',
        'yb_difficulty "2"',
        'yb_language "en"'
    )
}

function Set-MetamodPlugins {
    Write-Step 'Registering Metamod plugins'

    $amxDll = Find-FirstFile -Root (Join-Path $CstrikeDir 'addons\amxmodx') -FileName 'amxmodx_mm.dll'
    $yapbDll = Find-FirstFile -Root (Join-Path $CstrikeDir 'addons\yapb') -FileName 'yapb.dll'

    $pluginLines = @()
    foreach ($pluginDll in @($amxDll, $yapbDll)) {
        if (-not $pluginDll) {
            continue
        }
        $relativePath = $pluginDll.FullName.Substring($CstrikeDir.Length + 1).Replace('\', '/')
        $pluginLines += "win32 $relativePath"
        Write-Note $relativePath
    }

    if (-not $amxDll) {
        throw 'amxmodx_mm.dll is missing, AMX Mod X is not installed correctly.'
    }

    $metamodPluginsFile = Join-Path $CstrikeDir 'addons\metamod\plugins.ini'
    Set-Content -Path $metamodPluginsFile -Value $pluginLines -Encoding Ascii
}

<#
.SYNOPSIS
Appends lines to a text file unless the first line is already in it.
#>
function Add-BlockOnce {
    param(
        [string]$FilePath,
        [string[]]$Lines
    )

    $marker = $Lines[0]
    if ((Test-Path $FilePath) -and (Select-String -Path $FilePath -SimpleMatch $marker -Quiet)) {
        return
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $FilePath) | Out-Null
    Add-Content -Path $FilePath -Value (@('') + $Lines) -Encoding Ascii
}

function Install-FunFiles {
    Write-Step 'Fun configs and plugins'

    Copy-Item -Path (Join-Path $OverlayDir '*') -Destination $CstrikeDir -Recurse -Force

    Build-FunPlugins
    Set-AmxPluginList
    Set-AdminAccount

    # mapchooser prefers maps.ini over the map cycle. Without it, each mode's
    # own mapcycle file decides which maps are up for the vote.
    $mapsIni = Join-Path $CstrikeDir 'addons\amxmodx\configs\maps.ini'
    if (Test-Path $mapsIni) {
        Move-Item -Force $mapsIni "$mapsIni.disabled"
    }
}

function Build-FunPlugins {
    $scriptingDir = Join-Path $CstrikeDir 'addons\amxmodx\scripting'
    $pluginsDir = Join-Path $CstrikeDir 'addons\amxmodx\plugins'
    $compilerExe = Join-Path $scriptingDir 'amxxpc.exe'

    if (-not (Test-Path $compilerExe)) {
        throw 'amxxpc.exe is missing, AMX Mod X is not installed correctly.'
    }

    # The compiler writes its banner to stderr, which must not count as an error.
    $ErrorActionPreference = 'Continue'

    # The compiler finds its include folder relative to the working directory.
    Push-Location $scriptingDir
    try {
        foreach ($source in Get-ChildItem -Filter 'fun_*.sma') {
            $outputFile = Join-Path $pluginsDir ($source.BaseName + '.amxx')
            $compilerOutput = & $compilerExe $source.Name "-o$outputFile" 2>&1

            if ($LASTEXITCODE -ne 0 -or -not (Test-Path $outputFile)) {
                $compilerOutput | Out-Host
                throw "Plugin $($source.Name) failed to compile."
            }
            Write-Note "$($source.BaseName).amxx compiled"
        }
    } finally {
        Pop-Location
    }
}

function Set-AmxPluginList {
    $pluginsIni = Join-Path $CstrikeDir 'addons\amxmodx\configs\plugins.ini'

    # miscstats brings the "Headshot", "Monster Kill" and similar announcements.
    $content = Get-Content $pluginsIni
    $content = $content -replace '^;miscstats\.amxx', 'miscstats.amxx'
    Set-Content -Path $pluginsIni -Value $content -Encoding Ascii

    $funPlugins = @(
        'fun_modes.amxx',
        'fun_hook.amxx',
        'fun_grab.amxx',
        'fun_parachute.amxx',
        'fun_admincmds.amxx',
        'fun_gungame.amxx',
        'fun_zombie.amxx',
        'fun_menu.amxx'
    )
    Add-BlockOnce -FilePath $pluginsIni -Lines (@($FunPluginsMarker) + $funPlugins)

    # Plugins added in a later version of the package must reach existing
    # installs too, where the block above is already present.
    $registeredLines = @(Get-Content $pluginsIni | ForEach-Object { $_.Trim() })
    $missingPlugins = @($funPlugins | Where-Object { $_ -notin $registeredLines })
    if ($missingPlugins.Count -gt 0) {
        Add-Content -Path $pluginsIni -Value $missingPlugins -Encoding Ascii
    }
}

function Set-AdminAccount {
    $usersIni = Join-Path $CstrikeDir 'addons\amxmodx\configs\users.ini'
    if (Select-String -Path $usersIni -SimpleMatch $FunPluginsMarker -Quiet) {
        Write-Note 'Admin is already set up (addons\amxmodx\configs\users.ini).'
        return
    }

    Write-Host ''
    Write-Host '    Admin setup. Enter your CS player name and a password.' -ForegroundColor Green
    Write-Host '    (Leave empty to add it to users.ini yourself later)'
    $adminName = Read-Host '    Player name'
    if ([string]::IsNullOrWhiteSpace($adminName)) {
        Write-Note 'No admin created.'
        return
    }

    $adminPassword = ''
    while ([string]::IsNullOrWhiteSpace($adminPassword)) {
        $adminPassword = Read-Host '    Password (no spaces or quotes)'
    }

    # Flag "a" on the account kicks anyone who takes the name without the password.
    Add-BlockOnce -FilePath $usersIni -Lines @(
        $FunPluginsMarker,
        "`"$adminName`" `"$adminPassword`" `"abcdefghijklmnopqrstu`" `"a`""
    )

    Write-Note "Admin $adminName created. Before joining, type in the game console: setinfo _pw `"$adminPassword`""
}

function Install-MapPack {
    Write-Step 'Downloading fun maps'

    if (-not (Test-Path $MapListFile)) {
        Write-Problem 'maps.csv is missing, skipping the map download.'
        return
    }

    $failedMaps = @()
    foreach ($map in Import-Csv $MapListFile) {
        try {
            $archive = Get-CachedDownload -Url $map.Url -FileName ('maps\' + $map.ArchiveName)
            $extracted = Expand-Download $archive
            $installedMaps = Install-MapContent -SourceDir $extracted
            Write-Note "$($map.Name): $($installedMaps -join ', ')"
        } catch {
            $failedMaps += $map.Name
            Write-Problem "$($map.Name) failed: $($_.Exception.Message)"
        }
    }

    if ($failedMaps.Count -gt 0) {
        Write-Problem "Not installed: $($failedMaps -join ', '). Try again later with 3_UPDATE_MAPS.bat."
    }
}

function Install-OwnMaps {
    Write-Step 'Custom maps from the custom-maps folder'

    if (-not (Test-Path $OwnMapsDir)) {
        New-Item -ItemType Directory -Force -Path $OwnMapsDir | Out-Null
    }

    $looseMaps = Get-ChildItem -Path $OwnMapsDir -Recurse -File -Filter '*.bsp'
    if ($looseMaps) {
        try {
            $installedMaps = Install-MapContent -SourceDir $OwnMapsDir
            Write-Note "Loose files: $($installedMaps -join ', ')"
        } catch {
            Write-Problem "Loose files in custom-maps: $($_.Exception.Message)"
        }
    }

    foreach ($archive in Get-ChildItem -Path $OwnMapsDir -File | Where-Object { $_.Extension -in @('.zip', '.rar', '.7z') }) {
        try {
            $extracted = Expand-Download $archive.FullName
            $installedMaps = Install-MapContent -SourceDir $extracted
            Write-Note "$($archive.Name): $($installedMaps -join ', ')"
        } catch {
            Write-Problem "$($archive.Name) failed: $($_.Exception.Message)"
        }
    }
}

<#
.SYNOPSIS
Copies the map files from an extracted archive into cstrike and returns the
names of the maps it found.

Archives come in two shapes: with a "maps" folder (often inside cstrike\),
or with the .bsp and .wad lying loose. Both are handled. Existing files
outside the maps folder are never overwritten, so a map can not replace
stock models or sounds.
#>
function Install-MapContent {
    param([string]$SourceDir)

    $bspFiles = @(Get-ChildItem -Path $SourceDir -Recurse -File -Filter '*.bsp')
    if ($bspFiles.Count -eq 0) {
        throw 'no .bsp file in the archive'
    }

    # Map packs hold several maps in one maps folder, copy that tree only once.
    $copiedContentRoots = @{}

    foreach ($bspFile in $bspFiles) {
        if ($bspFile.Directory.Name -eq 'maps') {
            $contentRoot = $bspFile.Directory.Parent.FullName
            if (-not $copiedContentRoots.ContainsKey($contentRoot)) {
                Copy-MapContentTree -ContentRoot $contentRoot
                $copiedContentRoots[$contentRoot] = $true
            }
        } else {
            Copy-LooseMapFiles -BspFile $bspFile -SourceDir $SourceDir
        }
    }

    return $bspFiles | ForEach-Object { $_.BaseName.ToLowerInvariant() }
}

function Copy-MapContentTree {
    param([string]$ContentRoot)

    foreach ($folderName in $MapContentFolders) {
        $folder = Join-Path $ContentRoot $folderName
        if (-not (Test-Path $folder)) {
            continue
        }
        foreach ($file in Get-ChildItem -Path $folder -Recurse -File) {
            $relativePath = $file.FullName.Substring($ContentRoot.Length + 1)
            Copy-MapFile -SourceFile $file -RelativeTarget $relativePath
        }
    }

    # Map textures (.wad) usually sit next to the maps folder.
    foreach ($wadFile in Get-ChildItem -Path $ContentRoot -File -Filter '*.wad') {
        Copy-MapFile -SourceFile $wadFile -RelativeTarget $wadFile.Name
    }
}

function Copy-LooseMapFiles {
    param(
        [IO.FileInfo]$BspFile,
        [string]$SourceDir
    )

    $mapName = $BspFile.BaseName
    foreach ($companion in Get-ChildItem -Path $BspFile.DirectoryName -File -Filter "$mapName.*") {
        Copy-MapFile -SourceFile $companion -RelativeTarget ('maps\' + $companion.Name)
    }

    foreach ($wadFile in Get-ChildItem -Path $SourceDir -Recurse -File -Filter '*.wad') {
        Copy-MapFile -SourceFile $wadFile -RelativeTarget $wadFile.Name
    }

    # Resource folders can sit anywhere in a loose archive, keep their layout.
    foreach ($folderName in @('sound', 'models', 'sprites', 'gfx', 'overviews')) {
        foreach ($folder in Get-ChildItem -Path $SourceDir -Recurse -Directory -Filter $folderName) {
            foreach ($file in Get-ChildItem -Path $folder.FullName -Recurse -File) {
                $relativePath = $file.FullName.Substring($folder.Parent.FullName.Length + 1)
                Copy-MapFile -SourceFile $file -RelativeTarget $relativePath
            }
        }
    }
}

function Copy-MapFile {
    param(
        [IO.FileInfo]$SourceFile,
        [string]$RelativeTarget
    )

    if ($SourceFile.Extension.ToLowerInvariant() -notin $MapContentExtensions) {
        return
    }

    $targetPath = Join-Path $CstrikeDir $RelativeTarget
    $isInMapsFolder = $RelativeTarget.ToLowerInvariant().StartsWith('maps\')
    if ((Test-Path $targetPath) -and -not $isInMapsFolder) {
        return
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetPath) | Out-Null
    Copy-Item -Path $SourceFile.FullName -Destination $targetPath -Force
}

<#
.SYNOPSIS
Returns the modes a map fits, judged by its name prefix.
#>
function Get-MapModes {
    param([string]$MapName)

    $isZombieMap = $MapName -like 'zm_*'
    # Knife and grenade maps force their own weapons, which fights GunGame
    # levels and Deathmatch spawn weapons, so they only run in classic.
    $isSpecialWeaponMap = $MapName -match '^(35_?hp|he_|ka_)'
    $isSmallFunMap = $MapName -match '^(fy_|aim_|awp_|gg_|fun_)' -or $MapName -like '*rats*' -or $MapName -like 'de_dust2_2x2*'
    $isGoodDeathmatchMap = $MapName -in @('de_dust2', 'de_inferno', 'de_nuke', 'de_aztec', 'de_train', 'cs_assault', 'cs_italy', 'cs_office', 'cs_mansion')
    $isGoodZombieMap = $MapName -in @('de_dust2', 'de_inferno', 'de_nuke', 'de_aztec', 'de_train', 'de_survivor', 'de_vertigo')

    $modes = @()
    if ($isZombieMap) {
        $modes += 'zombie'
        return $modes
    }

    $modes += 'classic'
    if ($isSpecialWeaponMap) {
        return $modes
    }
    if ($isSmallFunMap -or $MapName -in @('de_dust2', 'cs_assault', 'cs_mansion')) {
        $modes += 'gungame'
    }
    if ($isSmallFunMap -or $isGoodDeathmatchMap) {
        $modes += 'deathmatch'
    }
    if ($isGoodZombieMap) {
        $modes += 'zombie'
    }
    return $modes
}

function Update-MapCycles {
    Write-Step 'Building the map lists for the modes'

    $mapsDir = Join-Path $CstrikeDir 'maps'
    $installedMaps = Get-ChildItem -Path $mapsDir -File -Filter '*.bsp' |
        ForEach-Object { $_.BaseName.ToLowerInvariant() } |
        Sort-Object -Unique

    $mapsByMode = @{
        classic    = New-Object System.Collections.Generic.List[string]
        gungame    = New-Object System.Collections.Generic.List[string]
        deathmatch = New-Object System.Collections.Generic.List[string]
        zombie     = New-Object System.Collections.Generic.List[string]
    }

    # Fun maps first, so a fresh server starts on something fun instead of
    # cycling through all the stock maps.
    $orderedMaps = @($installedMaps | Where-Object { $_ -notin $StockMaps }) + @($installedMaps | Where-Object { $_ -in $StockMaps })
    foreach ($mapName in $orderedMaps) {
        foreach ($mode in Get-MapModes -MapName $mapName) {
            $mapsByMode[$mode].Add($mapName)
        }
    }

    foreach ($mode in $mapsByMode.Keys) {
        $cycleFile = Join-Path $CstrikeDir "mapcycle_$mode.txt"
        Set-Content -Path $cycleFile -Value $mapsByMode[$mode] -Encoding Ascii
        Write-Note ("{0,-11} {1,3} Maps" -f $mode, $mapsByMode[$mode].Count)
    }

    # The engine starts with mapcycle.txt, which therefore mirrors classic.
    Copy-Item -Force (Join-Path $CstrikeDir 'mapcycle_classic.txt') (Join-Path $CstrikeDir 'mapcycle.txt')
}

function Add-FirewallRules {
    Write-Step 'Windows Firewall'

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdministrator) {
        Write-Note 'Not running as administrator. Windows will ask on the first server start,'
        Write-Note 'then click "Allow access" for private networks.'
        return
    }

    $rules = @(
        @{ Name = 'CS16 LAN Server (UDP)'; Protocol = 'UDP'; Port = '27015' },
        @{ Name = 'CS16 LAN Server (TCP)'; Protocol = 'TCP'; Port = '27015' },
        @{ Name = 'CS16 LAN Fast-Download'; Protocol = 'TCP'; Port = '27080' }
    )
    foreach ($rule in $rules) {
        netsh advfirewall firewall delete rule name="$($rule.Name)" | Out-Null
        netsh advfirewall firewall add rule name="$($rule.Name)" dir=in action=allow protocol=$($rule.Protocol) localport=$($rule.Port) | Out-Null
        Write-Note "$($rule.Name) allowed"
    }
}

function Invoke-ServerInstall {
    New-Item -ItemType Directory -Force -Path $ServerDir, $WorkDir | Out-Null

    Install-Hlds
    Install-ReHlds
    Install-ReGameDll
    Install-Metamod
    Install-AmxModX
    Install-Yapb
    Set-MetamodPlugins
    Install-FunFiles
    Install-MapPack
    Install-OwnMaps
    Update-MapCycles
    Add-FirewallRules
}

function Invoke-MapsInstall {
    if (-not (Test-Path (Join-Path $ServerDir 'hlds.exe'))) {
        throw 'The server is not installed yet. Please run 1_INSTALL.bat first.'
    }

    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    Install-MapPack
    Install-OwnMaps
    Update-MapCycles
}

try {
    if ($MapsOnly) {
        Invoke-MapsInstall
    } else {
        Invoke-ServerInstall
    }

    Write-Host ''
    Write-Host 'Done! Start the server with 2_START_SERVER.bat' -ForegroundColor Green
} catch {
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if (Test-Path $WorkDir) {
        Remove-Item -Recurse -Force $WorkDir -ErrorAction SilentlyContinue
    }
}
