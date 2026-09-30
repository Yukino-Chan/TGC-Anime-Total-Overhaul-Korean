#requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$CatalogPath,[Parameter(Mandatory=$true)][string]$KeyDirectory,[Parameter(Mandatory=$true)][string]$OutputDirectory)
Set-StrictMode -Version 3.0
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Online-Core.psm1') -Force -DisableNameChecking
Add-Type -AssemblyName System.Security
$utf8=[Text.UTF8Encoding]::new($false)
$repo='Yukino-Chan/TGC-Anime-Total-Overhaul-Korean'
foreach($p in @($CatalogPath,$KeyDirectory,$OutputDirectory)) { Assert-NoReparsePoint $p }
[void][IO.Directory]::CreateDirectory($KeyDirectory)
[void][IO.Directory]::CreateDirectory($OutputDirectory)
# Restrict the private directory before creating any key material.
$acl=New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true,$false)
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
$acl.AddAccessRule($rule)
[IO.Directory]::SetAccessControl($KeyDirectory,$acl)
$keyPath=Join-Path $KeyDirectory 'channel-key.dpapi'
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider(3072)
$rsa.PersistKeyInCsp=$false
$secret=$null
try {
    if ([IO.File]::Exists($keyPath)) {
        $secret=[Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($keyPath),$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        $rsa.FromXmlString($utf8.GetString($secret))
    } else {
        $secret=$utf8.GetBytes($rsa.ToXmlString($true))
        $protected=[Security.Cryptography.ProtectedData]::Protect($secret,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
        $stream=[IO.File]::Open($keyPath,[IO.FileMode]::CreateNew)
        try { $stream.Write($protected,0,$protected.Length) } finally { $stream.Dispose() }
    }
    $raw=[IO.File]::ReadAllBytes($CatalogPath)
    $cat=Read-ValidatedCatalog $raw $repo
    $channel=[ordered]@{schema=2;repository=$repo;release=$cat.Release;sequence=[long]($cat.Release.Substring(6).Replace('-',''));catalog_url="https://ghcr.io/v2/yukino-chan/tgcnv-patches/blobs/sha256:$(Get-Sha256 $CatalogPath)";catalog_bytes=$raw.Length;catalog_sha256=(Get-Sha256 $CatalogPath)}
    $bytes=$utf8.GetBytes(($channel | ConvertTo-Json -Compress))
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        $signer=New-Object Security.Cryptography.RSAPKCS1SignatureFormatter($rsa)
        $signer.SetHashAlgorithm('SHA256')
        $sig=$signer.CreateSignature($sha.ComputeHash($bytes))
    } finally { $sha.Dispose() }
    $envelope=[ordered]@{schema=2;channel=[Convert]::ToBase64String($bytes);signature=[Convert]::ToBase64String($sig)}
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'channel.json'),($envelope | ConvertTo-Json -Compress),$utf8)
    $public=$rsa.ToXmlString($false)
    if (-not (Test-ChannelSignature $bytes $sig $public)) { throw 'Self verification failed.' }
    [IO.File]::WriteAllBytes((Join-Path $OutputDirectory 'latest.json'),$bytes)
    [IO.File]::WriteAllBytes((Join-Path $OutputDirectory 'latest.sig'),$sig)
    [IO.File]::WriteAllText((Join-Path $OutputDirectory 'trust.json'),(@{schema=1;repository=$repo;public_key_xml=$public}|ConvertTo-Json),$utf8)
    Write-Host "Signed $($cat.Release) (public verification passed)."
} finally {
    if ($secret) { [Array]::Clear($secret,0,$secret.Length) }
    $rsa.Dispose()
}
