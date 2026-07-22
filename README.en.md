# QQ / WeChat SILK Voice Exporter

English | [简体中文](README.md)

Import and convert QQ SILK V3 voice messages on Windows. WeChat 4.x users can also record a voice while it is played, or read voice data from a **decrypted media-database copy**. This project contains auditable source code and a reproducible build workflow only. It does not include AutoIt, UPX, installers, self-extracting archives, telemetry, or network access.

## Why this project exists

The legacy Windows package provided by the widely used [`silk-v3-decoder`](https://github.com/kn007/silk-v3-decoder/tree/master/windows) includes an AutoIt3-compiled `silk2mp3.exe`; its upstream README also notes that some antivirus products may report false positives. A false positive does not mean that the upstream program contains malware, but the uncertainty creates a significant barrier for people who simply want to export QQ voice messages.

**This project was created as a fully open-source alternative to address antivirus reports around the popular `silk-v3-decoder` Windows tool.** Its goal is to make normal release packages much less likely to trigger false positives while allowing anyone to inspect the source, build process, and final files. The decoder is rebuilt from a pinned SILK SDK source revision, reuses none of the legacy Windows binaries, avoids AutoIt, UPX, packers, installers, and self-extractors, and is published through GitHub Actions with SHA-256 checksums and Artifact Attestations.

> The precise promise is “fully open source, auditable, and designed to reduce false positives,” not “no antivirus product will ever alert.” Security rules and file reputation change over time, and a new unsigned program may still receive a Microsoft SmartScreen “unknown app” warning even when it contains no malicious code.

## Design

Files in QQ's storage commonly use the `.amr` extension even when their actual content is SILK data with Tencent's `0x02` prefix followed by `#!SILK_V3`. The native `qq-silk.exe` program decodes these files to 24 kHz, 16-bit, mono WAV. `wechat-record.exe` uses Windows WASAPI loopback to capture audio that the user deliberately plays. `wechat-voice.exe` uses the Windows system `winsqlite3.dll` to read `VoiceInfo.voice_data` from a user-selected, decrypted `media_*.db` copy. Readable PowerShell scripts provide the GUI, filtering, and batch conversion.

Unlike legacy Windows packages, this project deliberately avoids:

- AutoIt GUIs and executable packers;
- UPX, obfuscation, self-extractors, and silent downloads;
- bundling FFmpeg or other third-party prebuilt executables;
- deleting or uploading any QQ or WeChat chat content;
- scanning `Weixin.exe` process memory, extracting database keys, or bypassing WeChat database encryption;
- fixed-size path buffers and unchecked SILK packet lengths.

## Quick start

Requirements: 64-bit Windows 10/11 and PowerShell 5.1 or later.

1. Download `qq-silk-windows-x64.zip` from [Releases](https://github.com/nekomiaoNyan/qq-silk-voice-exporter/releases/latest). Regular users do not need a compiler.
2. Extract every file and double-click the single launcher, `Start-VoiceConverter.cmd`.
3. For QQ, click **Files** or drag files/folders into the window. For WeChat, click **WeChat**, then choose **Record playback** (recommended) or **Decrypted DB** (advanced).

The graphical interface supports:

- selecting multiple files or adding an entire folder;
- recording a voice played by WeChat 4.x to a local WAV without reading its database;
- importing voices from a decrypted WeChat media database with date and count filters;
- WAV or MP3 output;
- 8, 12, 16, 24, 32, 44.1, and 48 kHz sample rates (24 kHz is the recommended default);
- choosing the output directory, overwrite behavior, MP3 quality, and the `ffmpeg.exe` needed for MP3;
- progress reporting, cancellation, and a local activity log.

QQ voice files are usually stored under:

```text
Documents\Tencent Files\<QQ-number>\nt_qq\nt_data\Ptt\YYYY-MM\Ori
```

In the file picker, sort or filter by **Date modified**. If the target file is missing, play that voice message once in QQ, then refresh or reopen the folder.

### WeChat support boundary

WeChat 3.x and some older clients store voice messages as standalone `.aud` files, commonly under:

```text
Documents\WeChat Files\<account>\FileStorage\MsgAttach\<conversation>\Audio\YYYY-MM
```

Drag these `.aud` files into the window or add their folder; they use the same local SILK decoder as QQ files.

#### WeChat 4.x

Recent WeChat versions commonly store account data under:

```text
Documents\xwechat_files\<account>\db_storage\message\media_*.db
```

WeChat 4.x voices are generally stored inside an encrypted database rather than as standalone files. The simplest safe method is to record a voice that you deliberately play:

1. Click **WeChat**, then **Record playback**.
2. Close music, videos, and other notification sounds, then click **Start**.
3. Play the target voice in WeChat. When playback ends, click **Stop and save**.
4. The tool uses Windows WASAPI to save the default playback-device mix as WAV. Default filenames contain only a timestamp, never a contact or group name.

**Every system sound** during the recording is included, so play only the target voice. This method is one voice at a time and passes through WeChat's playback path, but it never reads WeChat files, chat databases, process memory, account data, or encryption keys.

#### Decrypted database (advanced)

The project also supports a **decrypted SQLite database copy**, but it does not open an official database that is still encrypted:

1. Create a decrypted copy using a local, auditable method you trust. Never add the database, keys, or chat samples to this repository.
2. Click **WeChat** → **Decrypted DB**, then select the copy.
3. Optionally filter by date and maximum record count. Raw files use numeric names and never include contact or group names.
4. Choose WAV/MP3 output and click **Convert**.

To preserve the project's low-false-positive, auditable design, release packages do not scan `Weixin.exe` memory or obtain/store database keys. A [DMCA takedown notice published by GitHub on 2026-07-13](https://github.com/github/dmca/blob/master/2026/07/2026-07-13-wechat.md) says that a comparable key-extraction/decryption project and its repository network were removed. That page records the rights holder's allegations and GitHub's processing, not a court judgment. In any event, this project does not distribute such a component. Selecting an encrypted official database produces an actionable error and never modifies it.

The playback recorder can also be used directly. Press Enter to stop and finalize the WAV header:

```powershell
.\wechat-record.exe record 'D:\WeChat Voice\wechat-voice.wav'
```

Command-line extraction:

```powershell
.\Export-WeChatVoice.ps1 `
  -DatabasePath 'D:\WeChat database copy\media_0.db' `
  -OutputPath 'D:\WeChat Voice\Raw' `
  -StartTime '2026-07-01' `
  -EndTime '2026-07-31 23:59:59' `
  -PassThru
```

The native checker/extractor can also be used directly:

```powershell
.\wechat-voice.exe check 'D:\WeChat database copy\media_0.db'
.\wechat-voice.exe export 'D:\WeChat database copy\media_0.db' 'D:\WeChat Voice\Raw' --limit 1000
```

Changing the output sample rate cannot restore quality that was not present in the source. MP3 still requires FFmpeg from a source you trust.

If the launcher cannot start, run this command from the extracted directory:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\QQ-Silk-Converter-GUI.ps1
```

### Command-line batch export

To automatically export the current month's QQ voice messages without selecting individual files, use the original script:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Convert-QQVoice.ps1
```

By default, files are written to `Documents\QQ Voice Export\<current month>`. Source files are never modified. You can also specify both directories explicitly:

```powershell
.\Convert-QQVoice.ps1 `
  -InputPath 'C:\Users\YourName\Documents\Tencent Files\QQ-number\nt_qq\nt_data\Ptt\YYYY-MM\Ori' `
  -OutputPath 'D:\QQ Voice Backup' `
  -Format wav `
  -SampleRate 24000
```

Existing destination files are skipped by default. Add `-Force` to overwrite them, or `-WhatIf` to preview the operation.

### MP3 output

WAV output needs no additional software. The GUI first looks for `ffmpeg.exe` next to the converter, then searches the system `PATH`, and fills the path automatically when found. If it is still missing, click **Select** in MP3 mode and choose a trusted FFmpeg executable. The command-line tool can also receive the path explicitly:

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
- [Microsoft: WASAPI loopback recording](https://learn.microsoft.com/windows/win32/coreaudio/loopback-recording)
- [Microsoft: SmartScreen reputation for Windows app developers](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)
- [GitHub: Artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations)
- [GitHub-hosted Windows runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
