$ErrorActionPreference = "Stop"

$Repo = if ($env:RUNX_REPO) { $env:RUNX_REPO } else { "aryankahar31/runx" }
$Version = if ($env:RUNX_VERSION) { $env:RUNX_VERSION } else { "latest" }
$InstallDir = if ($env:RUNX_INSTALL_DIR) { $env:RUNX_INSTALL_DIR } else { Join-Path $HOME ".runx\bin" }

$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    "AMD64" { "x64" }
    "ARM64" { "arm64" }
    default { throw "Unsupported architecture: $env:PROCESSOR_ARCHITECTURE" }
}

$asset = "runx-windows-$arch.zip"
if ($Version -eq "latest") {
    $baseUrl = "https://github.com/$Repo/releases/latest/download"
} else {
    $baseUrl = "https://github.com/$Repo/releases/download/$Version"
}
$url = "$baseUrl/$asset"

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tmp | Out-Null
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

# ---------------------------------------------------------------------------
# SHA-256 checksum verification
# ---------------------------------------------------------------------------

function Test-Checksum {
    param(
        [string]$FilePath,
        [string]$FileName,
        [string]$ChecksumFile
    )

    $lines = Get-Content -Path $ChecksumFile
    $match = $lines | Where-Object { $_ -match [regex]::Escape($FileName) } | Select-Object -First 1

    if (-not $match) {
        Write-Error "Error: could not find checksum for $FileName in SHA256SUMS."
        return $false
    }

    $expected = ($match -split '\s+')[0]
    $computed = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash

    if ($expected -ieq $computed) {
        Write-Host "Checksum verified."
        return $true
    } else {
        Write-Error @"
Error: checksum verification failed for $FileName.
Expected: $expected
Got:      $computed
This may indicate a corrupted download or a compromised release. Aborting.
"@
        return $false
    }
}

# ---------------------------------------------------------------------------
# Download, verify, and install
# ---------------------------------------------------------------------------

try {
    $archive = Join-Path $tmp $asset
    Write-Host "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $archive

    # Download SHA256SUMS and verify
    $checksumUrl = "$baseUrl/SHA256SUMS"
    $checksumFile = Join-Path $tmp "SHA256SUMS"
    Write-Host "Downloading SHA256SUMS"
    Invoke-WebRequest -Uri $checksumUrl -OutFile $checksumFile

    if (-not (Test-Checksum -FilePath $archive -FileName $asset -ChecksumFile $checksumFile)) {
        exit 1
    }

    Expand-Archive -Path $archive -DestinationPath $tmp -Force
    Copy-Item -Path (Join-Path $tmp "runx.exe") -Destination (Join-Path $InstallDir "runx.exe") -Force
    Write-Host "Installed runx to $(Join-Path $InstallDir "runx.exe")"
    if (($env:PATH -split ';') -notcontains $InstallDir) {
        Write-Host "Add $InstallDir to PATH to run runx from any directory."
    }
}
finally {
    Remove-Item -Recurse -Force $tmp
}
