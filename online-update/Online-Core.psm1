function New-OnlineHttpRequest($Uri) { return [Net.HttpWebRequest]::Create($Uri) }
function Get-GhcrAnonymousPullToken {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $now = [DateTime]::UtcNow
    if ($null -ne $script:GhcrPullToken -and $script:GhcrPullTokenExpiresUtc -gt $now) {
        return $true
    }

    $uri = $null
    if (-not [Uri]::TryCreate($script:GhcrTokenUrl, [UriKind]::Absolute, [ref]$uri)) {
        throw 'Invalid GHCR token URL.'
    }

    $request = (New-OnlineHttpRequest $uri)
    $request.Method = 'GET'
    $request.AllowAutoRedirect = $false
    $request.UseDefaultCredentials = $false
    $request.Credentials = $null
    $request.UserAgent = 'TGCNV-OnlineUpdate/1.0'
    $request.Timeout = 30000
    $request.ReadWriteTimeout = 60000
    $request.AutomaticDecompression = [Net.DecompressionMethods]::None
    $request.KeepAlive = $false

    $response = $null
    $stream = $null
    $memory = $null
    try {
        $response = $request.GetResponse()
        $status = [int]$response.StatusCode
        if ($status -ge 300 -and $status -lt 400) {
            throw "GHCR token endpoint redirected (HTTP $status), which is not allowed."
        }
        if ($status -ne 200) {
            throw "GHCR token endpoint returned HTTP $status."
        }

        $declared = $response.ContentLength
        if ($declared -gt $script:GhcrTokenMaxBytes) {
            throw "GHCR token response is too large ($declared bytes)."
        }

        $stream = $response.GetResponseStream()
        $memory = New-Object System.IO.MemoryStream
        $buffer = New-Object byte[] 8192
        $total = [long]0
        while ($true) {
            $read = $stream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            $total += $read
            if ($total -gt $script:GhcrTokenMaxBytes) {
                throw "GHCR token response exceeded $($script:GhcrTokenMaxBytes) bytes."
            }
            $memory.Write($buffer, 0, $read)
        }

        $bytes = $memory.ToArray()
        $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $jsonText = $utf8.GetString($bytes)
        $obj = $null
        try { $obj = ConvertFrom-Json -InputObject $jsonText } catch { throw 'GHCR token response is not valid JSON.' }
        if ($null -eq $obj) { throw 'GHCR token response is empty.' }

        $token = $null
        $property = $obj.PSObject.Properties['token']
        if ($null -ne $property) { $token = [string]$property.Value }
        if ([string]::IsNullOrWhiteSpace($token)) {
            $property = $obj.PSObject.Properties['access_token']
            if ($null -ne $property) { $token = [string]$property.Value }
        }
        if ([string]::IsNullOrWhiteSpace($token)) {
            throw 'GHCR token response did not contain a token.'
        }
        if ($token.Length -gt $script:GhcrTokenMaxLength) {
            throw 'GHCR token is unreasonably long.'
        }
        if ($token -match '[\x00-\x20\x7f]') {
            throw 'GHCR token contains whitespace or control characters.'
        }

        $script:GhcrPullToken = $token
        $script:GhcrPullTokenExpiresUtc = $now.AddSeconds($script:GhcrTokenCacheSeconds)
        return $true
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $memory) { $memory.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
    }
}

$script:GhcrHost                  = 'ghcr.io'
$script:GhcrFixedRepository       = 'yukino-chan/tgcnv-patches'
$script:GhcrBlobUrlPattern        = '^https://ghcr\.io/v2/yukino-chan/tgcnv-patches/blobs/sha256:[0-9a-f]{64}$'
$script:GhcrNamespacePrefix       = '/v2/yukino-chan/tgcnv-patches/'
$script:ChannelUrl                = 'https://raw.githubusercontent.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/update-feed/channel.json'
$script:GhcrTokenUrl              = 'https://ghcr.io/token?service=ghcr.io&scope=repository%3Ayukino-chan%2Ftgcnv-patches%3Apull'
$script:GhcrTokenMaxBytes         = 65536
$script:GhcrTokenCacheSeconds     = 240
$script:GhcrTokenMaxLength        = 4096
$script:GhcrPullToken             = $null
$script:GhcrPullTokenExpiresUtc   = [DateTime]::MinValue

# Online-Core.psm1
# Pure helper module for the TGCNV signed online-update channel.
# SAVE THIS FILE AS UTF-8 WITH BOM: the metadata name '\uc124\uce58 \uc548\ub0b4.txt' must survive PowerShell 5.1 parsing.
# No execution, no shell-out, no credential use. Every byte-array return uses ',<array>'.

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$script:UpdateMutexName   = 'Local\TGCNV_OnlineUpdate'
$script:MetadataNames     = @('manifest.json','Setup.ps1','Setup.cmd','Restore.cmd','Verify.cmd','설치 안내.txt','SHA256SUMS.txt')
$script:TGCNVRoots        = @('common','decisions','events','gfx','history','interface','inventions','localisation','map','news','poptypes','runtime','sound','technologies','units')
$script:TGCNVRootFiles    = @('settings.txt','tgcnv_extension.json')
$script:TGORootFiles      = @('opening_music.md','victoria1_music.md','victoria1_music_manifest.json')
$script:GameRootFiles     = @('lua51.dll','lua51_ori.dll','tgcnv_memory_bridge.dll','tgcnv.exe')
$script:DeniedSegments    = @('v2game.exe','originallua','privateconfig','save games')
$script:MaxCatalogEntries = 100000
$script:MaxCatalogBytes   = 10737418240   # 10 GiB payload ceiling
$script:MaxAssetBytes     = 2147483647    # 4 GiB per asset zip
$script:MaxZipRawBytes    = 4294967296    # 4 GiB decompressed ceiling per archive
$script:MaxCatalogJson    = 33554432      # 32 MiB of catalog JSON
$script:AllowedHostSuffix = '.githubusercontent.com'
$script:BufferSize        = 131072

