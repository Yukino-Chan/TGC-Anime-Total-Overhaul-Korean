#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Install','Verify','Restore')][string]$Action = 'Install',
    [string]$GamePath,
    [string]$DocumentsPath,
    [string]$BackupId,
    [ValidateSet('Auto','ko','en')][string]$Language='Auto'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PackRoot = $PSScriptRoot
$ownedStages=New-Object 'Collections.Generic.List[object]'
Import-Module (Join-Path $PackRoot 'Language.psm1') -Force -DisableNameChecking

function Hash-File([string]$Path) {
    $s = [IO.File]::OpenRead($Path)
    $h = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($h.ComputeHash($s)).Replace('-','').ToLowerInvariant() }
    finally { $s.Dispose(); $h.Dispose() }
}
function Hash-Bytes([byte[]]$Bytes) {
    $h = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($h.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant() }
    finally { $h.Dispose() }
}
function Get-LauncherTokens([string]$Text) {
    $tokens = New-Object 'Collections.Generic.List[object]'
    $i = 0
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if ([char]::IsWhiteSpace($c)) { $i++; continue }
        if ($c -eq '#') {
            while ($i -lt $Text.Length -and $Text[$i] -ne "`r" -and $Text[$i] -ne "`n") { $i++ }
            continue
        }
        $start = $i
        if ($c -eq '"' -or $c -eq "'") {
            $quote = $c
            $i++
            $closed = $false
            while ($i -lt $Text.Length) {
                if ($Text[$i] -eq '\') { $i += 2; continue }
                if ($Text[$i] -eq $quote) { $closed = $true; $i++; break }
                $i++
            }
            if (-not $closed) { throw '런처 설정의 문자열이 닫히지 않았습니다.' }
            $raw = $Text.Substring($start, $i - $start)
            $tokens.Add([pscustomobject]@{ kind='string'; value=$raw.Substring(1,$raw.Length-2); raw=$raw; start=$start; end=$i })
            continue
        }
        if ('{}=,;'.IndexOf($c) -ge 0) {
            $tokens.Add([pscustomobject]@{ kind='symbol'; value=[string]$c; raw=[string]$c; start=$start; end=$start+1 })
            $i++
            continue
        }
        while ($i -lt $Text.Length) {
            $ch = $Text[$i]
            if ([char]::IsWhiteSpace($ch) -or $ch -eq '#' -or $ch -eq '"' -or $ch -eq "'" -or '{}=,;'.IndexOf($ch) -ge 0) { break }
            $i++
        }
        if ($i -eq $start) { throw "런처 설정에서 해석할 수 없는 문자입니다: $c" }
        $raw = $Text.Substring($start, $i - $start)
        $tokens.Add([pscustomobject]@{ kind='word'; value=$raw; raw=$raw; start=$start; end=$i })
    }
    return ,$tokens
}
function Get-LauncherFunctionBlocks([object[]]$Tokens) {
    $blocks = New-Object 'Collections.Generic.List[object]'
    for ($i=0; $i -lt $Tokens.Count; $i++) {
        $t = $Tokens[$i]
        if (($t.kind -eq 'word' -or $t.kind -eq 'string') -and $t.value -ceq 'function') {
            if ($i+2 -lt $Tokens.Count -and $Tokens[$i+1].kind -eq 'symbol' -and $Tokens[$i+1].value -eq '=' -and $Tokens[$i+2].kind -eq 'symbol' -and $Tokens[$i+2].value -eq '{') {
                $depth = 0
                $close = -1
                for ($j=$i+2; $j -lt $Tokens.Count; $j++) {
                    if ($Tokens[$j].kind -eq 'symbol' -and $Tokens[$j].value -eq '{') { $depth++ }
                    elseif ($Tokens[$j].kind -eq 'symbol' -and $Tokens[$j].value -eq '}') {
                        $depth--
                        if ($depth -eq 0) { $close=$j; break }
                    }
                }
                if ($close -lt 0) { throw '함수 블록의 중괄호가 맞지 않습니다.' }
                $blocks.Add([pscustomobject]@{ OpenIndex=$i+2; CloseIndex=$close; OpenStart=$Tokens[$i+2].start; CloseEnd=$Tokens[$close].end })
                $i = $close
            } elseif ($t.kind -eq 'word') {
                throw '함수 정의 형식이 올바르지 않습니다.'
            }
        }
    }
    return ,$blocks
}
function Get-LauncherLaunchPlan([string]$Text) {
    $tokens = Get-LauncherTokens $Text
    $depth = 0
    foreach ($token in $tokens) {
        if ($token.kind -eq 'symbol' -and $token.value -eq '{') { $depth++ }
        if ($token.kind -eq 'symbol' -and $token.value -eq '}') {
            $depth--
            if ($depth -lt 0) { throw '런처 설정의 중괄호가 맞지 않습니다.' }
        }
    }
    if ($depth -ne 0) { throw '런처 설정의 중괄호가 맞지 않습니다.' }
    $blocks = Get-LauncherFunctionBlocks $tokens
    $launch = $null
    foreach ($block in $blocks) {
        $type = $null
        $arg = $null
        $argToken = $null
        $j = $block.OpenIndex + 1
        while ($j -lt $block.CloseIndex) {
            $key = $tokens[$j]
            if (($key.kind -eq 'word' -or $key.kind -eq 'string') -and ($key.value -ceq 'type' -or $key.value -ceq 'arg') -and ($j+1 -lt $block.CloseIndex -and $tokens[$j+1].kind -eq 'symbol' -and $tokens[$j+1].value -eq '=')) {
                if ($j+2 -ge $block.CloseIndex) { throw '함수 인자 형식이 올바르지 않습니다.' }
                $val = $tokens[$j+2]
                if ($val.kind -ne 'word' -and $val.kind -ne 'string') { throw '함수 인자 값이 올바르지 않습니다.' }
                if ($key.value -ceq 'type') {
                    if ($null -ne $type) { throw '함수에 type이 중복되었습니다.' }
                    $type = $val.value
                } else {
                    if ($null -ne $arg) { throw '함수에 arg가 중복되었습니다.' }
                    $arg = $val.value
                    $argToken = $val
                }
                $j += 3
                continue
            }
            if ($tokens[$j].kind -eq 'symbol' -and $tokens[$j].value -eq '{') {
                throw '중첩된 런처 함수 설정은 지원하지 않습니다.'
            }
            $j++
        }
        if ($type -ceq 'launch') {
            if ($null -ne $launch) { throw 'launch 함수가 여러 개 있습니다.' }
            if ($null -eq $arg -or $null -eq $argToken) { throw 'launch 함수에 arg가 없습니다.' }
            $launch = [pscustomobject]@{ Type=$type; Arg=$arg; ArgToken=$argToken }
        }
    }
    if ($null -eq $launch) { throw 'launch 함수를 찾지 못했습니다.' }
    return $launch
}
function New-LauncherConfigPlan([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) {
        throw '런처 설정이 UTF-16 형식입니다.'
    }
    if ([Array]::IndexOf($bytes, [byte]0) -ge 0) { throw '런처 설정에 NUL 문자가 있습니다.' }
    $originalHash = Hash-Bytes $bytes
    $text = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
    $launch = Get-LauncherLaunchPlan $text
    if ($launch.ArgToken.kind -ne 'string') { throw 'launch 함수의 arg는 문자열이어야 합니다.' }
    if ($launch.Arg -cne 'v2game.exe' -and $launch.Arg -cne 'TGCNV.exe') { throw "지원하지 않는 런처 실행 파일입니다: $($launch.Arg)" }
    $modified = $bytes
    $changed = $false
    if ($launch.Arg -cne 'TGCNV.exe') {
        $quote = [string]$launch.ArgToken.raw[0]
        $replacement = $quote + 'TGCNV.exe' + $quote
        $newText = $text.Substring(0, $launch.ArgToken.start) + $replacement + $text.Substring($launch.ArgToken.end)
        $modified = [Text.Encoding]::GetEncoding(28591).GetBytes($newText)
        $changed = $true
    }
    return @{ OriginalSha256=$originalHash; Bytes=$modified; Changed=$changed }
}
function Assert-SafePath([string]$Path) {
    $p = [IO.Path]::GetFullPath($Path)
    while ($p) {
        if (Test-Path -LiteralPath $p) {
            if ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "연결 폴더(junction/symlink)는 설치 대상으로 지원하지 않습니다: $p"
            }
        }
        $parent = [IO.Path]::GetDirectoryName($p)
        if ($parent -eq $p) { break }
        $p = $parent
    }
}
function Child-Path([string]$Root,[string]$Relative,[switch]$SkipLinkCheck) {
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)') { throw '잘못된 상대 경로입니다.' }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $p = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $p.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) { throw '설치 경로가 허용된 폴더를 벗어났습니다.' }
    if (-not $SkipLinkCheck) { Assert-SafePath $p }
    return $p
}
function Assert-Closed {
    $running = @(Get-Process | Where-Object { $_.ProcessName -in @('v2game','victoria2','tgcnv_cache_handoff','TGCNV','map_worker','flag_cache_cpu') })
    if ($running.Count) { throw 'TGCNV 게임 또는 캐시 전환이 진행 중입니다. 자동 재실행이 끝난 뒤 게임과 런처를 종료하고 다시 시도해 주세요.' }
}
function Save-Json([string]$Path,$Value) {
    $temp = $Path + '.tmp'
    [IO.File]::WriteAllText($temp,($Value | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($true))
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[NullString]::Value) }
    else { [IO.File]::Move($temp,$Path) }
}
function Move-Safe([string]$From,[string]$To) {
    Assert-SafePath $From
    Assert-SafePath $To
    if (Test-Path -LiteralPath $To) { throw "대상이 이미 존재합니다: $To" }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($To)) | Out-Null
    if ([IO.Directory]::Exists($From)) { [IO.Directory]::Move($From,$To) }
    else { [IO.File]::Move($From,$To) }
}
function Verify-Payload($Manifest,[string]$Root) {
    Assert-SafePath $Root
    $index=New-Object 'Collections.Generic.Dictionary[string,IO.FileInfo]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in Get-ChildItem -LiteralPath (Join-Path $Root 'payload') -Recurse -Force) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '배포 파일에 junction/symlink가 있습니다.' }
        if (-not $item.PSIsContainer) { $index.Add($item.FullName,$item) }
    }
    if ($index.Count -ne $Manifest.files.Count) { throw 'payload 폴더에 목록과 다른 파일이 있습니다. 새 폴더에 다시 압축을 풀어 주세요.' }
    $count=0
    foreach ($entry in $Manifest.files) {
        $p=Child-Path $Root $entry.path -SkipLinkCheck
        if (-not $index.ContainsKey($p) -or $index[$p].Length -ne $entry.bytes -or (Hash-File $p) -cne $entry.sha256) {
            throw "배포 파일이 누락되거나 손상되었습니다. 압축을 다시 풀어 주세요: $($entry.path)"
        }
        $count++
        if (($count % 1000) -eq 0) { Write-Progress -Activity '배포 파일 검사' -Status "$count / $($Manifest.files.Count)" -PercentComplete (100*$count/$Manifest.files.Count) }
    }
    Write-Progress -Activity '배포 파일 검사' -Completed
}
function Game-Profile([string]$Root,[string]$Expected) {
    $path=Child-Path $Root 'v2game.exe'
    $bytes=[IO.File]::ReadAllBytes($path)
    $original=Hash-Bytes $bytes
    if ($original -ceq $Expected) { return @{ original=$original; adjust=$false; bytes=$bytes } }
    if ($bytes.Length -lt 64 -or [BitConverter]::ToUInt16($bytes,0) -ne 0x5a4d) { throw '지원하는 게임 EXE가 아닙니다.' }
    $pe=[BitConverter]::ToUInt32($bytes,60)
    if ($pe -lt 64 -or $pe -gt $bytes.Length-24 -or [BitConverter]::ToUInt32($bytes,[int]$pe) -ne 0x4550) { throw '게임 PE 헤더가 올바르지 않습니다.' }
    $bytes[$pe+22]=$bytes[$pe+22] -bor 0x20
    if ((Hash-Bytes $bytes) -cne $Expected) { throw '지원하지 않는 v2game.exe입니다. 설치 안내의 3.04 실행 파일 조건을 확인해 주세요. 파일은 변경하지 않았습니다.' }
    return @{ original=$original; adjust=$true; bytes=$bytes }
}
function Install-Path($Receipt,$Op,[ValidateSet('target','stage')][string]$Kind) {
    if ($Receipt.id -cnotmatch '^\d{8}-\d{6}-[0-9a-f]{8}$') { throw '잘못된 설치 작업 ID입니다.' }
    $root = if ($Op.scope -ceq 'game') { $Receipt.game } elseif ($Op.scope -ceq 'profile') { $Receipt.profile } else { throw '잘못된 설치 범위입니다.' }
    if ($Op.scope -ceq 'game' -and $Op.relative -cnotin @('mod/TGCNV','mod/TGCNV.mod','mod/TGO','mod/TGO.mod','lua51.dll','lua51_ori.dll','tgcnv_memory_bridge.dll','tgcnv_lua51_ori.dll','tgcnv_bootstrap_install.txt','v2game.exe','TGCNV.exe','launcher/launcher.cfg')) { throw '허용되지 않은 게임 설치 항목입니다.' }
    if ($Op.scope -ceq 'profile' -and $Op.relative -cne 'map/cache') { throw '허용되지 않은 캐시 설치 항목입니다.' }
    if ($Kind -ceq 'target') { return Child-Path $root $Op.relative }
    return Child-Path $root ("TGCNV_Install/$($Receipt.id)/stage/$($Op.relative)")
}
function Assert-PlainTree([string]$Path) {
    Assert-SafePath $Path
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $stack=New-Object 'Collections.Generic.Stack[string]'
    $stack.Push([IO.Path]::GetFullPath($Path))
    while ($stack.Count -gt 0) {
        $current=$stack.Pop()
        $item=Get-Item -LiteralPath $current -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "연결 파일이나 폴더는 덮어쓸 수 없습니다: $current" }
        if ($item.PSIsContainer) {
            foreach ($child in Get-ChildItem -LiteralPath $current -Force) {
                if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "연결 파일이나 폴더는 덮어쓸 수 없습니다: $($child.FullName)" }
                if ($child.PSIsContainer) { $stack.Push($child.FullName) }
            }
        }
    }
}
function Remove-InstallTarget($Receipt,$Op) {
    # Install-Path restricts deletion to the exact managed mod/cache/native paths.
    $target=Install-Path $Receipt $Op 'target'
    Assert-PlainTree $target
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
}
function Set-OverwriteTarget($Receipt,$Op) {
    $target=Install-Path $Receipt $Op 'target'
    $stage=Install-Path $Receipt $Op 'stage'
    Assert-PlainTree $target
    Assert-PlainTree $stage
    if (-not (Test-Path -LiteralPath $stage)) { throw "준비된 설치 파일이 없습니다: $stage" }
    if ([IO.Directory]::Exists($stage)) {
        Remove-InstallTarget $Receipt $Op
        Move-Safe $stage $target
    } elseif ([IO.File]::Exists($target)) {
        # ReplaceFile with a null backup path does not retain the previous file.
        [IO.File]::Replace($stage,$target,[NullString]::Value)
    } else {
        if (Test-Path -LiteralPath $target) { Remove-InstallTarget $Receipt $Op }
        Move-Safe $stage $target
    }
}
function Remove-OwnedStage([string]$Root,[string]$Id) {
    if ($Id -cnotmatch '^\d{8}-\d{6}-[0-9a-f]{8}$') { throw '잘못된 임시 설치 경로입니다.' }
    $stage=Child-Path $Root ("TGCNV_Install/$Id")
    Assert-PlainTree $stage
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}

