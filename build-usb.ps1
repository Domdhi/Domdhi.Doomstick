# build-usb.ps1 — fetch the runtime + GGUFs and assemble the kit on a target dir.
#
# Modes:
#   .\build-usb.ps1 <target-dir>                  Wizard (or sources existing config)
#   .\build-usb.ps1 -y <target-dir>               Skip wizard, use baked defaults
#   .\build-usb.ps1 -c <conf.ps1> <target-dir>    Source the named config file
#   .\build-usb.ps1 -i <target-dir>               Force wizard even if config exists
#   .\build-usb.ps1 -n <target-dir>               Dry-run: resolve config, print, exit
#   .\build-usb.ps1 -h                            Show help
#
# After an interactive run, settings are saved to <target>\build-usb-config.ps1
# so re-running on the same target skips prompts. Pass -i to re-prompt.

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Arg1,
    [Parameter(Position = 1)]
    [string]$Arg2,
    [Parameter(Position = 2)]
    [string]$Arg3,
    [switch]$y,
    [switch]$NonInteractive,
    [switch]$i,
    [switch]$Interactive,
    [switch]$n,
    [switch]$DryRun,
    [string]$c,
    [string]$Config,
    [switch]$h,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$Repo    = $PSScriptRoot
$Presets = Join-Path $Repo 'presets'

# ---------------------------------------------------------------- usage

function Show-Usage {
    @"
Usage:
  .\build-usb.ps1 <target-dir>                Wizard mode (or sources <target>\build-usb-config.ps1)
  .\build-usb.ps1 -y <target-dir>             Non-interactive — use baked defaults
  .\build-usb.ps1 -c <config.ps1> <target>    Source the named config file
  .\build-usb.ps1 -i <target-dir>             Force wizard even if config exists at target
  .\build-usb.ps1 -n <target-dir>             Dry-run: resolve config, print, exit
  .\build-usb.ps1 -h                          This help

Examples:
  .\build-usb.ps1 D:\                         Wizard, then build
  .\build-usb.ps1 $env:TEMP\doomstick-test    Local dry-run target (any writable dir)
  .\build-usb.ps1 -y D:\                      CI / scripted builds

Defaults / 'full' bundle download size:
  AI core    ~22.3 GB   (43 MB runtime + 5 GB E4B + 17 GB 26B + 329 MB embed)
  Side arms  ~ 910 MB   (whisperfile small.en + kiwix + simple-en zim + tesseract + monaco pbf)
  TTS        ~ 210 MB   (sherpa-onnx per-OS + Supertonic int8 model)
  Image gen  ~ 2.6 GB   (sd.cpp per-OS + FLUX.2 klein 4B Q4_K_M)
  Total      ~28.5 GB   (full; ~23.3 GB without image gen)

Re-runs skip files already present with the right size.
"@ | Write-Host
}

# ---------------------------------------------------------------- arg parsing

if ($h -or $Help -or $Arg1 -in @('-h','--help','/?')) { Show-Usage; exit 0 }

# Map both short and long forms to canonical bools/strings.
$ForceWizard = ($i -or $Interactive)
$DryRunMode  = ($n -or $DryRun)
$ConfigPath  = if ($c) { $c } elseif ($Config) { $Config } else { $null }

$Target = $null
if ($ConfigPath) {
    # When -c is used, target is the next positional. Could be Arg1 or Arg2 depending
    # on PowerShell's binding (-c <path> Arg1=path? or Arg1 already taken?). Resolve:
    $Target = if ($Arg1 -and $Arg1 -ne $ConfigPath) { $Arg1 } else { $Arg2 }
} else {
    $Target = $Arg1
}

if (-not $Target) { Show-Usage; exit 2 }

$Mode = 'wizard'
if ($y -or $NonInteractive) { $Mode = 'noninteractive' }
elseif ($ConfigPath)        { $Mode = 'config' }

# ---------------------------------------------------------------- baked defaults

function Apply-BakedDefaults {
    $script:DoomIncludeE4b      = 1
    $script:DoomIncludeMoe      = 1
    $script:DoomIncludeEmb      = 1

    $script:DoomIncludeWiki     = 1
    $script:DoomZimUrl          = 'https://download.kiwix.org/zim/wikipedia/wikipedia_en_simple_all_nopic_2026-02.zim'
    $script:DoomZimFile         = 'wikipedia_en_simple_all_nopic_2026-02.zim'
    $script:DoomZimBytes        = 966064955
    $script:DoomZimLabel        = 'Simple English'

    $script:DoomIncludeOsm      = 1
    $script:DoomPbfUrl          = 'https://download.geofabrik.de/europe/monaco-latest.osm.pbf'
    $script:DoomPbfFile         = 'monaco-latest.osm.pbf'
    $script:DoomPbfBytes        = 700000

    $script:DoomIncludeWhisper  = 1
    $script:DoomWhisperUrl      = 'https://huggingface.co/Mozilla/whisperfile/resolve/main/whisper-small.en.llamafile?download=true'
    $script:DoomWhisperFile     = 'whisper-small.en.llamafile'
    $script:DoomWhisperBytes    = 497053916
    $script:DoomWhisperLabel    = 'small.en'

    $script:DoomIncludeOcr      = 1
    $script:DoomOcrLangs        = 'eng'

    $script:DoomIncludeDocs     = 1

    $script:DoomIncludeRedbean  = 1
    $script:DoomIncludeDoom     = 1
    $script:DoomIncludeTts      = 1
    $script:DoomIncludeImg      = 1
    $script:DoomIncludePasswords = 1
    $script:DoomIncludeFfmpeg   = 1
    $script:DoomIncludeDevtools    = 1
    $script:DoomIncludeFieldmanual = 1
}

# ---------------------------------------------------------------- TSV loader

function Import-Tsv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Error "Missing preset file: $Path"; exit 2
    }
    $rows = @()
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }
        $rows += ,($line -split "`t")
    }
    return $rows
}

# ---------------------------------------------------------------- prompt helpers

function Read-Choice {
    param([string]$Label, [int]$DefaultIdx, [string[]]$Options)
    while ($true) {
        Write-Host ''
        Write-Host "  $Label"
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $marker = if (($i + 1) -eq $DefaultIdx) { '* ' } else { '  ' }
            Write-Host ("{0}[{1}] {2}" -f $marker, ($i+1), $Options[$i])
        }
        $reply = Read-Host ("  Pick [1-{0}, default {1}]" -f $Options.Count, $DefaultIdx)
        if (-not $reply) { return $DefaultIdx }
        if ($reply -match '^\d+$') {
            $n = [int]$reply
            if ($n -ge 1 -and $n -le $Options.Count) { return $n }
        }
        Write-Host "  → invalid, try again"
    }
}

function Read-YesNo {
    param([string]$Label, [string]$Default = 'Y')
    $hint = if ($Default -eq 'N') { '[y/N]' } else { '[Y/n]' }
    while ($true) {
        $reply = Read-Host ("  $Label $hint")
        if (-not $reply) { $reply = $Default }
        switch -Regex ($reply) {
            '^[Yy]([Ee][Ss])?$' { return $true }
            '^[Nn]([Oo])?$'     { return $false }
            default             { Write-Host "  → answer y or n" }
        }
    }
}

function Read-Subset {
    param([string]$Label, [string[]]$Keys, [string[]]$Labels, [string]$DefaultCsv)
    while ($true) {
        Write-Host ''
        Write-Host "  $Label"
        for ($i = 0; $i -lt $Keys.Count; $i++) {
            $isDefault = $DefaultCsv.Split(',') -contains $Keys[$i]
            $marker = if ($isDefault) { '* ' } else { '  ' }
            Write-Host ("{0}[{1}] {2}" -f $marker, $Keys[$i], $Labels[$i])
        }
        $sample = if ($Keys.Count -ge 2) { "{0},{1}" -f $Keys[0], $Keys[1] } else { $Keys[0] }
        $reply = Read-Host ("  Pick subset (e.g. '$sample' or 'all' or 'none', default '$DefaultCsv')")
        if (-not $reply) { $reply = $DefaultCsv }
        $reply = ($reply -replace '\s', '')
        if ($reply -eq 'all')  { return ($Keys -join ',') }
        if ($reply -eq 'none') { return '' }
        $tokens = $reply.Split(',') | Where-Object { $_ }
        $unknown = $tokens | Where-Object { $Keys -notcontains $_ }
        if ($unknown) {
            Write-Host ("  → unknown key: " + ($unknown -join ', '))
        } else {
            return ($tokens -join ',')
        }
    }
}

function Read-StringWithDefault {
    param([string]$Label, [string]$Default)
    $reply = Read-Host ("  $Label [$Default]")
    if (-not $reply) { return $Default }
    return $reply
}

function Format-Bytes {
    param([long]$N)
    if ($N -ge 1000000000) { return ("{0:N1} GB" -f ($N / 1GB)) }
    elseif ($N -ge 1000000) { return ("{0:N0} MB" -f ($N / 1MB)) }
    else                    { return ("{0:N0} KB" -f ($N / 1KB)) }
}

# ---------------------------------------------------------------- bundles

function Apply-Bundle {
    param([string]$Name)
    $rows = Import-Tsv (Join-Path $Presets 'bundles.tsv')
    $row = $rows | Where-Object { $_[0] -eq $Name } | Select-Object -First 1
    if (-not $row) { Write-Error "Unknown bundle: $Name"; exit 2 }
    # Schema (v0.12, 23 columns):
    #   0 name  1 label  2 e4b  3 moe  4 emb  5 wiki  6 osm  7 whisper  8 ocr  9 docs
    #   10 redbean  11 doom  12 tts  13 img  14 passwords  15 ffmpeg
    #   16 devtools  17 fieldmanual
    #   18 zim_idx  19 osm_idx  20 whisper_idx  21 estimated_bytes  22 summary
    $script:DoomIncludeE4b       = [int]$row[2]
    $script:DoomIncludeMoe       = [int]$row[3]
    $script:DoomIncludeEmb       = [int]$row[4]
    $script:DoomIncludeWiki      = [int]$row[5]
    $script:DoomIncludeOsm       = [int]$row[6]
    $script:DoomIncludeWhisper   = [int]$row[7]
    $script:DoomIncludeOcr       = [int]$row[8]
    $script:DoomIncludeDocs      = [int]$row[9]
    $script:DoomIncludeRedbean   = [int]$row[10]
    $script:DoomIncludeDoom      = [int]$row[11]
    $script:DoomIncludeTts       = [int]$row[12]
    $script:DoomIncludeImg       = [int]$row[13]
    $script:DoomIncludePasswords = [int]$row[14]
    $script:DoomIncludeFfmpeg      = [int]$row[15]
    $script:DoomIncludeDevtools    = [int]$row[16]
    $script:DoomIncludeFieldmanual = [int]$row[17]
    $zimIdx     = [int]$row[18]
    $osmIdx     = [int]$row[19]
    $whisperIdx = [int]$row[20]

    if ($DoomIncludeWiki -eq 1 -and $zimIdx -ge 1) {
        $z = (Import-Tsv (Join-Path $Presets 'zim.tsv'))[$zimIdx-1]
        $script:DoomZimLabel = $z[0]
        $script:DoomZimUrl   = $z[1]
        $script:DoomZimFile  = $z[2]
        $script:DoomZimBytes = [long]$z[3]
    }
    if ($DoomIncludeOsm -eq 1 -and $osmIdx -ge 1) {
        $o = (Import-Tsv (Join-Path $Presets 'osm.tsv'))[$osmIdx-1]
        $script:DoomPbfUrl   = $o[1]
        $script:DoomPbfFile  = $o[2]
        $script:DoomPbfBytes = [long]$o[3]
    }
    if ($DoomIncludeWhisper -eq 1 -and $whisperIdx -ge 1) {
        $w = (Import-Tsv (Join-Path $Presets 'whisper.tsv'))[$whisperIdx-1]
        $script:DoomWhisperLabel = $w[0]
        $script:DoomWhisperUrl   = $w[1]
        $script:DoomWhisperFile  = $w[2]
        $script:DoomWhisperBytes = [long]$w[3]
    }
    $script:DoomOcrLangs = if ($DoomIncludeOcr -eq 1) { 'eng' } else { '' }
}

# ---------------------------------------------------------------- wizard

