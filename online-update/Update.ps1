#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Check','Update','Restore')][string]$Action='Update',
    [string]$GamePath,
    [string]$DocumentsPath,
    [string]$BackupId,
    [ValidateSet('Auto','ko','en')][string]$Language='Auto',
    [switch]$ChooseLanguage
)
Set-StrictMode -Version 3.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Online-Core.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Language.psm1') -Force -DisableNameChecking
$utf8=[Text.UTF8Encoding]::new($false)
$mutex=$null
function Save-Json($Path,$Value) {
    Assert-NoReparsePoint $Path
    $temp=$Path+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($temp,($Value | ConvertTo-Json -Depth 20),$utf8)
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[NullString]::Value) }
    else { [IO.File]::Move($temp,$Path) }
}
function Read-Json($Path) { return [IO.File]::ReadAllText($Path,$utf8) | ConvertFrom-Json }
function Byte-Hash([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Validate-Channel([byte[]]$Bytes,[byte[]]$Signature,[switch]$AllowLegacy) {
    if (-not (Test-ChannelSignature $Bytes $Signature $trust.public_key_xml)) { throw '배포 서명이 올바르지 않습니다.' }
    $c=$utf8.GetString($Bytes) | ConvertFrom-Json
    if (((Assert-Integer $c.schema) -ne 2 -and -not ($AllowLegacy -and $c.schema -eq 1)) -or $c.repository -cne $trust.repository) { throw '지원하지 않는 배포 채널입니다.' }
    if ($c.release -cnotmatch '^TGCNV-[0-9]{8}-[0-9]{6}$') { throw '잘못된 배포 이름입니다.' }
    $stamp=[DateTime]::ParseExact($c.release.Substring(6),'yyyyMMdd-HHmmss',[Globalization.CultureInfo]::InvariantCulture)
    $seq=[long]$stamp.ToString('yyyyMMddHHmmss')
    if ((Assert-Integer $c.sequence) -ne $seq) { throw '배포 순서가 올바르지 않습니다.' }
    $expectedUrl="https://ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/sha256:$($c.catalog_sha256)"
    if ($c.schema -eq 1) { $expectedUrl="https://github.com/$($trust.repository)/releases/download/$($c.release)/catalog.json" }
    if ($c.catalog_url -cne $expectedUrl) { throw '잘못된 배포 목록 주소입니다.' }
    if ((Assert-Integer $c.catalog_bytes) -lt 1 -or $c.catalog_bytes -gt 33554432 -or $c.catalog_sha256 -cnotmatch '^[0-9a-f]{64}$') { throw '잘못된 배포 목록 정보입니다.' }
    return $c
}
function Validate-Files($Catalog,$Root) {
    $n=0
    foreach($f in $Catalog.Files) {
        $p=Resolve-SafeChild $Root $f.Path
        if (-not [IO.File]::Exists($p) -or (Get-Item -LiteralPath $p).Length -ne $f.Bytes -or (Get-Sha256 $p) -cne $f.Sha256) { throw "파일 검증 실패: $($f.Path)" }
        $n++
        if ($n % 500 -eq 0) { Write-Progress -Activity '파일 검증' -Status "$n / $($Catalog.Files.Count)" -PercentComplete (100*$n/$Catalog.Files.Count) }
    }
    Write-Progress -Activity '파일 검증' -Completed
}
function Invoke-Setup($Root,$Mode,[string]$Lang) {
    $args=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',(Join-Path $Root 'Setup.ps1'),'-Action',$Mode)
    if ($Mode -ne 'Verify') {
        $args+=@('-GamePath',$GamePath,'-DocumentsPath',$DocumentsPath)
        if ($Mode -eq 'Restore' -and $BackupId) { $args+=@('-BackupId',$BackupId) }
        if ($Mode -eq 'Install' -and $Lang) { $args+=@('-Language',$Lang) }
    }
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @args
    if ($LASTEXITCODE -ne 0) { throw "설치 도구가 실패했습니다 ($Mode). 위 오류와 복원 안내를 확인하세요." }
}
try {
    if ($Action -ne 'Update' -and ($Language -ne 'Auto' -or $ChooseLanguage)) { throw 'Language selection applies only to Update.' }
    if ($ChooseLanguage -and $Language -ne 'Auto') { throw 'Use either -ChooseLanguage or -Language.' }
    $trust=Read-Json (Join-Path $PSScriptRoot 'trust.json')
    if ($trust.schema -ne 1 -or $trust.repository -cne 'Yukino-Chan/TGC-Anime-Total-Overhaul-Korean') { throw '지원하지 않는 업데이트 설정입니다.' }
    $cache=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'TGCNV-Updater'
    Assert-NoReparsePoint $cache
    [void][IO.Directory]::CreateDirectory($cache)
    $mutex=Take-UpdateMutex
    $statePath=Resolve-SafeChild $cache 'state.json'
    $state=$null
    if ([IO.File]::Exists($statePath)) { $state=Read-Json $statePath }
    if ($state -and $state.schema -ne 1) { throw '지원하지 않는 로컬 상태입니다.' }
    if (-not $GamePath -and $state) { $GamePath=$state.game }
    if (-not $DocumentsPath -and $state) { $DocumentsPath=$state.documents }
    if ($Action -eq 'Restore') {
        if (-not $state) { throw '온라인 설치 기록이 없습니다. 기존 배포 팩의 Restore.cmd를 사용하세요.' }
        if ($GamePath -ine $state.game -or $DocumentsPath -ine $state.documents) { throw '복원은 설치 기록과 같은 경로에서 실행해야 합니다.' }
        Assert-GameClosed
        $saved=Resolve-SafeChild $cache $state.stage
        $channel=Validate-Channel ([IO.File]::ReadAllBytes((Join-Path $saved 'channel.json'))) ([IO.File]::ReadAllBytes((Join-Path $saved 'channel.sig'))) -AllowLegacy
        $raw=[IO.File]::ReadAllBytes((Join-Path $saved 'catalog.json'))
        if ($raw.Length -ne $channel.catalog_bytes -or (Byte-Hash $raw) -cne $channel.catalog_sha256) { throw '복원 도구 목록이 손상되었습니다.' }
        $catalog=Read-ValidatedCatalog $raw $trust.repository
        $pack=Join-Path $saved 'pack'
        Validate-Files $catalog $pack
        Invoke-Setup $pack 'Restore'
        $state.status='restored'
        Save-Json $statePath $state
        exit 0
    }
    if (-not $GamePath) {
        Add-Type -AssemblyName System.Windows.Forms
        $picker=New-Object Windows.Forms.OpenFileDialog
        $picker.Title='Victoria II 설치 폴더의 v2game.exe를 선택하세요'
        $picker.Filter='Victoria II|v2game.exe'
        try {
            if ($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw '취소했습니다.' }
            $GamePath=[IO.Path]::GetDirectoryName($picker.FileName)
        } finally { $picker.Dispose() }
    }
    $GamePath=[IO.Path]::GetFullPath($GamePath)
    Assert-NoReparsePoint $GamePath
    if (-not [IO.File]::Exists((Join-Path $GamePath 'v2game.exe'))) { throw 'v2game.exe가 없는 폴더입니다.' }
    if (-not $DocumentsPath) { $DocumentsPath=[Environment]::GetFolderPath('MyDocuments') }
    if (-not $DocumentsPath) { throw '문서 폴더를 지정하세요 (-DocumentsPath).' }
    $DocumentsPath=[IO.Path]::GetFullPath($DocumentsPath)
    $profile=Resolve-SafeChild $DocumentsPath 'Paradox Interactive/Victoria II/TGCNV'
    $installedLang=Read-InstalledLanguage (Join-Path $GamePath 'mod/TGCNV')
    if (-not $installedLang) { $installedLang='ko' }
    if ($Action -eq 'Update') { Assert-GameClosed }
    Write-Host '최신 배포 서명과 파일 목록을 확인합니다...'
    $envelopeRaw=Receive-LimitedBytes 'https://raw.githubusercontent.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/update-feed/channel.json' 131072 $trust.repository
    $envelope=$utf8.GetString($envelopeRaw) | ConvertFrom-Json
    if ((Assert-Integer $envelope.schema) -ne 2) { throw '지원하지 않는 채널 형식입니다.' }
    $channelRaw=[Convert]::FromBase64String($envelope.channel)
    $signature=[Convert]::FromBase64String($envelope.signature)
    if ($channelRaw.Length -gt 65536 -or $signature.Length -gt 1024) { throw '서명 채널 크기가 잘못되었습니다.' }
    $channel=Validate-Channel $channelRaw $signature
    $waterPath=Resolve-SafeChild $cache 'highest-sequence-v2.json'
    # Preserve the legacy anti-rollback floor while changing storage protocol.
    $legacyWater=Resolve-SafeChild $cache 'highest-sequence.json'
    if ([IO.File]::Exists($legacyWater)) {
        $legacy=Read-Json $legacyWater
        if ($channel.sequence -lt (Assert-Integer $legacy.sequence)) { throw '이전 업데이트 기록보다 오래된 배포입니다.' }
    }
    if ([IO.File]::Exists($waterPath)) {
        $water=Read-Json $waterPath
        if ($channel.sequence -lt (Assert-Integer $water.sequence)) { throw '이전에 확인한 버전보다 오래된 배포를 거부했습니다.' }
        if ($channel.sequence -eq $water.sequence -and $channel.catalog_sha256 -cne $water.catalog_sha256) { throw '같은 배포 번호의 내용이 변경되었습니다.' }
    }
    $catalogRaw=Receive-LimitedBytes $channel.catalog_url 33554432 $trust.repository
    if ($catalogRaw.Length -ne $channel.catalog_bytes -or (Byte-Hash $catalogRaw) -cne $channel.catalog_sha256) { throw '배포 목록 해시가 다릅니다.' }
    $catalog=Read-ValidatedCatalog $catalogRaw $trust.repository
    if ($catalog.Release -cne $channel.release) { throw '배포 번호가 일치하지 않습니다.' }
    Save-Json $waterPath @{sequence=$channel.sequence;catalog_sha256=$channel.catalog_sha256}
    $fileIndex=@{}
    foreach ($f in $catalog.Files) { $fileIndex[$f.Path]=$f }
    $packHasLanguage=$fileIndex.ContainsKey('payload/game/mod/TGCNV/runtime/languages/catalog.json')
    $requestedLang=$null
    if ($Action -eq 'Update') {
        if ($ChooseLanguage) {
            if (-not $packHasLanguage) { throw 'This release does not offer English / 이 배포는 영문을 지원하지 않습니다.' }
            $requestedLang=Show-LanguagePicker -Current $installedLang
        } elseif ($Language -ne 'Auto') { $requestedLang=$Language }
        if (-not $packHasLanguage -and ($requestedLang -eq 'en' -or (-not $requestedLang -and $installedLang -eq 'en'))) { throw 'English is unavailable; your preference was preserved.' }
    }
    $languageChange=($null -ne $requestedLang) -and ($requestedLang -cne $installedLang)
    $reuse=@{}
    $missing=New-Object 'System.Collections.Generic.HashSet[string]'
    $changed=0
    $previousPack=$null
    if ($state) { $previousPack=Join-Path (Resolve-SafeChild $cache $state.stage) 'pack' }
    $n=0
    foreach ($f in $catalog.Files) {
        $candidate=$null
        if ($f.Path.StartsWith('payload/game/')) { $candidate=Resolve-SafeChild $GamePath $f.Path.Substring(13) }
        elseif ($f.Path.StartsWith('payload/profile/')) { $candidate=Resolve-SafeChild $profile $f.Path.Substring(16) }
        elseif ($previousPack) { $candidate=Resolve-SafeChild $previousPack $f.Path }
        # Only the signed incoming catalog can authorize an intentional variant.
        # A cached or installed language file is never trusted merely by equality.
        if ($installedLang -eq 'en' -and $candidate -and [IO.File]::Exists($candidate)) {
            $variantRel=Get-LanguageVariantPath $f.Path 'en'
            if ($variantRel -and $fileIndex.ContainsKey($variantRel)) {
                $v=$fileIndex[$variantRel]
                if ((Get-Item -LiteralPath $candidate).Length -eq $v.Bytes -and (Get-Sha256 $candidate) -ceq $v.Sha256) {
                    $canonicalRel=Get-LanguageVariantPath $f.Path 'ko'
                    $candidate=Resolve-SafeChild $GamePath $canonicalRel.Substring(13)
                }
            } elseif ($f.Path -cin @('payload/game/mod/TGCNV.mod','payload/game/mod/TGO.mod') -and $previousPack) {
                $canonical=Resolve-SafeChild $previousPack $f.Path
                if ([IO.File]::Exists($canonical) -and (Get-Sha256 $canonical) -ceq $f.Sha256) {
                    $converted=if ($f.Path -ceq 'payload/game/mod/TGO.mod') { Convert-MusicDescriptor ([IO.File]::ReadAllBytes($canonical)) 'en' } else { Convert-ModDescriptor ([IO.File]::ReadAllBytes($canonical)) 'en' }
                    $expected=Byte-Hash $converted
                    if ((Get-Sha256 $candidate) -ceq $expected) { $candidate=$canonical }
                }
            }
        }
        if ($candidate -and [IO.File]::Exists($candidate) -and (Get-Item -LiteralPath $candidate).Length -eq $f.Bytes -and (Get-Sha256 $candidate) -ceq $f.Sha256) { $reuse[$f.Path]=$candidate }
        else {
            [void]$missing.Add($f.Asset)
            if ($f.Path.StartsWith('payload/')) { $changed++ }
        }
        $n++
        if ($n % 500 -eq 0) { Write-Progress -Activity '설치 파일 비교' -Status "$n / $($catalog.Files.Count)" -PercentComplete (100*$n/$catalog.Files.Count) }
    }
    Write-Progress -Activity '설치 파일 비교' -Completed
    $downloadBytes=[long]0
    foreach($id in $missing) { $downloadBytes+=$catalog.Assets[$id].Bytes }
    $displayEngine = $catalog.EngineVersion -replace '\+[0-9]{8}(?:-[0-9]{6})?(?=-|$)',''
    Write-Host ("TGCNV + TGO / 엔진: {0} / 변경·누락 파일: {1} / 다운로드 최대 {2:N1} MB" -f $displayEngine,$changed,($downloadBytes/1MB))
    if ($Action -eq 'Check') { exit 0 }
    # Even when all target files match, run the installer if no online installation
    # receipt exists: it also configures launcher/bootstrap files outside payload.
    if ($changed -eq 0 -and -not $languageChange -and $state -and $state.status -eq 'installed' -and $state.release -ceq $catalog.Release -and $state.game -ieq $GamePath -and $state.documents -ieq $DocumentsPath) {
        Write-Host '최신 배포가 설치되어 있습니다.'
        exit 0
    }
    $stageRel='packs/'+$catalog.Release+'/'+[Guid]::NewGuid().ToString('N')
    $stage=Resolve-SafeChild $cache $stageRel
    $pack=Join-Path $stage 'pack'
    [void][IO.Directory]::CreateDirectory($pack)
    [IO.File]::WriteAllBytes((Join-Path $stage 'channel.json'),$channelRaw)
    [IO.File]::WriteAllBytes((Join-Path $stage 'channel.sig'),$signature)
    [IO.File]::WriteAllBytes((Join-Path $stage 'catalog.json'),$catalogRaw)
    foreach ($f in $catalog.Files) {
        if ($reuse.ContainsKey($f.Path)) {
            $target=Resolve-SafeChild $pack $f.Path
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            [IO.File]::Copy($reuse[$f.Path],$target,$false)
            if ((Get-Sha256 $target) -cne $f.Sha256) { throw '복사 중 설치 파일이 변경되었습니다. 다시 실행하세요.' }
        }
    }
    foreach ($id in $missing) {
        $asset=$catalog.Assets[$id]
        $archive=Resolve-SafeChild $cache "objects/$id.zip"
        if (-not [IO.File]::Exists($archive) -or (Get-Item -LiteralPath $archive).Length -ne $asset.Bytes -or (Get-Sha256 $archive) -cne $id) {
            Write-Host ("패치 묶음 다운로드: {0:N1} MB" -f ($asset.Bytes/1MB))
            [void](Receive-VerifiedFile $asset.Url $archive $asset.Bytes $id $trust.repository 2147483647)
        }
        $entries=@($catalog.Files | Where-Object { $_.Asset -ceq $id -and -not $reuse.ContainsKey($_.Path) })
        [void](Expand-SelectedAsset $archive $entries $pack)
    }
    Validate-Files $catalog $pack
    Invoke-Setup $pack 'Verify'
    Assert-GameClosed
    # Persist the verified recovery tool before applying, including interrupted installs.
    $state=@{schema=1;release=$catalog.Release;stage=$stageRel;game=$GamePath;documents=$DocumentsPath;status='prepared'}
    Save-Json $statePath $state
    Write-Host '기존 모드·캐시를 백업한 뒤 업데이트를 설치합니다. 세이브는 유지합니다.'
    $langArg=$null
    if ($packHasLanguage) { $langArg=if ($requestedLang) { $requestedLang } else { 'Auto' } }
    Invoke-Setup $pack 'Install' $langArg
    $state.status='installed'
    $state.language=Read-InstalledLanguage (Join-Path $GamePath 'mod/TGCNV')
    Save-Json $statePath $state
    Write-Host '업데이트 완료. 이전 상태가 필요하면 Restore-Update.cmd를 실행하세요.'
} catch {
    Write-Host ('오류: '+$_.Exception.Message) -ForegroundColor Red
    Write-Host '다운로드·검증 실패 시 게임 파일은 변경하지 않습니다. 설치 중 실패했다면 Restore-Update.cmd로 복원하세요.'
    exit 1
} finally {
    if ($mutex) { $mutex.ReleaseMutex(); $mutex.Dispose() }
}
