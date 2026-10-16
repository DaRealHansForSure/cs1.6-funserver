# Builds the Server Control window into one self-contained exe in the package
# root (4_SERVER_CONTROL.exe), so the LAN PC needs no .NET installed.
#
# Needs the .NET 10 SDK once:  winget install Microsoft.DotNet.SDK.10
# Runs the unit tests first and stops when one fails.

$ErrorActionPreference = 'Stop'

$PackageRoot = Split-Path -Parent $PSScriptRoot
$ProjectFile = Join-Path $PackageRoot 'gui\ServerControl\ServerControl.csproj'
$TestProjectFile = Join-Path $PackageRoot 'gui\ServerControl.Tests\ServerControl.Tests.csproj'
$PublishDir = Join-Path $PackageRoot 'gui\publish'
# Own build folders, so a window that was started from gui\...\bin can not
# lock the files this build has to write.
$ArtifactsDir = Join-Path $PackageRoot 'gui\.artifacts'
$TargetExe = Join-Path $PackageRoot '4_SERVER_CONTROL.exe'

$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $dotnet) {
    Write-Host 'The .NET SDK is missing. Install it with:  winget install Microsoft.DotNet.SDK.10' -ForegroundColor Red
    exit 1
}

# dotnet writes progress to stderr, which must not count as an error.
$ErrorActionPreference = 'Continue'

Write-Host '==> Unit tests' -ForegroundColor Cyan
& $dotnet.Source test $TestProjectFile -nologo -v q
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Tests failed, nothing was built.' -ForegroundColor Red
    exit 1
}

Write-Host '==> Publishing' -ForegroundColor Cyan
& $dotnet.Source publish $ProjectFile -nologo -v q -c Release -r win-x64 --self-contained true `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true --artifacts-path $ArtifactsDir -o $PublishDir
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Publishing failed.' -ForegroundColor Red
    exit 1
}

# An open window locks the exe. The copy must not fail silently, or the
# package keeps the old version while this script says done.
try {
    Copy-Item -Force (Join-Path $PublishDir 'ServerControl.exe') $TargetExe -ErrorAction Stop
} catch {
    Write-Host "Could not replace 4_SERVER_CONTROL.exe, it is probably open. Close the window and run this again." -ForegroundColor Red
    exit 1
}
$sizeMb = [math]::Round((Get-Item $TargetExe).Length / 1MB)
Write-Host "Done: $TargetExe ($sizeMb MB)" -ForegroundColor Green