function Invoke-Wizard {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host '  DOOMSTICK Build Wizard'
    Write-Host "  Target: $Target"
    Write-Host '============================================================'

    # Bundle prelude
    $bundles = Import-Tsv (Join-Path $Presets 'bundles.tsv')
    $opts = @()
    foreach ($b in $bundles) { $opts += ("{0} — {1}" -f $b[0], $b[1]) }
    $opts += 'custom — pick each option individually'
    $pick = Read-Choice -Label 'Pick a bundle.' -DefaultIdx 2 -Options $opts

    if ($pick -le $bundles.Count) {
        Apply-Bundle -Name $bundles[$pick-1][0]
        return
    }

    Write-Host ''
    Write-Host '  --- Custom configuration ---'

    # 1. Models
    $modelsCsv = Read-Subset `
        -Label 'Which AI models?' `
        -Keys @('e4b','moe','emb') `
        -Labels @('Gemma 4 E4B (~5 GB)','Gemma 4 26B-A4B (~17 GB)','EmbeddingGemma 300M (~329 MB)') `
        -DefaultCsv 'e4b,emb'
    $script:DoomIncludeE4b = if ($modelsCsv -match '\be4b\b') { 1 } else { 0 }
    $script:DoomIncludeMoe = if ($modelsCsv -match '\bmoe\b') { 1 } else { 0 }
    $script:DoomIncludeEmb = if ($modelsCsv -match '\bemb\b') { 1 } else { 0 }

    # 2. ZIM
    $zimRows = Import-Tsv (Join-Path $Presets 'zim.tsv')
    $zOpts = @(); foreach ($r in $zimRows) { $zOpts += $r[0] }
    $zOpts += 'Custom URL'; $zOpts += 'Skip Wikipedia'
    $zPick = Read-Choice -Label 'Wikipedia ZIM?' -DefaultIdx 1 -Options $zOpts
    if ($zPick -le $zimRows.Count) {
        $script:DoomIncludeWiki = 1
        $r = $zimRows[$zPick-1]
        $script:DoomZimLabel = $r[0]
        $script:DoomZimUrl   = $r[1]
        $script:DoomZimFile  = $r[2]
        $script:DoomZimBytes = [long]$r[3]
    } elseif ($zPick -eq ($zimRows.Count + 1)) {
        $script:DoomIncludeWiki = 1
        $script:DoomZimUrl   = Read-StringWithDefault 'Custom ZIM URL' 'https://download.kiwix.org/zim/wikipedia/...'
        $script:DoomZimFile  = Split-Path -Leaf $DoomZimUrl
        $script:DoomZimBytes = 1000000
        $script:DoomZimLabel = 'custom'
    } else {
        $script:DoomIncludeWiki = 0
        $script:DoomZimUrl = ''; $script:DoomZimFile = ''; $script:DoomZimBytes = 0; $script:DoomZimLabel = '(skipped)'
    }

    # 3. OSM
    $osmRows = Import-Tsv (Join-Path $Presets 'osm.tsv')
    $oOpts = @(); foreach ($r in $osmRows) { $oOpts += $r[0] }
    $oOpts += 'Custom Geofabrik URL'; $oOpts += 'Skip maps'
    $oPick = Read-Choice -Label 'OSM region for mobile maps?' -DefaultIdx 1 -Options $oOpts
    if ($oPick -le $osmRows.Count) {
        $script:DoomIncludeOsm = 1
        $r = $osmRows[$oPick-1]
        $script:DoomPbfUrl   = $r[1]
        $script:DoomPbfFile  = $r[2]
        $script:DoomPbfBytes = [long]$r[3]
    } elseif ($oPick -eq ($osmRows.Count + 1)) {
        $script:DoomIncludeOsm = 1
        $script:DoomPbfUrl   = Read-StringWithDefault 'Custom .osm.pbf URL' 'https://download.geofabrik.de/...'
        $script:DoomPbfFile  = Split-Path -Leaf $DoomPbfUrl
        $script:DoomPbfBytes = 1000000
    } else {
        $script:DoomIncludeOsm = 0
        $script:DoomPbfUrl = ''; $script:DoomPbfFile = ''; $script:DoomPbfBytes = 0
    }

    # 4. Whisper
    $wRows = Import-Tsv (Join-Path $Presets 'whisper.tsv')
    $wOpts = @(); foreach ($r in $wRows) { $wOpts += $r[0] }
    $wOpts += 'Skip whisper'
    $wPick = Read-Choice -Label 'Whisper voice-to-text model?' -DefaultIdx 2 -Options $wOpts
    if ($wPick -le $wRows.Count) {
        $script:DoomIncludeWhisper = 1
        $r = $wRows[$wPick-1]
        $script:DoomWhisperLabel = $r[0]
        $script:DoomWhisperUrl   = $r[1]
        $script:DoomWhisperFile  = $r[2]
        $script:DoomWhisperBytes = [long]$r[3]
    } else {
        $script:DoomIncludeWhisper = 0
        $script:DoomWhisperUrl = ''; $script:DoomWhisperFile = ''; $script:DoomWhisperBytes = 0; $script:DoomWhisperLabel = '(skipped)'
    }

    # 5. OCR languages
    $oRows = Import-Tsv (Join-Path $Presets 'ocr.tsv')
    $ocrKeys = @(); $ocrLabels = @()
    foreach ($r in $oRows) { $ocrKeys += $r[0]; $ocrLabels += ("{0} — {1}" -f $r[0], $r[1]) }
    $ocrCsv = Read-Subset -Label 'OCR language packs?' -Keys $ocrKeys -Labels $ocrLabels -DefaultCsv 'eng'
    if ($ocrCsv) {
        $script:DoomIncludeOcr = 1
        $script:DoomOcrLangs   = ($ocrCsv -replace ',', ' ')
    } else {
        $script:DoomIncludeOcr = 0
        $script:DoomOcrLangs   = ''
    }

    # 6. DevDocs umbrella toggle
    $script:DoomIncludeDocs = if (Read-YesNo 'Include DevDocs landing zone? (manual setup, ~1 KB)' 'Y') { 1 } else { 0 }

    # 7. redbean local platform layer
    $script:DoomIncludeRedbean = if (Read-YesNo 'Include redbean local platform layer? (~5.5 MB, port 8768 — needed for DOOM)' 'Y') { 1 } else { 0 }

    # 8. DOOM — needs redbean
    if (Read-YesNo 'Include DOOM (Dwasm port + shareware DOOM1.WAD, ~7.5 MB)?' 'Y') {
        $script:DoomIncludeDoom = 1
        if ($DoomIncludeRedbean -ne 1) {
            Write-Host '  → DOOM needs redbean to serve. Re-enabling redbean.'
            $script:DoomIncludeRedbean = 1
        }
    } else {
        $script:DoomIncludeDoom = 0
    }

    # 9. TTS — Sherpa-ONNX runtime + Supertonic int8 model. Rides redbean's /tts.
    if (Read-YesNo 'Include TTS (Sherpa-ONNX + Supertonic, ~210 MB across 3 OS binaries + model)?' 'Y') {
        $script:DoomIncludeTts = 1
        if ($DoomIncludeRedbean -ne 1) {
            Write-Host '  → TTS rides on redbean''s /tts route. Re-enabling redbean.'
            $script:DoomIncludeRedbean = 1
        }
    } else {
        $script:DoomIncludeTts = 0
    }

    # 10. Image gen — sd.cpp + FLUX.2 klein 4B Q4_K_M (default N — heavy at ~2.6 GB)
    if (Read-YesNo 'Include offline image gen (sd.cpp + FLUX.2 klein 4B Q4, ~2.6 GB)?' 'N') {
        $script:DoomIncludeImg = 1
    } else {
        $script:DoomIncludeImg = 0
    }

    # 11. KeePassXC — cross-OS password manager (GPL-2.0+)
    if (Read-YesNo 'Include KeePassXC password manager (cross-OS, ~250 MB)?' 'Y') {
        $script:DoomIncludePasswords = 1
    } else {
        $script:DoomIncludePasswords = 0
    }

    # 12. ffmpeg — static cross-OS media swiss-army knife (GPL-3.0+)
    if (Read-YesNo 'Include static ffmpeg (cross-OS media swiss-army, ~210 MB)?' 'Y') {
        $script:DoomIncludeFfmpeg = 1
    } else {
        $script:DoomIncludeFfmpeg = 0
    }

    # 13. Dev tools — ripgrep + fzf + jq + 7-Zip + VSCodium
    if (Read-YesNo 'Include portable dev tools (ripgrep, fzf, jq, 7-Zip, VSCodium, ~280 MB)?' 'Y') {
        $script:DoomIncludeDevtools = 1
    } else {
        $script:DoomIncludeDevtools = 0
    }

    # 14. Field manual — public-domain corpus
    if (Read-YesNo 'Include field manual corpus (public-domain survival/first-aid/radio, ~1 MB)?' 'Y') {
        $script:DoomIncludeFieldmanual = 1
    } else {
        $script:DoomIncludeFieldmanual = 0
    }
}

# ---------------------------------------------------------------- estimate / free space

function Get-EstimatedTotalBytes {
    $total = 43800000  # runtime
    if ($DoomIncludeE4b -eq 1) { $total += 5000000000 }
    if ($DoomIncludeMoe -eq 1) { $total += 17000000000 }
    if ($DoomIncludeEmb -eq 1) { $total += 329000000 }
    if ($DoomIncludeWhisper -eq 1) { $total += $DoomWhisperBytes }
    if ($DoomIncludeWiki -eq 1)    { $total += $DoomZimBytes + 18000000 }
    if ($DoomIncludeOsm -eq 1)     { $total += $DoomPbfBytes }
    if ($DoomIncludeOcr -eq 1) {
        $total += 2600000
        $langs = $DoomOcrLangs -split '\s+' | Where-Object { $_ }
        $total += ($langs.Count * 12000000)
    }
    if ($DoomIncludeRedbean -eq 1) { $total += 5500000 }   # redbean.com
    if ($DoomIncludeDoom -eq 1)    { $total += 7500000 }   # Dwasm + DOOM1.WAD
    if ($DoomIncludeTts -eq 1)     { $total += 210000000 }  # sherpa runtime (3 OS) + Supertonic
    if ($DoomIncludeImg -eq 1)     { $total += 2646469190 } # sd.cpp 3-OS (~42 MB) + FLUX.2 klein 4B Q4_K_M (~2.6 GB)
    if ($DoomIncludePasswords -eq 1) { $total += 250000000 } # KeePassXC 3-OS (~47 MB AppImage + ~36 MB dmg + ~35 MB zip + extracted)
    if ($DoomIncludeFfmpeg    -eq 1) { $total += 210000000 } # ffmpeg 3-OS (~117 MB linux64 + ~28 MB mac + ~157 MB win)
    if ($DoomIncludeDevtools    -eq 1) { $total += 280000000 }  # devtools 5-tool cross-OS (VSCodium dominates ~240 MB)
    if ($DoomIncludeFieldmanual -eq 1) { $total += 1000000   }  # field-manual margin for user additions
    return $total
}

function Get-FreeBytesAt {
    param([string]$Path)
    try {
        $resolved = if (Test-Path -LiteralPath $Path) { Resolve-Path -LiteralPath $Path } else { $Repo }
        $drive = (Get-Item -LiteralPath $resolved).PSDrive
        if ($drive) { return [long]$drive.Free }
    } catch { }
    return 0
}

function Show-SummaryAndConfirm {
    $needed = Get-EstimatedTotalBytes
    $free   = Get-FreeBytesAt $Target

    Write-Host ''
    Write-Host '  ---------------- Summary ----------------'
    $models = ''
    if ($DoomIncludeE4b -eq 1) { $models += 'E4B ' }
    if ($DoomIncludeMoe -eq 1) { $models += '26B ' }
    if ($DoomIncludeEmb -eq 1) { $models += 'Embed ' }
    Write-Host ("  {0,-12} {1}" -f 'Models:',   $models)
    Write-Host ("  {0,-12} {1}" -f 'Wikipedia:', $(if ($DoomIncludeWiki -eq 1) { $DoomZimLabel } else { '(skipped)' }))
    Write-Host ("  {0,-12} {1}" -f 'OSM maps:',  $(if ($DoomIncludeOsm -eq 1) { $DoomPbfFile }   else { '(skipped)' }))
    Write-Host ("  {0,-12} {1}" -f 'Whisper:',   $(if ($DoomIncludeWhisper -eq 1) { $DoomWhisperLabel } else { '(skipped)' }))
    Write-Host ("  {0,-12} {1}" -f 'OCR:',       $(if ($DoomIncludeOcr -eq 1) { $DoomOcrLangs } else { '(skipped)' }))
    Write-Host ("  {0,-12} {1}" -f 'DevDocs:',   $(if ($DoomIncludeDocs -eq 1) { 'included (manual setup)' } else { '(skipped)' }))
    Write-Host ("  {0,-12} {1}" -f 'redbean:',   $(if ($DoomIncludeRedbean -eq 1) { 'included (port 8768)' } else { '(skipped)' }))
    Write-Host ("  {0,-12} {1}" -f 'DOOM:',      $(if ($DoomIncludeDoom -eq 1) { 'included (Dwasm + shareware WAD)' } else { '(skipped)' }))
    Write-Host ("  {0,-12} {1}" -f 'TTS:',       $(if ($DoomIncludeTts -eq 1) { 'included (Sherpa-ONNX + Supertonic int8)' } else { '(skipped)' }))
    Write-Host ("  {0,-12} {1}" -f 'Img gen:',   $(if ($DoomIncludeImg -eq 1) { 'included (sd.cpp + FLUX.2 klein 4B Q4_K_M)' } else { '(skipped)' }))
    Write-Host ("  {0,-12} {1}" -f 'Passwords:', $(if ($DoomIncludePasswords -eq 1) { 'included (KeePassXC password manager)' } else { '(skipped)' }))
    Write-Host ("  {0,-12} {1}" -f 'ffmpeg:',    $(if ($DoomIncludeFfmpeg -eq 1) { 'included (static ffmpeg, cross-OS media swiss-army)' } else { '(skipped)' }))
    Write-Host ("  {0,-12} {1}" -f 'Dev tools:',    $(if ($DoomIncludeDevtools    -eq 1) { 'included (ripgrep / fzf / jq / 7-Zip / VSCodium)' } else { '(skipped)' }))
    Write-Host ("  {0,-12} {1}" -f 'Field manual:', $(if ($DoomIncludeFieldmanual -eq 1) { 'included (public-domain corpus)' } else { '(skipped)' }))
    Write-Host ''
    Write-Host ("  Estimated download: {0}" -f (Format-Bytes $needed))
    if ($free -gt 0) {
        Write-Host ("  Free at target:     {0}" -f (Format-Bytes $free))
        if ($needed -gt $free) {
            Write-Host "  → WARNING: estimated download exceeds free space at $Target"
        }
    }
    Write-Host '  -----------------------------------------'

    if (-not (Read-YesNo 'Save these settings and proceed?' 'Y')) {
        Write-Host 'Aborted by user.'
        exit 0
    }
}

# ---------------------------------------------------------------- config writer