# ---------------------------------------------------------------- helpers ----

function Assert-Sha256Hex {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [string]$Label = 'sha256'
    )
    if ($Value -cnotmatch '^[0-9a-f]{64}$') {
        throw "$Label must be exactly 64 lowercase hex characters: '$Value'."
    }
    return $Value
}

function Test-AllowedDownloadHost {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)][string]$HostName)
    if ($HostName -ieq 'github.com') { return $true }
    if ($HostName -ieq $script:GhcrHost) { return $true }
    if ($HostName.Length -gt $script:AllowedHostSuffix.Length -and
        $HostName.EndsWith($script:AllowedHostSuffix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $false
}


function Assert-NoReparsePoint {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        $item = Get-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing a junction/symlink: '$current'."
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Get-CatalogEntryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Entry,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $property = $Entry.PSObject.Properties[$Name]
    if ($null -eq $property) { throw "Catalog entry is missing the required '$Name' property." }
    return $property.Value
}

# Downloads are funnelled through this: manual, bounded redirect handling that
# never follows a hop outside https://github.com or https://*.githubusercontent.com.
function Get-BoundedHttpResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$Repository = '',
        [int]$MaxRedirects = 5,
        [int]$TimeoutMilliseconds = 30000,
        [int]$ReadWriteTimeoutMilliseconds = 60000
    )
    if ($MaxRedirects -lt 0) { throw 'MaxRedirects must not be negative.' }

    $isGhcrBlob = $false
    if ($Repository -ceq 'Yukino-Chan/TGC-Anime-Total-Overhaul-Korean' -and $Url -cmatch $script:GhcrBlobUrlPattern) {
        $isGhcrBlob = $true
    }

    $current = $Url
    for ($hop = 0; $hop -le $MaxRedirects; $hop++) {
        $uri = $null
        if (-not [Uri]::TryCreate($current, [UriKind]::Absolute, [ref]$uri)) { throw "Invalid URL: '$current'." }
        if ($uri.Scheme -ne 'https' -or -not $uri.IsDefaultPort -or $uri.Fragment) { throw "Only https downloads are allowed: '$current'." }
        if (-not [string]::IsNullOrEmpty($uri.UserInfo)) { throw 'URLs carrying credentials are refused.' }

        if (-not (Test-AllowedDownloadHost -HostName $uri.Host)) {
            throw "Downloads are restricted to github.com, *$($script:AllowedHostSuffix), and the fixed GHCR namespace: '$($uri.Host)'."
        }
        if ($uri.Host -ieq $script:GhcrHost) {
            if ($Repository -cne 'Yukino-Chan/TGC-Anime-Total-Overhaul-Korean') {
                throw "GHCR downloads are only allowed for the fixed repository '$($script:GhcrFixedRepository)'."
            }
            if ($current -cnotmatch $script:GhcrBlobUrlPattern) {
                throw "GHCR URL path is outside the allowed namespace: '$($uri.AbsoluteUri)'."
            }
        }

        $useAuth = $false
        if ($hop -eq 0 -and $isGhcrBlob -and $uri.Host -ieq $script:GhcrHost -and $uri.AbsolutePath -match '^/v2/yukino-chan/tgcnv-patches/blobs/sha256:[0-9a-f]{64}$') {
            $useAuth = $true
        }

        $authAttempt = 0
        $response = $null
        while ($true) {
            $request = (New-OnlineHttpRequest $uri)
            $request.Method = 'GET'
            $request.AllowAutoRedirect = $false
            $request.UseDefaultCredentials = $false
            $request.Credentials = $null
            $request.UserAgent = 'TGCNV-OnlineUpdate/1.0'
            $request.Timeout = $TimeoutMilliseconds
            $request.ReadWriteTimeout = $ReadWriteTimeoutMilliseconds
            $request.AutomaticDecompression = [Net.DecompressionMethods]::None
            $request.KeepAlive = $false

            if ($useAuth) {
                [void](Get-GhcrAnonymousPullToken)
                if ($null -eq $script:GhcrPullToken) {
                    throw 'Failed to obtain an anonymous GHCR pull token.'
                }
                $request.Headers['Authorization'] = "Bearer $($script:GhcrPullToken)"
            }

            try {
                $response = $request.GetResponse()
                break
            } catch [Net.WebException] {
                $failed = $_.Exception.Response
                $status = $null
                if ($null -ne $failed) {
                    $status = [int]$failed.StatusCode
                    $failed.Dispose()
                }
                if ($status -eq 401 -and $useAuth -and $authAttempt -eq 0) {
                    $authAttempt++
                    $script:GhcrPullToken = $null
                    $script:GhcrPullTokenExpiresUtc = [DateTime]::MinValue
                    [void](Get-GhcrAnonymousPullToken)
                    if ($null -eq $script:GhcrPullToken) {
                        throw 'Failed to refresh GHCR pull token after HTTP 401.'
                    }
                    continue
                }
                throw
            }
        }

        $status = [int]$response.StatusCode
        if ($status -ge 300 -and $status -lt 400) {
            $location = $response.Headers['Location']
            $response.Dispose()
            if ([string]::IsNullOrWhiteSpace($location)) { throw 'Redirect response without a Location header.' }
            $next = $null
            if (-not [Uri]::TryCreate($location, [UriKind]::RelativeOrAbsolute, [ref]$next)) {
                throw 'Redirect target is not a valid URI.'
            }
            if ($next.IsAbsoluteUri) { $current = $next.AbsoluteUri }
            else { $current = (New-Object System.Uri($uri, $location)).AbsoluteUri }
            continue
        }
        if ($status -ne 200) {
            $response.Dispose()
            throw "HTTP $status for '$($uri.AbsoluteUri)'."
        }
        return [pscustomobject]@{ Response = $response; FinalUri = $uri.AbsoluteUri }
    }
    throw "Too many redirects (limit $MaxRedirects)."
}


