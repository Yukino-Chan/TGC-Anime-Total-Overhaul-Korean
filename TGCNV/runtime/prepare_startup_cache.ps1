# prepare_startup_cache.ps1
# Runtime pre-launch cache preparation for TGCNV.
# Deployed beside ensure_province_cache.ps1, map_worker.exe, and flag_cache_cpu.exe.
# Dot-source this file to test functions with fixture paths; the main entry is
# only executed when the script is run directly.

$ErrorActionPreference = 'Stop'

function Get-StartupStreamHash([IO.Stream]$Stream) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $Stream.Position = 0
        $value = [BitConverter]::ToString($hash.ComputeHash($Stream)).Replace('-', '').ToLowerInvariant()
        $Stream.Position = 0
        return $value
    } finally { $hash.Dispose() }
}

function Get-StartupFileHash([string]$Path) {
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'Read')
    try { return Get-StartupStreamHash $stream } finally { $stream.Dispose() }
}

function Assert-FlagWorker([IO.Stream]$Stream) {
    $reader = New-Object IO.BinaryReader($Stream, [Text.Encoding]::UTF8, $true)
    try {
        $Stream.Position = 0
        if ($reader.ReadUInt16() -ne 0x5a4d) { throw 'Flag worker lacks an MZ header' }
        $Stream.Position = 60
        $offset = $reader.ReadUInt32()
        if ($offset -gt $Stream.Length - 26) { throw 'Flag worker PE header is truncated' }
        $Stream.Position = $offset
        if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) {
            throw 'Flag worker must be AMD64'
        }
        $Stream.Position = $offset + 24
        if ($reader.ReadUInt16() -ne 0x20b) { throw 'Flag worker must be PE32+' }
    } finally { $reader.Dispose(); $Stream.Position = 0 }
}

function Get-FlagDdsInfo([string]$Path) {
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'Read')
    try {
        $length = $stream.Length
        if ($length -lt 128) { return @{ valid = $false; reason = 'DDS header truncated' } }
        $header = New-Object byte[] 128
        if ($stream.Read($header, 0, 128) -ne 128) { return @{ valid = $false; reason = 'DDS header short read' } }
        if ([BitConverter]::ToUInt32($header, 0) -ne 0x20534444) { return @{ valid = $false; reason = 'DDS magic mismatch' } }
        if ([BitConverter]::ToUInt32($header, 4) -ne 124 -or [BitConverter]::ToUInt32($header, 76) -ne 32) { return @{ valid = $false; reason = 'DDS header size mismatch' } }
        $height = [BitConverter]::ToUInt32($header, 12)
        $width = [BitConverter]::ToUInt32($header, 16)
        $mipCount = [BitConverter]::ToUInt32($header, 28)
        if ($mipCount -eq 0) { $mipCount = 1 }
        $pfFlags = [BitConverter]::ToUInt32($header, 80)
        $fourCC = [BitConverter]::ToUInt32($header, 84)
        $format = $null
        if ($pfFlags -band 0x4) {
            switch ($fourCC) {
                0x31545844 { $format = 'DXT1' }
                0x35545844 { $format = 'DXT5' }
                default { $format = 'UNKNOWN' }
            }
        } else { $format = 'UNCOMPRESSED' }
        $expectedLength = -1
        if ($format -eq 'DXT1') { $expectedLength = 128 + 4194304 }
        elseif ($format -eq 'DXT5') { $expectedLength = 128 + 8388608 }
        $valid = ($format -in @('DXT1','DXT5')) -and ($width -eq 4096) -and ($height -eq 2048) -and
                 ($mipCount -eq 1) -and ($length -eq $expectedLength)
        return @{
            valid = $valid
            reason = $(if (-not $valid) { "DDS header mismatch: $format ${width}x${height} mips=$mipCount len=$length" } else { $null })
            format = $format; width = $width; height = $height; mip_count = $mipCount; length = $length
        }
    } finally { $stream.Dispose() }
}

function Get-FlagTgaInfo([string]$Path) {
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'Read')
    try {
        if ($stream.Length -lt 18) { return @{ valid = $false; reason = 'TGA header truncated' } }
        $header = New-Object byte[] 18
        if ($stream.Read($header, 0, 18) -ne 18) { return @{ valid = $false; reason = 'TGA header short read' } }
        $imageType = $header[2]
        $width = [BitConverter]::ToUInt16($header, 12)
        $height = [BitConverter]::ToUInt16($header, 14)
        $pixelDepth = $header[16]
        $valid = ($imageType -eq 2) -and ($width -eq 4096) -and ($height -eq 2048) -and ($pixelDepth -eq 32)
        return @{
            valid = $valid
            reason = $(if (-not $valid) { "TGA header mismatch: type=$imageType ${width}x${height} depth=$pixelDepth" } else { $null })
            image_type = $imageType; width = $width; height = $height; pixel_depth = $pixelDepth
        }
    } finally { $stream.Dispose() }
}