function Write-Config {
    param([string]$Path)
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $content = @"
# Doomstick build config — written $stamp
# Re-run:        .\build-usb.ps1 "$Target"   (auto-sources this file)
# Re-customize:  .\build-usb.ps1 -i "$Target"
# Override one:  edit the relevant `$Doom* line below

`$DoomIncludeE4b = $DoomIncludeE4b
`$DoomIncludeMoe = $DoomIncludeMoe
`$DoomIncludeEmb = $DoomIncludeEmb

`$DoomIncludeWiki = $DoomIncludeWiki
`$DoomZimUrl   = '$DoomZimUrl'
`$DoomZimFile  = '$DoomZimFile'
`$DoomZimBytes = $DoomZimBytes
`$DoomZimLabel = '$DoomZimLabel'

`$DoomIncludeOsm = $DoomIncludeOsm
`$DoomPbfUrl   = '$DoomPbfUrl'
`$DoomPbfFile  = '$DoomPbfFile'
`$DoomPbfBytes = $DoomPbfBytes

`$DoomIncludeWhisper = $DoomIncludeWhisper
`$DoomWhisperUrl   = '$DoomWhisperUrl'
`$DoomWhisperFile  = '$DoomWhisperFile'
`$DoomWhisperBytes = $DoomWhisperBytes
`$DoomWhisperLabel = '$DoomWhisperLabel'

`$DoomIncludeOcr = $DoomIncludeOcr
`$DoomOcrLangs   = '$DoomOcrLangs'

`$DoomIncludeDocs = $DoomIncludeDocs

`$DoomIncludeRedbean  = $DoomIncludeRedbean
`$DoomIncludeDoom     = $DoomIncludeDoom
`$DoomIncludeTts      = $DoomIncludeTts
`$DoomIncludeImg      = $DoomIncludeImg
`$DoomIncludePasswords = $DoomIncludePasswords
`$DoomIncludeFfmpeg   = $DoomIncludeFfmpeg
`$DoomIncludeDevtools    = $DoomIncludeDevtools
`$DoomIncludeFieldmanual = $DoomIncludeFieldmanual
"@
    Set-Content -LiteralPath $Path -Value $content -NoNewline:$false
    Write-Host "  [save] wrote config: $Path"
}

# ---------------------------------------------------------------- mode dispatch

switch ($Mode) {
    'noninteractive' { Apply-BakedDefaults }
    'config' {
        if (-not (Test-Path -LiteralPath $ConfigPath)) {
            Write-Error "Config not found: $ConfigPath"; exit 2
        }
        . $ConfigPath
    }
    'wizard' {
        $existingConfig = Join-Path $Target 'build-usb-config.ps1'
        if ((Test-Path -LiteralPath $existingConfig) -and (-not $ForceWizard)) {
            Write-Host "==> Sourcing existing config: $existingConfig"
            Write-Host '    (Pass -i to re-prompt and overwrite.)'
            . $existingConfig
        } else {
            New-Item -ItemType Directory -Force -Path $Target | Out-Null
            Invoke-Wizard
            Show-SummaryAndConfirm
            Write-Config -Path $existingConfig
        }
    }
}

# ---------------------------------------------------------------- dry-run early-exit

if ($DryRunMode) {
    Write-Host ''
    Write-Host '  ---------------- Resolved $Doom* state ----------------'
    Get-Variable -Scope Script -Name 'Doom*' |
        Sort-Object Name |
        ForEach-Object { Write-Host ("  {0}={1}" -f $_.Name, $_.Value) }
    Write-Host '  -------------------------------------------------------'
    exit 0
}

# ---------------------------------------------------------------- prep dirs

$RuntimeDir    = Join-Path $Target 'ai-kit\runtime'
$ModelsDir     = Join-Path $Target 'ai-kit\models'
$WhisperDir    = Join-Path $Target 'ai-kit\whisper'
$KiwixWinDir   = Join-Path $Target 'ai-kit\kiwix\win'
$KiwixLinDir   = Join-Path $Target 'ai-kit\kiwix\linux'
$KiwixMacDir   = Join-Path $Target 'ai-kit\kiwix\mac'
$RedbeanDir    = Join-Path $Target 'ai-kit\redbean'
$SherpaLinDir  = Join-Path $Target 'ai-kit\sherpa-tts\linux'
$SherpaMacDir  = Join-Path $Target 'ai-kit\sherpa-tts\mac'
$SherpaWinDir  = Join-Path $Target 'ai-kit\sherpa-tts\win'
$SherpaModDir  = Join-Path $Target 'ai-kit\sherpa-tts\models\supertonic'
$SdImgLinDir   = Join-Path $Target 'ai-kit\sd-img\linux'
$SdImgMacDir   = Join-Path $Target 'ai-kit\sd-img\mac'
$SdImgWinDir   = Join-Path $Target 'ai-kit\sd-img\win'
$SdImgModelDir = Join-Path $Target 'ai-kit\sd-img\models'
$AgeLinDir     = Join-Path $Target 'ai-kit\age\linux'
$AgeMacDir     = Join-Path $Target 'ai-kit\age\mac'
$AgeWinDir     = Join-Path $Target 'ai-kit\age\win'
$KeePassLinDir = Join-Path $Target 'ai-kit\keepassxc\linux'
$KeePassMacDir = Join-Path $Target 'ai-kit\keepassxc\mac'
$KeePassWinDir = Join-Path $Target 'ai-kit\keepassxc\win'
$FfmpegLinDir  = Join-Path $Target 'ai-kit\ffmpeg\linux'
$FfmpegMacDir  = Join-Path $Target 'ai-kit\ffmpeg\mac'
$FfmpegWinDir  = Join-Path $Target 'ai-kit\ffmpeg\win'
$DevtoolsLinDir = Join-Path $Target 'ai-kit\devtools\linux'
$DevtoolsMacDir = Join-Path $Target 'ai-kit\devtools\mac'
$DevtoolsWinDir = Join-Path $Target 'ai-kit\devtools\win'
$CertsDir       = Join-Path $Target 'ai-kit\certs'
$FieldManualDir = Join-Path $Target 'field-manual'
$VaultDir      = Join-Path $Target 'vault'
$ZimDir        = Join-Path $Target 'zim'
$MapsDir       = Join-Path $Target 'maps'
$OcrLibDir     = Join-Path $Target 'ocr\lib'
$OcrLangDir    = Join-Path $Target 'ocr\lang-data'
$DocsDir       = Join-Path $Target 'docs-offline'
$DoomDir       = Join-Path $Target 'doom'
$ChatDir       = Join-Path $Target 'chat'
$RedbeanLuaDir = Join-Path $RedbeanDir 'lua'
$WorkspaceDir  = Join-Path $Target 'workspace\default'
$WsDocsDir     = Join-Path $WorkspaceDir 'docs'
$WsJournalDir  = Join-Path $WorkspaceDir 'journal'
$WsInboxDir    = Join-Path $WorkspaceDir '_inbox'
foreach ($d in @($RuntimeDir, $ModelsDir, $WhisperDir, $KiwixWinDir, $KiwixLinDir, $KiwixMacDir,
                 $RedbeanDir, $RedbeanLuaDir,
                 $SherpaLinDir, $SherpaMacDir, $SherpaWinDir, $SherpaModDir,
                 $SdImgLinDir, $SdImgMacDir, $SdImgWinDir, $SdImgModelDir,
                 $AgeLinDir, $AgeMacDir, $AgeWinDir,
                 $KeePassLinDir, $KeePassMacDir, $KeePassWinDir,
                 $FfmpegLinDir, $FfmpegMacDir, $FfmpegWinDir,
                 $DevtoolsLinDir, $DevtoolsMacDir, $DevtoolsWinDir,
                 $CertsDir, $FieldManualDir,
                 $VaultDir,
                 $ZimDir, $MapsDir, $OcrLibDir, $OcrLangDir, $DocsDir, $DoomDir,
                 $ChatDir, $WorkspaceDir, $WsDocsDir, $WsJournalDir, $WsInboxDir)) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

# ---------------------------------------------------------------- build helpers

$LlamafileUrl   = 'https://github.com/Mozilla-Ocho/llamafile/releases/download/0.10.1/llamafile-0.10.1-thin'
$LlamafileBytes = 43800000

$E4bUrl = 'https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf?download=true'
$E4bFile = 'gemma-4-E4B-it-Q4_K_M.gguf'; $E4bBytes = 5000000000
$MoeUrl = 'https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/resolve/main/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf?download=true'
$MoeFile = 'gemma-4-26B-A4B-it-UD-Q4_K_M.gguf'; $MoeBytes = 17000000000
$EmbUrl = 'https://huggingface.co/ggml-org/embeddinggemma-300m-qat-q8_0-GGUF/resolve/main/embeddinggemma-300m-qat-Q8_0.gguf?download=true'
$EmbFile = 'embeddinggemma-300m-qat-Q8_0.gguf'; $EmbBytes = 329000000

$KiwixLinuxUrl = 'https://download.kiwix.org/release/kiwix-tools/kiwix-tools_linux-x86_64.tar.gz'
$KiwixMacUrl   = 'https://download.kiwix.org/release/kiwix-tools/kiwix-tools_macos-x86_64.tar.gz'
$KiwixWinUrl   = 'https://download.kiwix.org/release/kiwix-tools/kiwix-tools_win-i686.zip'

$TessJsUrl     = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js'
$TessWorkerUrl = 'https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/worker.min.js'
$TessCoreUrl   = 'https://cdn.jsdelivr.net/npm/tesseract.js-core@5.1.1/tesseract-core.wasm.js'
$TessWasmUrl   = 'https://cdn.jsdelivr.net/npm/tesseract.js-core@5.1.1/tesseract-core.wasm'
$TessLangUrlBase = 'https://github.com/tesseract-ocr/tessdata_fast/raw/main'

$RedbeanUrl   = 'https://redbean.dev/redbean-3.0.0.com'
$RedbeanFile  = 'redbean.com'
$RedbeanBytes = 5500000

# Shareware DOOM1.WAD — see build-usb.sh for redistribution rationale + alternate mirrors.
$DoomWadUrl   = 'https://distro.ibiblio.org/slitaz/sources/packages/d/doom1.wad'
$DoomWadFile  = 'doom1.wad'
$DoomWadBytes = 4196020

# Sherpa-ONNX TTS runtime (v0.7) — see build-usb.sh for full rationale.
$SherpaVersion    = 'v1.13.1'
$SherpaLinuxUrl   = "https://github.com/k2-fsa/sherpa-onnx/releases/download/$SherpaVersion/sherpa-onnx-$SherpaVersion-linux-x64-shared.tar.bz2"
$SherpaLinuxBytes = 30000000
$SherpaMacUrl     = "https://github.com/k2-fsa/sherpa-onnx/releases/download/$SherpaVersion/sherpa-onnx-$SherpaVersion-osx-arm64-shared.tar.bz2"
$SherpaMacBytes   = 30000000
$SherpaWinUrl     = "https://github.com/k2-fsa/sherpa-onnx/releases/download/$SherpaVersion/sherpa-onnx-$SherpaVersion-win-x64-shared-MT-Release.tar.bz2"
$SherpaWinBytes   = 23278074

$SupertonicUrl     = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-supertonic-tts-int8-2026-03-06.tar.bz2'
$SupertonicArchive = 'sherpa-onnx-supertonic-tts-int8-2026-03-06.tar.bz2'
$SupertonicBytes   = 120000000

function Test-Size {
    param([string]$Path, [long]$Expected)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return ((Get-Item -LiteralPath $Path).Length -ge ($Expected * 0.95))
}

function Get-File {
    param([string]$Url, [string]$Dest, [long]$Expected, [string]$Label)
    if (Test-Size -Path $Dest -Expected $Expected) {
        Write-Host "  [skip] $Label already present"; return
    }
    Write-Host "  [fetch] $Label"
    Write-Host "          $Url"
    Write-Host "          -> $Dest"
    try {
        Start-BitsTransfer -Source $Url -Destination $Dest -DisplayName $Label -ErrorAction Stop
    } catch {
        Write-Host '  (BITS unavailable, falling back to Invoke-WebRequest)'
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
    }
}

# ---------------------------------------------------------------- runtime

Write-Host ''
Write-Host '==> runtime'
$llamafilePath = Join-Path $RuntimeDir 'llamafile'
Get-File -Url $LlamafileUrl -Dest $llamafilePath -Expected $LlamafileBytes -Label 'llamafile-0.10.1-thin'
Copy-Item -LiteralPath $llamafilePath -Destination (Join-Path $RuntimeDir 'llamafile.exe') -Force

# ---------------------------------------------------------------- weights

Write-Host ''
Write-Host '==> models'
if ($DoomIncludeE4b -eq 1) { Get-File -Url $E4bUrl -Dest (Join-Path $ModelsDir $E4bFile) -Expected $E4bBytes -Label 'Gemma 4 E4B Q4_K_M (~5 GB)' }
if ($DoomIncludeMoe -eq 1) { Get-File -Url $MoeUrl -Dest (Join-Path $ModelsDir $MoeFile) -Expected $MoeBytes -Label 'Gemma 4 26B-A4B UD-Q4_K_M (~17 GB)' }
if ($DoomIncludeEmb -eq 1) { Get-File -Url $EmbUrl -Dest (Join-Path $ModelsDir $EmbFile) -Expected $EmbBytes -Label 'EmbeddingGemma 300M Q8 (~329 MB)' }

# ---------------------------------------------------------------- side arms

Write-Host ''
Write-Host '==> side arms'

if ($DoomIncludeWhisper -eq 1 -and $DoomWhisperUrl) {
    Get-File -Url $DoomWhisperUrl -Dest (Join-Path $WhisperDir $DoomWhisperFile) -Expected $DoomWhisperBytes -Label "Whisperfile $DoomWhisperLabel"
}