function Get-Sha256 {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Path is required.' }
    if (-not [IO.File]::Exists($Path)) { throw "File not found: '$Path'." }

    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $hash = $sha.ComputeHash($stream)
        return ([BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        $sha.Dispose()
    }
}

function Assert-RelativePath {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$RelativePath)

    $path = $RelativePath
    if ([string]::IsNullOrWhiteSpace($path)) { throw 'Relative path must not be empty.' }
    if ($path.Length -gt 512) { throw 'Relative path is too long.' }
    if ($path.Contains('\')) { throw "Relative paths must use '/' separators: '$path'." }
    if ($path.Contains('%')) { throw "Percent-encoded characters are not allowed: '$path'." }
    if ($path -match '[<>"|?*]') { throw 'Invalid Windows filename character.' }
    if ($path.Contains(':')) { throw "Colons are not allowed in relative paths: '$path'." }
    if ($path -match '[\x00-\x1f\x7f]') { throw 'Relative path contains control characters.' }
    if ([IO.Path]::IsPathRooted($path)) { throw "Absolute paths are not allowed: '$path'." }

    foreach ($segment in $path.Split('/')) {
        if ($segment.Length -eq 0) { throw "Relative path contains an empty segment: '$path'." }
        if ($segment -eq '.' -or $segment -eq '..') { throw "Relative path contains a dot segment: '$path'." }
        if ($segment -match '[ .]$') { throw "Path segment ends with a dot or space: '$segment'." }
        if ($segment -match '^(?i:(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]))(\..*)?$') {
            throw "Path segment is a reserved Windows device name: '$segment'."
        }
    }
    return $path
}

function Resolve-SafeChild {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'Root is required.' }
    $relative = Assert-RelativePath -RelativePath $RelativePath

    $rootFull = [IO.Path]::GetFullPath($Root)
    $separator = [IO.Path]::DirectorySeparatorChar
    $rootPrefix = $rootFull
    if (-not $rootPrefix.EndsWith([string]$separator)) { $rootPrefix += $separator }

    $target = [IO.Path]::GetFullPath([IO.Path]::Combine($rootFull, ($relative -replace '/', '\')))
    if (-not $target.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Resolved path escapes the root directory: '$RelativePath'."
    }

    Assert-NoReparsePoint -Path $target
    return $target
}

function Assert-GitHubAssetUrl {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Url,
        [Parameter(Mandatory = $true)][string]$Repository
    )

    if ([string]::IsNullOrWhiteSpace($Url)) { throw 'Asset URL is required.' }
    if ($Url.Contains('%')) { throw "Percent-encoded asset URLs are refused: '$Url'." }
    if ($Url -match '[\x00-\x20\x7f]') { throw "Asset URL contains whitespace or control characters: '$Url'." }
    if ($Repository -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9._-]{0,38}[A-Za-z0-9])?/[A-Za-z0-9](?:[A-Za-z0-9._-]{0,99}[A-Za-z0-9])?$') {
        throw "Repository must be in 'owner/repo' form: '$Repository'."
    }

    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) { throw "Invalid asset URL: '$Url'." }
    if ($uri.Scheme -ne 'https' -or -not $uri.IsDefaultPort -or $uri.Fragment) { throw "Asset URL must use https: '$Url'." }
    if (-not $uri.IsDefaultPort) { throw "Explicit ports are not allowed: '$Url'." }
    if (-not [string]::IsNullOrEmpty($uri.UserInfo)) { throw "Userinfo is not allowed: '$Url'." }
    if (-not [string]::IsNullOrEmpty($uri.Query)) { throw "Query strings are not allowed: '$Url'." }
    if (-not [string]::IsNullOrEmpty($uri.Fragment)) { throw "URL fragments are not allowed: '$Url'." }

    # Exact fixed channel envelope URL.
    if ($Url -ceq $script:ChannelUrl -and $Repository -ceq 'Yukino-Chan/TGC-Anime-Total-Overhaul-Korean') {
        return $Url
    }

    # Exact canonical GHCR blob URL for the fixed namespace.
    if ($uri.Host -ieq $script:GhcrHost) {
        if ($Repository -cne 'Yukino-Chan/TGC-Anime-Total-Overhaul-Korean') {
            throw "GHCR asset URLs are only allowed for the fixed repository '$($script:GhcrFixedRepository)'."
        }
        if ($Url -cnotmatch $script:GhcrBlobUrlPattern) {
            throw "Noncanonical GHCR blob URL: '$Url'."
        }
        return $Url
    }

    if ($uri.Host -ine 'github.com') { throw "Asset host must be github.com: '$($uri.Host)'." }

    $rawPattern = '^https://github\.com/' + [regex]::Escape($Repository) + '/releases/download/[A-Za-z0-9][A-Za-z0-9._-]{0,63}/[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'
    if ($Url -cnotmatch $rawPattern) { throw 'Noncanonical GitHub release URL.' }
    $expectedOwner, $expectedRepo = $Repository.Split('/')
    $segments = $uri.AbsolutePath.Trim('/').Split('/')
    if ($segments.Count -ne 6) {
        throw "Asset URL must be /<owner>/<repo>/releases/download/<tag>/<asset>: '$Url'."
    }
    if ($segments[0] -ine $expectedOwner -or $segments[1] -ine $expectedRepo) {
        throw "Asset URL owner/repository does not match '$Repository'."
    }
    if ($segments[2] -ine 'releases' -or $segments[3] -ine 'download') {
        throw "Asset URL must live under /releases/download/: '$Url'."
    }

    $tag = $segments[4]
    $asset = $segments[5]
    if ($tag -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw "Release tag is not a safe path segment: '$tag'." }
    if ($asset -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw "Asset name is not a safe path segment: '$asset'." }

    return $Url
}


