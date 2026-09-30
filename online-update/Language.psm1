#requires -Version 5.1
# TGCNV language choice support.
# payload/game/mod/TGCNV/localisation/*.csv stays canonical Korean; complete
# same-file-set trees ship under payload/game/mod/TGCNV/runtime/languages/{ko,en}/
# localisation and are already hash-protected by the existing payload manifest.
# The choice marker mod/TGCNV/runtime/language.json (schema=1) is generated at
# staging inside the staged mod directory, so the existing whole-mod transaction
# and Restore cover marker, active localisation and descriptor suffix unchanged.
Set-StrictMode -Version Latest

$script:SupportedLanguages = @('ko','en')
$script:ModRelative        = 'mod/TGCNV'
$script:CatalogRelative    = 'payload/game/mod/TGCNV/runtime/languages/catalog.json'
$script:CanonLocPrefix     = 'payload/game/mod/TGCNV/localisation/'

function Assert-LangPath([string]$Path) {
    $p = [IO.Path]::GetFullPath($Path)
    while ($p) {
        if (Test-Path -LiteralPath $p) {
            if ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "연결 폴더(junction/symlink)는 지원하지 않습니다 / Reparse points are not supported: $p"
            }
        }
        $parent = [IO.Path]::GetDirectoryName($p)
        if ($parent -eq $p) { break }
        $p = $parent
    }
}
function Get-LangChild([string]$Root,[string]$Relative,[switch]$SkipLinkCheck) {
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)') { throw '잘못된 상대 경로입니다 / Invalid relative path.' }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $p = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (-not $p.StartsWith($base,[StringComparison]::OrdinalIgnoreCase)) { throw '허용된 폴더를 벗어났습니다 / Path escapes the allowed root.' }
    if (-not $SkipLinkCheck) { Assert-LangPath $p }
    return $p
}
function Get-JsonProp($Object,[string]$Name) {
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}
function ConvertTo-Sha256([byte[]]$Bytes) {
    $h = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($h.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant() }
    finally { $h.Dispose() }
}
function Get-FileSha256([string]$Path) {
    $s = [IO.File]::OpenRead($Path)
    $h = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($h.ComputeHash($s)).Replace('-','').ToLowerInvariant() }
    finally { $s.Dispose(); $h.Dispose() }
}
function Get-ManifestIndex($Manifest) {
    $index = New-Object 'Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in $Manifest.files) { $index[$entry.path] = $entry }
    return ,$index
}
function Get-LocalisationNameSet($Index,[string]$Prefix) {
    $set = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($key in $Index.Keys) {
        if ($key.StartsWith($Prefix,[StringComparison]::OrdinalIgnoreCase)) {
            $rest = $key.Substring($Prefix.Length)
            if ($rest.Length -gt 0 -and $rest -notmatch '[\\/]') { [void]$set.Add($rest) }
        }
    }
    return ,$set
}

function Get-ScriptFileSet($Catalog,$Index) {
    $set=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $declared=Get-JsonProp $Catalog 'script_files'
    if ($null -ne $declared) {
        foreach ($relative in @($declared)) {
            if ($relative -isnot [string] -or $relative -cnotmatch '^(decisions|events|history/wars)/[^/\\:]+\.txt$' -or $relative.Contains('..')) { throw 'Invalid language script path.' }
            if (-not $set.Add($relative)) { throw 'Duplicate language script path.' }
            $canonical='payload/game/mod/TGCNV/'+$relative
            if (-not $Index.ContainsKey($canonical)) { throw 'Language script has no canonical source.' }
            foreach ($lang in @('ko','en')) {
                $variant='payload/game/mod/TGCNV/runtime/languages/'+$lang+'/script-text/'+$relative
                if (-not $Index.ContainsKey($variant)) { throw 'Incomplete language script bank.' }
                if ($lang -eq 'ko' -and $Index[$variant].sha256 -cne $Index[$canonical].sha256) { throw 'Korean script source differs from canonical payload.' }
            }
        }
    }
    foreach ($lang in @('ko','en')) {
        $prefix='payload/game/mod/TGCNV/runtime/languages/'+$lang+'/script-text/'
        foreach ($path in $Index.Keys) {
            if ($path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -and -not $set.Contains($path.Substring($prefix.Length))) { throw 'Undeclared language script file.' }
        }
    }
    return ,$set
}

