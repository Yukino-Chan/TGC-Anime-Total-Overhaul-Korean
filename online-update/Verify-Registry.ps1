#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$Directory,[Parameter(Mandatory=$true)][string]$CacheDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 3.0
Import-Module (Join-Path $PSScriptRoot 'Online-Core.psm1') -Force -DisableNameChecking
Assert-NoReparsePoint $Directory
Assert-NoReparsePoint $CacheDirectory
[void][IO.Directory]::CreateDirectory($CacheDirectory)
$repo='Yukino-Chan/TGC-Anime-Total-Overhaul-Korean'
$expected=Join-Path $Directory 'catalog.json'
$hash=Get-Sha256 $expected
$raw=Receive-LimitedBytes "https://ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/sha256:$hash" 33554432 $repo
$local=[IO.File]::ReadAllBytes($expected)
if([Convert]::ToBase64String($raw) -cne [Convert]::ToBase64String($local)){throw 'Public catalog mismatch'}
$cat=Read-ValidatedCatalog $raw $repo
$output=Join-Path $Directory 'public-download'
Assert-NoReparsePoint $output
[void][IO.Directory]::CreateDirectory($output)
$pack=Join-Path $output 'pack'
$receipts=New-Object Collections.Generic.List[object]
$index=0
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
    # Resumable validation: already reconstructed entries are verified before reuse.
    $missing=@($entries | Where-Object { $p=Resolve-SafeChild $pack $_.Path; -not [IO.File]::Exists($p) -or (Get-Item -LiteralPath $p).Length -ne $_.Bytes -or (Get-Sha256 $p) -cne $_.Sha256 })
    if($missing.Count) { [void](Expand-SelectedAsset $object $missing $pack) }
    $receipts.Add(@{sha256=$id;bytes=$a.Bytes;files=$entries.Count;previous_public_download_reused=$cached})
}
foreach($f in $cat.Files) {
    $p=Resolve-SafeChild $pack $f.Path
    if((Get-Item -LiteralPath $p).Length -ne $f.Bytes -or (Get-Sha256 $p) -cne $f.Sha256){throw "Public payload mismatch: $($f.Path)"}
}
[IO.File]::WriteAllText((Join-Path $output 'validation.json'),(@{release=$cat.Release;catalog_sha256=$hash;files=$cat.Files.Count;assets=$receipts.ToArray();anonymous=$true;verified_utc=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Host "PUBLIC PAYLOAD VERIFIED: $($cat.Files.Count) files"
