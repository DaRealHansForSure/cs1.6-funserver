# Builds CS 1.6 Server Control (app\CsServerControl) into one self-contained
# exe in the package root, 4_SERVER_CONTROL.exe, so the LAN PC needs no .NET
# installed.
#
# Needs the .NET 10 SDK once:  winget install Microsoft.DotNet.SDK.10
# Runs the unit tests first and stops when one fails.
#
# -Release also packs release\CS16-FunServer.zip: everything a LAN PC needs
# (the .bat files, the exe, README.txt, server-files, tools\maps.csv and the
# custom-maps hint), without the source code and docs. That zip is what gets
# copied to the server PC; it needs neither .NET nor PowerShell scripts.

param(
    [switch]$Release
)

$ErrorActionPreference = 'Stop'

$PackageRoot = Split-Path -Parent $PSScriptRoot
$ProjectFile = Join-Path $PackageRoot 'app\CsServerControl\CsServerControl.csproj'
$TestProjectFile = Join-Path $PackageRoot 'app\CsServerControl.Tests\CsServerControl.Tests.csproj'
$PublishDir = Join-Path $PackageRoot 'app\publish'
# Own build folders, so a window that was started from app\...\bin can not
# lock the files this build has to write.
$ArtifactsDir = Join-Path $PackageRoot 'app\.artifacts'
$TargetExe = Join-Path $PackageRoot '4_SERVER_CONTROL.exe'

$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $dotnet) {
    Write-Host 'The .NET SDK is missing. Install it with:  winget install Microsoft.DotNet.SDK.10' -ForegroundColor Red
    exit 1
}

# dotnet writes progress to stderr, which must not count as an error.
$ErrorActionPreference = 'Continue'

Write-Host '==> Unit tests' -ForegroundColor Cyan
& $dotnet.Source test $TestProjectFile -nologo -v q --artifacts-path $ArtifactsDir
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Tests failed, nothing was built.' -ForegroundColor Red
    exit 1
}

Write-Host '==> Publishing' -ForegroundColor Cyan
& $dotnet.Source publish $ProjectFile -nologo -v q -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true `
    --artifacts-path $ArtifactsDir -o $PublishDir
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Publishing failed.' -ForegroundColor Red
    exit 1
}

# An open window locks the exe. The copy must not fail silently, or the
# package keeps the old version while this script says done.
try {
    Copy-Item -Force (Join-Path $PublishDir 'CsServerControl.exe') $TargetExe -ErrorAction Stop
} catch {
    Write-Host 'Could not replace 4_SERVER_CONTROL.exe, it is probably open. Close the window and run this again.' -ForegroundColor Red
    exit 1
}
$sizeMb = [math]::Round((Get-Item $TargetExe).Length / 1MB)
Write-Host "Done: $TargetExe ($sizeMb MB)" -ForegroundColor Green

if (-not $Release) {
    exit 0
}

Write-Host '==> Release zip' -ForegroundColor Cyan
# From here on every failure must stop the script, a half written zip is worse than none.
$ErrorActionPreference = 'Stop'
# Only tracked files, so nothing from server\, the download cache or a
# developer's local settings can end up in the zip.
$packageFiles = @(& git -C $PackageRoot ls-files -- '*.bat' 'README.txt' 'server-files' 'tools/maps.csv' 'custom-maps/PUT_MAPS_HERE.txt')
if ($LASTEXITCODE -ne 0 -or $packageFiles.Count -eq 0) {
    Write-Host 'git ls-files failed, no release zip.' -ForegroundColor Red
    exit 1
}

$stagingDir = Join-Path $ArtifactsDir 'release\CS16-FunServer'
if (Test-Path $stagingDir) {
    Remove-Item -Recurse -Force $stagingDir
}
foreach ($file in $packageFiles) {
    $target = Join-Path $stagingDir $file
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath (Join-Path $PackageRoot $file) -Destination $target
}
Copy-Item $TargetExe (Join-Path $stagingDir '4_SERVER_CONTROL.exe')

$releaseDir = Join-Path $PackageRoot 'release'
New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
$zipFile = Join-Path $releaseDir 'CS16-FunServer.zip'
if (Test-Path $zipFile) {
    Remove-Item -Force $zipFile
}
# Entries written one by one with forward slashes: Compress-Archive and
# ZipFile both write backslashes under PowerShell 5.1, which other unzip
# tools do not read as folders.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::Open($zipFile, [IO.Compression.ZipArchiveMode]::Create)
try {
    $stagingParent = Split-Path -Parent $stagingDir
    foreach ($file in Get-ChildItem -Path $stagingDir -Recurse -File) {
        $entryName = $file.FullName.Substring($stagingParent.Length + 1).Replace('\', '/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $entryName, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $zip.Dispose()
}
$zipMb = [math]::Round((Get-Item $zipFile).Length / 1MB)
Write-Host "Done: $zipFile ($zipMb MB, $($packageFiles.Count + 1) files)" -ForegroundColor Green
