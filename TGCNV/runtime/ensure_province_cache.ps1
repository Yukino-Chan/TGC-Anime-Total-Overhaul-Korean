# Automatic, isolated province-ID preparation. The game bridge consumes the
# prepared component; this script never installs an active map cache.
[CmdletBinding()]
param(
    [string]$SourceBitmap,
    [string]$Definitions,
    [int]$MaxProvinces = 0,
    [ValidateRange(1, 300)][int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'

function Get-ProvinceCanonicalFile([string]$Path) {
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Expected a regular input file: $Path"
    }
    return $item.FullName
}

function Get-ProvinceStreamHash([IO.Stream]$Stream) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $Stream.Position = 0
        $value = [BitConverter]::ToString($hash.ComputeHash($Stream)).Replace('-', '').ToLowerInvariant()
        $Stream.Position = 0
        return $value
    } finally { $hash.Dispose() }
}

function Get-ProvinceHash([string]$Path) {
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'Read')
    try { return Get-ProvinceStreamHash $stream } finally { $stream.Dispose() }
}

function Get-ProvinceTextHash([string]$Text) {
    $stream = New-Object IO.MemoryStream(,[Text.Encoding]::UTF8.GetBytes($Text))
    try { return Get-ProvinceStreamHash $stream } finally { $stream.Dispose() }
}

function Get-ProvinceLimit([string]$DefaultMap) {
    $content = [IO.File]::ReadAllText($DefaultMap)
    $content = [regex]::Replace($content, '#[^\r\n]*', '')
    $found = [regex]::Matches($content, '\bmax_provinces\s*=\s*([^\s{}]+)')
    if ($found.Count -ne 1 -or $found[0].Groups[1].Value -notmatch '^[0-9]+$') {
        throw 'default.map must contain exactly one integer max_provinces'
    }
    $count = [int]$found[0].Groups[1].Value
    if ($count -lt 2 -or $count -gt 65536) { throw 'max_provinces must be in [2, 65536]' }
    return $count
}

function Assert-ProvinceWorker([IO.Stream]$Stream) {
    $reader = New-Object IO.BinaryReader($Stream, [Text.Encoding]::UTF8, $true)
    try {
        $Stream.Position = 0
        if ($reader.ReadUInt16() -ne 0x5a4d) { throw 'Worker lacks an MZ header' }
        $Stream.Position = 60
        $offset = $reader.ReadUInt32()
        if ($offset -gt $Stream.Length - 26) { throw 'Worker PE header is truncated' }
        $Stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw 'Automatic map worker must be AMD64'
        }
        $Stream.Position = $offset + 24
        if ($reader.ReadUInt16() -ne 0x20b) { throw 'Automatic map worker must be PE32+' }
    } finally { $reader.Dispose(); $Stream.Position = 0 }
}

function Get-ProvinceLayout([string]$Path) {
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'Read')
    $reader = New-Object IO.BinaryReader($stream)
    try {
        $header = $reader.ReadBytes(54)
        if ($header.Length -ne 54) { throw 'Generated province cache header is truncated' }
        $width = [BitConverter]::ToInt32($header, 18)
        $height = [BitConverter]::ToInt32($header, 22)
        if ($width -le 0 -or $height -le 0 -or ($width % 2) -ne 0) { throw 'Invalid province cache dimensions' }
        $expected = New-Object byte[] 54
        $expected[0] = 66; $expected[1] = 77
        [BitConverter]::GetBytes([uint32]($width + 3L * $height + 110)).CopyTo($expected, 2)
        [BitConverter]::GetBytes([uint32]54).CopyTo($expected, 10)
        [BitConverter]::GetBytes([uint32]40).CopyTo($expected, 14)
        [BitConverter]::GetBytes($width).CopyTo($expected, 18)
        [BitConverter]::GetBytes($height).CopyTo($expected, 22)
        [BitConverter]::GetBytes([uint16]1).CopyTo($expected, 26)
        [BitConverter]::GetBytes([uint16]16).CopyTo($expected, 28)
        [BitConverter]::GetBytes([uint32]2834).CopyTo($expected, 38)
        [BitConverter]::GetBytes([uint32]2834).CopyTo($expected, 42)
        if ([Convert]::ToBase64String($header) -cne [Convert]::ToBase64String($expected) -or
            $stream.Length -ne 54L + 2L * $width * $height) { throw 'Province cache differs from the pinned native format' }
        return [ordered]@{ width = $width; height = $height; bytes = $stream.Length }
    } finally { $reader.Dispose() }
}

