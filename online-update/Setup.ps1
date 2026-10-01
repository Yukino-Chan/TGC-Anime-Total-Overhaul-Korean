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
    $path=Join-Path $Root 'v2game.exe'
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
function Transaction-Path($Receipt,$Op,[string]$Kind) {
    $root = if ($Op.scope -eq 'game') { $Receipt.game } elseif ($Op.scope -eq 'profile') { $Receipt.profile } else { throw '잘못된 백업 범위입니다.' }
    if ($Op.scope -eq 'game' -and $Op.relative -notin @('mod/TGCNV','mod/TGCNV.mod','mod/TGO','mod/TGO.mod','lua51.dll','lua51_ori.dll','tgcnv_memory_bridge.dll','tgcnv_lua51_ori.dll','tgcnv_bootstrap_install.txt','v2game.exe','TGCNV.exe','launcher/launcher.cfg')) { throw '잘못된 게임 백업 항목입니다.' }
    if ($Op.scope -eq 'profile' -and $Op.relative -ne 'map/cache') { throw '잘못된 캐시 백업 항목입니다.' }
    if ($Kind -eq 'target') { return Child-Path $root $Op.relative }
    return Child-Path $root ("TGCNV_Backups/$($Receipt.id)/$Kind/$($Op.relative)")
}
function Restore-Transaction($Receipt,[string]$ReceiptPath) {
    Assert-Closed
    if ($Receipt.id -notmatch '^\d{8}-\d{6}-[0-9a-f]{8}$') { throw '잘못된 백업 ID입니다.' }
    # Check every backup before moving anything. The removed+target pair also
    # covers interruption after the original was restored but before journaling.
    foreach ($op in $Receipt.operations) {
        if ($op.restored -or -not $op.had_before) { continue }
        $before=Transaction-Path $Receipt $op 'before'
        if (Test-Path -LiteralPath $before) { continue }
        $target=Transaction-Path $Receipt $op 'target'
        $stage=Transaction-Path $Receipt $op 'stage'
        $removed=Transaction-Path $Receipt $op 'removed'
        if (-not (Test-Path -LiteralPath $target) -or
            (-not (Test-Path -LiteralPath $stage) -and -not (Test-Path -LiteralPath $removed))) {
            throw "원본 백업이 누락되어 복원할 수 없습니다: $before"
        }
    }
    for ($i=$Receipt.operations.Count-1;$i -ge 0;$i--) {
        $op=$Receipt.operations[$i]
        $target=Transaction-Path $Receipt $op 'target'
        $before=Transaction-Path $Receipt $op 'before'
        $stage=Transaction-Path $Receipt $op 'stage'
        $removed=Transaction-Path $Receipt $op 'removed'
        $mustRestore=Test-Path -LiteralPath $before
        $newApplied=(-not $op.had_before) -and (-not (Test-Path -LiteralPath $stage))
        if ($op.restored) { continue }
        if ($mustRestore -or $newApplied) {
            if (Test-Path -LiteralPath $target) { Move-Safe $target $removed }
            if ($mustRestore) { Move-Safe $before $target }
        }
        $op.restored=$true
        Save-Json $ReceiptPath $Receipt
    }
    $Receipt.status='restored'
    Save-Json $ReceiptPath $Receipt
}

