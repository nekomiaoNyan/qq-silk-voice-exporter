[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $DecoderPath,

    [Parameter(Mandatory)]
    [string] $WeChatExtractorPath,

    [Parameter(Mandatory)]
    [string] $WeChatRecorderPath,

    [Parameter(Mandatory)]
    [string] $LauncherPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Invoke-LauncherSelfTest {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $launcherStartInfo = New-Object Diagnostics.ProcessStartInfo
    $launcherStartInfo.FileName = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $launcherStartInfo.Arguments = '--self-test'
    $launcherStartInfo.UseShellExecute = $false
    $launcherStartInfo.CreateNoWindow = $true
    $launcherProcess = New-Object Diagnostics.Process
    $launcherProcess.StartInfo = $launcherStartInfo
    try {
        if (-not $launcherProcess.Start()) {
            throw 'Native GUI launcher self-test process did not start.'
        }
        if (-not $launcherProcess.WaitForExit(60000)) {
            $launcherProcess.Kill()
            throw 'Native GUI launcher self-test timed out after 60 seconds.'
        }
        if ($launcherProcess.ExitCode -ne 0) {
            throw "Native GUI launcher self-test failed with exit code $($launcherProcess.ExitCode)."
        }
    }
    finally {
        $launcherProcess.Dispose()
    }
}
$scripts = @(
    (Join-Path $root 'scripts\Convert-QQVoice.ps1'),
    (Join-Path $root 'scripts\Export-WeChatVoice.ps1'),
    (Join-Path $root 'scripts\QQ-Silk-Converter-GUI.ps1')
)

foreach ($scriptPath in $scripts) {
    $tokens = $null
    $errors = $null
    [void] [Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $messages = $errors | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" }
        throw "PowerShell parse errors in $scriptPath`n$($messages -join "`n")"
    }
}

foreach ($readmeName in @('README.md', 'README.en.md')) {
    $readme = Get-Content -LiteralPath (Join-Path $root $readmeName) -Raw
    if ($readme -notmatch 'QQ-WeChat-SILK-Voice-Converter-v1\.3\.1-windows-x64\.zip' -or
        $readme -notmatch 'Start-VoiceConverter\.exe' -or
        $readme -notmatch '(?i)bin') {
        throw "$readmeName does not prominently identify the download and single GUI entry point."
    }
}

$guiSource = Get-Content -LiteralPath (Join-Path $root 'scripts\QQ-Silk-Converter-GUI.ps1') -Raw
if ($guiSource -notmatch 'record-process' -or
    $guiSource -notmatch 'WeChat only' -or
    $guiSource -notmatch 'System audio') {
    throw 'GUI does not expose process-only WeChat recording with an explicit system-audio fallback.'
}

$selfTest = & (Join-Path $root 'scripts\QQ-Silk-Converter-GUI.ps1') `
    -SelfTest `
    -DecoderPath $DecoderPath `
    -WeChatExtractorPath $WeChatExtractorPath `
    -WeChatRecorderPath $WeChatRecorderPath
if (-not $selfTest.GuiAssembliesLoaded -or
    -not $selfTest.BatchScriptFound -or
    -not $selfTest.WeChatScriptFound -or
    -not $selfTest.DecoderFound -or
    -not $selfTest.WeChatExtractorFound -or
    -not $selfTest.WeChatRecorderFound) {
    throw 'GUI self-test failed.'
}
if ($selfTest.SampleRates -ne '8000,12000,16000,24000,32000,44100,48000') {
    throw 'GUI sample-rate list is unexpected.'
}
if ($selfTest.Mp3Qualities -ne '2,4,6') {
    throw 'GUI MP3-quality list is unexpected.'
}

Invoke-LauncherSelfTest -Path $LauncherPath
foreach ($obsoleteLauncher in @('Start-VoiceConverter.cmd', 'Start-VoiceConverter.vbs')) {
    if (Test-Path -LiteralPath (Join-Path $root $obsoleteLauncher)) {
        throw "The obsolete launcher must not be present: $obsoleteLauncher"
    }
}

$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('qq-silk-frontend-test-' + [Guid]::NewGuid().ToString('N'))
$originalPath = $env:Path
New-Item -ItemType Directory -Path $testDirectory | Out-Null
try {
    $inputFile = Join-Path $testDirectory 'header-only.amr'
    $outputDirectory = Join-Path $testDirectory 'output with spaces'
    $mockDecoder = Join-Path $testDirectory 'mock-decoder.cmd'
    $decoderLog = Join-Path $testDirectory 'decoder-arguments.txt'
    $mockFfmpeg = Join-Path $testDirectory 'mock-ffmpeg.cmd'
    $ffmpegLog = Join-Path $testDirectory 'ffmpeg-arguments.txt'
    $frontendPackage = Join-Path $testDirectory 'frontend package'
    $frontendBin = Join-Path $frontendPackage 'bin'
    $pathFfmpegDirectory = Join-Path $testDirectory 'ffmpeg on path'
    [IO.File]::WriteAllBytes(
        $inputFile,
        [byte[]](0x02, 0x23, 0x21, 0x53, 0x49, 0x4c, 0x4b, 0x5f, 0x56, 0x33)
    )
    $encryptedDatabase = Join-Path $testDirectory 'encrypted-media.db'
    [IO.File]::WriteAllBytes($encryptedDatabase, [Text.Encoding]::ASCII.GetBytes('not a database'))
    try {
        & (Join-Path $root 'scripts\Export-WeChatVoice.ps1') `
            -DatabasePath $encryptedDatabase `
            -OutputPath (Join-Path $testDirectory 'unused raw output') `
            -ExtractorPath $WeChatExtractorPath `
            -Force
        throw 'The encrypted-database test unexpectedly succeeded.'
    }
    catch {
        if ($_.Exception.Message -notmatch 'Record playback' -or
            $_.Exception.Message -notmatch 'does not scan Weixin\.exe') {
            throw 'The encrypted-database error is not actionable or does not explain the privacy boundary.'
        }
    }
    [IO.File]::WriteAllText(
        $mockDecoder,
        "@echo off`r`n> `"%QQ_SILK_DECODER_LOG%`" echo %*`r`n> %2 echo RIFF`r`nexit /b 0`r`n",
        [Text.Encoding]::ASCII
    )
    New-Item -ItemType Directory -Path $pathFfmpegDirectory | Out-Null
    $pathFfmpeg = Join-Path $pathFfmpegDirectory 'ffmpeg.exe'
    [IO.File]::WriteAllBytes($pathFfmpeg, [byte[]](0x4d, 0x5a))
    $env:Path = "$pathFfmpegDirectory;$originalPath"
    $pathSelfTest = & (Join-Path $root 'scripts\QQ-Silk-Converter-GUI.ps1') `
        -SelfTest `
        -DecoderPath $DecoderPath `
        -WeChatExtractorPath $WeChatExtractorPath `
        -WeChatRecorderPath $WeChatRecorderPath
    if (-not $pathSelfTest.FfmpegFound -or $pathSelfTest.FfmpegPath -ne $pathFfmpeg) {
        throw 'GUI did not automatically detect ffmpeg.exe on PATH.'
    }
    New-Item -ItemType Directory -Path $frontendBin | Out-Null
    Copy-Item (Join-Path $root 'scripts\QQ-Silk-Converter-GUI.ps1') $frontendPackage
    Copy-Item (Join-Path $root 'scripts\Convert-QQVoice.ps1') $frontendPackage
    Copy-Item (Join-Path $root 'scripts\Export-WeChatVoice.ps1') $frontendPackage
    Copy-Item $LauncherPath (Join-Path $frontendPackage 'Start-VoiceConverter.exe')
    Copy-Item $DecoderPath (Join-Path $frontendBin 'qq-silk.exe')
    Copy-Item $WeChatExtractorPath (Join-Path $frontendBin 'wechat-voice.exe')
    Copy-Item $WeChatRecorderPath (Join-Path $frontendBin 'wechat-record.exe')
    $localFfmpeg = Join-Path $frontendPackage 'ffmpeg.exe'
    [IO.File]::WriteAllBytes($localFfmpeg, [byte[]](0x4d, 0x5a))
    $packagedSelfTest = & (Join-Path $frontendPackage 'QQ-Silk-Converter-GUI.ps1') -SelfTest
    if (-not $packagedSelfTest.DecoderFound -or
        -not $packagedSelfTest.WeChatExtractorFound -or
        -not $packagedSelfTest.WeChatRecorderFound -or
        -not $packagedSelfTest.FfmpegFound -or
        $packagedSelfTest.FfmpegPath -ne $localFfmpeg) {
        throw 'GUI did not automatically detect the packaged bin components or adjacent ffmpeg.exe.'
    }
    $rootExecutables = @(Get-ChildItem -LiteralPath $frontendPackage -File -Filter '*.exe')
    if ($rootExecutables.Count -ne 2 -or
        'Start-VoiceConverter.exe' -notin $rootExecutables.Name -or
        'ffmpeg.exe' -notin $rootExecutables.Name) {
        throw 'The packaged root must contain only the launcher and optional user-provided ffmpeg.exe.'
    }
    $binExecutables = @(Get-ChildItem -LiteralPath $frontendBin -File -Filter '*.exe' | Sort-Object Name | ForEach-Object Name)
    $expectedBinExecutables = @('qq-silk.exe', 'wechat-record.exe', 'wechat-voice.exe') | Sort-Object
    if (@(Compare-Object $expectedBinExecutables $binExecutables).Count -ne 0) {
        throw 'The packaged bin directory has an unexpected executable layout.'
    }
    Invoke-LauncherSelfTest -Path (Join-Path $frontendPackage 'Start-VoiceConverter.exe')
    [IO.File]::WriteAllText(
        $mockFfmpeg,
        "@echo off`r`nsetlocal EnableExtensions`r`n> `"%QQ_SILK_FFMPEG_LOG%`" echo %*`r`nset `"last=`"`r`nfor %%A in (%*) do set `"last=%%~A`"`r`n> `"%last%`" echo ID3`r`nexit /b 0`r`n",
        [Text.Encoding]::ASCII
    )
    $env:QQ_SILK_DECODER_LOG = $decoderLog
    $env:QQ_SILK_FFMPEG_LOG = $ffmpegLog
    & (Join-Path $root 'scripts\Convert-QQVoice.ps1') `
        -InputPath $inputFile `
        -OutputPath $outputDirectory `
        -Format mp3 `
        -SampleRate 16000 `
        -Mp3Quality 6 `
        -DecoderPath $mockDecoder `
        -FfmpegPath $mockFfmpeg

    $mp3 = Join-Path $outputDirectory 'header-only.mp3'
    if (-not (Test-Path -LiteralPath $mp3 -PathType Leaf)) {
        throw 'PowerShell converter did not produce the mocked MP3 output.'
    }
    $loggedArguments = Get-Content -LiteralPath $ffmpegLog -Raw
    if ($loggedArguments -notmatch '(?:^|\s)-q:a\s+6(?:\s|$)') {
        throw 'PowerShell converter did not pass the selected MP3 quality to FFmpeg.'
    }
    $loggedDecoderArguments = Get-Content -LiteralPath $decoderLog -Raw
    if ($loggedDecoderArguments -notmatch '(?:^|\s)--sample-rate\s+16000(?:\s|$)') {
        throw 'PowerShell converter did not pass the selected sample rate to the decoder.'
    }
}
finally {
    $env:Path = $originalPath
    Remove-Item Env:QQ_SILK_DECODER_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:QQ_SILK_FFMPEG_LOG -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testDirectory) {
        Remove-Item -LiteralPath $testDirectory -Recurse -Force
    }
}