function Write-ProvinceBytesAtomic([string]$Path, [byte[]]$Data) {
    $temporary = $Path + '.tmp.' + [Guid]::NewGuid().ToString('N')
    $stream = [IO.File]::Open($temporary, 'CreateNew', 'Write', 'None')
    try {
        $stream.Write($Data, 0, $Data.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    try {
        # Windows PowerShell 5.1 coerces $null to an empty string for this
        # overload. NullString preserves the null backup path File.Replace needs.
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Write-ProvinceJsonAtomic([string]$Path, $Value) {
    Write-ProvinceBytesAtomic $Path ([Text.Encoding]::UTF8.GetBytes(($Value | ConvertTo-Json -Depth 12) + "`n"))
}

function Get-ProvinceConsumerBytes($Inputs, $OutputHash, $Layout, [int]$Limit) {
    $stream = New-Object IO.MemoryStream
    $writer = New-Object IO.BinaryWriter($stream, [Text.Encoding]::ASCII, $true)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes('TGCNVM01'))
        # Fixed 212-byte ABI: magic, 6 SHA256 digests, 3 uint32 little endian.
        $hashes = @($Inputs['provinces.bmp'].sha256, $Inputs['definition.csv'].sha256,
            $Inputs.worker.sha256, $Inputs.game.sha256, $Inputs['default.map'].sha256, $OutputHash)
        foreach ($hash in $hashes) {
            if ($hash -cnotmatch '^[0-9a-f]{64}$') { throw 'Invalid consumer digest' }
            for ($i = 0; $i -lt 64; $i += 2) { $writer.Write([Convert]::ToByte($hash.Substring($i, 2), 16)) }
        }
        $writer.Write([uint32]$Layout.width)
        $writer.Write([uint32]$Layout.height)
        $writer.Write([uint32]$Limit)
        $writer.Flush()
        return ,$stream.ToArray()
    } finally { $writer.Dispose(); $stream.Dispose() }
}

function Invoke-ProvinceWorker([string]$Worker, [string]$Bitmap, [string]$Palette,
                               [string]$Output, [int]$Limit, [int]$Timeout) {
    # All paths are files (no trailing slash); quotes cannot occur in Windows
    # filenames. No shell parses these arguments, including spaces or Unicode.
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Worker
    $start.Arguments = '--provinces "' + $Bitmap + '" --definitions "' + $Palette +
        '" --output "' + $Output + '" --max-provinces ' + $Limit
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Could not start the AMD64 map worker' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($Timeout * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            throw "Map worker exceeded its $Timeout second timeout"
        }
        $process.WaitForExit()
        $outputText = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        [IO.File]::WriteAllText((Join-Path (Split-Path $Output -Parent) 'worker.stdout.log'), $outputText)
        [IO.File]::WriteAllText((Join-Path (Split-Path $Output -Parent) 'worker.stderr.log'), $errorText)
        if ($process.ExitCode -ne 0) { throw "Map worker failed ($($process.ExitCode)): $errorText" }
        $summary = $outputText | ConvertFrom-Json
        if ($summary.pointer_bits -ne 64) { throw 'Worker did not report a 64-bit process' }
        return $summary
    } finally { $process.Dispose() }
}