# Strictly validated view of runtime/languages/catalog.json. Returns $null for
# old packs without a catalog. A non-ko language is offered only when its
# manifest-verified file set matches the canonical set; incomplete languages are
# excluded with a warning instead of breaking Korean installs.
function Read-LanguageCatalog {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PackRoot,[Parameter(Mandatory)]$Manifest)
    $catalogPath = Get-LangChild $PackRoot $script:CatalogRelative
    $index = Get-ManifestIndex $Manifest
    if (-not $index.ContainsKey($script:CatalogRelative)) {
        if ([IO.File]::Exists($catalogPath)) { throw 'Unlisted language catalog.' }
        return $null
    }
    if (-not [IO.File]::Exists($catalogPath) -or (Get-FileSha256 $catalogPath) -cne $index[$script:CatalogRelative].sha256) { throw 'Language catalog failed verification.' }
    try { $json = [IO.File]::ReadAllText($catalogPath,[Text.UTF8Encoding]::new($false)) | ConvertFrom-Json -ErrorAction Stop }
    catch { throw '언어 목록 파일이 손상되었습니다 / Language catalog is invalid.' }
    $schema = Get-JsonProp $json 'schema'
    $default = Get-JsonProp $json 'default'
    $languages = Get-JsonProp $json 'languages'
    if ($schema -ne 1 -or $default -cne 'ko' -or $null -eq $languages) {
        throw '지원하지 않는 언어 목록 형식입니다 / Unsupported language catalog (schema=1, default=ko required).'
    }
    $langs = @($languages)
    if ($langs.Count -lt 1) { throw '언어 목록이 비었습니다 / Language catalog has no languages.' }
    $seen = @{}
    foreach ($l in $langs) {
        if ($l -isnot [string] -or $l -cnotin $script:SupportedLanguages) { throw "지원하지 않는 언어입니다 / Unsupported language: $l" }
        if ($seen.ContainsKey($l)) { throw '언어 목록이 중복되었습니다 / Duplicate language in catalog.' }
        $seen[$l] = $true
    }
    if (-not $seen.ContainsKey($default)) { throw '기본 언어가 목록에 없습니다 / Default language missing from list.' }
    $index = Get-ManifestIndex $Manifest
    $canonSet = Get-LocalisationNameSet $index $script:CanonLocPrefix
    if ($canonSet.Count -lt 1) { throw '원본 한국어 현지화 파일이 목록에 없습니다 / Canonical localisation files are missing.' }
    $offer = @('ko')
    foreach ($l in $langs) {
        if ($l -ceq 'ko') { continue }
        $langPrefix = "payload/game/mod/TGCNV/runtime/languages/$l/localisation/"
        $langSet = Get-LocalisationNameSet $index $langPrefix
        foreach ($name in $langSet) {
            $p = Get-LangChild $PackRoot ($langPrefix + $name)
            if (-not [IO.File]::Exists($p) -or (Get-FileSha256 $p) -cne $index[$langPrefix + $name].sha256) { throw 'Language file failed verification.' }
        }
        $missing = @($canonSet | Where-Object { -not $langSet.Contains($_) })
        $extra = @($langSet | Where-Object { -not $canonSet.Contains($_) })
        if ($langSet.Count -lt 1 -or $missing.Count -gt 0 -or $extra.Count -gt 0) {
            Write-Warning "언어 파일이 불완전하여 선택지에서 제외합니다 / Incomplete localisation excluded: $l (missing $($missing.Count), extra $($extra.Count))"
            continue
        }
        $offer += $l
    }
    $scripts=Get-ScriptFileSet $json $index
    foreach ($relative in $scripts) {
        foreach ($l in @('ko','en')) {
            $rel='payload/game/mod/TGCNV/runtime/languages/'+$l+'/script-text/'+$relative
            $p=Get-LangChild $PackRoot $rel
            if (-not [IO.File]::Exists($p) -or (Get-FileSha256 $p) -cne $index[$rel].sha256) { throw 'Language script failed verification.' }
        }
    }
    return [pscustomobject]@{ Schema=1; Default=$default; Languages=[string[]]$offer; ScriptFiles=@($scripts) }
}