function Receive-VerifiedFile {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][long]$ExpectedBytes,
        [Parameter(Mandatory = $true)][string]$Sha256,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][long]$MaxBytes
    )

    if ($ExpectedBytes -lt 0) { throw 'ExpectedBytes must not be negative.' }
    if ($MaxBytes -lt 1) { throw 'MaxBytes must be positive.' }
    if ($ExpectedBytes -gt $MaxBytes) { throw 'ExpectedBytes exceeds MaxBytes.' }
    [void](Assert-Sha256Hex -Value $Sha256 -Label 'Sha256')
    [void](Assert-GitHubAssetUrl -Url $Url -Repository $Repository)

    if ([string]::IsNullOrWhiteSpace($Destination)) { throw 'Destination is required.' }
    $destinationFull = [IO.Path]::GetFullPath($Destination)
    $destinationDir = [IO.Path]::GetDirectoryName($destinationFull)
    if ([string]::IsNullOrWhiteSpace($destinationDir)) { throw 'Destination must include a directory.' }
    Assert-NoReparsePoint -Path $destinationFull
    [void][IO.Directory]::CreateDirectory($destinationDir)

    # Unique sibling partial so the final rename stays on the same volume.
    $partial = [IO.Path]::Combine($destinationDir, ('{0}.{1}.partial' -f [IO.Path]::GetFileName($destinationFull), [Guid]::NewGuid().ToString('N')))

    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    $response = $null
    $networkStream = $null
    $fileStream = $null
    $hasher = $null
    $partialCreated = $false
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $session = Get-BoundedHttpResponse -Url $Url -Repository $Repository
        $response = $session.Response

        $declared = $response.ContentLength
        if ($declared -ge 0) {
            if ($declared -gt $MaxBytes) { throw "Server declared $declared bytes, above the $MaxBytes byte cap." }
            if ($ExpectedBytes -gt 0 -and $declared -ne $ExpectedBytes) {
                throw "Server declared $declared bytes but $ExpectedBytes were expected."
            }
        }

        $networkStream = $response.GetResponseStream()
        $fileStream = New-Object System.IO.FileStream($partial, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $partialCreated = $true
        $hasher = [Security.Cryptography.SHA256]::Create()

        $buffer = New-Object byte[] $script:BufferSize
        $total = [long]0
        while ($true) {
            $read = $networkStream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            $total += $read
            if ($total -gt $MaxBytes) { throw "Download exceeded the $MaxBytes byte cap." }
            if ($total -gt $ExpectedBytes) { throw "Download exceeded the expected $ExpectedBytes bytes." }
            [void]$hasher.TransformBlock($buffer, 0, $read, $buffer, 0)
            $fileStream.Write($buffer, 0, $read)
        }
        [void]$hasher.TransformFinalBlock((New-Object byte[] 0), 0, 0)
        $fileStream.Flush()
        $fileStream.Dispose()
        $fileStream = $null

        if ($total -ne $ExpectedBytes) { throw "Downloaded $total bytes but $ExpectedBytes were expected." }
        $actual = ([BitConverter]::ToString($hasher.Hash) -replace '-', '').ToLowerInvariant()
        if ($actual -cne $Sha256) { throw "SHA256 mismatch for '$Url'." }

        if ([IO.File]::Exists($destinationFull)) { [IO.File]::Replace($partial, $destinationFull, [NullString]::Value) }
        else { [IO.File]::Move($partial, $destinationFull) }
        $partialCreated = $false
        return $destinationFull
    } finally {
        if ($null -ne $networkStream) { $networkStream.Dispose() }
        if ($null -ne $fileStream) { $fileStream.Dispose() }
        if ($null -ne $hasher) { $hasher.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
        # Only ever delete the temporary file this call created.
        if ($partialCreated -and [IO.File]::Exists($partial)) {
            Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
        }
    }
}