if ($DoomIncludeWiki -eq 1) {
    $KiwixWinZip = Join-Path $KiwixWinDir 'kiwix-tools.zip'
    $KiwixLinTgz = Join-Path $KiwixLinDir 'kiwix-tools.tar.gz'
    $KiwixMacTgz = Join-Path $KiwixMacDir 'kiwix-tools.tar.gz'
    if (-not (Test-Path -LiteralPath (Join-Path $KiwixWinDir 'kiwix-serve.exe'))) {
        Get-File -Url $KiwixWinUrl -Dest $KiwixWinZip -Expected 6000000 -Label 'kiwix-tools (windows)'
        Expand-Archive -LiteralPath $KiwixWinZip -DestinationPath $KiwixWinDir -Force
        Get-ChildItem -LiteralPath $KiwixWinDir -Directory | ForEach-Object {
            Get-ChildItem -LiteralPath $_.FullName | Move-Item -Destination $KiwixWinDir -Force
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        }
        Remove-Item -LiteralPath $KiwixWinZip -Force
    }
    if (-not (Test-Path -LiteralPath (Join-Path $KiwixLinDir 'kiwix-serve'))) {
        Get-File -Url $KiwixLinuxUrl -Dest $KiwixLinTgz -Expected 6000000 -Label 'kiwix-tools (linux)'
        if (Get-Command tar -ErrorAction SilentlyContinue) {
            tar -xzf $KiwixLinTgz -C $KiwixLinDir --strip-components=1
            Remove-Item -LiteralPath $KiwixLinTgz -Force
        } else {
            Write-Host '  [warn] tar not available; leaving kiwix-tools.tar.gz'
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $KiwixMacDir 'kiwix-serve'))) {
        Get-File -Url $KiwixMacUrl -Dest $KiwixMacTgz -Expected 6000000 -Label 'kiwix-tools (macOS)'
        if (Get-Command tar -ErrorAction SilentlyContinue) {
            tar -xzf $KiwixMacTgz -C $KiwixMacDir --strip-components=1
            Remove-Item -LiteralPath $KiwixMacTgz -Force
        } else {
            Write-Host '  [warn] tar not available; leaving kiwix-tools.tar.gz'
        }
    }
    Get-File -Url $DoomZimUrl -Dest (Join-Path $ZimDir $DoomZimFile) -Expected $DoomZimBytes -Label "Wikipedia: $DoomZimLabel"
}

if ($DoomIncludeOcr -eq 1) {
    Get-File -Url $TessJsUrl     -Dest (Join-Path $OcrLibDir 'tesseract.min.js')        -Expected 500000  -Label 'tesseract.js'
    Get-File -Url $TessWorkerUrl -Dest (Join-Path $OcrLibDir 'worker.min.js')           -Expected 50000   -Label 'tesseract.js worker'
    Get-File -Url $TessCoreUrl   -Dest (Join-Path $OcrLibDir 'tesseract-core.wasm.js')  -Expected 3000    -Label 'tesseract-core wrapper'
    Get-File -Url $TessWasmUrl   -Dest (Join-Path $OcrLibDir 'tesseract-core.wasm')     -Expected 2000000 -Label 'tesseract-core wasm'
    foreach ($lang in ($DoomOcrLangs -split '\s+' | Where-Object { $_ })) {
        Get-File -Url "$TessLangUrlBase/$lang.traineddata" -Dest (Join-Path $OcrLangDir "$lang.traineddata") -Expected 5000000 -Label "tesseract pack: $lang"
    }
}

if ($DoomIncludeOsm -eq 1 -and $DoomPbfUrl) {
    Get-File -Url $DoomPbfUrl -Dest (Join-Path $MapsDir $DoomPbfFile) -Expected $DoomPbfBytes -Label "OSM .pbf ($DoomPbfFile)"
}

# redbean — local platform layer (port 8768)
# Fetch + stage; the zip-bake (.init.lua + doom/* if included) happens
# AFTER DOOM staging in a single combined step below.
if ($DoomIncludeRedbean -eq 1) {
    Get-File -Url $RedbeanUrl -Dest (Join-Path $RedbeanDir $RedbeanFile) -Expected $RedbeanBytes -Label 'redbean 3.0.0 (~5.5 MB)'
    Copy-Item -LiteralPath (Join-Path $Repo 'redbean\.init.lua')          -Destination (Join-Path $RedbeanDir '.init.lua')          -Force
    Copy-Item -LiteralPath (Join-Path $Repo 'redbean\README.txt')         -Destination (Join-Path $RedbeanDir 'README.txt')         -Force
    # v0.8 RAG: pure-Lua cosine module — baked into redbean.com at .lua/rag-cosine.lua
    # so require("rag-cosine") in .init.lua resolves from the zip's package.path.
    Copy-Item -LiteralPath (Join-Path $Repo 'redbean\lua\rag-cosine.lua') -Destination (Join-Path $RedbeanLuaDir 'rag-cosine.lua') -Force
}

# DOOM — Dwasm port (vendored under doom/ in repo) + shareware DOOM1.WAD (fetched)
if ($DoomIncludeDoom -eq 1) {
    Get-File -Url $DoomWadUrl -Dest (Join-Path $DoomDir $DoomWadFile) -Expected $DoomWadBytes -Label 'DOOM1.WAD shareware (~4.2 MB)'
    foreach ($f in @('index.html', 'index.js', 'index.data', 'index.wasm', 'LICENSE-GPL-2.0', 'NOTICE.md')) {
        Copy-Item -LiteralPath (Join-Path $Repo "doom\$f") -Destination (Join-Path $DoomDir $f) -Force
    }
}

# Bake .init.lua (+ doom/* when shipped) into redbean.com's appended zip.
#
# Why baked into the zip and not just the static -D <docroot> overlay:
#   - redbean reads .init.lua from its asset zip; -D overlays static files
#     but does NOT expose .init.lua as an asset, and the -A runtime-add flag
#     is broken in 3.0.0 (StoreAsset regression).
#   - When the USB is exFAT (typical) and accessed from native Windows,
#     Cosmopolitan's stat() reports directories as mode 040700, which fails
#     redbean's static-serve "other readable" check → 403 on /doom/. Files
#     served from the appended zip skip that filesystem check entirely.
#
# Why this is not a one-line .NET ZipArchive Update call (regression hunted
# down 2026-05-08): redbean.com is an APE polyglot — an MZ-prefixed PE/ELF/
# Mach-O/shell prelude with a ZIP appended at the tail. .NET's ZipArchive
# treats the input stream as a pure zip, and on Update it overwrites the
# file from offset 0 with a fresh pure-zip body — silently destroying the
# prelude. The result is a 3.5 MB pure-zip file that Windows refuses to
# launch ("not a valid application") and that no other OS can run either.
#
# Workaround: capture the prelude bytes (everything before the first local
# file header) before the .NET op, let .NET do its thing on the file in
# place, then re-prepend the prelude and shift every absolute offset in
# the new zip's central directory by +preludeSize so the EOCD and CD entry
# offsets remain accurate against the final polyglot. Idempotent.
function Invoke-PolyglotZipBake {
    param(
        [Parameter(Mandatory)][string]$PolyglotPath,
        [Parameter(Mandatory)][hashtable[]]$Entries
    )

    $bytes = [System.IO.File]::ReadAllBytes($PolyglotPath)
    if ($bytes.Length -lt 100) { throw "polyglot bake: input too small ($($bytes.Length) bytes): $PolyglotPath" }
    if ($bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
        throw "polyglot bake: input does not start with MZ magic (got 0x$($bytes[0].ToString('X2'))$($bytes[1].ToString('X2'))). File is corrupted from a prior failed bake — delete it and re-run build-usb.ps1 to refetch."
    }
    # BUG-1 recovery: detect already-bloated input from prior buggy bake (v0.10
    # pre-fix .NET-preserve-prelude regression caused 8.84M → 14.16M → 24.80M
    # progression). Pristine redbean.com is ~5.72 MB; a single sane bake adds
    # ~3.5 MB of compressed entries → ~9 MB. Anything materially larger is a
    # bloated prior-bake artifact that this function CAN'T repair (the
    # captured prelude would be the bloated [prelude × N] block, not the
    # single pristine prelude). Abort with a clear refetch message.
    $maxSaneInputBytes = 12000000  # 12 MB: pristine 5.72M + ~6 MB headroom for legitimate bake growth
    if ($bytes.Length -gt $maxSaneInputBytes) {
        throw "polyglot bake: input ($($bytes.Length) bytes / $([Math]::Round($bytes.Length/1MB, 2)) MB) exceeds sane threshold of $maxSaneInputBytes bytes (~$([Math]::Round($maxSaneInputBytes/1MB, 1)) MB). This is a bloated artifact from a prior buggy bake (BUG-1 — .NET ZipArchive Update preserved prelude, function double-prepended). Delete '$PolyglotPath' and re-run build-usb.ps1 to refetch the pristine redbean.com (~5.72 MB) and re-bake cleanly."
    }

    # Find EOCD (PK\x05\x06) by scanning backwards from end. Max comment is 64KB.
    $eocdPos = -1
    $minScan = [Math]::Max(0, $bytes.Length - 65557)
    for ($i = $bytes.Length - 22; $i -ge $minScan; $i--) {
        if ($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and $bytes[$i+2] -eq 0x05 -and $bytes[$i+3] -eq 0x06) {
            $eocdPos = $i; break
        }
    }
    if ($eocdPos -lt 0) { throw "polyglot bake: no EOCD record found in $PolyglotPath" }

    # Read first CD entry's local-header-offset (absolute, includes prelude).
    $cdOffset = [BitConverter]::ToUInt32($bytes, $eocdPos + 16)
    if ($cdOffset -ge $bytes.Length) { throw "polyglot bake: invalid CD offset $cdOffset" }
    $firstLfhOffset = [BitConverter]::ToUInt32($bytes, $cdOffset + 42)
    if ($firstLfhOffset -ge $bytes.Length) { throw "polyglot bake: invalid LFH offset $firstLfhOffset" }
    if ($bytes[$firstLfhOffset] -ne 0x50 -or $bytes[$firstLfhOffset+1] -ne 0x4B -or $bytes[$firstLfhOffset+2] -ne 0x03 -or $bytes[$firstLfhOffset+3] -ne 0x04) {
        throw "polyglot bake: first CD entry's offset $firstLfhOffset does not point at a local file header"
    }
    $preludeSize = [int]$firstLfhOffset
    $prelude = New-Object byte[] $preludeSize
    [Array]::Copy($bytes, 0, $prelude, 0, $preludeSize)

    # Run .NET ZipArchive Update on the file as-is. It will read the existing
    # entries (offsets are polyglot-aware so this works), then on dispose it
    # rewrites the file. Two observed runtime behaviors:
    #   (A) Older .NET / .NET Framework: rewrites from offset 0 with a fresh
    #       pure-zip body — prelude is lost. Function then re-prepends.
    #   (B) Modern .NET (5+): preserves "extra bytes before zip" on Update
    #       per ZIP spec, so the rewritten file STILL starts with the prelude.
    #       Re-prepending without detecting this doubles the prelude
    #       (BUG-1 in v0.10 — caught by Windows verification: redbean.com.exe
    #       grew 8.84M → 14.16M → 24.80M across rebakes, each adding another
    #       prelude copy).
    # Defensive fix: after the .NET op, find the first PK\x03\x04 in the
    # rewritten file and strip everything before it. Works for both runtimes.
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($PolyglotPath, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        foreach ($e in $Entries) {
            $existing = $zip.GetEntry($e.Path)
            if ($existing) { $existing.Delete() }
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $e.Src, $e.Path) | Out-Null
        }
    } finally {
        $zip.Dispose()
    }

    # Read the rewritten file. Detect what .NET did via the AUTHORITATIVE
    # EOCD -> CD offset -> first CD entry's LFH offset chain (same logic the
    # pre-bake step uses to find the pristine prelude). Forward-scanning for
    # PK\x03\x04 is UNSAFE for APE polyglots — redbean's prelude contains a
    # false-positive PK signature inside its PE section (~offset 731K) before
    # the real LFH at offset 5,318,376. Caught by Windows verification
    # 2026-05-10 against the previous fix attempt.
    $rawNewBytes = [System.IO.File]::ReadAllBytes($PolyglotPath)

    # Find new EOCD (scan backward from end — safe; EOCD is always near tail).
    $newEocdPos = -1
    $newMinScan = [Math]::Max(0, $rawNewBytes.Length - 65557)
    for ($i = $rawNewBytes.Length - 22; $i -ge $newMinScan; $i--) {
        if ($rawNewBytes[$i] -eq 0x50 -and $rawNewBytes[$i+1] -eq 0x4B -and $rawNewBytes[$i+2] -eq 0x05 -and $rawNewBytes[$i+3] -eq 0x06) {
            $newEocdPos = $i; break
        }
    }
    if ($newEocdPos -lt 0) { throw "polyglot bake: rewritten file has no EOCD" }
    $newRawCdOffset = [BitConverter]::ToUInt32($rawNewBytes, $newEocdPos + 16)
    if ($newRawCdOffset -ge $rawNewBytes.Length) { throw "polyglot bake: invalid new CD offset $newRawCdOffset" }
    $newFirstLfhAbs = [BitConverter]::ToUInt32($rawNewBytes, $newRawCdOffset + 42)

    # CASE B (modern .NET 5+): the runtime preserved "extra bytes before zip
    # data" per ZIP spec on Update. The file already IS a valid polyglot —
    # .NET wrote the prelude, the entries (with absolute offsets that include
    # the prelude), the CD (absolute offsets), and the EOCD (absolute CD
    # offset). Nothing to do — return after sanity checks.
    if ($newFirstLfhAbs -gt 0) {
        if ($rawNewBytes[0] -ne 0x4D -or $rawNewBytes[1] -ne 0x5A) {
            throw "polyglot bake: Case B detected (LFH at $newFirstLfhAbs) but file doesn't start with MZ magic — runtime-behavior corner case, inspect $PolyglotPath"
        }
        Write-Host "  [polyglot bake] .NET preserved $newFirstLfhAbs-byte prelude on Update (Case B) — file already correct, no re-prepend needed"
        # Post-bake size invariant (BUG-1 regression guard — Case B flavor).
        $expectedMaxSize = $preludeSize + 8000000
        if ($rawNewBytes.Length -gt $expectedMaxSize) {
            throw "polyglot bake: Case B output ($($rawNewBytes.Length) bytes) exceeds prelude + 8 MB ($expectedMaxSize bytes) — possible BUG-1 regression. Inspect $PolyglotPath."
        }
        return
    }

    # CASE A (older .NET / .NET Framework): the runtime rewrote from offset 0
    # with a pure-zip body, destroying the prelude. newFirstLfhAbs is 0 (zip
    # starts at file offset 0). Re-prepend captured prelude AND shift CD
    # offsets by +preludeSize so the EOCD and CD entries point at the right
    # places in the final polyglot.
    Write-Host "  [polyglot bake] .NET destroyed prelude on Update (Case A) — re-prepending captured $preludeSize-byte prelude and shifting CD offsets"
    $newBytes = $rawNewBytes
    $newCdOffset = $newRawCdOffset
    $newCdSize   = [BitConverter]::ToUInt32($newBytes, $newEocdPos + 12)

    # Shift CD-start offset in EOCD by +preludeSize.
    [Array]::Copy([BitConverter]::GetBytes([uint32]($newCdOffset + $preludeSize)), 0, $newBytes, $newEocdPos + 16, 4)

    # Walk every CD entry, shift its local-header-offset by +preludeSize.
    $pos = [int]$newCdOffset
    $cdEnd = [int]$newCdOffset + [int]$newCdSize
    while ($pos -lt $cdEnd) {
        $sig = [BitConverter]::ToUInt32($newBytes, $pos)
        if ($sig -ne 0x02014b50) { throw "polyglot bake: expected CD signature at $pos, got 0x$($sig.ToString('X8'))" }
        $filenameLen = [BitConverter]::ToUInt16($newBytes, $pos + 28)
        $extraLen    = [BitConverter]::ToUInt16($newBytes, $pos + 30)
        $commentLen  = [BitConverter]::ToUInt16($newBytes, $pos + 32)
        $lfhOff = [BitConverter]::ToUInt32($newBytes, $pos + 42)
        [Array]::Copy([BitConverter]::GetBytes([uint32]($lfhOff + $preludeSize)), 0, $newBytes, $pos + 42, 4)
        $pos += 46 + $filenameLen + $extraLen + $commentLen
    }

    # Concatenate prelude + offset-corrected zip; write back atomically.
    $tmp = "$PolyglotPath.bake.tmp"
    $fs = [System.IO.File]::Open($tmp, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    try {
        $fs.Write($prelude, 0, $prelude.Length)
        $fs.Write($newBytes, 0, $newBytes.Length)
    } finally {
        $fs.Dispose()
    }
    Move-Item -LiteralPath $tmp -Destination $PolyglotPath -Force

    # Sanity-verify: still polyglot, still sized like one, NOT bloated.
    $verify = Get-Item -LiteralPath $PolyglotPath
    $head = [System.IO.File]::ReadAllBytes($PolyglotPath)[0..1]
    if ($head[0] -ne 0x4D -or $head[1] -ne 0x5A) {
        throw "polyglot bake: APE prelude lost after re-stitch (got 0x$($head[0].ToString('X2'))$($head[1].ToString('X2')))"
    }
    if ($verify.Length -lt $preludeSize) {
        throw "polyglot bake: output ($($verify.Length) bytes) smaller than original prelude ($preludeSize bytes)"
    }
    # Post-bake size invariant: output should be ~prelude + ~zip-body. The zip
    # body should NOT contain a duplicate prelude (BUG-1 regression guard).
    # Total entry data + CD + EOCD across the kit's 8 baked entries (.init.lua,
    # .lua/rag-cosine.lua, doom/* x6) is well under 5 MB compressed. Allow
    # generous 8 MB headroom for future entries; anything beyond signals a
    # progressive-prelude regression.
    $expectedMaxSize = $preludeSize + 8000000
    if ($verify.Length -gt $expectedMaxSize) {
        throw "polyglot bake: Case A output ($($verify.Length) bytes) exceeds prelude + 8 MB ($expectedMaxSize bytes) — possible BUG-1 regression: a Case A re-prepend produced an unexpectedly large file. Inspect $PolyglotPath."
    }
}