# Returns $null when no marker exists (pre-language installs default to ko).
# A present but malformed marker fails loudly instead of guessing a language.
function Read-InstalledLanguage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ModRoot)
    $markerPath = Get-LangChild $ModRoot 'runtime/language.json'
    if (-not [IO.File]::Exists($markerPath)) { return $null }
    try { $json = [IO.File]::ReadAllText($markerPath,[Text.UTF8Encoding]::new($false)) | ConvertFrom-Json -ErrorAction Stop }
    catch { throw '언어 기록 파일이 손상되었습니다. 게임 폴더를 확인하세요 / Language marker is corrupted.' }
    $schema = Get-JsonProp $json 'schema'
    $language = Get-JsonProp $json 'language'
    if ($schema -ne 1 -or $language -cnotin $script:SupportedLanguages) {
        throw '언어 기록 파일 형식이 올바르지 않습니다 / Language marker is invalid.'
    }
    return $language
}

function Show-LanguagePicker {
    [CmdletBinding()]
    param([ValidateSet('ko','en')][string]$Current='ko')
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $form = New-Object Windows.Forms.Form
    $form.Text = 'TGCNV 언어 선택 / Language'
    $form.FormBorderStyle = [Windows.Forms.FormBorderStyle]::FixedDialog
    $form.StartPosition = [Windows.Forms.FormStartPosition]::CenterScreen
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object Drawing.Size(340,120)
    $label = New-Object Windows.Forms.Label
    $label.AutoSize = $true
    $label.Location = New-Object Drawing.Point(12,12)
    $label.Text = "게임 텍스트 언어를 선택하세요.`r`nChoose the in-game text language."
    $combo = New-Object Windows.Forms.ComboBox
    $combo.DropDownStyle = [Windows.Forms.ComboBoxStyle]::DropDownList
    [void]$combo.Items.Add('한국어 (Korean)')
    [void]$combo.Items.Add('English')
    $combo.SelectedIndex = if ($Current -eq 'en') { 1 } else { 0 }
    $combo.Location = New-Object Drawing.Point(12,50)
    $combo.Width = 316
    $ok = New-Object Windows.Forms.Button
    $ok.Text = '확인 / OK'
    $ok.DialogResult = [Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object Drawing.Point(160,86)
    $ok.Width = 80
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = '취소 / Cancel'
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $cancel.Location = New-Object Drawing.Point(248,86)
    $cancel.Width = 80
    $form.Controls.AddRange(@($label,$combo,$ok,$cancel))
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel
    $result = $form.ShowDialog()
    $choice = $combo.SelectedIndex
    $form.Dispose()
    if ($result -ne [Windows.Forms.DialogResult]::OK) { throw '언어 선택을 취소했습니다 / Language selection cancelled.' }
    if ($choice -eq 1) { return 'en' }
    return 'ko'
}

# Decision order: explicit parameter -> remembered installed marker -> UI (only
# when this pack offers more than one language) -> default ko without UI.
function Resolve-LanguageChoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Auto','ko','en')][string]$Requested,
        [AllowNull()]$Catalog,
        [AllowNull()][string]$Installed
    )
    if ($Requested -cne 'Auto') {
        if ($Requested -ceq 'ko') { return 'ko' }   # canonical Korean is always available
        if ($null -eq $Catalog) { throw '이 설치 팩에는 언어 선택 파일이 없습니다 / This pack has no language choice files.' }
        if ($Requested -cnotin $Catalog.Languages) { throw '이 설치 팩에서 지원하지 않는 언어입니다 / This pack does not offer that language.' }
        return $Requested
    }
    if ($Installed) {
        if ($Catalog -and $Installed -cin $Catalog.Languages) { return $Installed }
        if ($Installed -ceq 'en') { throw 'English is unavailable in this release; language preference was preserved. / 이 배포에는 영문이 없습니다.' }
        return 'ko'
    }
    if ($Catalog) {
        if (@($Catalog.Languages).Count -gt 1) { return Show-LanguagePicker }
        return $Catalog.Default
    }
    return 'ko'
}

