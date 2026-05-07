# build-usb.ps1 — fetch the runtime + GGUFs and assemble the kit on a target dir.
#
# Usage:
#   .\build-usb.ps1 <target-dir>           e.g. D:\, .\usb-layout
#
# Resumable: re-running skips files whose size already matches the expected size.
# Doesn't check signatures or hashes — for an air-gapped build, mirror the
# upstream URLs locally and edit the URL constants below.

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Target
)

$ErrorActionPreference = 'Stop'

if (-not $Target -or $Target -in @('-h', '--help', '/?')) {
    @"
Usage: .\build-usb.ps1 <target-dir>

Examples:
  .\build-usb.ps1 D:\              Copy onto a mounted USB
  .\build-usb.ps1 .\usb-layout     Local dry-run: populate the in-repo skeleton

The script downloads ~22 GB total (43 MB runtime + 5 GB + 17 GB + 329 MB).
A re-run skips files that already exist with the right size.
"@ | Write-Host
    exit 0
}

$Repo = $PSScriptRoot

# ---------------------------------------------------------------- constants

$LlamafileUrl   = 'https://github.com/Mozilla-Ocho/llamafile/releases/download/0.10.1/llamafile-0.10.1-thin'
$LlamafileBytes = 43800000          # ~43 MB

$E4bUrl   = 'https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf?download=true'
$E4bFile  = 'gemma-4-E4B-it-Q4_K_M.gguf'
$E4bBytes = 5000000000              # ~5.0 GB

$MoeUrl   = 'https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/resolve/main/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf?download=true'
$MoeFile  = 'gemma-4-26B-A4B-it-UD-Q4_K_M.gguf'
$MoeBytes = 17000000000             # ~17 GB

$EmbUrl   = 'https://huggingface.co/ggml-org/embeddinggemma-300m-qat-q8_0-GGUF/resolve/main/embeddinggemma-300m-qat-Q8_0.gguf?download=true'
$EmbFile  = 'embeddinggemma-300m-qat-Q8_0.gguf'
$EmbBytes = 329000000               # ~329 MB

# ---------------------------------------------------------------- helpers

function Test-Size {
    param([string]$Path, [long]$Expected)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $actual = (Get-Item -LiteralPath $Path).Length
    return ($actual -ge ($Expected * 0.95))
}

function Get-File {
    param(
        [string]$Url,
        [string]$Dest,
        [long]$Expected,
        [string]$Label
    )

    if (Test-Size -Path $Dest -Expected $Expected) {
        Write-Host "  [skip] $Label already present at $Dest"
        return
    }

    Write-Host "  [fetch] $Label"
    Write-Host "          $Url"
    Write-Host "          -> $Dest"

    # BITS gives a real progress bar and resumes on partial files. Falls back
    # to Invoke-WebRequest if BITS is unavailable (e.g. on Server Core).
    try {
        Start-BitsTransfer -Source $Url -Destination $Dest -DisplayName $Label -ErrorAction Stop
    } catch {
        Write-Host "  (BITS unavailable, falling back to Invoke-WebRequest)"
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
    }
}

# ---------------------------------------------------------------- prep

$RuntimeDir = Join-Path $Target 'ai-kit\runtime'
$ModelsDir  = Join-Path $Target 'ai-kit\models'
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
New-Item -ItemType Directory -Force -Path $ModelsDir  | Out-Null

# ---------------------------------------------------------------- runtime

Write-Host ''
Write-Host '==> runtime'
$llamafilePath = Join-Path $RuntimeDir 'llamafile'
Get-File -Url $LlamafileUrl -Dest $llamafilePath -Expected $LlamafileBytes -Label 'llamafile-0.10.1-thin'
Copy-Item -LiteralPath $llamafilePath -Destination (Join-Path $RuntimeDir 'llamafile.exe') -Force

# ---------------------------------------------------------------- weights

Write-Host ''
Write-Host '==> models  (this is the slow part — about 22 GB total)'
Get-File -Url $E4bUrl -Dest (Join-Path $ModelsDir $E4bFile) -Expected $E4bBytes -Label 'Gemma 4 E4B Q4_K_M (~5 GB)'
Get-File -Url $MoeUrl -Dest (Join-Path $ModelsDir $MoeFile) -Expected $MoeBytes -Label 'Gemma 4 26B-A4B UD-Q4_K_M (~17 GB)'
Get-File -Url $EmbUrl -Dest (Join-Path $ModelsDir $EmbFile) -Expected $EmbBytes -Label 'EmbeddingGemma 300M Q8 (~329 MB)'

# ---------------------------------------------------------------- launchers + dashboard

Write-Host ''
Write-Host '==> launchers + dashboard'
Copy-Item -LiteralPath (Join-Path $Repo 'launchers\start.bat')     -Destination (Join-Path $Target 'start.bat')     -Force
Copy-Item -LiteralPath (Join-Path $Repo 'launchers\start.command') -Destination (Join-Path $Target 'start.command') -Force
Copy-Item -LiteralPath (Join-Path $Repo 'launchers\start.sh')      -Destination (Join-Path $Target 'start.sh')      -Force
Copy-Item -LiteralPath (Join-Path $Repo 'dashboard\index.html')    -Destination (Join-Path $Target 'index.html')    -Force
Copy-Item -LiteralPath (Join-Path $Repo 'dashboard\README.txt')    -Destination (Join-Path $Target 'README.txt')    -Force

Write-Host ''
Write-Host '------------------------------------------------------------'
Write-Host "  Done."
Write-Host "  Kit assembled at: $Target"
Write-Host ''
Write-Host '  Next:'
Write-Host "    Double-click $Target\start.bat in Explorer"
Write-Host '------------------------------------------------------------'