if ($DoomIncludeRedbean -eq 1) {
    $rbBin = Join-Path $RedbeanDir $RedbeanFile
    $entries = @(
        @{ Src = (Join-Path $RedbeanDir '.init.lua');                Path = '.init.lua' }
        @{ Src = (Join-Path $RedbeanLuaDir 'rag-cosine.lua');        Path = '.lua/rag-cosine.lua' }
    )
    if ($DoomIncludeDoom -eq 1) {
        foreach ($f in @('index.html', 'index.js', 'index.data', 'index.wasm', $DoomWadFile, 'LICENSE-GPL-2.0', 'NOTICE.md')) {
            $entries += @{ Src = (Join-Path $DoomDir $f); Path = "doom/$f" }
        }
    }

    Invoke-PolyglotZipBake -PolyglotPath $rbBin -Entries $entries

    # Keep redbean.com.exe in sync with redbean.com so start-doom.bat launches
    # the freshly-baked binary, not a stale .exe from a prior deploy.
    Copy-Item -LiteralPath $rbBin -Destination "$rbBin.exe" -Force

    if ($DoomIncludeDoom -eq 1) {
        Write-Host "  baked .init.lua + doom/ into $rbBin (+.exe synced)"
    } else {
        Write-Host "  baked .init.lua into $rbBin (+.exe synced)"
    }
}

# ---------------------------------------------------------------- TTS (sherpa-onnx + supertonic)

# v0.7 customer of redbean's /tts route. Per-OS native binaries (no Python on host).
# Windows 10 1803+ ships tar.exe in System32 with bzip2 support — we shell out
# to it for .tar.bz2. If tar.exe is missing (very old Win10), the user gets a
# clear warning and the archive stays in place for manual extraction.
if ($DoomIncludeTts -eq 1) {
    Write-Host ''
    Write-Host '==> tts (sherpa-onnx + supertonic)'

    function Expand-TarBz2 {
        param([string]$Archive, [string]$Dest)
        $tar = Get-Command tar -ErrorAction SilentlyContinue
        if (-not $tar) {
            Write-Host "  [warn] tar.exe not found in PATH — leaving $Archive for manual extraction"
            return $false
        }
        & tar -xjf $Archive -C $Dest --strip-components=1
        return ($LASTEXITCODE -eq 0)
    }

    # Linux runtime — multi-file shared tarball.
    $linuxBin = Join-Path $SherpaLinDir 'sherpa-onnx-offline-tts'
    if (-not (Test-Path -LiteralPath $linuxBin)) {
        $linTbz = Join-Path $SherpaLinDir 'sherpa-onnx.tar.bz2'
        Get-File -Url $SherpaLinuxUrl -Dest $linTbz -Expected $SherpaLinuxBytes -Label "sherpa-onnx $SherpaVersion linux-x64"
        if (Expand-TarBz2 -Archive $linTbz -Dest $SherpaLinDir) {
            # Flatten bin/ + lib/ into the top of sherpa-tts/linux/.
            foreach ($sub in @('bin', 'lib')) {
                $subPath = Join-Path $SherpaLinDir $sub
                if (Test-Path -LiteralPath $subPath) {
                    Get-ChildItem -LiteralPath $subPath -Force |
                        Move-Item -Destination $SherpaLinDir -Force
                    Remove-Item -LiteralPath $subPath -Recurse -Force
                }
            }
            Remove-Item -LiteralPath $linTbz -Force
        }
    }

    # macOS runtime (arm64) — same shape as Linux.
    $macBin = Join-Path $SherpaMacDir 'sherpa-onnx-offline-tts'
    if (-not (Test-Path -LiteralPath $macBin)) {
        $macTbz = Join-Path $SherpaMacDir 'sherpa-onnx.tar.bz2'
        Get-File -Url $SherpaMacUrl -Dest $macTbz -Expected $SherpaMacBytes -Label "sherpa-onnx $SherpaVersion osx-arm64"
        if (Expand-TarBz2 -Archive $macTbz -Dest $SherpaMacDir) {
            foreach ($sub in @('bin', 'lib')) {
                $subPath = Join-Path $SherpaMacDir $sub
                if (Test-Path -LiteralPath $subPath) {
                    Get-ChildItem -LiteralPath $subPath -Force |
                        Move-Item -Destination $SherpaMacDir -Force
                    Remove-Item -LiteralPath $subPath -Recurse -Force
                }
            }
            Remove-Item -LiteralPath $macTbz -Force
        }
    }

    # Windows runtime — multi-file shared tarball, same shape as Linux/Mac.
    # MT-Release variant: static CRT, so no Visual C++ Redistributable
    # required on host. The standalone single-.exe download from the same
    # release is the GUI app, not the CLI we need — see CLAUDE.md gotcha.
    # Guard requires both the .exe AND onnxruntime.dll — earlier kits
    # shipped the GUI .exe under this same filename, which lacks
    # onnxruntime.dll, so refetch the proper CLI archive over it.
    $winBin = Join-Path $SherpaWinDir 'sherpa-onnx-offline-tts.exe'
    $winOrt = Join-Path $SherpaWinDir 'onnxruntime.dll'
    if (-not (Test-Path -LiteralPath $winBin) -or -not (Test-Path -LiteralPath $winOrt)) {
        if (Test-Path -LiteralPath $winBin) { Remove-Item -LiteralPath $winBin -Force }
        $winTbz = Join-Path $SherpaWinDir 'sherpa-onnx.tar.bz2'
        Get-File -Url $SherpaWinUrl -Dest $winTbz -Expected $SherpaWinBytes -Label "sherpa-onnx $SherpaVersion win-x64 (MT-Release)"
        if (Expand-TarBz2 -Archive $winTbz -Dest $SherpaWinDir) {
            foreach ($sub in @('bin', 'lib')) {
                $subPath = Join-Path $SherpaWinDir $sub
                if (Test-Path -LiteralPath $subPath) {
                    Get-ChildItem -LiteralPath $subPath -Force |
                        Move-Item -Destination $SherpaWinDir -Force
                    Remove-Item -LiteralPath $subPath -Recurse -Force
                }
            }
            Remove-Item -LiteralPath $winTbz -Force
        }
    }

    # Supertonic int8 model — shared across all 3 OS binaries.
    $voiceFile = Join-Path $SherpaModDir 'voice.bin'
    if (-not (Test-Path -LiteralPath $voiceFile)) {
        $supTbz = Join-Path (Split-Path $SherpaModDir -Parent) $SupertonicArchive
        Get-File -Url $SupertonicUrl -Dest $supTbz -Expected $SupertonicBytes -Label 'Supertonic int8 (~120 MB)'
        if (Expand-TarBz2 -Archive $supTbz -Dest $SherpaModDir) {
            Remove-Item -LiteralPath $supTbz -Force
        }
    }
}

# ---------------------------------------------------------------- image gen (sd.cpp + flux.2 klein)

# stable-diffusion.cpp runtime + FLUX.2 klein 4B Q4_K_M model. v0.10 standalone
# launcher (start-img.*) — NOT a redbean route (60-180s blocking image gen would
# DoS every other 8768 customer). Native C++ binaries per OS, no Python on host.
# sd.cpp uses rolling master-N-sha tags, NOT semver. ALL three OSes ship .zip
# (Linux/Mac/Win) with files at zip root — Expand-Archive handles all three; no
# tar.exe shellout, no Move-Item flatten step needed.
$ImgVersion       = 'master-596-90e87bc'
$ImgLinuxUrl      = "https://github.com/leejet/stable-diffusion.cpp/releases/download/$ImgVersion/sd-master-90e87bc-bin-Linux-Ubuntu-24.04-x86_64.zip"
$ImgMacUrl        = "https://github.com/leejet/stable-diffusion.cpp/releases/download/$ImgVersion/sd-master-90e87bc-bin-Darwin-macOS-15.7.4-arm64.zip"
$ImgWinUrl        = "https://github.com/leejet/stable-diffusion.cpp/releases/download/$ImgVersion/sd-master-90e87bc-bin-win-avx2-x64.zip"
$ImgLinuxBytes    = 11560677
$ImgMacBytes      = 21432078
$ImgWinBytes      = 9165331

# FLUX.2 klein 4B Q4_K_M — Black Forest Labs (Jan 2026), Apache-2.0. Transformer-
# only GGUF (~2.6 GB). NOT all-in-one: sd.cpp needs companion VAE (--vae) +
# Qwen3-4B text encoder (--llm) supplied separately. See sd.cpp docs/flux2.md.
$ImgModelUrl      = 'https://huggingface.co/unsloth/FLUX.2-klein-4B-GGUF/resolve/main/flux-2-klein-4b-Q4_K_M.gguf'
$ImgModelBytes    = 2604311104
$ImgModelFilename = 'flux-2-klein-4b-Q4_K_M.gguf'

# Qwen3-4B Q4_K_M — Apache-2.0 (Alibaba/Qwen). Doubles as FLUX.2 klein text
# encoder (sd.cpp --llm flag) AND a standalone AI core option in start.{sh,bat,
# command} picker (runtime-detected). Lives at ai-kit\models\ alongside Gemma
# weights, NOT inside sd-img\ — shared resource. ~2.33 GB.
$ImgLlmUrl       = 'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf?download=true'
$ImgLlmBytes     = 2497281312
$ImgLlmFilename  = 'Qwen3-4B-Q4_K_M.gguf'

# FLUX.2 small-decoder VAE — Black Forest Labs, Apache-2.0. Ungated alternative
# to the gated FLUX.2-dev VAE. ~238 MB.
$ImgVaeUrl       = 'https://huggingface.co/black-forest-labs/FLUX.2-small-decoder/resolve/main/full_encoder_small_decoder.safetensors?download=true'
$ImgVaeBytes     = 249519092
$ImgVaeFilename  = 'full_encoder_small_decoder.safetensors'