# Rewrites only the (Korean)/(English) suffix of the descriptor's quoted name
# value, preserving all other bytes (Latin-1 round trip, like launcher.cfg).
function Convert-ModDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][ValidateSet('ko','en')][string]$Language
    )
    $enc = [Text.Encoding]::GetEncoding(28591)
    $text = $enc.GetString($Bytes)
    $target = if ($Language -eq 'en') { 'English' } else { 'Korean' }
    $other  = if ($Language -eq 'en') { 'Korean' } else { 'English' }
    $pattern = '(?m)^([ \t]*name[ \t]*=[ \t]*"[^"\r\n]*)\(' + $other + '\)(")'
    $matches = [regex]::Matches($text,$pattern)
    if ($matches.Count -gt 1) { throw '모드 설명(.mod)의 name 항목이 여러 개입니다 / Multiple name entries in descriptor.' }
    if ($matches.Count -eq 0) {
        if ($Language -eq 'en') { throw '모드 설명(.mod)에서 (Korean) 이름 끝맺음을 찾지 못했습니다 / Descriptor name suffix not found.' }
        return ,$Bytes
    }
    $newText = [regex]::Replace($text,$pattern,('${1}(' + $target + ')${2}'))
    return ,$enc.GetBytes($newText)
}

function Convert-MusicDescriptor {
    param([byte[]]$Bytes,[ValidateSet('ko','en')][string]$Language)
    $enc=[Text.Encoding]::GetEncoding(28591)
    $text=$enc.GetString($Bytes)
    $blocks=[regex]::Matches($text,'(?ms)\bdependencies\s*=\s*\{([^{}]*)\}')
    if ($blocks.Count -ne 1) { throw 'TGO dependency block is missing or ambiguous.' }
    $source=if ($Language -eq 'en') { 'Korean' } else { 'English' }
    $target=if ($Language -eq 'en') { 'English' } else { 'Korean' }
    $old='"TGC - Anime Total Overhaul ('+$source+')"'
    $new='"TGC - Anime Total Overhaul ('+$target+')"'
    $body=$blocks[0].Groups[1]
    if ($body.Value.Contains($new) -and -not $body.Value.Contains($old)) { return ,$Bytes }
    if ([regex]::Matches($body.Value,[regex]::Escape($old)).Count -ne 1) { throw 'TGO does not reference the expected TGCNV mod name.' }
    $replacement=$body.Value.Replace($old,$new)
    return ,$enc.GetBytes($text.Substring(0,$body.Index)+$replacement+$text.Substring($body.Index+$body.Length))
}

# Maps a canonical localisation payload path to its per-language variant path,
# or $null when the file has no language variant. Used by the updater reuse scan.
function Get-LanguageVariantPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PayloadPath,
        [Parameter(Mandatory)][ValidateSet('ko','en')][string]$Language
    )
    $modPrefix='payload/game/mod/TGCNV/'
    if ($PayloadPath.StartsWith($modPrefix,[StringComparison]::OrdinalIgnoreCase)) {
        $rel=$PayloadPath.Substring($modPrefix.Length)
        if ($rel -cmatch '^(decisions|events|history/wars)/[^/\\:]+\.txt$' -and -not $rel.Contains('..')) {
            return "payload/game/mod/TGCNV/runtime/languages/$Language/script-text/$rel"
        }
    }
    if (-not $PayloadPath.StartsWith($script:CanonLocPrefix,[StringComparison]::OrdinalIgnoreCase)) { return $null }
    $rest = $PayloadPath.Substring($script:CanonLocPrefix.Length)
    if ($rest.Length -lt 1 -or $rest -match '[\\/]') { return $null }
    return "payload/game/mod/TGCNV/runtime/languages/$Language/localisation/$rest"
}

