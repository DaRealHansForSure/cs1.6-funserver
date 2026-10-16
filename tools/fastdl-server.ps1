# Tiny read-only web server for CS 1.6 fast downloads (sv_downloadurl).
#
# Without it, clients pull maps through the game connection at a crawl. It
# only serves files with map related extensions from the cstrike folder, so
# configs, passwords and plugins stay private. One request at a time is plenty
# for a LAN, because the game client downloads its files one after another.

param(
    [Parameter(Mandatory = $true)][string]$Root,
    [int]$Port = 27080
)

$ErrorActionPreference = 'Stop'

$AllowedExtensions = @('.bsp', '.wad', '.res', '.txt', '.wav', '.mp3', '.mdl', '.spr', '.tga', '.bmp', '.nav', '.bz2')
$AllowedFolders = @('maps', 'sound', 'models', 'sprites', 'gfx', 'overviews')
$CopyBufferBytes = 64KB
$RootFullPath = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'

<#
.SYNOPSIS
Maps a request path to a file under the root, or returns $null when the
request must not be served.
#>
function Resolve-RequestedFile {
    param([string]$RequestPath)

    $decodedPath = [Uri]::UnescapeDataString($RequestPath.Split('?')[0]).TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($decodedPath)) {
        return $null
    }

    $fullPath = [IO.Path]::GetFullPath((Join-Path $RootFullPath $decodedPath.Replace('/', '\')))

    # GetFullPath resolves "..", so this check stops any escape from the root.
    if (-not $fullPath.StartsWith($RootFullPath, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    # Only the folders a client may need, plus map textures (.wad) in the root.
    $relativePath = $fullPath.Substring($RootFullPath.Length)
    $topFolder = $relativePath.Split('\')[0].ToLowerInvariant()
    $isRootWad = $relativePath -notlike '*\*' -and $relativePath.ToLowerInvariant().EndsWith('.wad')
    if ($topFolder -notin $AllowedFolders -and -not $isRootWad) {
        return $null
    }

    $extension = [IO.Path]::GetExtension($fullPath).ToLowerInvariant()
    if ($extension -notin $AllowedExtensions -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        return $null
    }

    return $fullPath
}

function Send-Response {
    param(
        [Net.Sockets.NetworkStream]$Stream,
        [string]$FilePath,
        [bool]$IsHeadRequest
    )

    $writer = New-Object IO.StreamWriter($Stream, [Text.Encoding]::ASCII)
    $writer.NewLine = "`r`n"

    if (-not $FilePath) {
        $writer.WriteLine('HTTP/1.1 404 Not Found')
        $writer.WriteLine('Content-Length: 0')
        $writer.WriteLine('Connection: close')
        $writer.WriteLine('')
        $writer.Flush()
        return
    }

    $fileStream = [IO.File]::OpenRead($FilePath)
    try {
        $writer.WriteLine('HTTP/1.1 200 OK')
        $writer.WriteLine('Content-Type: application/octet-stream')
        $writer.WriteLine("Content-Length: $($fileStream.Length)")
        $writer.WriteLine('Connection: close')
        $writer.WriteLine('')
        $writer.Flush()

        if (-not $IsHeadRequest) {
            $fileStream.CopyTo($Stream, $CopyBufferBytes)
        }
    } finally {
        $fileStream.Dispose()
    }
}

function Receive-Request {
    param([Net.Sockets.TcpClient]$Client)

    $stream = $Client.GetStream()
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII)

    # Only the request line matters, e.g. "GET /maps/de_rats.bsp HTTP/1.1".
    # The headers are read up to the empty line so the client is not cut off.
    $requestLine = $reader.ReadLine()
    while ($true) {
        $headerLine = $reader.ReadLine()
        if ([string]::IsNullOrEmpty($headerLine)) {
            break
        }
    }

    if (-not $requestLine) {
        return
    }

    $requestParts = $requestLine.Split(' ')
    if ($requestParts.Count -lt 2) {
        return
    }

    $method = $requestParts[0].ToUpperInvariant()
    $isSupportedMethod = $method -eq 'GET' -or $method -eq 'HEAD'

    $filePath = $null
    if ($isSupportedMethod) {
        $filePath = Resolve-RequestedFile -RequestPath $requestParts[1]
    }

    Send-Response -Stream $stream -FilePath $filePath -IsHeadRequest ($method -eq 'HEAD')

    if ($filePath) {
        Write-Host "[$(Get-Date -Format HH:mm:ss)] $($Client.Client.RemoteEndPoint) $($requestParts[1])"
    }
}

$host.UI.RawUI.WindowTitle = "CS 1.6 Fast Download (Port $Port)"
$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Any, $Port)
$listener.Start()
Write-Host "Fast download is running on port $Port and serves files from $RootFullPath"

try {
    while ($true) {
        $client = $listener.AcceptTcpClient()
        $client.ReceiveTimeout = 10000
        $client.SendTimeout = 30000
        try {
            Receive-Request -Client $client
        } catch {
            Write-Host "Request aborted: $($_.Exception.Message)"
        } finally {
            $client.Close()
        }
    }
} finally {
    $listener.Stop()
}