# KeePassXC — cross-OS password manager, GPL-2.0+.
# Linux: AppImage (self-contained, deposit raw; launcher extracts on first run with --appimage-extract).
# macOS: arm64 .dmg (deferred extraction — hdiutil runs at first launch, not at build time).
# Windows: Win64.zip (flattened; keepassxc.ini activates portable mode so config/db stays next to binary).
$KeePassXcVersion      = '2.7.12'
$KeePassXcLinuxFilename = "KeePassXC-${KeePassXcVersion}-x86_64.AppImage"
$KeePassXcLinuxUrl     = "https://github.com/keepassxreboot/keepassxc/releases/download/${KeePassXcVersion}/${KeePassXcLinuxFilename}"
$KeePassXcLinuxBytes   = 49283072
$KeePassXcMacFilename  = "KeePassXC-${KeePassXcVersion}-arm64.dmg"
$KeePassXcMacUrl       = "https://github.com/keepassxreboot/keepassxc/releases/download/${KeePassXcVersion}/${KeePassXcMacFilename}"
$KeePassXcMacBytes     = 37748736
$KeePassXcWinFilename  = "KeePassXC-${KeePassXcVersion}-Win64.zip"
$KeePassXcWinUrl       = "https://github.com/keepassxreboot/keepassxc/releases/download/${KeePassXcVersion}/${KeePassXcWinFilename}"
$KeePassXcWinBytes     = 36700160

# ffmpeg — GPL-3.0+. BtbN builds for Linux/Windows; Martin-Riedl for macOS arm64.
#
# NOTE: BtbN's "latest" tag is rolling for the n7.1 stable branch — re-running
# build-usb on different days may fetch different patch builds. The n7.1 major
# version is pinned; only the specific commit within that release line can vary.
# Trade-off: always-current security patches without the pain of manual version
# bumps. Pin to a specific commit tag only if reproducible builds matter.
$FfmpegVersion       = 'n7.1'
$FfmpegLinux64Url    = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-${FfmpegVersion}-latest-linux64-gpl-7.1.tar.xz"
$FfmpegLinux64Bytes  = 122683392
$FfmpegLinuxArm64Url  = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-${FfmpegVersion}-latest-linuxarm64-gpl-7.1.tar.xz"
$FfmpegLinuxArm64Bytes = 104857600
$FfmpegMacUrl        = 'https://ffmpeg.martin-riedl.de/download/macos/arm64/1777624525_N-124279-g0f6ba39122/ffmpeg.zip'
$FfmpegMacBytes      = 28950528
$FfmpegWinUrl        = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-${FfmpegVersion}-latest-win64-gpl-7.1.zip"
$FfmpegWinBytes      = 164626432

$RipgrepVersion       = '14.1.1'
$RipgrepLinux64Url    = "https://github.com/BurntSushi/ripgrep/releases/download/$RipgrepVersion/ripgrep-$RipgrepVersion-x86_64-unknown-linux-musl.tar.gz"
$RipgrepLinux64Bytes  = 2621440
$RipgrepLinuxArm64Url = "https://github.com/BurntSushi/ripgrep/releases/download/$RipgrepVersion/ripgrep-$RipgrepVersion-aarch64-unknown-linux-gnu.tar.gz"
$RipgrepLinuxArm64Bytes = 2621440
$RipgrepMacUrl        = "https://github.com/BurntSushi/ripgrep/releases/download/$RipgrepVersion/ripgrep-$RipgrepVersion-aarch64-apple-darwin.tar.gz"
$RipgrepMacBytes      = 2097152
$RipgrepWinUrl        = "https://github.com/BurntSushi/ripgrep/releases/download/$RipgrepVersion/ripgrep-$RipgrepVersion-x86_64-pc-windows-msvc.zip"
$RipgrepWinBytes      = 2621440

$FzfVersion           = '0.61.3'
$FzfLinux64Url        = "https://github.com/junegunn/fzf/releases/download/v$FzfVersion/fzf-$FzfVersion-linux_amd64.tar.gz"
$FzfLinux64Bytes      = 1608889
$FzfLinuxArm64Url     = "https://github.com/junegunn/fzf/releases/download/v$FzfVersion/fzf-$FzfVersion-linux_arm64.tar.gz"
$FzfLinuxArm64Bytes   = 1493628
$FzfMacUrl            = "https://github.com/junegunn/fzf/releases/download/v$FzfVersion/fzf-$FzfVersion-darwin_arm64.tar.gz"
$FzfMacBytes          = 1628690
$FzfWinUrl            = "https://github.com/junegunn/fzf/releases/download/v$FzfVersion/fzf-$FzfVersion-windows_amd64.zip"
$FzfWinBytes          = 1832326

$JqVersion            = '1.7.1'
$JqLinux64Url         = "https://github.com/jqlang/jq/releases/download/jq-$JqVersion/jq-linux-amd64"
$JqLinux64Bytes       = 2097152
$JqLinuxArm64Url      = "https://github.com/jqlang/jq/releases/download/jq-$JqVersion/jq-linux-arm64"
$JqLinuxArm64Bytes    = 2097152
$JqMacUrl             = "https://github.com/jqlang/jq/releases/download/jq-$JqVersion/jq-macos-arm64"
$JqMacBytes           = 2097152
$JqWinUrl             = "https://github.com/jqlang/jq/releases/download/jq-$JqVersion/jq-windows-amd64.exe"
$JqWinBytes           = 2097152

$SevenZipVersion      = '2409'
$SevenZipLinuxUrl     = "https://www.7-zip.org/a/7z$($SevenZipVersion)-linux-x64.tar.xz"
$SevenZipLinuxBytes   = 1048576
$SevenZipMacUrl       = "https://www.7-zip.org/a/7z$($SevenZipVersion)-mac-arm64.tar.xz"
$SevenZipMacBytes     = 1048576
$SevenZipWinUrl       = 'https://www.7-zip.org/a/7zr.exe'
$SevenZipWinBytes     = 520000

$VSCodiumVersion      = '1.99.3'
$VSCodiumLinuxUrl     = "https://github.com/VSCodium/vscodium/releases/download/$VSCodiumVersion/VSCodium-linux-x64-$VSCodiumVersion.tar.gz"
$VSCodiumLinuxBytes   = 90177536
$VSCodiumMacUrl       = "https://github.com/VSCodium/vscodium/releases/download/$VSCodiumVersion/VSCodium-darwin-arm64-$VSCodiumVersion.zip"
$VSCodiumMacBytes     = 90177536
$VSCodiumWinUrl       = "https://github.com/VSCodium/vscodium/releases/download/$VSCodiumVersion/VSCodiumPortable_$($VSCodiumVersion)_x64.zip"
$VSCodiumWinBytes     = 90177536

$CacertUrl            = 'https://curl.se/ca/cacert.pem'
$CacertBytes          = 226168

if ($DoomIncludeImg -eq 1) {
    Write-Host ''
    Write-Host "==> image gen (sd.cpp $ImgVersion + FLUX.2 klein)"

    # Linux runtime — .zip with files at root (sd-cli + libstable-diffusion.so + sd-server + *.txt).
    # Two-file guard catches partial-extraction state.
    $linBin = Join-Path $SdImgLinDir 'sd-cli'
    $linLib = Join-Path $SdImgLinDir 'libstable-diffusion.so'
    if (-not (Test-Path -LiteralPath $linBin) -or -not (Test-Path -LiteralPath $linLib)) {
        $linZip = Join-Path $SdImgLinDir 'sd-linux.zip'
        Get-File -Url $ImgLinuxUrl -Dest $linZip -Expected $ImgLinuxBytes -Label "sd.cpp $ImgVersion linux-x64"
        Expand-Archive -LiteralPath $linZip -DestinationPath $SdImgLinDir -Force
        Remove-Item -LiteralPath $linZip -Force
    }

    # macOS runtime (arm64) — same shape as Linux.
    $macBin = Join-Path $SdImgMacDir 'sd-cli'
    $macLib = Join-Path $SdImgMacDir 'libstable-diffusion.dylib'
    if (-not (Test-Path -LiteralPath $macBin) -or -not (Test-Path -LiteralPath $macLib)) {
        $macZip = Join-Path $SdImgMacDir 'sd-mac.zip'
        Get-File -Url $ImgMacUrl -Dest $macZip -Expected $ImgMacBytes -Label "sd.cpp $ImgVersion osx-arm64"
        Expand-Archive -LiteralPath $macZip -DestinationPath $SdImgMacDir -Force
        Remove-Item -LiteralPath $macZip -Force
    }

    # Windows runtime — .zip with sd-cli.exe + stable-diffusion.dll + sd-server.exe + *.txt at root.
    # Files-at-root means no flatten/--strip-components needed.
    $winBin = Join-Path $SdImgWinDir 'sd-cli.exe'
    $winDll = Join-Path $SdImgWinDir 'stable-diffusion.dll'
    if (-not (Test-Path -LiteralPath $winBin) -or -not (Test-Path -LiteralPath $winDll)) {
        $winZip = Join-Path $SdImgWinDir 'sd-win.zip'
        Get-File -Url $ImgWinUrl -Dest $winZip -Expected $ImgWinBytes -Label "sd.cpp $ImgVersion win-avx2-x64"
        Expand-Archive -LiteralPath $winZip -DestinationPath $SdImgWinDir -Force
        Remove-Item -LiteralPath $winZip -Force
    }

    # FLUX.2 klein 4B Q4_K_M transformer GGUF — 2.6 GB. NOT all-in-one (see
    # comment block above). VAE + text-encoder companions fetched below.
    $modelDest = Join-Path $SdImgModelDir $ImgModelFilename
    if (-not (Test-Path -LiteralPath $modelDest)) {
        Get-File -Url $ImgModelUrl -Dest $modelDest -Expected $ImgModelBytes -Label 'FLUX.2 klein 4B Q4_K_M (~2.6 GB)'
    }

    # FLUX.2 small-decoder VAE companion — required for sd.cpp --vae flag.
    $vaeDest = Join-Path $SdImgModelDir $ImgVaeFilename
    if (-not (Test-Path -LiteralPath $vaeDest)) {
        Get-File -Url $ImgVaeUrl -Dest $vaeDest -Expected $ImgVaeBytes -Label 'FLUX.2 small-decoder VAE (~238 MB)'
    }

    # Qwen3-4B Q4_K_M text encoder + AI core option — required for sd.cpp --llm
    # flag. Lives at ai-kit\models\ so start.{sh,bat,command} can detect it as
    # a 3rd AI core menu option (E4B / 26B / Qwen3-4B).
    $llmDest = Join-Path $ModelsDir $ImgLlmFilename
    if (-not (Test-Path -LiteralPath $llmDest)) {
        Get-File -Url $ImgLlmUrl -Dest $llmDest -Expected $ImgLlmBytes -Label 'Qwen3-4B Q4_K_M (~2.33 GB) — FLUX.2 text encoder + AI core option'
    }
}

# ---------------------------------------------------------------- vault (age)

# Per-OS pre-built age binaries (BSD-3, native Go, no APE polyglot, no Defender FP).
# Sherpa pattern: one subdir per OS. Always-on (research D1) — no bundle.tsv
# knob; $DoomIncludeVault default 1, env-var override only.
$AgeVersion  = 'v1.3.1'
$AgeLinuxUrl = "https://github.com/FiloSottile/age/releases/download/$AgeVersion/age-$AgeVersion-linux-amd64.tar.gz"
$AgeMacUrl   = "https://github.com/FiloSottile/age/releases/download/$AgeVersion/age-$AgeVersion-darwin-arm64.tar.gz"
$AgeWinUrl   = "https://github.com/FiloSottile/age/releases/download/$AgeVersion/age-$AgeVersion-windows-amd64.zip"
$AgeBytes    = 6000000  # ~5.5 MB compressed; same threshold for all 3

if (($DoomIncludeVault -eq $null) -or ($DoomIncludeVault -eq 1)) {
    Write-Host ''
    Write-Host "==> vault (age $AgeVersion)"

    # Linux binary — .tar.gz with age/age + age/age-keygen at top level
    $linAge = Join-Path $AgeLinDir 'age'
    if (-not (Test-Path -LiteralPath $linAge)) {
        $linTgz = Join-Path $AgeLinDir 'age.tar.gz'
        Get-File -Url $AgeLinuxUrl -Dest $linTgz -Expected $AgeBytes -Label "age $AgeVersion linux-amd64"
        if (Get-Command tar -ErrorAction SilentlyContinue) {
            tar -xzf $linTgz -C $AgeLinDir --strip-components=1
            Remove-Item -LiteralPath $linTgz -Force
            Write-Host "  [extract] $linAge"
        } else {
            Write-Host '  [warn] tar.exe not available; leaving age.tar.gz for manual extraction'
        }
    } else {
        Write-Host "  [skip] $linAge (already extracted)"
    }

    # macOS binary (arm64) — same shape as Linux
    $macAge = Join-Path $AgeMacDir 'age'
    if (-not (Test-Path -LiteralPath $macAge)) {
        $macTgz = Join-Path $AgeMacDir 'age.tar.gz'
        Get-File -Url $AgeMacUrl -Dest $macTgz -Expected $AgeBytes -Label "age $AgeVersion darwin-arm64"
        if (Get-Command tar -ErrorAction SilentlyContinue) {
            tar -xzf $macTgz -C $AgeMacDir --strip-components=1
            Remove-Item -LiteralPath $macTgz -Force
            Write-Host "  [extract] $macAge"
        } else {
            Write-Host '  [warn] tar.exe not available; leaving age.tar.gz for manual extraction'
        }
    } else {
        Write-Host "  [skip] $macAge (already extracted)"
    }

    # Windows binary — .zip with age/age.exe + age/age-keygen.exe; flatten the age/ subdir
    $winAge = Join-Path $AgeWinDir 'age.exe'
    if (-not (Test-Path -LiteralPath $winAge)) {
        $winZip = Join-Path $AgeWinDir 'age.zip'
        Get-File -Url $AgeWinUrl -Dest $winZip -Expected $AgeBytes -Label "age $AgeVersion windows-amd64"
        Expand-Archive -LiteralPath $winZip -DestinationPath $AgeWinDir -Force
        # .zip nests under age/; flatten contents up one level then remove the empty subdir
        $nestedDir = Join-Path $AgeWinDir 'age'
        if (Test-Path -LiteralPath $nestedDir) {
            Get-ChildItem -LiteralPath $nestedDir -Force |
                Move-Item -Destination $AgeWinDir -Force
            Remove-Item -LiteralPath $nestedDir -Recurse -Force
        }
        Remove-Item -LiteralPath $winZip -Force
        Write-Host "  [extract] $winAge"
    } else {
        Write-Host "  [skip] $winAge (already extracted)"
    }

    # vault/ skeleton — only the README; recovery.tar.age is user-created, not fetched
    $vaultReadme = Join-Path $Repo 'vault\README.txt'
    if (Test-Path -LiteralPath $vaultReadme) {
        Copy-Item -LiteralPath $vaultReadme -Destination (Join-Path $VaultDir 'README.txt') -Force
    }
}

