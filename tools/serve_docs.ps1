param(
    [string]$Root = "docs/build",
    [int]$Port = 8000,
    [string]$BindHost = "127.0.0.1"
)

$ErrorActionPreference = "Stop"

$rootPath = (Resolve-Path $Root).Path
$prefix = "http://$BindHost`:$Port/"

$mime = @{
    ".html" = "text/html; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".svg"  = "image/svg+xml"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".jpeg" = "image/jpeg"
    ".gif"  = "image/gif"
    ".ico"  = "image/x-icon"
    ".txt"  = "text/plain; charset=utf-8"
    ".xml"  = "application/xml; charset=utf-8"
    ".map"  = "application/json; charset=utf-8"
    ".wasm" = "application/wasm"
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)
$listener.Start()

Write-Host "Serving docs from '$rootPath' at $prefix"

while ($listener.IsListening) {
    $ctx = $null
    try {
        $ctx = $listener.GetContext()

        $reqPath = [System.Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
        if ([string]::IsNullOrWhiteSpace($reqPath)) {
            $reqPath = "index.html"
        }
        $candidate = Join-Path $rootPath ($reqPath -replace '/', [System.IO.Path]::DirectorySeparatorChar)
        $fullPath = [System.IO.Path]::GetFullPath($candidate)

        if (-not $fullPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Invalid request path."
        }

        if ((Test-Path $fullPath) -and -not (Get-Item $fullPath).PSIsContainer) {
            $ext = [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()
            if ($mime.ContainsKey($ext)) {
                $ctx.Response.ContentType = $mime[$ext]
            } else {
                $ctx.Response.ContentType = "application/octet-stream"
            }

            $bytes = [System.IO.File]::ReadAllBytes($fullPath)
            $ctx.Response.StatusCode = 200
            $ctx.Response.ContentLength64 = $bytes.Length
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
            $ctx.Response.StatusCode = 404
            $ctx.Response.ContentType = "text/plain; charset=utf-8"
            $ctx.Response.ContentLength64 = $msg.Length
            $ctx.Response.OutputStream.Write($msg, 0, $msg.Length)
        }
    } catch {
        if ($ctx -ne $null) {
            $msg = [System.Text.Encoding]::UTF8.GetBytes("500 Internal Server Error")
            $ctx.Response.StatusCode = 500
            $ctx.Response.ContentType = "text/plain; charset=utf-8"
            $ctx.Response.ContentLength64 = $msg.Length
            $ctx.Response.OutputStream.Write($msg, 0, $msg.Length)
        }
    } finally {
        if ($ctx -ne $null) {
            $ctx.Response.OutputStream.Close()
        }
    }
}

$listener.Stop()
