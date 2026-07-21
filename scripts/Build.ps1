[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string] $Configuration = 'Release',

    [string] $BuildDirectory
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $BuildDirectory) {
    $BuildDirectory = Join-Path $repositoryRoot 'build'
}

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    throw 'CMake was not found. Install Visual Studio 2022 Build Tools with Desktop development with C++ and CMake.'
}

& cmake -S $repositoryRoot -B $BuildDirectory -A x64 -DQQ_SILK_BUILD_TESTS=ON
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed with exit code $LASTEXITCODE" }

& cmake --build $BuildDirectory --config $Configuration --parallel
if ($LASTEXITCODE -ne 0) { throw "Build failed with exit code $LASTEXITCODE" }

& ctest --test-dir $BuildDirectory -C $Configuration --output-on-failure
if ($LASTEXITCODE -ne 0) { throw "Tests failed with exit code $LASTEXITCODE" }

$executables = @(
    (Join-Path $BuildDirectory "$Configuration\qq-silk.exe"),
    (Join-Path $BuildDirectory "$Configuration\wechat-voice.exe")
)
foreach ($executable in $executables) {
    $hash = Get-FileHash -LiteralPath $executable -Algorithm SHA256
    Write-Host "Build complete: $executable"
    Write-Host "SHA-256: $($hash.Hash)"
}