# ---------------------------------------------------------------- KeePassXC (passwords)

# Per-OS KeePassXC password manager binaries, GPL-2.0+.
# Linux:   deposit raw AppImage as-is (PowerShell on Windows can't run --appimage-extract;
#          the launcher detects and extracts on a Linux end-user host at first run).
# macOS:   fetch .dmg raw (deferred extraction by launcher via hdiutil at first launch).
# Windows: fetch Win64.zip, Expand-Archive, flatten KeePassXC-<ver>/ subdir, write
#          keepassxc.ini to activate portable mode (config/db stays next to binary).
if ($DoomIncludePasswords -eq 1) {
    Write-Host ''
    Write-Host "==> passwords (KeePassXC $KeePassXcVersion)"

    # Linux — deposit raw AppImage
    $linAppImage = Join-Path $KeePassLinDir $KeePassXcLinuxFilename
    if (-not (Test-Size -Path $linAppImage -Expected $KeePassXcLinuxBytes)) {
        Get-File -Url $KeePassXcLinuxUrl -Dest $linAppImage -Expected $KeePassXcLinuxBytes -Label "KeePassXC $KeePassXcVersion linux-x64 AppImage (~47 MB)"
    } else {
        Write-Host "  [skip] KeePassXC linux AppImage already present"
    }

    # macOS — fetch .dmg raw (extraction deferred to first-launch via hdiutil)
    $macDmg = Join-Path $KeePassMacDir $KeePassXcMacFilename
    if (-not (Test-Size -Path $macDmg -Expected $KeePassXcMacBytes)) {
        Get-File -Url $KeePassXcMacUrl -Dest $macDmg -Expected $KeePassXcMacBytes -Label "KeePassXC $KeePassXcVersion osx-arm64 dmg (~36 MB)"
    } else {
        Write-Host "  [skip] KeePassXC mac dmg already present"
    }

    # Windows — fetch Win64.zip, extract, flatten subdir, write portable-mode ini
    $winExe = Join-Path $KeePassWinDir 'KeePassXC.exe'
    if (-not (Test-Path -LiteralPath $winExe)) {
        $winZip = Join-Path $env:TEMP $KeePassXcWinFilename
        Get-File -Url $KeePassXcWinUrl -Dest $winZip -Expected $KeePassXcWinBytes -Label "KeePassXC $KeePassXcVersion win64 zip (~35 MB)"
        Expand-Archive -LiteralPath $winZip -DestinationPath $KeePassWinDir -Force
        # Flatten the nested KeePassXC-<version>/ subdir
        $nestedDir = Get-ChildItem -LiteralPath $KeePassWinDir -Directory | Select-Object -First 1
        if ($nestedDir) {
            Get-ChildItem -LiteralPath $nestedDir.FullName -Force |
                Move-Item -Destination $KeePassWinDir -Force
            Remove-Item -LiteralPath $nestedDir.FullName -Recurse -Force
        }
        Remove-Item -LiteralPath $winZip -Force
        # Write keepassxc.ini to activate portable mode
        $iniPath = Join-Path $KeePassWinDir 'keepassxc.ini'
        @("[General]", "PortableMode=true") | Set-Content -LiteralPath $iniPath
        Write-Host "  [extract] KeePassXC.exe + keepassxc.ini (portable mode)"
    } else {
        Write-Host "  [skip] KeePassXC win already extracted"
    }

    # License files
    Copy-Item -LiteralPath (Join-Path $Repo 'licenses\keepassxc-NOTICE.md')     -Destination (Join-Path $Target 'ai-kit\keepassxc\NOTICE.md')      -Force
    Copy-Item -LiteralPath (Join-Path $Repo 'licenses\keepassxc-LICENSE-GPL-2.0') -Destination (Join-Path $Target 'ai-kit\keepassxc\LICENSE-GPL-2.0') -Force

    # passwords/ skeleton — silently skipped if Wave 2's V11-10 hasn't yet produced the file
    if (Test-Path -LiteralPath (Join-Path $Repo 'passwords\README.txt')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $Target 'passwords') | Out-Null
        Copy-Item -LiteralPath (Join-Path $Repo 'passwords\README.txt') -Destination (Join-Path $Target 'passwords\README.txt') -Force
    }
}

# ---------------------------------------------------------------- ffmpeg

# Per-OS static ffmpeg binaries, GPL-3.0+.
# Linux x64 + arm64: BtbN .tar.xz. Use tar.exe -xJf (Windows 10+ ships bsdtar with xz support).
#   Architecture controlled by $env:DOOM_FFMPEG_LINUX_ARCH or default x64.
# macOS arm64: Martin-Riedl .zip (Expand-Archive).
# Windows x64: BtbN win64-gpl .zip (Expand-Archive), flatten nested ffmpeg-*/bin/ into win/.
if ($DoomIncludeFfmpeg -eq 1) {
    Write-Host ''
    Write-Host "==> ffmpeg ($FfmpegVersion)"

    # Linux — .tar.xz from BtbN; x64 by default, arm64 via env var
    $linArch = if ($env:DOOM_FFMPEG_LINUX_ARCH -eq 'arm64') { 'arm64' } else { 'x64' }
    $linFfmpegBin = Join-Path $FfmpegLinDir 'ffmpeg'
    $linFfprobeBin = Join-Path $FfmpegLinDir 'ffprobe'
    if ((-not (Test-Path -LiteralPath $linFfmpegBin)) -or (-not (Test-Path -LiteralPath $linFfprobeBin))) {
        if ($linArch -eq 'arm64') {
            $linTxz = Join-Path $env:TEMP "ffmpeg-linuxarm64.tar.xz"
            Get-File -Url $FfmpegLinuxArm64Url -Dest $linTxz -Expected $FfmpegLinuxArm64Bytes -Label "ffmpeg $FfmpegVersion linuxarm64 (~100 MB)"
        } else {
            $linTxz = Join-Path $env:TEMP "ffmpeg-linux64.tar.xz"
            Get-File -Url $FfmpegLinux64Url -Dest $linTxz -Expected $FfmpegLinux64Bytes -Label "ffmpeg $FfmpegVersion linux64 (~117 MB)"
        }
        $tar = Get-Command tar -ErrorAction SilentlyContinue
        if ($tar) {
            # Stage in temp with strip=1 (drops top-level dir, keeps bin/), then
            # move only ffmpeg + ffprobe into the dest. strip=2 would scatter
            # sibling dirs (doc/, presets/, etc.) directly into FfmpegLinDir.
            $linStage = Join-Path $env:TEMP 'ffmpeg-linux-stage'
            if (Test-Path -LiteralPath $linStage) { Remove-Item -LiteralPath $linStage -Recurse -Force }
            New-Item -ItemType Directory -Force -Path $linStage | Out-Null
            & tar -xJf $linTxz -C $linStage --strip-components=1
            Move-Item -LiteralPath (Join-Path $linStage 'bin\ffmpeg')  -Destination $FfmpegLinDir -Force
            Move-Item -LiteralPath (Join-Path $linStage 'bin\ffprobe') -Destination $FfmpegLinDir -Force
            Remove-Item -LiteralPath $linTxz -Force
            Remove-Item -LiteralPath $linStage -Recurse -Force
            Write-Host "  [extract] ffmpeg + ffprobe -> $FfmpegLinDir"
        } else {
            Write-Host "  [warn] tar.exe not found — leaving $linTxz for manual extraction"
        }
    } else {
        Write-Host "  [skip] ffmpeg linux already present"
    }

    # macOS arm64 — Martin-Riedl .zip (contains ffmpeg at root)
    $macFfmpegBin = Join-Path $FfmpegMacDir 'ffmpeg'
    if (-not (Test-Path -LiteralPath $macFfmpegBin)) {
        $macZip = Join-Path $env:TEMP 'ffmpeg-mac.zip'
        Get-File -Url $FfmpegMacUrl -Dest $macZip -Expected $FfmpegMacBytes -Label "ffmpeg $FfmpegVersion osx-arm64 (~28 MB)"
        Expand-Archive -LiteralPath $macZip -DestinationPath $FfmpegMacDir -Force
        Remove-Item -LiteralPath $macZip -Force
        Write-Host "  [extract] ffmpeg mac -> $FfmpegMacDir"
    } else {
        Write-Host "  [skip] ffmpeg mac already present"
    }

    # Windows x64 — BtbN win64-gpl .zip; flatten nested ffmpeg-*/bin/ into win/
    $winFfmpegBin = Join-Path $FfmpegWinDir 'ffmpeg.exe'
    if (-not (Test-Path -LiteralPath $winFfmpegBin)) {
        $winZip = Join-Path $env:TEMP 'ffmpeg-win.zip'
        Get-File -Url $FfmpegWinUrl -Dest $winZip -Expected $FfmpegWinBytes -Label "ffmpeg $FfmpegVersion win64-gpl (~157 MB)"
        $tmpExtract = Join-Path $env:TEMP 'ffmpeg-win-extract'
        Expand-Archive -LiteralPath $winZip -DestinationPath $tmpExtract -Force
        Remove-Item -LiteralPath $winZip -Force
        # Archive nests: ffmpeg-n7.1-latest-win64-gpl-7.1/bin/ffmpeg.exe etc.
        # Flatten contents of the nested bin/ directory into $FfmpegWinDir
        $nestedBin = Get-ChildItem -LiteralPath $tmpExtract -Recurse -Filter 'ffmpeg.exe' | Select-Object -First 1
        if ($nestedBin) {
            Get-ChildItem -LiteralPath $nestedBin.DirectoryName -Force |
                Move-Item -Destination $FfmpegWinDir -Force
        }
        Remove-Item -LiteralPath $tmpExtract -Recurse -Force
        Write-Host "  [extract] ffmpeg.exe + ffprobe.exe -> $FfmpegWinDir"
    } else {
        Write-Host "  [skip] ffmpeg win already present"
    }

    # License files
    Copy-Item -LiteralPath (Join-Path $Repo 'licenses\ffmpeg-NOTICE.md')      -Destination (Join-Path $Target 'ai-kit\ffmpeg\NOTICE.md')      -Force
    Copy-Item -LiteralPath (Join-Path $Repo 'licenses\ffmpeg-LICENSE-GPL-3.0') -Destination (Join-Path $Target 'ai-kit\ffmpeg\LICENSE-GPL-3.0') -Force
}

# ---------------------------------------------------------------- devtools (ripgrep + fzf + jq + 7-Zip + VSCodium)