function Receive-LimitedBytes {
    [CmdletBinding()]
    [OutputType([byte[]])]
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][long]$MaxBytes,
        [Parameter(Mandatory = $true)][string]$Repository
    )

    if ($MaxBytes -lt 1) { throw 'MaxBytes must be positive.' }
    [void](Assert-GitHubAssetUrl -Url $Url -Repository $Repository)

    $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
    $response = $null
    $networkStream = $null
    $memory = $null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $session = Get-BoundedHttpResponse -Url $Url -Repository $Repository
        $response = $session.Response

        $declared = $response.ContentLength
        if ($declared -gt $MaxBytes) { throw "Server declared $declared bytes, above the $MaxBytes byte cap." }

        $networkStream = $response.GetResponseStream()
        $memory = New-Object System.IO.MemoryStream
        $buffer = New-Object byte[] 65536
        $total = [long]0
        while ($true) {
            $read = $networkStream.Read($buffer, 0, $buffer.Length)
            if ($read -le 0) { break }
            $total += $read
            if ($total -gt $MaxBytes) { throw "Response exceeded the $MaxBytes byte cap." }
            $memory.Write($buffer, 0, $read)
        }
        return ,$memory.ToArray()
    } finally {
        if ($null -ne $networkStream) { $networkStream.Dispose() }
        if ($null -ne $memory) { $memory.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
    }
}

function Test-ChannelSignature {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$ChannelBytes,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$SignatureBytes,
        [Parameter(Mandatory = $true)][string]$PublicKeyXml
    )

    if ($null -eq $ChannelBytes) { throw 'ChannelBytes is required.' }
    if ($null -eq $SignatureBytes -or $SignatureBytes.Length -eq 0) { throw 'SignatureBytes is required.' }
    if ([string]::IsNullOrWhiteSpace($PublicKeyXml)) { throw 'PublicKeyXml is required.' }

    $document = New-Object System.Xml.XmlDocument
    $document.XmlResolver = $null
    try { $document.LoadXml($PublicKeyXml) } catch { throw 'PublicKeyXml is not valid XML.' }
    $documentElement = $document.DocumentElement
    if ($null -eq $documentElement -or $documentElement.Name -ne 'RSAKeyValue') {
        throw 'PublicKeyXml must be an RSAKeyValue element.'
    }
    foreach ($secret in @('D', 'P', 'Q', 'DP', 'DQ', 'InverseQ')) {
        if ($null -ne $documentElement.SelectSingleNode($secret)) {
            throw "PublicKeyXml must be public-only (found private element '$secret')."
        }
    }

    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider
    try {
        $rsa.PersistKeyInCsp = $false
        $rsa.FromXmlString($documentElement.OuterXml)
        if ($rsa.KeySize -lt 2048) { throw "RSA key is too small." }
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $hash = $sha.ComputeHash($ChannelBytes)
            $deformatter = New-Object System.Security.Cryptography.RSAPKCS1SignatureDeformatter -ArgumentList $rsa
            $deformatter.SetHashAlgorithm('SHA256')
            return [bool]$deformatter.VerifySignature($hash, $SignatureBytes)
        } finally {
            $sha.Dispose()
        }
    } catch [System.Security.Cryptography.CryptographicException] {
        return $false
    } catch [System.Xml.XmlException] {
        return $false
    } finally {
        $rsa.Dispose()
    }
}

function Test-CatalogPath {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($script:MetadataNames -contains $Path) { return $true }

    if (-not $Path.StartsWith('payload/', [StringComparison]::Ordinal)) { return $false }
    $Path = $Path.Substring(8)
    $segments = $Path.Split('/')
    $lower = New-Object System.Collections.Generic.List[string]
    foreach ($segment in $segments) { $lower.Add($segment.ToLowerInvariant()) }
    $count = $lower.Count

    foreach ($segment in $lower) {
        if ($script:DeniedSegments -contains $segment -or $segment.StartsWith('.') -or $segment -eq '_backups') { return $false }
    }
    if ($count -lt 2) { return $false }

    if ($count -ge 3 -and $lower[0] -eq 'game' -and $lower[1] -eq 'mod') {
        if ($count -eq 3 -and ($lower[2] -eq 'tgcnv.mod' -or $lower[2] -eq 'tgo.mod')) { return $true }
        if ($lower[2] -eq 'tgcnv') {
            if ($count -eq 4) { return ($script:TGCNVRootFiles -contains $lower[3]) }
            if ($count -ge 5) { return ($script:TGCNVRoots -contains $lower[3]) }
            return $false
        }
        if ($lower[2] -eq 'tgo') {
            if ($count -eq 4) { return ($script:TGORootFiles -contains $lower[3]) }
            if ($count -ge 5 -and ($lower[3] -eq 'events' -or $lower[3] -eq 'music')) { return $true }
            return $false
        }
        return $false
    }

    if ($count -eq 2 -and $lower[0] -eq 'game') {
        return ($script:GameRootFiles -contains $lower[1])
    }

    if ($count -ge 4 -and $lower[0] -eq 'profile' -and $lower[1] -eq 'map' -and $lower[2] -eq 'cache') {
        return $true
    }
    return $false
}

