# Third-party notices

## Skype SILK SDK

The files under `third_party/silk-sdk/` originate from the SILK SDK copy in:

- Project: `kn007/silk-v3-decoder`
- Upstream commit: `507be6bca8ce1fb977a061481f1d79e8c610e309`
- Upstream URL: <https://github.com/kn007/silk-v3-decoder>

The upstream repository is distributed under the MIT License. A copy is in `LICENSES/silk-v3-decoder-MIT.txt`.

Individual SILK SDK files carry a separate copyright and redistribution notice from Skype Limited. A copy is in `LICENSES/SILK-SDK.txt`. In particular, that notice states that no express or implied patent license is granted. The original notices are retained in the vendored source files.

No upstream Windows executable, AutoIt source, shell converter, FFmpeg binary, or UPX-packed artifact is included in this repository.

## Windows system SQLite

`wechat-voice.exe` dynamically loads the `winsqlite3.dll` component supplied by Windows. The repository and release packages do not bundle a SQLite DLL, SQLCipher binary, or database decryption tool.

`wechat-record.exe` uses the Windows Core Audio (WASAPI) interfaces supplied by the operating system. It does not bundle an audio-capture library or access WeChat process memory.
