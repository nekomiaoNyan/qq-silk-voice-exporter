# QQ SILK Voice Exporter

English | [简体中文](README.md)

Batch-export SILK V3 voice messages from the `nt_qq\nt_data\Ptt` directory used by recent Windows versions of QQ. This project contains auditable source code and a reproducible build workflow only. It does not include AutoIt, UPX, installers, self-extracting archives, telemetry, or network access.

> No developer can permanently guarantee that a file will never trigger antivirus software. This project aims to reduce heuristic false positives and let users verify which source revision and GitHub Actions workflow produced a binary. Malware detection and a Microsoft SmartScreen “unknown app” reputation warning are different: a new unsigned program may still show a SmartScreen warning even when it contains no malicious code.

## Design

Files in QQ's storage commonly use the `.amr` extension even when their actual content is SILK data with Tencent's `0x02` prefix followed by `#!SILK_V3`. The native `qq-silk.exe` program only decodes these files to 24 kHz, 16-bit, mono WAV. A readable PowerShell script handles discovery and batch conversion.

Unlike legacy Windows packages, this project deliberately avoids:

- AutoIt GUIs and executable packers;
- UPX, obfuscation, self-extractors, and silent downloads;
- bundling FFmpeg or other third-party prebuilt executables;
- reading, deleting, or uploading the original QQ voice messages;
- fixed-size path buffers and unchecked SILK packet lengths.

## Quick start

Requirements: 64-bit Windows 10/11 and PowerShell 5.1 or later.

1. Download `qq-silk-windows-x64.zip` from [Releases](https://github.com/nekomiaoNyan/qq-silk-voice-exporter/releases/latest). Regular users do not need a compiler.
2. Extract the archive, open PowerShell, and enter the extracted directory.
3. Export all QQ voice messages automatically found for the current month:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Convert-QQVoice.ps1
```

By default, files are written to `Documents\QQ Voice Export\<current month>`. Source files are never modified. You can also specify both directories explicitly:

```powershell
.\Convert-QQVoice.ps1 `
  -InputPath 'C:\Users\YourName\Documents\Tencent Files\QQ-number\nt_qq\nt_data\Ptt\YYYY-MM\Ori' `
  -OutputPath 'D:\QQ Voice Backup' `
  -Format wav
```

Existing destination files are skipped by default. Add `-Force` to overwrite them, or `-WhatIf` to preview the operation.

### MP3 output

WAV output needs no additional software. MP3 output requires FFmpeg from a source you trust. Ensure `ffmpeg.exe` is available in `PATH`, or pass its location explicitly:

```powershell
.\Convert-QQVoice.ps1 `
  -InputPath 'C:\path\to\Ori' `
  -Format mp3 `
  -FfmpegPath 'C:\path\to\ffmpeg.exe'
```

The FFmpeg project does not directly distribute Windows executables. Its [official download page](https://ffmpeg.org/download.html) links to third-party Windows builds; obtain and verify one from a source you trust.

## Use the decoder directly

```powershell
.\qq-silk.exe 'input.amr' 'output.wav'
.\qq-silk.exe 'input.slk' 'output.wav' --sample-rate 24000
```

The decoder accepts both Tencent's `0x02` prefix and a standard `#!SILK_V3` header. WAV output is limited to about 4 GiB. Oversized, truncated, malformed, or decoder-rejected input causes an error, and any incomplete output is removed.

## Build from source

The recommended toolchain is Visual Studio 2022 Build Tools with the **Desktop development with C++** workload, plus CMake:

```powershell
.\scripts\Build.ps1 -Configuration Release
```

Or run the commands manually:

```powershell
cmake -S . -B build -A x64 -DQQ_SILK_BUILD_TESTS=ON
cmake --build build --config Release --parallel
ctest --test-dir build -C Release --output-on-failure
```

Release builds use the static MSVC runtime, CFG, ASLR, DEP, CET, and reproducible linker options, so an additional Visual C++ runtime is not required. The build does not download dependencies; the pinned SILK SDK source is included in the repository.

To include one local real-world sample in the functional test, temporarily set this environment variable. The test only reads the file and does not add it to Git:

```powershell
$env:QQ_SILK_TEST_INPUT = 'C:\path\to\one-voice-message.amr'
ctest --test-dir build -C Release --output-on-failure
Remove-Item Env:QQ_SILK_TEST_INPUT
```

## Verify a build

Every release archive includes `SHA256SUMS.txt` for its contents:

```powershell
Get-FileHash .\qq-silk.exe -Algorithm SHA256
Get-Content .\SHA256SUMS.txt
```

Non-PR builds of this public repository also receive a GitHub artifact attestation that binds the ZIP archive to the repository, commit, and workflow:

```powershell
gh attestation verify .\qq-silk-windows-x64.zip --repo nekomiaoNyan/qq-silk-voice-exporter
```

Build provenance improves supply-chain transparency, but does not by itself prove that code is perfectly secure.

Optional local Microsoft Defender scan:

```powershell
Start-MpScan -ScanType CustomScan -ScanPath (Resolve-Path .\qq-silk.exe)
```

If Defender identifies the file as malware, submit it to [Microsoft Security Intelligence for analysis](https://www.microsoft.com/wdsi/filesubmission). If SmartScreen only reports an unrecognized app, that is usually a download-reputation or code-signing issue. Stable reputation generally requires trusted code signing or Microsoft Store distribution.

## Source and licenses

- The SILK SDK source comes from [`kn007/silk-v3-decoder`](https://github.com/kn007/silk-v3-decoder) at pinned commit `507be6bca8ce1fb977a061481f1d79e8c610e309`.
- The upstream repository is MIT-licensed. SILK SDK files carry Skype Limited's BSD-style license and patent disclaimer.
- See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and [`LICENSES/`](LICENSES/) for complete attribution and license texts.

This project is not affiliated with or endorsed by Tencent, QQ, Skype, Microsoft, or the FFmpeg project. Only process chat content that you are authorized to access and retain.

## References

- [Upstream silk-v3-decoder source](https://github.com/kn007/silk-v3-decoder/tree/507be6bca8ce1fb977a061481f1d79e8c610e309/silk)
- [Microsoft: SmartScreen reputation for Windows app developers](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)
- [GitHub: Artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations)
- [GitHub-hosted Windows runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