function Invoke-FlagConverter([string]$Worker, [string]$InputPath, [string]$OutputPath, [int]$TimeoutSeconds) {
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Worker
    $start.Arguments = '--convert-cpu "' + $InputPath + '" "' + $OutputPath + '"'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'Could not start flag CPU converter' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            throw "Flag CPU converter exceeded its $TimeoutSeconds second timeout"
        }
        $process.WaitForExit()
        $outputText = $stdout.GetAwaiter().GetResult()
        $errorText = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "Flag CPU converter failed ($($process.ExitCode)): $errorText" }
        return $outputText | ConvertFrom-Json
    } finally { $process.Dispose() }
}

function Assert-FlagConverterEvidence($Summary, [string]$ExpectedSourceHash, [long]$ExpectedSourceLength) {
    foreach ($field in @('ok','cpu_only','source_unchanged')) {
        if ($Summary.$field -isnot [bool] -or -not $Summary.$field) { throw "Converter boolean evidence missing: $field" }
    }
    if ($Summary.mode -cne 'convert_cpu' -or $Summary.pointer_bits -ne 64) { throw 'Converter execution mode differs' }
    if ($Summary.source_sha256 -cne $ExpectedSourceHash -or $Summary.source_file_bytes -ne $ExpectedSourceLength) { throw 'Converter input evidence differs' }
    if ($Summary.output_sha256 -cnotmatch '^[0-9a-f]{64}$' -or $Summary.output_file_bytes -notin @(4194432,8388736)) { throw 'Converter output evidence missing' }
    if ($null -eq $Summary.decoded_error.alpha_mismatch_pixels -or $Summary.decoded_error.alpha_mismatch_pixels -ne 0) { throw 'Converter alpha verification missing or failed' }
    if ($Summary.dds.width -ne 4096 -or $Summary.dds.height -ne 2048 -or $Summary.dds.mips -ne 1 -or $Summary.dds.format -notin @('DXT1','DXT5')) { throw 'Converter DDS evidence differs' }
    if ($Summary.dds.format -eq 'DXT1' -and ($Summary.decoded_error.source_alpha_min -ne 255 -or $Summary.decoded_error.output_alpha_min -ne 255)) { throw 'BC1 conversion is not opaque' }
}

function Copy-StartupVerified([string]$SourcePath, [string]$DestinationPath, [string]$ExpectedHash) {
    $source = [IO.File]::Open($SourcePath, 'Open', 'Read', 'Read')
    try {
        $dest = [IO.File]::Open($DestinationPath, 'CreateNew', 'Write', 'None')
        try {
            $source.Position = 0
            $source.CopyTo($dest)
            $dest.Flush($true)
        } finally { $dest.Dispose() }
    } finally { $source.Dispose() }
    $actual = Get-StartupFileHash $DestinationPath
    if ($actual -cne $ExpectedHash) { throw "Backup hash mismatch for $SourcePath" }
}

function Assert-NoV2Game {
    $procs = Get-Process -Name v2game -ErrorAction SilentlyContinue
    if ($procs) { throw 'Victoria II (v2game.exe) is running' }
}