function Test-OverwriteLuaRecovery($GamePath,$Profile,$Manifest,[string]$BootstrapHash,[string]$CurrentOriHash) {
    # Strict [bool] gate: permits rerunning only the SAME verified pack in overwrite mode.
    try {
        if ($null -eq $GamePath -or $null -eq $Profile -or $null -eq $Manifest) { return $false }
        if ($BootstrapHash -cnotmatch '^[0-9a-f]{64}$') { return $false }
        $oriHash = $Manifest.original_lua_sha256
        if ($oriHash -isnot [string] -or $oriHash -cnotmatch '^[0-9a-f]{64}$') { return $false }
        if ($Manifest.release -isnot [string]) { return $false }
        $raw = Get-Content -LiteralPath (Child-Path $GamePath 'TGCNV_Install/receipt.json') -Raw -Encoding UTF8 -ErrorAction Stop
        if (-not $raw.TrimStart().StartsWith('{',[StringComparison]::Ordinal)) { return $false }
        $receipt = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $receipt -or $receipt -isnot [System.Management.Automation.PSCustomObject]) { return $false }
        # Schema must be the integer 2; booleans, fractional (or any non-integer type) are rejected.
        $schema = $receipt.schema
        if ($schema -isnot [int] -and $schema -isnot [long]) { return $false }
        if ($schema -ne 2) { return $false }
        if ($receipt.mode -isnot [string] -or $receipt.mode -cne 'overwrite_no_backup') { return $false }
        if ($receipt.status -isnot [string] -or ($receipt.status -cne 'applying' -and $receipt.status -cne 'failed')) { return $false }
        if ($receipt.game -isnot [string] -or $receipt.game -ine $GamePath) { return $false }
        if ($receipt.profile -isnot [string] -or $receipt.profile -ine $Profile) { return $false }
        if ($receipt.release -isnot [string] -or $receipt.release -cne $Manifest.release) { return $false }
        if ($receipt.original_lua_sha256 -isnot [string] -or $receipt.original_lua_sha256 -cne $oriHash) { return $false }
        if ($receipt.incoming_bootstrap_sha256 -isnot [string] -or $receipt.incoming_bootstrap_sha256 -cne $BootstrapHash) { return $false }
        # Accepted current-ori states: only this pack's original or this pack's bootstrap.
        if ($CurrentOriHash -cne $oriHash -and $CurrentOriHash -cne $BootstrapHash) {
            # A fresh install can stop after saving the required original Lua,
            # before creating lua51_ori.dll for the first time.
            if ($CurrentOriHash -or (Test-Path -LiteralPath (Child-Path $GamePath 'lua51_ori.dll')) -or (Hash-File (Child-Path $GamePath 'lua51.dll')) -cne $oriHash) { return $false }
        }
        $saved = Child-Path $GamePath 'tgcnv_lua51_ori.dll'
        if (-not (Test-Path -LiteralPath $saved -PathType Leaf)) { return $false }
        if ((Hash-File $saved) -cne $oriHash) { return $false }
        return $true
    }
    catch { return $false }
}

