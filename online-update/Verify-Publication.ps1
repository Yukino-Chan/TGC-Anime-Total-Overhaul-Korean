#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$Directory)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Online-Core.psm1') -Force -DisableNameChecking
$trust=Get-Content -LiteralPath (Join-Path $Directory 'channel/trust.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$bytes=[IO.File]::ReadAllBytes((Join-Path $Directory 'channel/latest.json'))
$sig=[IO.File]::ReadAllBytes((Join-Path $Directory 'channel/latest.sig'))
if (-not (Test-ChannelSignature $bytes $sig $trust.public_key_xml)) { throw 'Invalid channel signature' }
$channel=[Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
if ($channel.catalog_sha256 -cne (Get-Sha256 (Join-Path $Directory 'catalog.json'))) { throw 'Catalog mismatch' }
$cat=Read-ValidatedCatalog ([IO.File]::ReadAllBytes((Join-Path $Directory 'catalog.json'))) $trust.repository
if ($cat.Release -cne $channel.release) { throw 'Release mismatch' }
Write-Host "Validated signed catalog: $($cat.Files.Count) files."
