#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$Directory,[Parameter(Mandatory=$true)][string]$CacheDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 3.0
Import-Module (Join-Path $PSScriptRoot 'Online-Core.psm1') -Force -DisableNameChecking
Assert-NoReparsePoint $Directory
Assert-NoReparsePoint $CacheDirectory
[void][IO.Directory]::CreateDirectory($CacheDirectory)
function Get-Field($o,$n){ if($null -eq $o){return $null}; $p=$o.PSObject.Properties[$n]; if($null -ne $p){$p.Value}else{$null} }
function Test-ReusableFile($File,$Old,$Asset,$OldAsset) {
    if($null -eq $Old -or $null -eq $OldAsset){return $false}
    # ZIP entry name is the catalog Path; there is no separate Entry field.
    return ($Old.Path -ceq $File.Path -and $Old.Sha256 -ceq $File.Sha256 -and
            $Old.Bytes -eq $File.Bytes -and $Old.Asset -ceq $File.Asset -and
            $OldAsset.Url -ceq $Asset.Url -and $OldAsset.Bytes -eq $Asset.Bytes)
}
$repo='Yukino-Chan/TGC-Anime-Total-Overhaul-Korean'
$expected=Join-Path $Directory 'catalog.json'
$hash=Get-Sha256 $expected
$raw=Receive-LimitedBytes "https://ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/sha256:$hash" 33554432 $repo
$local=[IO.File]::ReadAllBytes($expected)
if([Convert]::ToBase64String($raw) -cne [Convert]::ToBase64String($local)){throw 'Public catalog mismatch'}
$cat=Read-ValidatedCatalog $raw $repo
# Resume a completed verification of this exact signed catalog after a later
# release/feed failure. Rehash immutable ZIPs instead of unpacking files again.
$completedPath=Join-Path $Directory 'public-download\validation.json'
if([IO.File]::Exists($completedPath)) {
    $completedHash=Get-Sha256 $completedPath
    $done=[IO.File]::ReadAllText($completedPath)|ConvertFrom-Json
    $canResume=((Get-Field $done 'release') -ceq $cat.Release -and (Get-Field $done 'catalog_sha256') -ceq $hash -and
        (Get-Field $done 'anonymous') -eq $true -and (Get-Field $done 'files') -eq $cat.Files.Count)
    if($canResume) {
        $seen=@{};$count=0
        foreach($entry in @($done.assets)) {
            $id=[string]$entry.sha256
            if($seen.ContainsKey($id) -or -not $cat.Assets.ContainsKey($id)){ $canResume=$false;break }
            $seen[$id]=$true;$a=$cat.Assets[$id]
            $object=Resolve-SafeChild $CacheDirectory "objects/$id.zip"
            if($entry.bytes -ne $a.Bytes -or -not [IO.File]::Exists($object) -or
                (Get-Item -LiteralPath $object).Length -ne $a.Bytes -or (Get-Sha256 $object) -cne $id){$canResume=$false;break}
            $count += [int]$entry.files
        }
        $canResume=($canResume -and $seen.Count -eq $cat.Assets.Count -and $count -eq $cat.Files.Count -and (Get-Sha256 $completedPath) -ceq $completedHash)
        if($canResume) {
            [IO.File]::WriteAllText((Join-Path $Directory 'public-download\resume-validation.json'),
                (@{release=$cat.Release;catalog_sha256=$hash;completed_validation_sha256=$completedHash;
                   immutable_assets_rehashed=$seen.Count;files=$count;anonymous_catalog_rechecked=$true;
                   verified_utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
            Write-Host "PUBLIC PAYLOAD VERIFIED: $count files (completed verification reused; $($seen.Count) immutable ZIP hashes rechecked)"
            return
        }
    }
}
# Prior results are reused only for identical paths, hashes, sizes and immutable assets.
# --- Prior-evidence reuse gate (publisher-local, publisher-only) ---
$priorFiles=@{}
$priorAssets=@{}
$priorRelease=$null
$priorCatalogSha=$null
$priorValidationSha=$null
$priorEvidence=$null
$statePath=Join-Path $PSScriptRoot 'online-state.json'
if([IO.File]::Exists($statePath)){
    $state=[IO.File]::ReadAllText($statePath)|ConvertFrom-Json
    $stateRelease=Get-Field $state 'release'
    if((Get-Field $state 'public_verified') -eq $true -and (Get-Field $state 'transport') -ceq 'ghcr-v2' -and $stateRelease -and ([string]$stateRelease -cne [string]$cat.Release)){
        $rel=[string]$stateRelease
        if($rel -cnotmatch '^TGCNV-[0-9]{8}-[0-9]{6}$'){throw 'Unsafe prior release name'}
        $sha=[string](Get-Field $state 'catalog_sha256')
        $dir=Join-Path (Join-Path $PSScriptRoot 'ghcr-releases') $rel
        $pc=Join-Path $dir 'catalog.json'
        $pv=Join-Path $dir 'public-download\validation.json'
        $pp=Join-Path $dir 'publication.json'
        Assert-NoReparsePoint $dir
        if([IO.File]::Exists($pc) -and [IO.File]::Exists($pv) -and [IO.File]::Exists($pp)){
            $pcSha=Get-Sha256 $pc
            if($pcSha -ceq $sha){
                $val=[IO.File]::ReadAllText($pv)|ConvertFrom-Json
                $pub=[IO.File]::ReadAllText($pp)|ConvertFrom-Json
                if((Get-Field $val 'catalog_sha256') -ceq $sha -and (Get-Field (Get-Field $pub 'catalog') 'sha256') -ceq $sha -and (Get-Field $val 'anonymous') -eq $true -and (Get-Field $pub 'public_payload_verified') -eq $true){
                    $pcat=Read-ValidatedCatalog ([IO.File]::ReadAllBytes($pc)) $repo
                    if((Get-Field $val 'files') -eq $pcat.Files.Count -and $pcat.Release -ceq $rel -and (Get-Field $val 'release') -ceq $rel -and (Get-Field $pub 'release') -ceq $rel){
                        foreach($pf in $pcat.Files){ $priorFiles[[string]$pf.Path]=$pf }
                        foreach($pk in @($pcat.Assets.Keys)){ $priorAssets[[string]$pk]=$pcat.Assets[$pk] }
                        $priorRelease=$rel
                        $priorCatalogSha=$pcSha
                        $priorValidationSha=(Get-Sha256 $pv)
                        $priorEvidence=$pv
                    }
                }
            }
        }
    }
}
$output=Join-Path $Directory 'public-download'
Assert-NoReparsePoint $output
[void][IO.Directory]::CreateDirectory($output)
$pack=Join-Path $output 'pack'
$receipts=New-Object Collections.Generic.List[object]
$changedEntries=New-Object Collections.Generic.List[object]
$index=0
$totalReused=0
$totalChanged=0
foreach($id in @($cat.Assets.Keys | Sort-Object)) {
    $a=$cat.Assets[$id]
    $object=Resolve-SafeChild $CacheDirectory "objects/$id.zip"
    $receipt=Resolve-SafeChild $CacheDirectory "objects/$id.json"
    $cached=$false
    if([IO.File]::Exists($object) -and [IO.File]::Exists($receipt)) {
        $v=[IO.File]::ReadAllText($receipt)|ConvertFrom-Json
        $cached=($v.url -ceq $a.Url -and $v.sha256 -ceq $id -and (Get-Item -LiteralPath $object).Length -eq $a.Bytes -and (Get-Sha256 $object) -ceq $id)
    }
    $index++
    Write-Host "Public payload verification $index / $($cat.Assets.Count)"
    if(-not $cached) {
        [void](Receive-VerifiedFile $a.Url $object $a.Bytes $id $repo 2147483647)
        [IO.File]::WriteAllText($receipt,(@{url=$a.Url;sha256=$id;bytes=$a.Bytes;verified_utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    }
    $entries=@($cat.Files | Where-Object { $_.Asset -ceq $id })
    $changed=New-Object Collections.Generic.List[object]
    foreach($f in $entries){
        $o=$null
        if($priorFiles.ContainsKey([string]$f.Path)){ $o=$priorFiles[[string]$f.Path] }
        $oa=$null
        if($priorAssets.ContainsKey([string]$f.Asset)){ $oa=$priorAssets[[string]$f.Asset] }
        $reuse=Test-ReusableFile $f $o $a $oa
        if($reuse){ $totalReused++ } else { $totalChanged++; $changed.Add($f); $changedEntries.Add($f) }
    }
    if($changed.Count) { [void](Expand-SelectedAsset $object $changed.ToArray() $pack) }
    $receipts.Add(@{sha256=$id;bytes=$a.Bytes;files=$entries.Count;reused_files=($entries.Count-$changed.Count);newly_verified_files=$changed.Count;previous_public_download_reused=$cached})
}
Write-Host "Incremental reuse: reused $totalReused / changed $totalChanged of $($cat.Files.Count)"
if($totalReused+$totalChanged -ne $cat.Files.Count){throw 'Validation coverage mismatch'}
foreach($f in $changedEntries) {
    $p=Resolve-SafeChild $pack $f.Path
    if(-not [IO.File]::Exists($p) -or (Get-Item -LiteralPath $p).Length -ne $f.Bytes -or (Get-Sha256 $p) -cne $f.Sha256){throw "Public payload mismatch: $($f.Path)"}
}
$mode='full'
if($totalReused -gt 0){ $mode='incremental' }
$validation=@{release=$cat.Release;catalog_sha256=$hash;files=$cat.Files.Count;assets=$receipts.ToArray();anonymous=$true;verification_mode=$mode;reused_files=$totalReused;newly_verified_files=$totalChanged;previous_release=$priorRelease;previous_catalog_sha256=$priorCatalogSha;previous_validation_sha256=$priorValidationSha;prior_evidence=$priorEvidence;prior_evidence_sha256=($(if($priorEvidence){Get-Sha256 $priorEvidence}else{$null}));verified_utc=[DateTime]::UtcNow.ToString('o')}
[IO.File]::WriteAllText((Join-Path $output 'validation.json'),($validation|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Host "PUBLIC PAYLOAD VERIFIED: $($cat.Files.Count) files (reused $totalReused, changed $totalChanged, mode $mode)"
