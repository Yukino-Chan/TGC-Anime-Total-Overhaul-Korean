#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$TrustPath,[Parameter(Mandatory=$true)][string]$ExpectedRelease)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 3.0
Import-Module (Join-Path $PSScriptRoot 'Online-Core.psm1') -Force -DisableNameChecking
$trust=Get-Content -LiteralPath $TrustPath -Raw -Encoding UTF8 | ConvertFrom-Json
$base="https://github.com/$($trust.repository)/releases/download/update-channel"
$bytes=Receive-LimitedBytes "$base/latest.json" 65536 $trust.repository
$sig=Receive-LimitedBytes "$base/latest.sig" 1024 $trust.repository
if(-not (Test-ChannelSignature $bytes $sig $trust.public_key_xml)){throw 'Public signature verification failed'}
$c=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
if($c.schema -ne 1 -or $c.repository -cne $trust.repository -or $c.release -cne $ExpectedRelease){throw 'Public channel mismatch'}
$raw=Receive-LimitedBytes $c.catalog_url 33554432 $trust.repository
$sha=[Security.Cryptography.SHA256]::Create()
try{$digest=([BitConverter]::ToString($sha.ComputeHash($raw))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
if($raw.Length -ne $c.catalog_bytes -or $digest -cne $c.catalog_sha256){throw 'Public catalog mismatch'}
$cat=Read-ValidatedCatalog $raw $trust.repository
if($cat.Release -cne $ExpectedRelease){throw 'Public catalog release mismatch'}
Write-Host "PUBLIC VERIFIED: $($cat.Release); $($cat.Files.Count) files; $($cat.Assets.Count) assets; catalog SHA256 $digest"