# Runs after the existing staged file-copy hash validation and before any real
# file move. Overwrites staged active localisation from the selected staged
# runtime/languages subtree, re-verifies every written byte against manifest
# entries, swaps the staged .mod name suffix, and writes the marker.
function Set-StagedLanguage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StageGameRoot,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][ValidateSet('ko','en')][string]$Language
    )
    Assert-LangPath $StageGameRoot
    $index = Get-ManifestIndex $Manifest
    $modStage = Get-LangChild $StageGameRoot $script:ModRelative
    $descStage = Get-LangChild $StageGameRoot 'mod/TGCNV.mod'
    if (-not [IO.File]::Exists($descStage)) { throw '모드 설명 파일(.mod)이 준비되지 않았습니다 / Descriptor missing from stage.' }
    $origDesc = [IO.File]::ReadAllBytes($descStage)
    $newDesc = Convert-ModDescriptor $origDesc $Language
    if ((ConvertTo-Sha256 $origDesc) -cne (ConvertTo-Sha256 $newDesc)) {
        [IO.File]::WriteAllBytes($descStage,$newDesc)
    }
    $musicStage=Get-LangChild $StageGameRoot 'mod/TGO.mod'
    if ([IO.File]::Exists($musicStage)) {
        [IO.File]::WriteAllBytes($musicStage,(Convert-MusicDescriptor ([IO.File]::ReadAllBytes($musicStage)) $Language))
    }
    $langLocRel = "runtime/languages/$Language/localisation"
    $langLocPrefix = "payload/game/mod/TGCNV/$langLocRel/"
    $canonSet = Get-LocalisationNameSet $index $script:CanonLocPrefix
    $langSet = Get-LocalisationNameSet $index $langLocPrefix
    if ($Language -ceq 'ko' -and $langSet.Count -eq 0) {
        # Canonical Korean is already staged; packs may rely on that.
    } else {
        $missing = @($canonSet | Where-Object { -not $langSet.Contains($_) })
        $extra = @($langSet | Where-Object { -not $canonSet.Contains($_) })
        if ($canonSet.Count -lt 1 -or $missing.Count -gt 0 -or $extra.Count -gt 0) {
            throw "선택한 언어 파일이 불완전합니다(누락 $($missing.Count), 추가 $($extra.Count)) / Selected language files are incomplete."
        }
        foreach ($name in $langSet) {
            $srcEntry = $index[$langLocPrefix + $name]
            $src = Get-LangChild $modStage "$langLocRel/$name"
            $dst = Get-LangChild $modStage "localisation/$name"
            if (-not [IO.File]::Exists($src) -or (Get-FileSha256 $src) -cne $srcEntry.sha256) {
                throw "언어 원본 검증 실패 / Language source failed verification: $name"
            }
            if (-not [IO.File]::Exists($dst)) { throw "원본 현지화 파일이 없습니다 / Canonical file missing: $name" }
            [IO.File]::Copy($src,$dst,$true)
            if ((Get-FileSha256 $dst) -cne $srcEntry.sha256) {
                throw "언어 적용 검증 실패 / Language copy failed verification: $name"
            }
        }
    }
    $catalogPath=Get-LangChild $modStage 'runtime/languages/catalog.json'
    if (-not $index.ContainsKey($script:CatalogRelative) -or (Get-FileSha256 $catalogPath) -cne $index[$script:CatalogRelative].sha256) { throw 'Staged language catalog failed verification.' }
    $catalog=[IO.File]::ReadAllText($catalogPath,[Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
    $scripts=Get-ScriptFileSet $catalog $index
    foreach ($relative in $scripts) {
        $rel="runtime/languages/$Language/script-text/$relative"
        $src=Get-LangChild $modStage $rel
        $dst=Get-LangChild $modStage $relative
        $expected=$index['payload/game/mod/TGCNV/'+$rel].sha256
        if (-not [IO.File]::Exists($src) -or -not [IO.File]::Exists($dst) -or (Get-FileSha256 $src) -cne $expected) { throw 'Staged script language source failed verification.' }
        [IO.File]::Copy($src,$dst,$true)
        if ((Get-FileSha256 $dst) -cne $expected) { throw 'Script language copy failed verification.' }
    }
    $runtimeDir = Get-LangChild $modStage 'runtime'
    if (-not [IO.Directory]::Exists($runtimeDir)) { [void][IO.Directory]::CreateDirectory($runtimeDir) }
    $markerPath = Get-LangChild $runtimeDir 'language.json'
    $markerTemp = $markerPath + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($markerTemp,(@{schema=1;language=$Language} | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    if ([IO.File]::Exists($markerPath)) { [IO.File]::Replace($markerTemp,$markerPath,[NullString]::Value) }
    else { [IO.File]::Move($markerTemp,$markerPath) }
    return [pscustomobject]@{ Language=$Language; Overlaid=$langSet.Count; Scripts=$scripts.Count }
}

Export-ModuleMember -Function @(
    'Read-LanguageCatalog',
    'Read-InstalledLanguage',
    'Resolve-LanguageChoice',
    'Show-LanguagePicker',
    'Convert-ModDescriptor',
    'Convert-MusicDescriptor',
    'Get-LanguageVariantPath',
    'Set-StagedLanguage'
)