function Write-StartupJsonAtomic([string]$Path, $Value) {
    $json = ($Value | ConvertTo-Json -Depth 12 -Compress) + "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $temporary = $Path + '.tmp.' + [Guid]::NewGuid().ToString('N')
    $stream = [IO.File]::Open($temporary, 'CreateNew', 'Write', 'None')
    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    } finally { $stream.Dispose() }
    try {
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Invoke-FlagCompression {
    param(
        [Parameter(Mandatory=$true)][string]$FlagsRoot,
        [Parameter(Mandatory=$true)][string]$StageRoot,
        [Parameter(Mandatory=$true)][string]$Worker,
        [int]$TimeoutSeconds = 90
    )
    $allowed = @(
        'flagfiles', 'flagfiles_communist', 'flagfiles_dominion', 'flagfiles_dominion2',
        'flagfiles_dominion3', 'flagfiles_fascist', 'flagfiles_monarchy', 'flagfiles_monarchy2',
        'flagfiles_republic', 'flagfiles_republic2', 'flagfiles_theocracy'
    )
    if (-not [IO.Directory]::Exists($FlagsRoot)) { return @{ generated=0; reused=0; skipped=0; errors=@(); reason='No generated flag atlases yet' } }
    $flagsRootCanonical = (Get-Item -LiteralPath $FlagsRoot -ErrorAction Stop).FullName
    if ((Get-Item -LiteralPath $flagsRootCanonical).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw 'Flags root must not be a reparse point'
    }

    Assert-NoV2Game
    $workerCanonical = (Get-Item -LiteralPath $Worker -ErrorAction Stop).FullName
    if ((Get-Item -LiteralPath $workerCanonical).PSIsContainer) { throw 'Worker is a directory' }
    $workerStream = [IO.File]::Open($workerCanonical, 'Open', 'Read', 'Read')
    try {
    Assert-FlagWorker $workerStream
    if ((Get-StartupStreamHash $workerStream) -cne '4af31ca55ba6ef1559c4be88f8ae90aacb186815f5556f3f89c02b65482a5faf') { throw 'Flag CPU converter hash mismatch' }
    $stageDir = $null
    $report = [ordered]@{
        generated = 0
        reused = 0
        skipped = 0
        errors = @()
    }

    $tgaFiles = @(Get-ChildItem -LiteralPath $flagsRootCanonical -Filter 'flagfiles*.tga' -File -ErrorAction Stop |
        Where-Object { $allowed -contains [IO.Path]::GetFileNameWithoutExtension($_.Name) } |
        Sort-Object Name)

    foreach ($file in $tgaFiles) {
        $sourcePath = $file.FullName
        $base = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $indexPath = Join-Path $file.DirectoryName ($base + '.txt')
        if (-not [IO.File]::Exists($indexPath)) {
            $report.skipped++
            $report.errors += @{ file = $sourcePath; error = "Missing index file: $indexPath" }
            continue
        }

        $sourceStream = $null
        $indexStream = $null
        $tempOutput = $null
        try {
            foreach ($checked in @($sourcePath,$indexPath)) {
                $item = Get-Item -LiteralPath $checked
                if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Atlas and index must be regular files' }
            }
            $sourceStamp = Get-Item -LiteralPath $sourcePath
            $creationUtc = $sourceStamp.CreationTimeUtc
            $writeUtc = $sourceStamp.LastWriteTimeUtc
            $accessUtc = $sourceStamp.LastAccessTimeUtc
            $sourceStream = [IO.File]::Open($sourcePath, 'Open', 'Read', 'Read')
            $indexStream = [IO.File]::Open($indexPath, 'Open', 'Read', 'Read')
            $sourceHash = Get-StartupStreamHash $sourceStream
            $indexHash = Get-StartupStreamHash $indexStream
            $sourceLength = $sourceStream.Length

            $ddsInfo = Get-FlagDdsInfo $sourcePath
            if ($ddsInfo.valid) {
                $report.reused++
                continue
            }

            $tgaInfo = Get-FlagTgaInfo $sourcePath
            if (-not $tgaInfo.valid) {
                $report.skipped++
                $report.errors += @{ file = $sourcePath; error = $tgaInfo.reason }
                continue
            }

            if (-not $stageDir) {
                $stageDir = Join-Path $StageRoot ([Guid]::NewGuid().ToString('N'))
                [IO.Directory]::CreateDirectory($stageDir) | Out-Null
            }
            $backupSource = Join-Path $stageDir ($base + '.source.bak')
            $backupIndex = Join-Path $stageDir ($base + '.index.bak')
            Copy-StartupVerified $sourcePath $backupSource $sourceHash
            Copy-StartupVerified $indexPath $backupIndex $indexHash

            Assert-NoV2Game

            $tempOutput = Join-Path $file.DirectoryName ('.' + $base + '.tmp.' + [Guid]::NewGuid().ToString('N'))
            if ([IO.File]::Exists($tempOutput)) { throw 'Temporary output already exists' }

            $summary = Invoke-FlagConverter $workerCanonical $sourcePath $tempOutput $TimeoutSeconds
            Assert-FlagConverterEvidence $summary $sourceHash $sourceLength

            $outDds = Get-FlagDdsInfo $tempOutput
            if (-not $outDds.valid) { throw "Converted output is not a valid DDS: $($outDds.reason)" }
            $tempHash = Get-StartupFileHash $tempOutput
            if ($summary.output_sha256 -cne $tempHash -or $summary.output_file_bytes -ne $outDds.length -or $summary.dds.format -cne $outDds.format) {
                throw 'Converter output hash differs from file'
            }

            $sourceStream.Dispose(); $sourceStream = $null

            $recheckSourceHash = Get-StartupFileHash $sourcePath
            if ($recheckSourceHash -cne $sourceHash) { throw 'Source file changed during conversion' }
            $recheckIndexHash = Get-StartupStreamHash $indexStream
            if ($recheckIndexHash -cne $indexHash) { throw 'Index file changed during conversion' }

            Assert-NoV2Game

            # Last-write time participates in the game's atlas freshness checks.
            [IO.File]::SetCreationTimeUtc($tempOutput, $creationUtc)
            [IO.File]::SetLastWriteTimeUtc($tempOutput, $writeUtc)
            [IO.File]::SetLastAccessTimeUtc($tempOutput, $accessUtc)
            # Existing target only: if another process removed it, leave its state alone.
            [IO.File]::Replace($tempOutput, $sourcePath, [NullString]::Value)
            $tempOutput = $null
            if ((Get-StartupFileHash $sourcePath) -cne $tempHash) { throw 'Installed atlas hash differs' }
            Write-StartupJsonAtomic (Join-Path $stageDir ($base + '.json')) ([ordered]@{
                source=$sourcePath; backup=$backupSource; index_backup=$backupIndex
                input_sha256=$sourceHash; index_sha256=$indexHash; output_sha256=$tempHash
                worker_sha256='4af31ca55ba6ef1559c4be88f8ae90aacb186815f5556f3f89c02b65482a5faf'
                original_write_utc=$writeUtc.ToString('o'); evidence=$summary
            })
            $report.generated++
        } catch {
            $report.skipped++
            $report.errors += @{ file = $sourcePath; error = $_.Exception.Message }
        } finally {
            if ($sourceStream) { $sourceStream.Dispose() }
            if ($indexStream) { $indexStream.Dispose() }
            if ($tempOutput -and [IO.File]::Exists($tempOutput)) { [IO.File]::Delete($tempOutput) }
        }
    }

    return $report
    } finally { $workerStream.Dispose() }
}

function Invoke-StartupCachePreparation {
    param(
        [string]$FlagsRoot,
        [string]$StageRoot,
        [string]$LogPath,
        [string]$Worker,
        [int]$ConverterTimeoutSeconds = 90
    )
    if (-not $FlagsRoot) {
        $FlagsRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Paradox Interactive/Victoria II/TGCNV/gfx/flags'
    }
    if (-not $StageRoot) {
        $StageRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TGCNV/cache/startup-flags'
    }
    if (-not $LogPath) {
        $LogPath = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TGCNV/logs/prelaunch-cache.json'
    }
    if (-not $Worker) {
        $Worker = Join-Path $PSScriptRoot 'flag_cache_cpu.exe'
    }

    if (-not [Environment]::Is64BitProcess) { throw 'A 64-bit PowerShell process is required' }

    $mutex = New-Object Threading.Mutex -ArgumentList @($false, 'Local\TGCNV_StartupCache_V1')
    $hasMutex = $false
    $report = [ordered]@{
        started_utc = [DateTime]::UtcNow.ToString('o')
        schema = 1
        pointer_bits = 64
        game_started = $false
        whole_map_ready = $false
        province = $null
        flags = $null
        durations = [ordered]@{}
        error = $null
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        try { $hasMutex = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $hasMutex = $true }
        if (-not $hasMutex) { throw 'Another startup cache preparation is active' }
        Assert-NoV2Game

        $ensure = Join-Path $PSScriptRoot 'ensure_province_cache.ps1'
        . $ensure
        $provinceSw = [Diagnostics.Stopwatch]::StartNew()
        $report.province = Invoke-ProvinceCacheAutomatic
        $provinceSw.Stop()
        $report.durations.province_ms = $provinceSw.ElapsedMilliseconds

        $flagSw = [Diagnostics.Stopwatch]::StartNew()
        try {
            $report.flags = Invoke-FlagCompression -FlagsRoot $FlagsRoot -StageRoot $StageRoot -Worker $Worker -TimeoutSeconds $ConverterTimeoutSeconds
        } catch {
            # Atlas absence/corruption retains the existing in-game fallback.
            $report.flags = @{ generated=0; reused=0; skipped=0; errors=@($_.Exception.Message) }
        }
        $flagSw.Stop()
        $report.durations.flags_ms = $flagSw.ElapsedMilliseconds
    } catch {
        $report.error = $_.Exception.Message
        throw
    } finally {
        $sw.Stop()
        $report.durations.total_ms = $sw.ElapsedMilliseconds
        $report.finished_utc = [DateTime]::UtcNow.ToString('o')
        try {
            $logDir = Split-Path $LogPath -Parent
            if ($logDir) { [IO.Directory]::CreateDirectory($logDir) | Out-Null }
            Write-StartupJsonAtomic $LogPath $report
        } catch { }
        if ($hasMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-StartupCachePreparation
        exit 0
    } catch {
        [Console]::Error.WriteLine('Startup cache preparation failed: ' + $_.Exception.Message)
        exit 1
    }
}
