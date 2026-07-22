[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RecorderPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$recorder = (Resolve-Path -LiteralPath $RecorderPath -ErrorAction Stop).Path
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('wechat-recorder-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory | Out-Null
try {
    $output = Join-Path $testDirectory 'synthetic-silence.wav'
    & $recorder self-test $output
    if ($LASTEXITCODE -ne 0) {
        throw "Recorder self-test failed with exit code $LASTEXITCODE."
    }
    $bytes = [IO.File]::ReadAllBytes($output)
    if ($bytes.Length -ne 206) {
        throw "Unexpected self-test WAV length: $($bytes.Length)."
    }
    if ([Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'RIFF' -or
        [Text.Encoding]::ASCII.GetString($bytes, 8, 4) -ne 'WAVE' -or
        [Text.Encoding]::ASCII.GetString($bytes, 38, 4) -ne 'data') {
        throw 'Recorder self-test did not create a valid RIFF/WAVE header.'
    }
    if ([BitConverter]::ToUInt32($bytes, 4) -ne 198 -or
        [BitConverter]::ToUInt32($bytes, 42) -ne 160) {
        throw 'Recorder self-test WAV sizes were not finalized correctly.'
    }

    $originalErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $recorder record-process not-a-pid (Join-Path $testDirectory 'must-not-exist.wav') 2>$null
    $invalidPidExitCode = $LASTEXITCODE
    $ErrorActionPreference = $originalErrorPreference
    if ($invalidPidExitCode -ne 2) {
        throw "Recorder did not reject an invalid process ID with exit code 2. Actual: $invalidPidExitCode."
    }
}
finally {
    if (Test-Path -LiteralPath $testDirectory) {
        Remove-Item -LiteralPath $testDirectory -Recurse -Force
    }
}