function Assert-Integer {
    param($Value)
    if ($Value -isnot [int] -and $Value -isnot [long]) { throw 'Expected an integer.' }
    return [long]$Value
}

function Read-ValidatedCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][string]$Repository
    )

    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { throw 'Catalog payload is empty.' }
    if ($Bytes.Length -gt $script:MaxCatalogJson) { throw 'Catalog payload exceeds the tolerated size.' }
    if ([string]::IsNullOrWhiteSpace($Repository)) { throw 'Repository is required.' }

    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try { $text = $utf8.GetString($Bytes) } catch { throw 'Catalog is not valid UTF-8.' }
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }

    $catalog = $null
    try { $catalog = ConvertFrom-Json -InputObject $text } catch { throw 'Catalog is not valid JSON.' }
    if ($null -eq $catalog) { throw 'Catalog is empty.' }

    $root = $catalog.PSObject.Properties
    foreach ($required in @('schema', 'release', 'engine_version', 'manifest_sha256', 'files', 'assets')) {
        if ($null -eq $root[$required]) { throw "Catalog is missing the required '$required' property." }
    }
    if ((Assert-Integer $root['schema'].Value) -ne 1) { throw 'Only catalog schema 1 is supported.' }

    $release = [string]$root['release'].Value
    if ($release -cnotmatch '^TGCNV-\d{8}-\d{6}$') { throw "Catalog release stamp is invalid: '$release'." }

    $engineVersion = [string]$root['engine_version'].Value
    if ([string]::IsNullOrWhiteSpace($engineVersion) -or $engineVersion.Length -gt 64 -or
        $engineVersion -notmatch '^[0-9A-Za-z][0-9A-Za-z.+_-]*$') {
        throw "Catalog engine_version is invalid: '$engineVersion'."
    }

    $manifestSha = Assert-Sha256Hex -Value ([string]$root['manifest_sha256'].Value) -Label 'manifest_sha256'

    # ---- assets -------------------------------------------------------------
    $assetsNode = $root['assets'].Value
    $assetNames = @($assetsNode.PSObject.Properties | ForEach-Object { $_.Name })
    if ($assetNames.Count -eq 0) { throw 'Catalog declares no assets.' }
    if ($assetNames.Count -gt 4096) { throw 'Catalog declares too many assets.' }

    $assetTable = @{}
    $assetTotal = [long]0
    foreach ($key in $assetNames) {
        [void](Assert-Sha256Hex -Value $key -Label 'asset key')
        $node = $assetsNode.PSObject.Properties[$key].Value
        foreach ($required in @('url', 'bytes', 'sha256')) {
            if ($null -eq $node.PSObject.Properties[$required]) { throw "Asset '$key' is missing '$required'." }
        }
        $assetUrl = [string]$node.PSObject.Properties['url'].Value
        [void](Assert-GitHubAssetUrl -Url $assetUrl -Repository $Repository)
        $assetBytes = Assert-Integer $node.PSObject.Properties['bytes'].Value
        if ($assetBytes -le 0 -or $assetBytes -gt $script:MaxAssetBytes) {
            throw "Asset '$key' has an out-of-range byte count."
        }
        if ([string]$node.PSObject.Properties['sha256'].Value -cne $key) {
            throw "Asset '$key' declares a mismatched sha256."
        }
        if (-not $assetUrl.EndsWith("/objects-$key.zip", [StringComparison]::Ordinal) -and $assetUrl -cne "https://ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/sha256:$key") { throw "Asset name mismatch." }
        $assetTotal += $assetBytes
        if ($assetTotal -gt $script:MaxCatalogBytes) { throw 'Catalog assets exceed the 10 GiB total cap.' }
        $assetTable[$key] = [pscustomobject]@{ Sha256 = $key; Url = $assetUrl; Bytes = $assetBytes }
    }

    # ---- files --------------------------------------------------------------
    $filesNode = @($root['files'].Value)
    if ($filesNode.Count -eq 0) { throw 'Catalog declares no files.' }
    if ($filesNode.Count -gt $script:MaxCatalogEntries) { throw 'Catalog declares too many files.' }

    $filePaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $dirPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $seenMetadata = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $collected = New-Object System.Collections.ArrayList
    $totalBytes = [long]0

    foreach ($node in $filesNode) {
        foreach ($required in @('path', 'bytes', 'sha256', 'asset')) {
            if ($null -eq $node.PSObject.Properties[$required]) { throw "Catalog file entry is missing '$required'." }
        }
        $path = Assert-RelativePath -RelativePath ([string]$node.PSObject.Properties['path'].Value)
        if (-not (Test-CatalogPath -Path $path)) { throw "Catalog path is not permitted by the distribution layout: '$path'." }

        $entryBytes = Assert-Integer $node.PSObject.Properties['bytes'].Value
        if ($entryBytes -lt 0 -or $entryBytes -gt 2147483647) { throw "File '$path' has an out-of-range byte count." }
        $entrySha = Assert-Sha256Hex -Value ([string]$node.PSObject.Properties['sha256'].Value) -Label "sha256 for '$path'"
        $assetRef = [string]$node.PSObject.Properties['asset'].Value
        if (-not $assetTable.ContainsKey($assetRef)) { throw "File '$path' references unknown asset '$assetRef'." }

        if ($path -ieq 'manifest.json' -and $entrySha -cne $manifestSha) {
            throw "manifest.json hash does not match the catalog manifest_sha256."
        }

        if ($filePaths.Contains($path)) { throw "Duplicate catalog path (case-insensitive): '$path'." }
        if ($dirPaths.Contains($path)) { throw "Catalog path '$path' collides with a directory implied by another entry." }

        $segments = $path.Split('/')
        $prefix = ''
        for ($i = 0; $i -lt ($segments.Count - 1); $i++) {
            $prefix = if ($i -eq 0) { $segments[0] } else { "$prefix/$($segments[$i])" }
            if ($filePaths.Contains($prefix)) { throw "Catalog path '$path' is nested below the file '$prefix'." }
            [void]$dirPaths.Add($prefix)
        }
        [void]$filePaths.Add($path)
        if ($script:MetadataNames -contains $path) { [void]$seenMetadata.Add($path) }

        $totalBytes += $entryBytes
        if ($totalBytes -gt $script:MaxCatalogBytes) { throw 'Catalog payload exceeds the 10 GiB cap.' }

        [void]$collected.Add([pscustomobject]@{ Path = $path; Bytes = $entryBytes; Sha256 = $entrySha; Asset = $assetRef })
    }

    foreach ($name in $script:MetadataNames) {
        if (-not $seenMetadata.Contains($name)) { throw "Catalog is missing the required metadata file '$name'." }
    }

    return [pscustomobject]@{
        Schema         = 1
        Release        = $release
        EngineVersion  = $engineVersion
        ManifestSha256 = $manifestSha
        Files          = $collected.ToArray()
        Assets         = $assetTable
        TotalBytes     = $totalBytes
    }
}

