[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, Position = 0)]
    [string] $DatabasePath,

    [string] $OutputPath,

    [DateTime] $StartTime,

    [DateTime] $EndTime,

    [ValidateRange(1, 1000000)]
    [int] $Limit = 10000,

    [string] $ExtractorPath,

    [switch] $Force,

    [switch] $PassThru
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Resolve-WeChatExtractor {
    param([string] $RequestedPath)

    if ($RequestedPath) {
        return (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path
    }

    $candidates = @(
        (Join-Path $PSScriptRoot 'wechat-voice.exe'),
        (Join-Path $PSScriptRoot '..\wechat-voice.exe'),
        (Join-Path $PSScriptRoot '..\build\Release\wechat-voice.exe'),
        (Join-Path $PSScriptRoot '..\build\wechat-voice.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw 'wechat-voice.exe was not found next to the script or in the build directory.'
}

function ConvertTo-UnixSeconds {
    param([DateTime] $Value)

    $offset = [DateTimeOffset]::new($Value)
    return $offset.ToUnixTimeSeconds()
}

function Invoke-WeChatExtractor {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string[]] $Arguments
    )

    $previousPreference = $ErrorActionPreference
    try {
        # PowerShell 5.1 wraps native stderr as ErrorRecord objects. Capture it
        # without letting the script-wide Stop preference hide the exit code.
        $ErrorActionPreference = 'Continue'
        $lines = @(& $Path @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    return [PSCustomObject]@{
        ExitCode = $exitCode
        Lines = $lines
    }
}

$database = (Resolve-Path -LiteralPath $DatabasePath -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $database -PathType Leaf)) {
    throw 'DatabasePath must point to a decrypted media_*.db file.'
}

$extractor = Resolve-WeChatExtractor -RequestedPath $ExtractorPath
$hasStartTime = $PSBoundParameters.ContainsKey('StartTime')
$hasEndTime = $PSBoundParameters.ContainsKey('EndTime')

$check = Invoke-WeChatExtractor -Path $extractor -Arguments @('check', $database)
if ($check.ExitCode -ne 0) {
    $details = ($check.Lines | ForEach-Object { $_.ToString() }) -join "`n"
    throw @"
The selected file is not a readable decrypted WeChat media database.

WeChat 4.x official media_*.db files are normally still encrypted and cannot be imported directly. Return to the main window, click WeChat, and use the recommended Record playback method. If you already have a lawfully obtained SQLite copy, select one containing the VoiceInfo table.

To protect account safety, reduce antivirus false positives, and avoid platform-compliance risk, this project does not scan Weixin.exe process memory, extract or store database keys, or modify the selected file.

Details:

$details
"@
}

if (-not $OutputPath) {
    $documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
    $OutputPath = Join-Path (Join-Path $documents 'WeChat Voice Export') (Get-Date -Format 'yyyy-MM')
}
$outputDirectory = [IO.Path]::GetFullPath($OutputPath)

if ($hasStartTime -and $hasEndTime -and $StartTime -gt $EndTime) {
    throw 'StartTime must be earlier than or equal to EndTime.'
}

if (-not $PSCmdlet.ShouldProcess($database, "Extract WeChat SILK voice messages to $outputDirectory")) {
    return
}

if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$arguments = [Collections.Generic.List[string]]::new()
foreach ($value in @('export', $database, $outputDirectory, '--limit', [string]$Limit)) {
    [void] $arguments.Add($value)
}
if ($hasStartTime) {
    [void] $arguments.Add('--since')
    [void] $arguments.Add([string](ConvertTo-UnixSeconds -Value $StartTime))
}
if ($hasEndTime) {
    [void] $arguments.Add('--until')
    [void] $arguments.Add([string](ConvertTo-UnixSeconds -Value $EndTime))
}
if ($Force) {
    [void] $arguments.Add('--force')
}

$export = Invoke-WeChatExtractor -Path $extractor -Arguments $arguments.ToArray()
if ($export.ExitCode -ne 0) {
    throw "WeChat voice extraction failed:`n$(($export.Lines | ForEach-Object { $_.ToString() }) -join "`n")"
}
$exportOutput = $export.Lines

$exportedPaths = @(
    $exportOutput |
        ForEach-Object { $_.ToString() } |
        Where-Object { $_ -like 'exported=*' } |
        ForEach-Object { Join-Path $outputDirectory $_.Substring('exported='.Length) }
)

$summary = @{}
foreach ($line in ($exportOutput | ForEach-Object { $_.ToString() })) {
    if ($line -match '^summary_(exported|skipped|invalid|failed)=(\d+)$') {
        $summary[$matches[1]] = [int]$matches[2]
    }
}

Write-Host ("Done: {0} exported, {1} skipped, {2} invalid, {3} failed. Output: {4}" -f `
    $(if ($summary.ContainsKey('exported')) { $summary.exported } else { $exportedPaths.Count }), `
    $(if ($summary.ContainsKey('skipped')) { $summary.skipped } else { 0 }), `
    $(if ($summary.ContainsKey('invalid')) { $summary.invalid } else { 0 }), `
    $(if ($summary.ContainsKey('failed')) { $summary.failed } else { 0 }), `
    $outputDirectory)

if ($PassThru) {
    foreach ($path in $exportedPaths) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Get-Item -LiteralPath $path
        }
    }
}