try {
    if ($Action -eq 'Restore') { throw '이 설치기는 백업 없이 덮어씁니다. 이전 상태 복원은 제공하지 않습니다. 설치가 중단됐다면 같은 Setup.cmd를 다시 실행하세요.' }
    if ($Action -ne 'Install' -and $Language -ne 'Auto') { throw 'Language applies only to Install.' }
    $created=$false
    $setupMutex=New-Object Threading.Mutex($true,'Local\TGCNV_DistributionSetup',[ref]$created)
    if (-not $created) { throw '다른 TGCNV 설치 도구가 실행 중입니다.' }
    if (-not [Environment]::Is64BitOperatingSystem) { throw '64비트 Windows가 필요합니다.' }
    $manifest=Get-Content -LiteralPath (Join-Path $PackRoot 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schema -ne 1) { throw '지원하지 않는 배포 목록 형식입니다.' }
    if ($Action -ne 'Restore') {
        Write-Host '배포 파일의 SHA-256을 검사하고 있습니다...'
        Verify-Payload $manifest $PackRoot
        if ($Action -eq 'Verify') { Write-Host "정상: $($manifest.files.Count)개 파일을 확인했습니다."; exit 0 }
    }
    if (-not $GamePath) {
        Add-Type -AssemblyName System.Windows.Forms
        $picker=New-Object Windows.Forms.OpenFileDialog
        $picker.Title='Victoria II 설치 폴더의 v2game.exe를 선택하세요'
        $picker.Filter='Victoria II (v2game.exe)|v2game.exe'
        $picker.CheckFileExists=$true
        if ($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw '설치를 취소했습니다.' }
        $GamePath=Split-Path -Parent $picker.FileName
        $picker.Dispose()
    }
    $GamePath=[IO.Path]::GetFullPath($GamePath).TrimEnd('\')
    if ($GamePath -match '^[A-Za-z]:$') { $GamePath+='\' }
    Assert-SafePath $GamePath
    Assert-Closed
    $gameInfo=Game-Profile $GamePath $manifest.game_sha256
    if ((Hash-File (Child-Path $GamePath 'lua5.1.dll')) -cne $manifest.base_lua_sha256) { throw '지원하는 기본 lua5.1.dll이 아닙니다. 게임 파일을 확인해 주세요.' }
    if (-not (Test-Path -LiteralPath (Join-Path $GamePath 'victoria2.exe'))) { throw 'Victoria II 런처가 없는 폴더입니다.' }
    if (-not $DocumentsPath) { $DocumentsPath=[Environment]::GetFolderPath('MyDocuments') }
    if (-not $DocumentsPath) { throw '문서 폴더를 찾지 못했습니다. -DocumentsPath로 지정해 주세요.' }
    $profile=Child-Path $DocumentsPath 'Paradox Interactive/Victoria II/TGCNV'
    if ($GamePath -match '[^\x20-\x7e]' -or $profile -match '[^\x20-\x7e]') {
        Write-Warning '게임/문서 경로에 비영문 문자가 있습니다. 일부 네이티브 지도 처리는 영문 경로만 지원하므로 설치 안내의 경로 제한을 확인해 주세요.'
    }
    $knownKorean=@('8b95a4cfbda4cc520dc26ad0f8516cd1cf8469c4e2ce73ed44a84ea1f6138629','e7677f677d186e95a45d770baa6827d8369aeb69b02b82d69c1a0b6c1e4d41dc','5602ccc12f5ede7c30e73670f161e2a77a0f80abf5bfe934dd30b0a99835e485','213b773ec7ead206fe0c33be3658081e9547391ab923c4c18a0a056d60d56c2c')
    $luaPath=Child-Path $GamePath 'lua51.dll'
    $luaHash=Hash-File $luaPath
    $ori=Child-Path $GamePath 'lua51_ori.dll'
    $saved=Child-Path $GamePath 'tgcnv_lua51_ori.dll'
    $bootstrapReceipt=Child-Path $GamePath 'tgcnv_bootstrap_install.txt'
    $bootstrapHash=Hash-File (Join-Path $PackRoot 'payload/game/lua51_ori.dll')
    $currentOriHash=$null
    if (Test-Path -LiteralPath $ori -PathType Leaf) { $currentOriHash=Hash-File $ori }
    $overwriteRecovery=Test-OverwriteLuaRecovery $GamePath $profile $manifest $bootstrapHash $currentOriHash
    if ($overwriteRecovery) { $originalSource=$saved }
    elseif (Test-Path -LiteralPath $saved) {
        if ((Hash-File $saved) -cne $manifest.original_lua_sha256 -or -not (Test-Path -LiteralPath $bootstrapReceipt)) { throw '원본 Lua 실행 의존 파일의 설치 기록/해시를 확인할 수 없습니다.' }
        $record=[IO.File]::ReadAllText($bootstrapReceipt)
        if ($record -notmatch '(?m)^TGCNV_BOOTSTRAP_INSTALL 1\r?$' -or $record -notmatch ('(?m)^backup_sha256='+$manifest.original_lua_sha256+'\r?$') -or $record -notmatch '(?m)^pending_sha256=-\r?$') { throw '기존 Lua 설치 기록이 올바르지 않거나 설치가 중단된 상태입니다.' }
        $installed=[regex]::Match($record,'(?m)^installed_sha256=([0-9a-f]{64})\r?$')
        if (-not $installed.Success -or (Hash-File $ori) -cne $installed.Groups[1].Value) { throw '기존 Lua 설치 기록과 실제 파일이 다릅니다.' }
        $originalSource=$saved
    } elseif (Test-Path -LiteralPath $bootstrapReceipt) { throw 'Lua 설치 기록은 있지만 원본 실행 의존 파일이 없습니다.' }
    elseif ($luaHash -ceq $manifest.original_lua_sha256) {
        if ((Test-Path -LiteralPath $ori) -and (Hash-File $ori) -cne $manifest.original_lua_sha256) { throw '다른 Lua 연결이 이미 설치되어 있습니다.' }
        $originalSource=$luaPath
    } elseif ($luaHash -cin $knownKorean -and (Test-Path -LiteralPath $ori) -and (Hash-File $ori) -ceq $manifest.original_lua_sha256) { $originalSource=$ori }
    else { throw '지원하는 원본 Lua 또는 한글 Lua 구성이 아닙니다. 설치 안내를 확인해 주세요.' }
    if ($luaHash -cne $manifest.original_lua_sha256 -and $luaHash -cnotin $knownKorean) { throw '알 수 없는 Lua 패치를 덮어쓸 수 없습니다.' }
    $bridge=Join-Path $GamePath 'tgcnv_memory_bridge.dll'
    $bridgePayloadHash=Hash-File (Join-Path $PackRoot 'payload/game/tgcnv_memory_bridge.dll')
    $bridgePreviousHash='8cd176f7672d053e5a0667a573114af8c9238f2e408f64a7c5c800769233cdb2'
    if (Test-Path -LiteralPath $bridge) {
        $bridgeHash=Hash-File $bridge
        if ($bridgeHash -cne $bridgePayloadHash -and $bridgeHash -cne $bridgePreviousHash) { throw '알 수 없는 지도 메모리 확장이 이미 설치되어 있습니다.' }
    }
    $launcherCfg=$null
    $launcherPlan=$null
    $tgcnvExeTargetHash=$null
    $tgcnvExePayload=Join-Path $PackRoot 'payload/game/TGCNV.exe'
    if (Test-Path -LiteralPath $tgcnvExePayload) {
        $tgcnvExeTarget=Child-Path $GamePath 'TGCNV.exe'
        $tgcnvExePayloadHash=Hash-File $tgcnvExePayload
        # Prior official prelauncher, pinned to published release manifests.
        $tgcnvExePriorHash='5bcb0ded3c9eede36f42a7d561f283bbab32d8acea0b5236f1b1957429ef19c9'
        if (Test-Path -LiteralPath $tgcnvExeTarget) {
            $tgcnvExeTargetHash=Hash-File $tgcnvExeTarget
            if ($tgcnvExeTargetHash -cne $tgcnvExePayloadHash -and $tgcnvExeTargetHash -cne $tgcnvExePriorHash) {
                throw "알 수 없는 TGCNV.exe가 이미 설치되어 있습니다. 파일을 삭제하지 말고 보관한 뒤 다음 SHA-256과 함께 문의해 주세요: $tgcnvExeTargetHash"
            }
        }
        $launcherCfg=Child-Path $GamePath 'launcher/launcher.cfg'
        if (-not (Test-Path -LiteralPath $launcherCfg)) { throw '런처 설정(launcher/launcher.cfg)을 찾을 수 없습니다.' }
        $launcherPlan=New-LauncherConfigPlan $launcherCfg
    }
    $tgoPayloadDir=Join-Path $PackRoot 'payload/game/mod/TGO'
    $tgoPayloadMod=Join-Path $PackRoot 'payload/game/mod/TGO.mod'
    $tgoDirExists=Test-Path -LiteralPath $tgoPayloadDir -PathType Container
    $tgoModExists=Test-Path -LiteralPath $tgoPayloadMod -PathType Leaf
    $hasTgo=($tgoDirExists -and $tgoModExists)
    if ((Test-Path -LiteralPath $tgoPayloadDir) -or (Test-Path -LiteralPath $tgoPayloadMod)) {
        if (-not $hasTgo) { throw 'TGO 배포 파일이 불완전합니다. 폴더와 .mod가 모두 있어야 합니다. 압축을 다시 풀어 주세요.' }
        if (@(Get-ChildItem -LiteralPath $tgoPayloadDir -Recurse -Force -File).Count -lt 1) { throw 'TGO 배포 폴더가 비어 있습니다. 압축을 다시 풀어 주세요.' }
    }
    $id=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
    $installRoot=Child-Path $GamePath 'TGCNV_Install'
    $txn=Child-Path $GamePath "TGCNV_Install/$id"
    $profileTxn=Child-Path $profile "TGCNV_Install/$id"
    $receiptPath=Child-Path $GamePath 'TGCNV_Install/receipt.json'
    $priorReceipt=$null
    if (Test-Path -LiteralPath $receiptPath -PathType Leaf) {
        try { $priorReceipt=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $priorReceipt=$null }
    }
    if (Test-Path -LiteralPath $txn) { throw '임시 설치 폴더가 이미 존재합니다.' }
    if (Test-Path -LiteralPath $profileTxn) { throw '임시 캐시 폴더가 이미 존재합니다.' }
    $langCatalog=Read-LanguageCatalog $PackRoot $manifest
    $installedLang=Read-InstalledLanguage (Join-Path $GamePath 'mod/TGCNV')
    $selectedLanguage=Resolve-LanguageChoice -Requested $Language -Catalog $langCatalog -Installed $installedLang
    [IO.Directory]::CreateDirectory($txn) | Out-Null
    $ownedStages.Add(@{root=$GamePath;id=$id})
    [IO.Directory]::CreateDirectory($profileTxn) | Out-Null
    $ownedStages.Add(@{root=$profile;id=$id})
    Write-Host '새 파일을 준비합니다. 기존 모드·캐시·DLL은 백업 없이 덮어씁니다...'
    Copy-Item -LiteralPath (Join-Path $PackRoot 'payload/game') -Destination (Join-Path $txn 'stage') -Recurse
    Copy-Item -LiteralPath (Join-Path $PackRoot 'payload/profile') -Destination (Join-Path $profileTxn 'stage') -Recurse
    Copy-Item -LiteralPath $originalSource -Destination (Join-Path $txn 'stage/tgcnv_lua51_ori.dll')
    $text="TGCNV_BOOTSTRAP_INSTALL 1`nbackup_sha256=$($manifest.original_lua_sha256)`ninstalled_sha256=$bootstrapHash`npending_sha256=-`n"
    [IO.File]::WriteAllText((Join-Path $txn 'stage/tgcnv_bootstrap_install.txt'),$text,[Text.UTF8Encoding]::new($false))
    if ($gameInfo.adjust) {
        Write-Host '호환되는 원본 EXE를 확인했습니다. 4GB 메모리 플래그 1비트만 적용합니다.'
        [IO.File]::WriteAllBytes((Join-Path $txn 'stage/v2game.exe'),$gameInfo.bytes)
    }
    foreach ($entry in $manifest.files) {
        $rel=$entry.path -replace '^payload/(game|profile)/',''
        $root=if ($entry.path.StartsWith('payload/game/')) { $txn } else { $profileTxn }
        if ((Hash-File (Join-Path $root "stage/$rel")) -cne $entry.sha256) { throw "복사 검증에 실패했습니다: $rel" }
    }
    if ((Hash-File (Join-Path $txn 'stage/tgcnv_lua51_ori.dll')) -cne $manifest.original_lua_sha256) { throw '원본 Lua 실행 의존 파일의 복사 검증에 실패했습니다.' }
    if ($gameInfo.adjust -and (Hash-File (Join-Path $txn 'stage/v2game.exe')) -cne $manifest.game_sha256) { throw '4GB 메모리 플래그 파일 검증에 실패했습니다.' }
    if ($langCatalog) {
        [void](Set-StagedLanguage -StageGameRoot (Join-Path $txn 'stage') -Manifest $manifest -Language $selectedLanguage)
    }
    if ($launcherPlan) {
        if ((Hash-File $launcherCfg) -cne $launcherPlan.OriginalSha256) { throw '런처 설정이 설치 준비 중 변경되었습니다.' }
        $launcherStage=Join-Path $txn 'stage/launcher/launcher.cfg'
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($launcherStage)) | Out-Null
        [IO.File]::WriteAllBytes($launcherStage,$launcherPlan.Bytes)
    }
    $ops=@()
    $gameRelatives=@('mod/TGCNV','mod/TGCNV.mod')
    if ($hasTgo) { $gameRelatives+=@('mod/TGO','mod/TGO.mod') }
    $gameRelatives+=@('tgcnv_memory_bridge.dll','tgcnv_lua51_ori.dll','lua51_ori.dll','tgcnv_bootstrap_install.txt','lua51.dll')
    foreach ($relative in $gameRelatives) {
        $ops+=@{scope='game';relative=$relative;had_before=(Test-Path -LiteralPath (Child-Path $GamePath $relative));applied=$false}
    }
    if ($launcherPlan) {
        $ops+=@{scope='game';relative='launcher/launcher.cfg';had_before=$true;applied=$false}
    }
    if ($gameInfo.adjust) { $ops+=@{scope='game';relative='v2game.exe';had_before=$true;applied=$false} }
    $ops+=@{scope='profile';relative='map/cache';had_before=(Test-Path -LiteralPath (Child-Path $profile 'map/cache'));applied=$false}
    # Apply the validated prelaunch executable last.
    if (Test-Path -LiteralPath $tgcnvExePayload) {
        $ops+=@{scope='game';relative='TGCNV.exe';had_before=($null -ne $tgcnvExeTargetHash);applied=$false}
    }
    $receipt=@{schema=2;mode='overwrite_no_backup';id=$id;game=$GamePath;profile=$profile;release=$manifest.release;language=$selectedLanguage;status='preparing';operations=$ops;original_lua_sha256=$manifest.original_lua_sha256;incoming_bootstrap_sha256=$bootstrapHash}
    # Validate every deletion/replacement boundary before modifying any target.
    foreach ($op in $ops) {
        $target=Install-Path $receipt $op 'target'
        $stage=Install-Path $receipt $op 'stage'
        Assert-PlainTree $target
        Assert-PlainTree $stage
        if (-not (Test-Path -LiteralPath $stage)) { throw "준비된 설치 항목이 없습니다: $stage" }
        $op.before_kind=if ([IO.Directory]::Exists($target)) { 'directory' } elseif ([IO.File]::Exists($target)) { 'file' } else { 'absent' }
        $op.before_sha256=if ([IO.File]::Exists($target)) { Hash-File $target } else { $null }
        $op.after_sha256=if ([IO.File]::Exists($stage)) { Hash-File $stage } else { $null }
    }
    if ($priorReceipt) {
        try {
            if ($priorReceipt.schema -eq 2 -and $priorReceipt.mode -ceq 'overwrite_no_backup' -and $priorReceipt.game -ieq $GamePath -and $priorReceipt.id -cne $id -and $priorReceipt.id -cmatch '^\d{8}-\d{6}-[0-9a-f]{8}$') {
                Remove-OwnedStage $GamePath $priorReceipt.id
                if ($priorReceipt.profile -ieq $profile) { Remove-OwnedStage $profile $priorReceipt.id }
            }
        } catch { Write-Warning ('이전 임시 새 파일 정리를 완료하지 못했습니다: '+$_.Exception.Message) }
    }
    Save-Json $receiptPath $receipt
    $receipt.status='applying'
    Save-Json $receiptPath $receipt
    try {
        if ($launcherPlan -and (Hash-File $launcherCfg) -cne $launcherPlan.OriginalSha256) { throw '런처 설정이 설치 직전에 변경되었습니다.' }
        foreach ($op in $ops) {
            Assert-Closed
            $target=Install-Path $receipt $op 'target'
            $currentKind=if ([IO.Directory]::Exists($target)) { 'directory' } elseif ([IO.File]::Exists($target)) { 'file' } else { 'absent' }
            if ($currentKind -cne $op.before_kind) { throw "설치 대상의 종류가 준비 중 변경되었습니다: $target" }
            if ($null -ne $op.before_sha256 -and ((-not [IO.File]::Exists($target)) -or (Hash-File $target) -cne $op.before_sha256)) { throw "설치 대상이 준비 중 변경되었습니다: $target" }
            if ($op.scope -ceq 'game' -and $op.relative -ceq 'launcher/launcher.cfg' -and (Hash-File $target) -cne $launcherPlan.OriginalSha256) { throw '런처 설정이 설치 중 변경되었습니다.' }
            if ($op.scope -ceq 'game' -and $op.relative -ceq 'TGCNV.exe') {
                $currentHash=$null
                if (Test-Path -LiteralPath $target) { $currentHash=Hash-File $target }
                if ($currentHash -cne $tgcnvExeTargetHash) { throw 'TGCNV.exe가 설치 준비 중 변경되었습니다.' }
            }
            Set-OverwriteTarget $receipt $op
            if ($null -ne $op.after_sha256 -and (Hash-File $target) -cne $op.after_sha256) { throw "덮어쓰기 검증 실패: $target" }
            $op.applied=$true
            Save-Json $receiptPath $receipt
        }
        $receipt.status='installed'
        Save-Json $receiptPath $receipt
    } catch {
        $failure=$_
        $receipt.status='failed'
        $receipt.error=$failure.Exception.Message
        try { Save-Json $receiptPath $receipt } catch { }
        throw "설치가 중단되었습니다. 백업 없이 덮어쓰는 방식이므로 같은 설치기를 다시 실행해 마무리하세요. 원인: $($failure.Exception.Message)"
    }
    $modSuffix=if ($selectedLanguage -eq 'en') { '(English)' } else { '(Korean)' }
    Write-Host ('Installed language / 설치 언어: '+$selectedLanguage)
    if ($hasTgo) {
        Write-Host "설치 완료! Victoria II 런처에서 TGC - Anime Total Overhaul $modSuffix AND TGO - The Grand Orchestra 모드를 함께 선택해 시작하세요."
    } else {
        Write-Host "설치 완료! Victoria II 런처에서 TGC - Anime Total Overhaul ${modSuffix}만 선택해 시작하세요."
    }
    Write-Host '백업 없이 덮어쓰기 완료. 설치 도중 중단되면 같은 설치기를 다시 실행하세요.'
    Write-Host '게임과 런처는 자동 실행하지 않습니다. 처음에는 새 캠페인으로 확인해 주세요.'
    exit 0
} catch {
    Write-Host ("오류: "+$_.Exception.Message) -ForegroundColor Red
    Write-Host '쓰기 권한 오류라면 현재 Windows 사용자 계정에서 Setup.cmd를 관리자 권한으로 실행하세요. 다른 계정으로 실행하면 문서 경로가 달라질 수 있습니다.'
    exit 1
} finally {
    foreach ($owned in $ownedStages) {
        try { Remove-OwnedStage $owned.root $owned.id }
        catch { Write-Warning ('임시 새 파일 정리를 완료하지 못했습니다: '+$_.Exception.Message) }
    }
    if (Get-Variable setupMutex -ErrorAction SilentlyContinue) {
        if ($created) { $setupMutex.ReleaseMutex() }
        $setupMutex.Dispose()
    }
}