function Expand-SelectedAsset {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$CatalogEntries,
        [Parameter(Mandatory = $true)][string]$StageRoot
    )

    if ([string]::IsNullOrWhiteSpace($ArchivePath)) { throw 'ArchivePath is required.' }
    if (-not [IO.File]::Exists($ArchivePath)) { throw "Archive not found: '$ArchivePath'." }
    if ($null -eq $CatalogEntries) { throw 'CatalogEntries is required.' }
    if ([string]::IsNullOrWhiteSpace($StageRoot)) { throw 'StageRoot is required.' }
    if (-not ('System.IO.Compression.ZipFile' -as [type])) {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    }
    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop

    $stageFull = [IO.Path]::GetFullPath($StageRoot)
    Assert-NoReparsePoint -Path $stageFull
    [void][IO.Directory]::CreateDirectory($stageFull)

    $expected = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $CatalogEntries) {
        $entryPath = Assert-RelativePath -RelativePath ([string](Get-CatalogEntryValue -Entry $entry -Name 'Path'))
        $entrySha = Assert-Sha256Hex -Value ([string](Get-CatalogEntryValue -Entry $entry -Name 'Sha256')) -Label 'sha256'
        $entryBytes = [long](Get-CatalogEntryValue -Entry $entry -Name 'Bytes')
        if ($entryBytes -lt 0) { throw "Negative byte count for '$entryPath'." }
        if ($expected.ContainsKey($entryPath)) { throw "Duplicate catalog entry '$entryPath'." }
        $expected.Add($entryPath, [pscustomobject]@{ Path = $entryPath; Bytes = $entryBytes; Sha256 = $entrySha })
    }
    if ($expected.Count -eq 0) { throw 'Expand-SelectedAsset requires at least one catalog entry.' }

    $archive = $null
    try {
        $archive = [IO.Compression.ZipFile]::Open($ArchivePath, [IO.Compression.ZipArchiveMode]::Read)

        $members = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
        $rawTotal = [long]0
        if ($archive.Entries.Count -gt $script:MaxCatalogEntries) { throw "Too many ZIP entries." }
        foreach ($zipEntry in $archive.Entries) {
            $name = $zipEntry.FullName
            if ([string]::IsNullOrEmpty($name)) { throw 'Archive contains an entry with an empty name.' }

            $canonical = $name
            $isDirectory = $canonical.EndsWith('/')
            if ($isDirectory) { $canonical = $canonical.TrimEnd('/') }
            if ($canonical.Length -eq 0) { throw 'Archive contains an entry with an empty name.' }
            [void](Assert-RelativePath -RelativePath $canonical)

            # Unix mode bits live in the high 16 bits of ExternalAttributes.
            $unixMode = ($zipEntry.ExternalAttributes -shr 16) -band 0xFFFF
            if (($unixMode -band 0xF000) -eq 0xA000) {
                throw "Archive entry is a symlink and will not be extracted: '$name'."
            }
            if ($isDirectory) { continue }

            if ($members.ContainsKey($canonical)) { throw "Archive contains a duplicate entry: '$canonical'." }
            $members.Add($canonical, $zipEntry)
            if ($zipEntry.Length -lt 0) { throw "Archive entry '$canonical' declares an invalid length." }
            $rawTotal += $zipEntry.Length
            if ($rawTotal -gt $script:MaxZipRawBytes) { throw 'Archive raw size exceeds the 4 GiB cap.' }

        }

        # Deleted/obsolete members are tolerated: they are simply never written.
        foreach ($path in $expected.Keys) {
            if (-not $members.ContainsKey($path)) { throw "Archive is missing the expected member '$path'." }
        }

        $extracted = 0
        foreach ($path in $expected.Keys) {
            $meta = $expected[$path]
            $target = Resolve-SafeChild -Root $stageFull -RelativePath $path
            if ($members[$path].Length -ne $meta.Bytes) { throw "ZIP size differs from catalog: $path" }

            $targetDir = [IO.Path]::GetDirectoryName($target)
            [void][IO.Directory]::CreateDirectory($targetDir)

            if ([IO.File]::Exists($target)) {
                $existing = Get-Item -LiteralPath $target -Force
                if ($existing.Length -ne $meta.Bytes) { throw "Staged file has the wrong length: '$target'." }
                if ((Get-Sha256 -Path $target) -cne $meta.Sha256) { throw "Staged file failed hash verification: '$target'." }
                continue
            }

            $zipEntry = $members[$path]
            $temp = [IO.Path]::Combine($targetDir, ('{0}.{1}.part' -f [IO.Path]::GetFileName($target), [Guid]::NewGuid().ToString('N')))
            $tempCreated = $false
            try {
                $source = $zipEntry.Open()
                try {
                    $destination = New-Object System.IO.FileStream($temp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                    $tempCreated = $true
                    try {
                        $buffer = New-Object byte[] $script:BufferSize
                        $written = [long]0
                        while ($true) {
                            $read = $source.Read($buffer, 0, $buffer.Length)
                            if ($read -le 0) { break }
                            $written += $read
                            if ($written -gt $meta.Bytes) {
                                throw "Archive member '$path' is larger than the catalog declares."
                            }
                            $destination.Write($buffer, 0, $read)
                        }
                        $destination.Flush()
                    } finally {
                        $destination.Dispose()
                    }
                } finally {
                    $source.Dispose()
                }

                $staged = Get-Item -LiteralPath $temp -Force
                if ($staged.Length -ne $meta.Bytes) { throw "Archive member '$path' did not match the declared length." }
                if ((Get-Sha256 -Path $temp) -cne $meta.Sha256) { throw "Archive member '$path' failed hash verification." }

                [IO.File]::Move($temp, $target)
                $tempCreated = $false
                $extracted++
            } finally {
                if ($tempCreated -and [IO.File]::Exists($temp)) {
                    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
                }
            }
        }
        return $extracted
    } finally {
        if ($null -ne $archive) { $archive.Dispose() }
    }
}

