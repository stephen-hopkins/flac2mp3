#Requires -Version 7.0
<#
.SYNOPSIS
    Converts FLAC files in a two-level directory tree to MP3 using ffmpeg.

.DESCRIPTION
    PowerShell port of flac2mp3.sh. Walks <InputDir>/<Artist>/<Album>/
    subdirectories, converts every .flac file to .mp3 using ffmpeg (in parallel),
    then moves (or copies, if no .flac files are present) the resulting .mp3 files
    into a matching tree under <OutputDir>.

    Requires PowerShell 7+ (for ForEach-Object -Parallel) and ffmpeg on PATH.

.PARAMETER InputDir
    Root of the source two-level directory tree (artist/album layout).

.PARAMETER OutputDir
    Root of the destination directory tree. Created automatically if it does not
    exist. Resolved relative to the caller's working directory, matching the bash
    script's $topDir/$outputDir behaviour.

.PARAMETER ThrottleLimit
    Maximum number of concurrent ffmpeg processes. Defaults to the number of
    logical processors on the machine, matching GNU parallel's default.

.EXAMPLE
    .\flac2mp3.ps1 D:\Music\FLAC D:\Music\MP3

.EXAMPLE
    .\flac2mp3.ps1 .\input .\output -ThrottleLimit 4
#>
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$InputDir,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$OutputDir,

    [Parameter(Mandatory = $false)]
    [int]$ThrottleLimit = [Environment]::ProcessorCount
)

# --- Pre-flight checks --------------------------------------------------------

# Capture the caller's working directory before any navigation so that relative
# paths behave exactly like the bash version's $topDir/$outputDir expansion.
$topDir = (Get-Location).Path

# Resolve both arguments to absolute paths relative to the caller's CWD.
$absInputDir  = [System.IO.Path]::GetFullPath($InputDir,  $topDir)
$absOutputDir = [System.IO.Path]::GetFullPath($OutputDir, $topDir)

if (-not (Test-Path -LiteralPath $absInputDir -PathType Container)) {
    Write-Error "InputDir '$absInputDir' does not exist or is not a directory."
    exit 1
}

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Error "ffmpeg was not found on PATH. Please install ffmpeg and try again."
    exit 1
}

# --- Main loop ----------------------------------------------------------------

foreach ($d1 in Get-ChildItem -LiteralPath $absInputDir -Directory) {
    Write-Host "d1: $($d1.Name)"

    foreach ($d2 in Get-ChildItem -LiteralPath $d1.FullName -Directory) {
        $relPath = Join-Path $d1.Name $d2.Name
        Write-Host "d2: $relPath"

        $flacFiles = @(Get-ChildItem -LiteralPath $d2.FullName -Filter *.flac -File)

        if ($flacFiles.Count -eq 0) {
            Write-Warning "No .flac files found in '$($d2.FullName)' - skipping."
            continue
        }

        # Convert every .flac to .mp3 in parallel, output alongside the source file.
        # Mirrors: parallel ffmpeg -i {} -qscale:a 0 {.}.mp3 ::: *.flac
        # Note: -vsync was a video-sync option removed in ffmpeg 6.0 and is not
        # applicable to audio-only conversion, so it is omitted here.
        $flacFiles | ForEach-Object -Parallel {
            $mp3Path = [System.IO.Path]::ChangeExtension($_.FullName, '.mp3')
            & ffmpeg -i $_.FullName -qscale:a 0 $mp3Path
        } -ThrottleLimit $ThrottleLimit

        # Create the mirrored output directory.
        # Mirrors: mkdir -p topDir/outputDir/d1/d2
        $destDir = Join-Path $absOutputDir $relPath
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null

        # Collect the mp3s that ffmpeg just produced.
        $mp3Files = @(Get-ChildItem -LiteralPath $d2.FullName -Filter *.mp3 -File)

        # Move if .flac files were present (normal case); copy otherwise.
        # Mirrors: if ls *.flac; then mv *.mp3 ...; else cp *.mp3 ...; fi
        if ($flacFiles.Count -gt 0) {
            $mp3Files | Move-Item -Destination $destDir -Force
        } else {
            $mp3Files | Copy-Item -Destination $destDir -Force
        }
    }
}

