[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $DecoderPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$decoder = (Resolve-Path -LiteralPath $DecoderPath).Path
$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('qq-silk-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory | Out-Null

try {
    $invalidInput = Join-Path $testDirectory 'invalid.amr'
    $invalidOutput = Join-Path $testDirectory 'invalid.wav'
    [IO.File]::WriteAllBytes($invalidInput, [byte[]](0x23, 0x21, 0x41, 0x4d, 0x52))

    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $decoder $invalidInput $invalidOutput 2>$null
    $invalidExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    if ($invalidExitCode -eq 0) {
        throw 'Decoder unexpectedly accepted an invalid header.'
    }
    if (Test-Path -LiteralPath $invalidOutput) {
        throw 'Decoder left a partial output after rejecting an invalid header.'
    }

    $truncatedInput = Join-Path $testDirectory 'truncated.amr'
    $truncatedOutput = Join-Path $testDirectory 'truncated.wav'
    [IO.File]::WriteAllBytes(
        $truncatedInput,
        [byte[]](0x02, 0x23, 0x21, 0x53, 0x49, 0x4c, 0x4b, 0x5f, 0x56, 0x33, 0x08)
    )

    $ErrorActionPreference = 'Continue'
    & $decoder $truncatedInput $truncatedOutput 2>$null
    $truncatedExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    if ($truncatedExitCode -eq 0) {
        throw 'Decoder unexpectedly accepted a truncated packet length.'
    }
    if (Test-Path -LiteralPath $truncatedOutput) {
        throw 'Decoder left a partial output after a truncated input.'
    }

    $aliasInput = Join-Path $testDirectory 'alias-input.amr'
    $aliasOutput = Join-Path $testDirectory 'alias-output.wav'
    $validHeaderOnly = [byte[]](0x02, 0x23, 0x21, 0x53, 0x49, 0x4c, 0x4b, 0x5f, 0x56, 0x33)
    [IO.File]::WriteAllBytes($aliasInput, $validHeaderOnly)
    New-Item -ItemType HardLink -Path $aliasOutput -Target $aliasInput | Out-Null

    $ErrorActionPreference = 'Continue'
    & $decoder $aliasInput $aliasOutput 2>$null
    $aliasExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousPreference
    if ($aliasExitCode -eq 0) {
        throw 'Decoder unexpectedly accepted a hard-link output alias.'
    }
    $preserved = [IO.File]::ReadAllBytes($aliasInput)
    if ($preserved.Length -ne $validHeaderOnly.Length) {
        throw 'Decoder modified the input through a hard-link output alias.'
    }
    for ($index = 0; $index -lt $validHeaderOnly.Length; $index++) {
        if ($preserved[$index] -ne $validHeaderOnly[$index]) {
            throw 'Decoder modified the input through a hard-link output alias.'
        }
    }

    if ($env:QQ_SILK_TEST_INPUT) {
        $waveOutput = Join-Path $testDirectory 'decoded.wav'
        & $decoder $env:QQ_SILK_TEST_INPUT $waveOutput --sample-rate 24000
        if ($LASTEXITCODE -ne 0) {
            throw "Functional decode failed with exit code $LASTEXITCODE."
        }
        $bytes = [IO.File]::ReadAllBytes($waveOutput)
        if ($bytes.Length -le 44 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne 'RIFF') {
            throw 'Functional decode did not create a valid non-empty WAV file.'
        }
    }
}
finally {
    if (Test-Path -LiteralPath $testDirectory) {
        Remove-Item -LiteralPath $testDirectory -Recurse -Force
    }
}
