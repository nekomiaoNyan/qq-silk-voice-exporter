[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [string] $InputPath,

    [Parameter(Position = 1)]
    [string] $OutputPath,

    [ValidateSet('wav', 'mp3')]
    [string] $Format = 'wav',

    [ValidateSet(8000, 12000, 16000, 24000, 32000, 44100, 48000)]
    [int] $SampleRate = 24000,

    [ValidateRange(0, 9)]
    [int] $Mp3Quality = 2,

    [string] $DecoderPath,

    [string] $FfmpegPath,

    [switch] $Recurse,

    [switch] $Force
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Get-DefaultInputDirectories {
    $documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    $month = Get-Date -Format 'yyyy-MM'
    $tencentRoot = Join-Path $documents 'Tencent Files'

    if (-not (Test-Path -LiteralPath $tencentRoot -PathType Container)) {
        return @()
    }

    return @(
        Get-ChildItem -LiteralPath $tencentRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                Join-Path $_.FullName "nt_qq\nt_data\Ptt\$month\Ori"
            } |
            Where-Object { Test-Path -LiteralPath $_ -PathType Container }
    )
}

function Resolve-DecoderPath {
    param([string] $RequestedPath)

    if ($RequestedPath) {
        return (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path
    }

    $candidates = @(
        (Join-Path $PSScriptRoot 'bin\qq-silk.exe'),
        (Join-Path $PSScriptRoot 'qq-silk.exe'),
        (Join-Path $PSScriptRoot '..\qq-silk.exe'),
        (Join-Path $PSScriptRoot '..\build\Release\qq-silk.exe'),
        (Join-Path $PSScriptRoot '..\build\qq-silk.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'qq-silk.exe was not found in the package bin directory or build directory. Re-extract the complete Release ZIP or use -DecoderPath.'
}

function Resolve-FfmpegPath {
    param([string] $RequestedPath)

    if ($RequestedPath) {
        return (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path
    }

    $command = Get-Command ffmpeg -CommandType Application -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw 'MP3 output requires FFmpeg. Install it from a trusted source or use -FfmpegPath.'
    }
    return $command.Source
}

function Test-SilkHeader {
    param([string] $Path)

    $expected = [byte[]](0x23, 0x21, 0x53, 0x49, 0x4c, 0x4b, 0x5f, 0x56, 0x33)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $header = New-Object byte[] 10
        $read = $stream.Read($header, 0, $header.Length)
        $offset = if ($read -ge 10 -and $header[0] -eq 0x02) { 1 } else { 0 }
        if ($read -lt ($offset + $expected.Length)) {
            return $false
        }
        for ($index = 0; $index -lt $expected.Length; $index++) {
            if ($header[$index + $offset] -ne $expected[$index]) {
                return $false
            }
        }
        return $true
    }
    finally {
        $stream.Dispose()
    }
}

$inputItems = @()
if ($InputPath) {
    $resolvedInput = Resolve-Path -LiteralPath $InputPath -ErrorAction Stop
    $inputItems = @($resolvedInput)
}
else {
    $defaultInputs = @(Get-DefaultInputDirectories)
    if ($defaultInputs.Count -eq 0) {
        throw 'No QQ voice directory was found for this month. Specify the Ori directory with -InputPath.'
    }
    $inputItems = @($defaultInputs | ForEach-Object { Resolve-Path -LiteralPath $_ })
    Write-Host "Automatically found $($inputItems.Count) QQ voice directory/directories for this month."
}

if (-not $OutputPath) {
    $documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    $OutputPath = Join-Path (Join-Path $documents 'QQ Voice Export') (Get-Date -Format 'yyyy-MM')
}
$outputDirectory = [IO.Path]::GetFullPath($OutputPath)
$decoder = Resolve-DecoderPath -RequestedPath $DecoderPath
$ffmpeg = if ($Format -eq 'mp3') { Resolve-FfmpegPath -RequestedPath $FfmpegPath } else { $null }

if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$extensions = @('.amr', '.slk', '.silk', '.aud')
$files = foreach ($item in $inputItems) {
    if (Test-Path -LiteralPath $item.Path -PathType Leaf) {
        Get-Item -LiteralPath $item.Path
    }
    else {
        Get-ChildItem -LiteralPath $item.Path -File -Recurse:$Recurse |
            Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() }
    }
}
$files = @($files | Sort-Object FullName -Unique)

if ($files.Count -eq 0) {
    throw 'No candidate voice files were found in the input location.'
}

$converted = 0
$skipped = 0
$failed = 0

foreach ($file in $files) {
    if (-not (Test-SilkHeader -Path $file.FullName)) {
        Write-Warning "Skipping a non-SILK-V3 file: $($file.FullName)"
        $skipped++
        continue
    }

    $destination = Join-Path $outputDirectory ($file.BaseName + '.' + $Format)
    $sourceFullPath = [IO.Path]::GetFullPath($file.FullName)
    $destinationFullPath = [IO.Path]::GetFullPath($destination)
    if ($sourceFullPath.Equals($destinationFullPath, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Error -ErrorAction Continue "Refusing to replace the source file with converted output: $($file.FullName)"
        $failed++
        continue
    }
    if ((Test-Path -LiteralPath $destination -PathType Leaf) -and -not $Force) {
        Write-Warning "Destination already exists; skipping (use -Force to overwrite): $destination"
        $skipped++
        continue
    }
    if (-not $PSCmdlet.ShouldProcess($file.FullName, "Convert to $destination")) {
        continue
    }

    $temporaryStem = '.' + $file.BaseName + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    $temporaryWave = Join-Path $outputDirectory ($temporaryStem + '.wav')
    $temporaryMp3 = Join-Path $outputDirectory ($temporaryStem + '.mp3')

    try {
        & $decoder $file.FullName $temporaryWave --sample-rate $SampleRate
        if ($LASTEXITCODE -ne 0) {
            throw "qq-silk.exe exited with code $LASTEXITCODE"
        }

        if ($Format -eq 'mp3') {
            & $ffmpeg -nostdin -hide_banner -loglevel error -y -i $temporaryWave -map_metadata -1 -vn -codec:a libmp3lame -q:a $Mp3Quality $temporaryMp3
            if ($LASTEXITCODE -ne 0) {
                throw "ffmpeg.exe exited with code $LASTEXITCODE"
            }
        }

        $completedFile = if ($Format -eq 'mp3') { $temporaryMp3 } else { $temporaryWave }
        Move-Item -LiteralPath $completedFile -Destination $destination -Force:$Force

        $converted++
        Write-Host "Exported: $destination"
    }
    catch {
        $failed++
        Write-Error -ErrorAction Continue "Conversion failed: $($file.FullName)`n$($_.Exception.Message)"
    }
    finally {
        foreach ($temporaryFile in @($temporaryWave, $temporaryMp3)) {
            if (Test-Path -LiteralPath $temporaryFile -PathType Leaf) {
                Remove-Item -LiteralPath $temporaryFile -Force
            }
        }
    }
}

Write-Host "Done: $converted converted, $skipped skipped, $failed failed. Output: $outputDirectory"
if ($failed -gt 0) {
    exit 1
}
