#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$TrustPath,[Parameter(Mandatory=$true)][string]$ExpectedRelease)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 3.0
Import-Module (Join-Path $PSScriptRoot 'Online-Core.psm1') -Force -DisableNameChecking
$trust=Get-Content -LiteralPath $TrustPath -Raw -Encoding UTF8 | ConvertFrom-Json
$envelope=Receive-LimitedBytes 'https://raw.githubusercontent.com/Yukino-Chan/TGC-Anime-Total-Overhaul-Korean/update-feed/channel.json' 131072 $trust.repository
$e=[Text.Encoding]::UTF8.GetString($envelope)|ConvertFrom-Json
if($e.schema -ne 2){throw 'Public feed schema mismatch'}
$bytes=[Convert]::FromBase64String($e.channel)
$sig=[Convert]::FromBase64String($e.signature)
if(-not (Test-ChannelSignature $bytes $sig $trust.public_key_xml)){throw 'Public signature verification failed'}
$c=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
if($c.schema -ne 2 -or $c.repository -cne $trust.repository -or $c.release -cne $ExpectedRelease){throw 'Public channel mismatch'}
if($c.catalog_url -cne "https://ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/sha256:$($c.catalog_sha256)"){throw 'Public catalog URL mismatch'}
$raw=Receive-LimitedBytes $c.catalog_url 33554432 $trust.repository
$sha=[Security.Cryptography.SHA256]::Create()
try{$digest=([BitConverter]::ToString($sha.ComputeHash($raw))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
if($raw.Length -ne $c.catalog_bytes -or $digest -cne $c.catalog_sha256){throw 'Public catalog mismatch'}
$cat=Read-ValidatedCatalog $raw $trust.repository
if($cat.Release -cne $ExpectedRelease){throw 'Public catalog release mismatch'}
Write-Host "PUBLIC VERIFIED: $($cat.Release); $($cat.Files.Count) files; $($cat.Assets.Count) assets; catalog SHA256 $digest"
