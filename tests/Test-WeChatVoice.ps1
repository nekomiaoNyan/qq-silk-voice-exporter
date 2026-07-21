[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $ExtractorPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$extractor = (Resolve-Path -LiteralPath $ExtractorPath -ErrorAction Stop).Path
$temporaryDirectory = [IO.Path]::GetTempPath()

$output = & $extractor self-test $temporaryDirectory
if ($LASTEXITCODE -ne 0) {
    throw "wechat-voice.exe self-test failed with exit code $LASTEXITCODE"
}
if (($output -join "`n") -notmatch '(?m)^self_test=ok$') {
    throw 'wechat-voice.exe did not report a successful self-test.'
}

$encryptedDatabase = Join-Path $temporaryDirectory ('wechat-encrypted-test-' + [Guid]::NewGuid().ToString('N') + '.db')
try {
    [IO.File]::WriteAllBytes($encryptedDatabase, [byte[]](0x01, 0x02, 0x03, 0x04, 0x05))
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $extractor check $encryptedDatabase 2>$null | Out-Null
        $checkExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($checkExitCode -eq 0) {
        throw 'wechat-voice.exe accepted a non-SQLite database.'
    }
}
finally {
    if (Test-Path -LiteralPath $encryptedDatabase -PathType Leaf) {
        Remove-Item -LiteralPath $encryptedDatabase -Force
    }
}