try {
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
    if ($Action -eq 'Restore') {
        $backupRoot=Child-Path $GamePath 'TGCNV_Backups'
        if (-not $BackupId) {
            $candidates=@(Get-ChildItem -LiteralPath $backupRoot -Directory | Sort-Object Name -Descending | Where-Object {
                $j=Join-Path $_.FullName 'receipt.json'
                (Test-Path -LiteralPath $j) -and ((Get-Content -LiteralPath $j -Raw -Encoding UTF8 | ConvertFrom-Json).status -ne 'restored')
            })
            if (-not $candidates.Count) { throw '복원할 설치 백업이 없습니다.' }
            $BackupId=$candidates[0].Name
        }
        if ($BackupId -notmatch '^\d{8}-\d{6}-[0-9a-f]{8}$') { throw '잘못된 백업 ID입니다.' }
        $receiptPath=Child-Path $backupRoot "$BackupId/receipt.json"
        $receipt=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($receipt.game -ine $GamePath -or $receipt.id -cne $BackupId) { throw '이 게임 폴더의 백업이 아닙니다.' }
        Restore-Transaction $receipt $receiptPath
        Write-Host '설치 전 상태로 복원했습니다. 설치본과 백업은 TGCNV_Backups에 보존했습니다. 세이브는 변경하지 않았습니다.'
        exit 0
    }
    $gameInfo=Game-Profile $GamePath $manifest.game_sha256
    if ((Hash-File (Join-Path $GamePath 'lua5.1.dll')) -cne $manifest.base_lua_sha256) { throw '지원하는 기본 lua5.1.dll이 아닙니다. 게임 파일을 확인해 주세요.' }
    if (-not (Test-Path -LiteralPath (Join-Path $GamePath 'victoria2.exe'))) { throw 'Victoria II 런처가 없는 폴더입니다.' }
    if (-not $DocumentsPath) { $DocumentsPath=[Environment]::GetFolderPath('MyDocuments') }
    if (-not $DocumentsPath) { throw '문서 폴더를 찾지 못했습니다. -DocumentsPath로 지정해 주세요.' }
    $profile=Child-Path $DocumentsPath 'Paradox Interactive/Victoria II/TGCNV'
    if ($GamePath -match '[^\x20-\x7e]' -or $profile -match '[^\x20-\x7e]') {
        Write-Warning '게임/문서 경로에 비영문 문자가 있습니다. 일부 네이티브 지도 처리는 영문 경로만 지원하므로 설치 안내의 경로 제한을 확인해 주세요.'
    }
    $knownKorean=@('8b95a4cfbda4cc520dc26ad0f8516cd1cf8469c4e2ce73ed44a84ea1f6138629','e7677f677d186e95a45d770baa6827d8369aeb69b02b82d69c1a0b6c1e4d41dc','5602ccc12f5ede7c30e73670f161e2a77a0f80abf5bfe934dd30b0a99835e485','213b773ec7ead206fe0c33be3658081e9547391ab923c4c18a0a056d60d56c2c')
    $luaPath=Join-Path $GamePath 'lua51.dll'
    $luaHash=Hash-File $luaPath
    $ori=Join-Path $GamePath 'lua51_ori.dll'
    $saved=Join-Path $GamePath 'tgcnv_lua51_ori.dll'
    $bootstrapReceipt=Join-Path $GamePath 'tgcnv_bootstrap_install.txt'
    $bootstrapHash=Hash-File (Join-Path $PackRoot 'payload/game/lua51_ori.dll')
    if (Test-Path -LiteralPath $saved) {
        if ((Hash-File $saved) -cne $manifest.original_lua_sha256 -or -not (Test-Path -LiteralPath $bootstrapReceipt)) { throw '기존 Lua 백업의 소유/해시를 확인할 수 없습니다.' }
        $record=[IO.File]::ReadAllText($bootstrapReceipt)
        if ($record -notmatch '(?m)^TGCNV_BOOTSTRAP_INSTALL 1\r?$' -or $record -notmatch ('(?m)^backup_sha256='+$manifest.original_lua_sha256+'\r?$') -or $record -notmatch '(?m)^pending_sha256=-\r?$') { throw '기존 Lua 설치 기록이 올바르지 않거나 설치가 중단된 상태입니다.' }
        $installed=[regex]::Match($record,'(?m)^installed_sha256=([0-9a-f]{64})\r?$')
        if (-not $installed.Success -or (Hash-File $ori) -cne $installed.Groups[1].Value) { throw '기존 Lua 설치 기록과 실제 파일이 다릅니다.' }
        $originalSource=$saved
    } elseif (Test-Path -LiteralPath $bootstrapReceipt) { throw 'Lua 설치 기록은 있지만 원본 백업이 없습니다.' }
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
    $tgcnvExePayload=Join-Path $PackRoot 'payload/game/TGCNV.exe'
    if (Test-Path -LiteralPath $tgcnvExePayload) {
        $tgcnvExeTarget=Child-Path $GamePath 'TGCNV.exe'
        $tgcnvExePayloadHash=Hash-File $tgcnvExePayload
        if (Test-Path -LiteralPath $tgcnvExeTarget) {
            if ((Hash-File $tgcnvExeTarget) -cne $tgcnvExePayloadHash) { throw '알 수 없는 TGCNV.exe가 이미 설치되어 있습니다.' }
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
    $txn=Child-Path $GamePath "TGCNV_Backups/$id"
    $profileTxn=Child-Path $profile "TGCNV_Backups/$id"
    $pendingRoot=Child-Path $GamePath 'TGCNV_Backups'
    if (Test-Path -LiteralPath $pendingRoot) {
        foreach ($prior in Get-ChildItem -LiteralPath $pendingRoot -Directory) {
            $j=Join-Path $prior.FullName 'receipt.json'
            if ((Test-Path -LiteralPath $j) -and (Get-Content -LiteralPath $j -Raw -Encoding UTF8 | ConvertFrom-Json).status -eq 'applying') { throw '이전 설치가 중단되었습니다. Restore.cmd로 복원한 뒤 다시 설치해 주세요.' }
        }
    }
    $langCatalog=Read-LanguageCatalog $PackRoot $manifest
    $installedLang=Read-InstalledLanguage (Join-Path $GamePath 'mod/TGCNV')
    $selectedLanguage=Resolve-LanguageChoice -Requested $Language -Catalog $langCatalog -Installed $installedLang
    [IO.Directory]::CreateDirectory($txn) | Out-Null
    [IO.Directory]::CreateDirectory($profileTxn) | Out-Null
    Write-Host '파일을 준비하고 있습니다. 기존 모드와 지도 캐시는 별도 백업으로 보존합니다...'
    Copy-Item -LiteralPath (Join-Path $PackRoot 'payload/game') -Destination (Join-Path $txn 'stage') -Recurse
    Copy-Item -LiteralPath (Join-Path $PackRoot 'payload/profile') -Destination (Join-Path $profileTxn 'stage') -Recurse
    Copy-Item -LiteralPath $originalSource -Destination (Join-Path $txn 'stage/tgcnv_lua51_ori.dll')
    $text="TGCNV_BOOTSTRAP_INSTALL 1`nbackup_sha256=$($manifest.original_lua_sha256)`ninstalled_sha256=$bootstrapHash`npending_sha256=-`n"
    [IO.File]::WriteAllText((Join-Path $txn 'stage/tgcnv_bootstrap_install.txt'),$text,[Text.UTF8Encoding]::new($false))
    if ($gameInfo.adjust) {
        Write-Host '호환되는 원본 EXE를 확인했습니다. 백업 후 4GB 메모리 플래그 1비트만 적용합니다.'
        [IO.File]::WriteAllBytes((Join-Path $txn 'stage/v2game.exe'),$gameInfo.bytes)
    }
    foreach ($entry in $manifest.files) {
        $rel=$entry.path -replace '^payload/(game|profile)/',''
        $root=if ($entry.path.StartsWith('payload/game/')) { $txn } else { $profileTxn }
        if ((Hash-File (Join-Path $root "stage/$rel")) -cne $entry.sha256) { throw "복사 검증에 실패했습니다: $rel" }
    }
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
        $ops+=@{scope='game';relative=$relative;had_before=(Test-Path -LiteralPath (Child-Path $GamePath $relative));restored=$false}
    }
    if (Test-Path -LiteralPath $tgcnvExePayload) {
        $ops+=@{scope='game';relative='TGCNV.exe';had_before=(Test-Path -LiteralPath (Child-Path $GamePath 'TGCNV.exe'));restored=$false}
    }
    if ($launcherPlan) {
        $ops+=@{scope='game';relative='launcher/launcher.cfg';had_before=$true;restored=$false}
    }
    if ($gameInfo.adjust) { $ops+=@{scope='game';relative='v2game.exe';had_before=$true;restored=$false} }
    $ops+=@{scope='profile';relative='map/cache';had_before=(Test-Path -LiteralPath (Child-Path $profile 'map/cache'));restored=$false}
    $receipt=@{schema=1;id=$id;game=$GamePath;profile=$profile;release=$manifest.release;language=$selectedLanguage;status='applying';operations=$ops}
    $receiptPath=Join-Path $txn 'receipt.json'
    Save-Json $receiptPath $receipt
    try {
        if ($launcherPlan -and (Hash-File $launcherCfg) -cne $launcherPlan.OriginalSha256) { throw '런처 설정이 설치 직전에 변경되었습니다.' }
        foreach ($op in $ops) {
            Assert-Closed
            if ($op.scope -eq 'game' -and $op.relative -eq 'launcher/launcher.cfg') {
                if (-not $launcherPlan -or (Hash-File (Transaction-Path $receipt $op 'target')) -cne $launcherPlan.OriginalSha256) { throw '런처 설정이 설치 중 변경되었습니다.' }
            }
            $target=Transaction-Path $receipt $op 'target'
            if ($op.had_before) { Move-Safe $target (Transaction-Path $receipt $op 'before') }
            Move-Safe (Transaction-Path $receipt $op 'stage') $target
        }
        $receipt.status='installed'
        Save-Json $receiptPath $receipt
    } catch {
        $failure=$_
        try { Restore-Transaction $receipt $receiptPath }
        catch { throw "설치가 중단되었으며 자동 복원도 완료하지 못했습니다. 게임을 실행하지 말고 Restore.cmd를 실행하세요. 백업: $txn / $($_.Exception.Message)" }
        throw "설치 실패로 기존 파일을 복원했습니다: $($failure.Exception.Message)"
    }
    $modSuffix=if ($selectedLanguage -eq 'en') { '(English)' } else { '(Korean)' }
    Write-Host ('Installed language / 설치 언어: '+$selectedLanguage)
    if ($hasTgo) {
        Write-Host "설치 완료! Victoria II 런처에서 TGC - Anime Total Overhaul $modSuffix AND TGO - The Grand Orchestra 모드를 함께 선택해 시작하세요."
    } else {
        Write-Host "설치 완료! Victoria II 런처에서 TGC - Anime Total Overhaul ${modSuffix}만 선택해 시작하세요."
    }
    Write-Host "백업: $txn"
    Write-Host '게임과 런처는 자동 실행하지 않습니다. 처음에는 새 캠페인으로 확인해 주세요.'
    exit 0
} catch {
    Write-Host ("오류: "+$_.Exception.Message) -ForegroundColor Red
    Write-Host '쓰기 권한 오류라면 현재 Windows 사용자 계정에서 Setup.cmd를 관리자 권한으로 실행하세요. 다른 계정으로 실행하면 문서 경로가 달라질 수 있습니다.'
    exit 1
} finally {
    if (Get-Variable setupMutex -ErrorAction SilentlyContinue) {
        if ($created) { $setupMutex.ReleaseMutex() }
        $setupMutex.Dispose()
    }
}