function Invoke-ProvinceCacheStage([string]$Bitmap, [string]$Palette, [string]$DefaultMap,
                                  [string]$Worker, [string]$Game, [string]$StageRoot,
                                  [int]$Timeout = 300) {
    $names = @('provinces.bmp', 'definition.csv', 'default.map', 'worker', 'game')
    $paths = @($Bitmap, $Palette, $DefaultMap, $Worker, $Game)
    $streams = @()
    $stageLock = $null
    $pending = $null
    try {
        [IO.Directory]::CreateDirectory($StageRoot) | Out-Null
        $StageRoot = (Get-Item -LiteralPath $StageRoot).FullName
        if ((Get-Item -LiteralPath $StageRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Automatic stage root must not be a reparse point'
        }
        $stageLock = [IO.File]::Open((Join-Path $StageRoot 'preflight.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
        $inputs = [ordered]@{}
        for ($i = 0; $i -lt $paths.Count; ++$i) {
            $path = Get-ProvinceCanonicalFile $paths[$i]
            $stream = [IO.File]::Open($path, 'Open', 'Read', 'Read')
            $streams += $stream
            $inputs[$names[$i]] = [ordered]@{ path = $path; bytes = $stream.Length; sha256 = (Get-ProvinceStreamHash $stream) }
        }
        Assert-ProvinceWorker $streams[3]
        $limit = Get-ProvinceLimit $inputs['default.map'].path
        $identityText = 'TGCNV_PROVINCE_AUTO_V1' + "`n"
        foreach ($name in $names) {
            $identityText += $name + ':' + $inputs[$name].sha256 + ':' + $inputs[$name].path.ToLowerInvariant() + "`n"
        }
        $identity = Get-ProvinceTextHash $identityText
        $stage = Join-Path $StageRoot $identity
        $manifestPath = Join-Path $stage 'manifest.json'
        $reused = $false
        if ([IO.Directory]::Exists($stage)) {
            if ((Get-Item -LiteralPath $stage).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Stage must not be a reparse point' }
            $manifest = [IO.File]::ReadAllText((Get-ProvinceCanonicalFile $manifestPath)) | ConvertFrom-Json
            if ($manifest.schema -ne 1 -or $manifest.identity -cne $identity -or $manifest.status -cne 'PREPARED' -or
                $manifest.max_provinces -ne $limit) { throw 'Existing stage manifest is invalid' }
            $output = Get-ProvinceCanonicalFile (Join-Path $stage 'provincecache.bin')
            $layout = Get-ProvinceLayout $output
            if ((Get-ProvinceHash $output) -cne $manifest.output.sha256 -or $layout.bytes -ne $manifest.output.bytes -or
                $layout.width -ne $manifest.layout.width -or $layout.height -ne $manifest.layout.height) {
                throw 'Existing stage output failed hash or layout verification'
            }
            foreach ($name in $names) {
                if ($manifest.inputs.$name.sha256 -cne $inputs[$name].sha256 -or $manifest.inputs.$name.path -cne $inputs[$name].path) {
                    throw 'Existing stage input identity differs'
                }
            }
            for ($i = 0; $i -lt 3; ++$i) {
                $snapshot = Get-ProvinceCanonicalFile (Join-Path (Join-Path $stage 'inputs') $names[$i])
                if ((Get-ProvinceHash $snapshot) -cne $inputs[$names[$i]].sha256) { throw 'Existing staged source differs' }
            }
            $reused = $true
        } else {
            $pending = Join-Path $StageRoot ('.pending.' + [Guid]::NewGuid().ToString('N'))
            $snapshots = Join-Path $pending 'inputs'
            [IO.Directory]::CreateDirectory($snapshots) | Out-Null
            for ($i = 0; $i -lt 3; ++$i) {
                $snapshot = Join-Path $snapshots $names[$i]
                $destination = [IO.File]::Open($snapshot, 'CreateNew', 'Write', 'None')
                try { $streams[$i].Position = 0; $streams[$i].CopyTo($destination); $destination.Flush($true) }
                finally { $destination.Dispose() }
                if ((Get-ProvinceHash $snapshot) -cne $inputs[$names[$i]].sha256) { throw 'Snapshot copy differs from input' }
            }
            $output = Join-Path $pending 'provincecache.bin'
            $summary = Invoke-ProvinceWorker $inputs.worker.path (Join-Path $snapshots 'provinces.bmp') `
                (Join-Path $snapshots 'definition.csv') $output $limit $Timeout
            $layout = Get-ProvinceLayout $output
            if ($summary.width -ne $layout.width -or $summary.height -ne $layout.height -or $summary.output_bytes -ne $layout.bytes) {
                throw 'Worker report differs from generated output'
            }
            for ($i = 0; $i -lt 3; ++$i) {
                if ((Get-ProvinceHash (Join-Path $snapshots $names[$i])) -cne $inputs[$names[$i]].sha256) { throw 'Staged source changed' }
            }
            $manifest = [ordered]@{
                schema = 1; status = 'PREPARED'; identity = $identity
                created_utc = [DateTime]::UtcNow.ToString('o'); max_provinces = $limit
                inputs = $inputs; layout = $layout; worker_result = $summary
                output = [ordered]@{ path = (Join-Path $stage 'provincecache.bin'); bytes = $layout.bytes; sha256 = (Get-ProvinceHash $output) }
                installed = $false; whole_map_ready = $false
            }
            Write-ProvinceJsonAtomic (Join-Path $pending 'manifest.json') $manifest
            Write-ProvinceBytesAtomic (Join-Path $pending 'consumer.bin') `
                (Get-ProvinceConsumerBytes $inputs $manifest.output.sha256 $layout $limit)
            [IO.Directory]::Move($pending, $stage)
            $pending = $null
        }
        $consumer = [IO.File]::ReadAllBytes((Get-ProvinceCanonicalFile (Join-Path $stage 'consumer.bin')))
        $expectedConsumer = Get-ProvinceConsumerBytes $inputs $manifest.output.sha256 $layout $limit
        if ([Convert]::ToBase64String($consumer) -cne [Convert]::ToBase64String($expectedConsumer)) {
            throw 'Consumer manifest differs from the validated inputs or output'
        }
        # FileShare.Read source handles still prevent source writes or deletion.
        # Publish this pointer only after the complete immutable stage is ready.
        Write-ProvinceJsonAtomic (Join-Path $StageRoot 'current.json') $manifest
        Write-ProvinceBytesAtomic (Join-Path $StageRoot 'current.txt') ([Text.Encoding]::UTF8.GetBytes($identity + "`n"))
        return [ordered]@{ status = $(if ($reused) { 'reused' } else { 'prepared' }); identity = $identity;
            manifest = $manifestPath; output = (Join-Path $stage 'provincecache.bin'); max_provinces = $limit }
    } catch {
        if ($pending -and [IO.Directory]::Exists($pending)) {
            Write-ProvinceJsonAtomic (Join-Path $pending 'failed.json') @{ status = 'FAILED'; error = $_.Exception.Message }
        }
        throw
    } finally {
        foreach ($stream in $streams) { $stream.Dispose() }
        if ($stageLock) { $stageLock.Dispose() }
    }
}

function Invoke-ProvinceCacheAutomatic {
    $modRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $gameRoot = [IO.Path]::GetFullPath((Join-Path $modRoot '../..'))
    $bitmap = Get-ProvinceCanonicalFile (Join-Path $modRoot 'map/provinces.bmp')
    $palette = Get-ProvinceCanonicalFile (Join-Path $modRoot 'map/definition.csv')
    $defaultMap = Get-ProvinceCanonicalFile (Join-Path $modRoot 'map/default.map')
    $game = Get-ProvinceCanonicalFile (Join-Path $gameRoot 'v2game.exe')
    if ((Get-ProvinceHash $game) -cne '62d48c204364dd706584777c2e2b3c7ab3c5f1dd0170872554943575d53d6648') {
        throw 'Unsupported Victoria II executable; native format profile is pinned'
    }
    $limit = Get-ProvinceLimit $defaultMap
    # A runtime bridge may supply its VFS-resolved paths. Only the investigated
    # TGCNV input pair is enabled until another map profile is verified.
    if ($SourceBitmap -or $Definitions -or $MaxProvinces) {
        if (-not $SourceBitmap -or -not $Definitions -or $MaxProvinces -ne $limit -or
            (Get-ProvinceCanonicalFile $SourceBitmap) -ine $bitmap -or
            (Get-ProvinceCanonicalFile $Definitions) -ine $palette) { throw 'Runtime map inputs differ from the supported TGCNV profile' }
    }
    $mapText = [regex]::Replace([IO.File]::ReadAllText($defaultMap), '#[^\r\n]*', '')
    $provinceFields = [regex]::Matches($mapText, '(?m)^\s*provinces\s*=\s*"([^"]+)"\s*$')
    $paletteFields = [regex]::Matches($mapText, '(?m)^\s*definitions\s*=\s*"([^"]+)"\s*$')
    if ($provinceFields.Count -ne 1 -or $provinceFields[0].Groups[1].Value -cne 'provinces.bmp' -or
        $paletteFields.Count -ne 1 -or $paletteFields[0].Groups[1].Value -notin @('definition.csv', '../mod/TGCNV/map/definition.csv')) {
        throw 'default.map redirects the supported province inputs'
    }
    return Invoke-ProvinceCacheStage $bitmap $palette $defaultMap (Join-Path $PSScriptRoot 'map_worker.exe') `
        $game (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TGCNV/cache/province') $TimeoutSeconds
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        $result = Invoke-ProvinceCacheAutomatic
        $result | ConvertTo-Json -Compress
        exit 0
    } catch {
        [Console]::Error.WriteLine('Automatic province-cache preparation failed: ' + $_.Exception.Message)
        exit 1
    }
}