function Assert-GameClosed {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # Reports a terminating error to the caller; it never kills processes itself.
    $watched = @('v2game', 'victoria2', 'tgcnv_cache_handoff', 'TGCNV', 'map_worker', 'flag_cache_cpu')
    $running = New-Object System.Collections.ArrayList
    foreach ($name in $watched) {
        $processes = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
        if ($processes.Count -gt 0) { [void]$running.Add($name) }
    }
    if ($running.Count -gt 0) {
        throw ("Close these processes before continuing: {0}." -f ($running -join ', '))
    }
}

function Take-UpdateMutex {
    [CmdletBinding()]
    param([int]$TimeoutSeconds = 30)

    if ($TimeoutSeconds -lt 1) { throw 'TimeoutSeconds must be positive.' }

    # Separate from Local\TGCNV_DistributionSetup: the signed Setup may be launched
    # later while this mutex is still held.
    $createdNew = $false
    $mutex = New-Object System.Threading.Mutex($false, $script:UpdateMutexName, [ref]$createdNew)
    $acquired = $false
    try {
        try { $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds), $false) }
        catch [Threading.AbandonedMutexException] { $acquired = $true }
        if (-not $acquired) {
            throw "Another TGCNV online update is already running ('$($script:UpdateMutexName)')."
        }
    } catch {
        $mutex.Dispose()
        throw
    }
    # Caller owns the handle and must call ReleaseMutex() then Dispose().
    return $mutex
}

Export-ModuleMember -Function @(
    'Assert-NoReparsePoint',
    'Assert-Integer',
    'Get-Sha256',
    'Assert-RelativePath',
    'Resolve-SafeChild',
    'Assert-GitHubAssetUrl',
    'Receive-VerifiedFile',
    'Receive-LimitedBytes',
    'Test-ChannelSignature',
    'Read-ValidatedCatalog',
    'Expand-SelectedAsset',
    'Assert-GameClosed',
    'Take-UpdateMutex'
)