if ($DoomIncludeDevtools -eq 1) {
    Write-Host ''
    Write-Host "==> devtools (ripgrep $RipgrepVersion + fzf $FzfVersion + jq $JqVersion + 7-Zip $SevenZipVersion + VSCodium $VSCodiumVersion)"

    # ripgrep Linux x64
    if (-not (Test-Path (Join-Path $DevtoolsLinDir 'rg'))) {
        $tmp = "$env:TEMP\rg-linux64.tar.gz"
        Get-File -Url $RipgrepLinux64Url -Dest $tmp -Expected $RipgrepLinux64Bytes -Label "ripgrep $RipgrepVersion linux-x64-musl"
        $stg = "$env:TEMP\rg-linux64-stage"; New-Item -ItemType Directory -Force $stg | Out-Null
        tar.exe -xzf $tmp -C $stg --strip-components=1
        Move-Item (Join-Path $stg 'rg') (Join-Path $DevtoolsLinDir 'rg') -Force
        Remove-Item $tmp, $stg -Recurse -Force -ErrorAction SilentlyContinue
    } else { Write-Host '  [skip] ripgrep linux already present' }

    # ripgrep macOS arm64
    if (-not (Test-Path (Join-Path $DevtoolsMacDir 'rg'))) {
        $tmp = "$env:TEMP\rg-mac.tar.gz"
        Get-File -Url $RipgrepMacUrl -Dest $tmp -Expected $RipgrepMacBytes -Label "ripgrep $RipgrepVersion mac-arm64"
        $stg = "$env:TEMP\rg-mac-stage"; New-Item -ItemType Directory -Force $stg | Out-Null
        tar.exe -xzf $tmp -C $stg --strip-components=1
        Move-Item (Join-Path $stg 'rg') (Join-Path $DevtoolsMacDir 'rg') -Force
        Remove-Item $tmp, $stg -Recurse -Force -ErrorAction SilentlyContinue
    } else { Write-Host '  [skip] ripgrep mac already present' }

    # ripgrep Windows
    if (-not (Test-Path (Join-Path $DevtoolsWinDir 'rg.exe'))) {
        $tmp = "$env:TEMP\rg-win.zip"
        Get-File -Url $RipgrepWinUrl -Dest $tmp -Expected $RipgrepWinBytes -Label "ripgrep $RipgrepVersion win-x64"
        Expand-Archive -Path $tmp -DestinationPath "$env:TEMP\rg-win-stage" -Force
        $rgExe = Get-ChildItem "$env:TEMP\rg-win-stage" -Recurse -Filter 'rg.exe' | Select-Object -First 1
        if ($rgExe) { Copy-Item $rgExe.FullName (Join-Path $DevtoolsWinDir 'rg.exe') }
        Remove-Item $tmp, "$env:TEMP\rg-win-stage" -Recurse -Force -ErrorAction SilentlyContinue
    } else { Write-Host '  [skip] ripgrep windows already present' }

    # fzf Linux x64
    if (-not (Test-Path (Join-Path $DevtoolsLinDir 'fzf'))) {
        $tmp = "$env:TEMP\fzf-linux64.tar.gz"
        Get-File -Url $FzfLinux64Url -Dest $tmp -Expected $FzfLinux64Bytes -Label "fzf $FzfVersion linux-amd64"
        tar.exe -xzf $tmp -C $DevtoolsLinDir fzf
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    } else { Write-Host '  [skip] fzf linux already present' }

    # fzf macOS arm64
    if (-not (Test-Path (Join-Path $DevtoolsMacDir 'fzf'))) {
        $tmp = "$env:TEMP\fzf-mac.tar.gz"
        Get-File -Url $FzfMacUrl -Dest $tmp -Expected $FzfMacBytes -Label "fzf $FzfVersion darwin-arm64"
        tar.exe -xzf $tmp -C $DevtoolsMacDir fzf
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    } else { Write-Host '  [skip] fzf mac already present' }

    # fzf Windows
    if (-not (Test-Path (Join-Path $DevtoolsWinDir 'fzf.exe'))) {
        $tmp = "$env:TEMP\fzf-win.zip"
        Get-File -Url $FzfWinUrl -Dest $tmp -Expected $FzfWinBytes -Label "fzf $FzfVersion windows-amd64"
        Expand-Archive -Path $tmp -DestinationPath $DevtoolsWinDir -Force
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    } else { Write-Host '  [skip] fzf windows already present' }

    # jq — single-file binaries
    if (-not (Test-Path (Join-Path $DevtoolsLinDir 'jq'))) {
        Get-File -Url $JqLinux64Url -Dest (Join-Path $DevtoolsLinDir 'jq') -Expected $JqLinux64Bytes -Label "jq $JqVersion linux-amd64"
    } else { Write-Host '  [skip] jq linux already present' }

    if (-not (Test-Path (Join-Path $DevtoolsMacDir 'jq'))) {
        Get-File -Url $JqMacUrl -Dest (Join-Path $DevtoolsMacDir 'jq') -Expected $JqMacBytes -Label "jq $JqVersion macos-arm64"
    } else { Write-Host '  [skip] jq mac already present' }

    if (-not (Test-Path (Join-Path $DevtoolsWinDir 'jq.exe'))) {
        Get-File -Url $JqWinUrl -Dest (Join-Path $DevtoolsWinDir 'jq.exe') -Expected $JqWinBytes -Label "jq $JqVersion windows-amd64"
    } else { Write-Host '  [skip] jq windows already present' }

    # 7-Zip Linux
    if (-not (Test-Path (Join-Path $DevtoolsLinDir '7zzs'))) {
        $tmp = "$env:TEMP\7z-linux.tar.xz"
        Get-File -Url $SevenZipLinuxUrl -Dest $tmp -Expected $SevenZipLinuxBytes -Label "7-Zip $SevenZipVersion linux-x64"
        $stg = "$env:TEMP\7z-linux-stage"; New-Item -ItemType Directory -Force $stg | Out-Null
        tar.exe -xf $tmp -C $stg
        $bin = Get-ChildItem $stg -Filter '7zzs' -Recurse | Select-Object -First 1
        if (-not $bin) { $bin = Get-ChildItem $stg -Filter '7zz' -Recurse | Select-Object -First 1 }
        if ($bin) { Copy-Item $bin.FullName (Join-Path $DevtoolsLinDir '7zzs') }
        Remove-Item $tmp, $stg -Recurse -Force -ErrorAction SilentlyContinue
    } else { Write-Host '  [skip] 7-Zip linux already present' }

    # 7-Zip macOS (name is 7zz, NOT 7zzs — upstream naming inconsistency)
    if (-not (Test-Path (Join-Path $DevtoolsMacDir '7zz'))) {
        $tmp = "$env:TEMP\7z-mac.tar.xz"
        Get-File -Url $SevenZipMacUrl -Dest $tmp -Expected $SevenZipMacBytes -Label "7-Zip $SevenZipVersion mac-arm64"
        $stg = "$env:TEMP\7z-mac-stage"; New-Item -ItemType Directory -Force $stg | Out-Null
        tar.exe -xf $tmp -C $stg
        $bin = Get-ChildItem $stg -Filter '7zz' -Recurse | Select-Object -First 1
        if ($bin) { Copy-Item $bin.FullName (Join-Path $DevtoolsMacDir '7zz') }
        Remove-Item $tmp, $stg -Recurse -Force -ErrorAction SilentlyContinue
    } else { Write-Host '  [skip] 7-Zip mac already present' }

    # 7-Zip Windows — fetch 7zr.exe (single-file, free CLI extractor) as 7za.exe
    if (-not (Test-Path (Join-Path $DevtoolsWinDir '7za.exe'))) {
        Get-File -Url $SevenZipWinUrl -Dest (Join-Path $DevtoolsWinDir '7za.exe') -Expected $SevenZipWinBytes -Label "7-Zip $SevenZipVersion win (7zr.exe portable)"
    } else { Write-Host '  [skip] 7-Zip windows already present' }

    # VSCodium Linux
    $vscLinBin = Join-Path $DevtoolsLinDir 'vscode\codium'
    if (-not (Test-Path $vscLinBin)) {
        $vscLinDir = Join-Path $DevtoolsLinDir 'vscode'
        New-Item -ItemType Directory -Force $vscLinDir | Out-Null
        $tmp = "$env:TEMP\vscodium-linux.tar.gz"
        Get-File -Url $VSCodiumLinuxUrl -Dest $tmp -Expected $VSCodiumLinuxBytes -Label "VSCodium $VSCodiumVersion linux-x64"
        tar.exe -xzf $tmp -C $vscLinDir
        New-Item -ItemType Directory -Force (Join-Path $vscLinDir 'data') | Out-Null
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    } else { Write-Host '  [skip] VSCodium linux already present' }

    # VSCodium macOS
    $vscMacApp = Join-Path $DevtoolsMacDir 'vscode\VSCodium.app'
    if (-not (Test-Path $vscMacApp)) {
        $vscMacDir = Join-Path $DevtoolsMacDir 'vscode'
        New-Item -ItemType Directory -Force $vscMacDir | Out-Null
        $tmp = "$env:TEMP\vscodium-mac.zip"
        Get-File -Url $VSCodiumMacUrl -Dest $tmp -Expected $VSCodiumMacBytes -Label "VSCodium $VSCodiumVersion darwin-arm64"
        Expand-Archive -Path $tmp -DestinationPath $vscMacDir -Force
        New-Item -ItemType Directory -Force (Join-Path $vscMacDir 'data') | Out-Null
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    } else { Write-Host '  [skip] VSCodium mac already present' }

    # VSCodium Windows
    $vscWinExe = Join-Path $DevtoolsWinDir 'vscode\VSCodium.exe'
    $vscWinExe2 = Join-Path $DevtoolsWinDir 'vscode\codium.exe'
    if (-not (Test-Path $vscWinExe) -and -not (Test-Path $vscWinExe2)) {
        $vscWinDir = Join-Path $DevtoolsWinDir 'vscode'
        New-Item -ItemType Directory -Force $vscWinDir | Out-Null
        $tmp = "$env:TEMP\vscodium-win.zip"
        Get-File -Url $VSCodiumWinUrl -Dest $tmp -Expected $VSCodiumWinBytes -Label "VSCodium $VSCodiumVersion win-x64-portable"
        Expand-Archive -Path $tmp -DestinationPath $vscWinDir -Force
        New-Item -ItemType Directory -Force (Join-Path $vscWinDir 'data') | Out-Null
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    } else { Write-Host '  [skip] VSCodium windows already present' }
}

# ---------------------------------------------------------------- certs (always-on)

Write-Host ''
Write-Host '==> certs (Mozilla CA bundle)'
New-Item -ItemType Directory -Force $CertsDir | Out-Null
$cacertDest = Join-Path $CertsDir 'cacert.pem'
if (-not (Test-Path $cacertDest)) {
    Get-File -Url $CacertUrl -Dest $cacertDest -Expected $CacertBytes -Label 'Mozilla CA bundle (cacert.pem)'
} else { Write-Host '  [skip] cacert.pem already present' }
$certReadme = Join-Path $CertsDir 'README.txt'
if (-not (Test-Path $certReadme)) {
    Set-Content -Path $certReadme -Value @'
Mozilla CA Certificate Bundle
==============================
File: cacert.pem   (~226 KB, MPL-2.0, from curl.se/docs/caextract.html)

Use with curl:
  curl --cacert "%ROOT%\ai-kit\certs\cacert.pem" https://example.com

Use with Python/requests:
  set REQUESTS_CA_BUNDLE=%ROOT%\ai-kit\certs\cacert.pem

License: Mozilla Public License 2.0 (see ai-kit\certs\LICENSE-MPL-2.0)
Updated: run build-usb.ps1 against this USB to re-fetch the latest bundle.
'@
}

# ---------------------------------------------------------------- field-manual

if ($DoomIncludeFieldmanual -eq 1) {
    Write-Host ''
    Write-Host '==> field-manual (public-domain corpus)'
    $fmDest = Join-Path $Target 'field-manual'
    if (-not (Test-Path (Join-Path $fmDest 'index.html'))) {
        Copy-Item -Recurse (Join-Path $Repo 'field-manual') $fmDest -Force
        Write-Host '  [done] field-manual corpus copied'
    } else { Write-Host '  [skip] field-manual already present' }
}

# ---------------------------------------------------------------- v0.12 license copies

if ($DoomIncludeDevtools -eq 1) {
    $dtLicDir = Join-Path $Target 'ai-kit\devtools\LICENSES'
    New-Item -ItemType Directory -Force $dtLicDir | Out-Null
    if (Test-Path (Join-Path $Repo 'licenses\devtools-NOTICE.md'))  { Copy-Item (Join-Path $Repo 'licenses\devtools-NOTICE.md') (Join-Path $Target 'ai-kit\devtools\NOTICE.md') }
    if (Test-Path (Join-Path $Repo 'licenses\devtools-LICENSES'))   { Copy-Item -Recurse (Join-Path $Repo 'licenses\devtools-LICENSES') $dtLicDir -Force }
}
# cacert is always-on
if (Test-Path (Join-Path $Repo 'licenses\cacert-NOTICE.md'))       { Copy-Item (Join-Path $Repo 'licenses\cacert-NOTICE.md')       (Join-Path $CertsDir 'NOTICE.md') }
if (Test-Path (Join-Path $Repo 'licenses\cacert-LICENSE-MPL-2.0')) { Copy-Item (Join-Path $Repo 'licenses\cacert-LICENSE-MPL-2.0') (Join-Path $CertsDir 'LICENSE-MPL-2.0') }

# ---------------------------------------------------------------- launchers + dashboard

Write-Host ''
Write-Host '==> launchers + dashboard'

Copy-Item -LiteralPath (Join-Path $Repo 'launchers\start.bat')     -Destination (Join-Path $Target 'start.bat')     -Force
Copy-Item -LiteralPath (Join-Path $Repo 'launchers\start.command') -Destination (Join-Path $Target 'start.command') -Force
Copy-Item -LiteralPath (Join-Path $Repo 'launchers\start.sh')      -Destination (Join-Path $Target 'start.sh')      -Force

foreach ($tool in @('whisper', 'wiki', 'ocr', 'docs', 'doom', 'embed', 'vault', 'img', 'passwords', 'ffmpeg', 'devtools')) {
    foreach ($ext in @('bat', 'command', 'sh')) {
        Copy-Item -LiteralPath (Join-Path $Repo "launchers\start-$tool.$ext") `
                  -Destination (Join-Path $Target "start-$tool.$ext") -Force
    }
}

Copy-Item -LiteralPath (Join-Path $Repo 'ocr\index.html')          -Destination (Join-Path $Target 'ocr\index.html')          -Force
Copy-Item -LiteralPath (Join-Path $Repo 'ocr\README.txt')          -Destination (Join-Path $Target 'ocr\README.txt')          -Force
Copy-Item -LiteralPath (Join-Path $Repo 'maps\README.md')          -Destination (Join-Path $Target 'maps\README.md')          -Force
$docsOfflineSrc = Join-Path $Repo 'docs-offline\README.txt'
if (Test-Path -LiteralPath $docsOfflineSrc) {
    Copy-Item -LiteralPath $docsOfflineSrc -Destination (Join-Path $Target 'docs-offline\README.txt') -Force
} else {
    Write-Host "  [skip] docs-offline\README.txt not in source tree (stale clone?); skipping"
}

Copy-Item -LiteralPath (Join-Path $Repo 'dashboard\index.html')    -Destination (Join-Path $Target 'index.html')              -Force
Copy-Item -LiteralPath (Join-Path $Repo 'dashboard\mobile.html')   -Destination (Join-Path $Target 'mobile.html')             -Force
Copy-Item -LiteralPath (Join-Path $Repo 'dashboard\README.txt')    -Destination (Join-Path $Target 'README.txt')              -Force

# v0.8: vendored Hollama chat tab + workspace skeleton + workspace README
# -Path (not -LiteralPath) so the trailing `*` expands as a glob — matches the
# bash side's `cp -r .../chat/. .../chat/`. -LiteralPath treats `*` literally
# and Copy-Item then errors with "Cannot find path …\chat\*" on a fresh build.
Copy-Item -Path (Join-Path $Repo 'dashboard\chat\*') -Destination $ChatDir -Recurse -Force
Copy-Item -LiteralPath (Join-Path $Repo 'workspace\README.md') -Destination (Join-Path $Target 'workspace\README.md') -Force

Write-Host ''
Write-Host '------------------------------------------------------------'
Write-Host '  Done.'
Write-Host "  Kit assembled at: $Target"
Write-Host ''
Write-Host '  Next:'
Write-Host "    Double-click $Target\start.bat in Explorer"
Write-Host ''
Write-Host "  Re-run with new settings:  .\build-usb.ps1 -i $Target"
Write-Host '------------------------------------------------------------'
