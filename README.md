# QQ SILK 语音导出工具

从 Windows 新版 QQ 的 `nt_qq\nt_data\Ptt` 目录中批量导出 SILK V3 语音。项目只包含可审计源码和可复现构建流程，不包含 AutoIt、UPX、安装器、自解压程序、遥测或联网功能。

> “不报毒”不能被任何开发者永久保证。这个项目的目标是尽量减少启发式误报，并让你能检查二进制由哪份源码、在哪个 GitHub Actions 工作流中构建。杀毒软件的恶意代码检测与 SmartScreen 的“未知应用”信誉提示也不是同一件事：全新的未签名程序即使没有恶意代码，仍可能出现 SmartScreen 提示。

## 为什么这样做

QQ 目录中的文件扩展名经常是 `.amr`，但实际内容可能是腾讯前缀 `0x02` 加 `#!SILK_V3` 的 SILK 数据。本项目的原生程序 `qq-silk.exe` 只负责把这类文件解码为 24 kHz、16-bit、单声道 WAV；可阅读的 PowerShell 脚本负责查找和批量转换。

与旧 Windows 工具相比，这里有意避免：

- AutoIt GUI 和打包器；
- UPX、壳、混淆、自解压或静默下载；
- 把 FFmpeg 或其他预编译程序塞进仓库；
- 读取、删除或上传原始 QQ 语音；
- 固定长度路径缓冲区和未校验的 SILK 包长度。

## 快速使用

1. 在仓库的 **Actions → build-windows → Artifacts** 下载 `qq-silk-windows-x64`。
2. 解压后打开 PowerShell，进入解压目录。
3. 导出本月所有自动发现的 QQ 语音：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Convert-QQVoice.ps1
```

脚本默认输出到“文档\QQ Voice Export\当前月份”，不会改动源文件。也可以明确指定目录：

```powershell
.\Convert-QQVoice.ps1 `
  -InputPath 'C:\Users\你的用户名\Documents\Tencent Files\QQ号\nt_qq\nt_data\Ptt\2026-07\Ori' `
  -OutputPath 'D:\QQ语音备份' `
  -Format wav
```

已有目标默认跳过。确认需要覆盖时加 `-Force`；只查看将执行什么可加 `-WhatIf`。

### 输出 MP3

WAV 不需要额外程序。MP3 需要你自行安装可信来源的 FFmpeg，并确保 `ffmpeg.exe` 在 `PATH` 中，或明确指定：

```powershell
.\Convert-QQVoice.ps1 `
  -InputPath 'C:\路径\到\Ori' `
  -Format mp3 `
  -FfmpegPath 'C:\路径\到\ffmpeg.exe'
```

FFmpeg 项目本身不直接提供 Windows EXE；其[官方下载页](https://ffmpeg.org/download.html)列出了第三方 Windows 构建。请从你信任的来源取得并自行校验。

## 直接使用解码器

```powershell
.\qq-silk.exe '输入.amr' '输出.wav'
.\qq-silk.exe '输入.slk' '输出.wav' --sample-rate 24000
```

支持带腾讯 `0x02` 前缀和标准 `#!SILK_V3` 文件头。输出 WAV 上限约 4 GiB；超长、截断、包尺寸异常或解码器拒绝的数据会报错，并删除不完整的目标文件。

## 自己从源码构建

推荐使用 Visual Studio 2022 Build Tools（“使用 C++ 的桌面开发”工作负载）和 CMake：

```powershell
.\scripts\Build.ps1 -Configuration Release
```

或手动执行：

```powershell
cmake -S . -B build -A x64 -DQQ_SILK_BUILD_TESTS=ON
cmake --build build --config Release --parallel
ctest --test-dir build -C Release --output-on-failure
```

Release 构建使用静态 MSVC 运行库以及 CFG、ASLR、DEP、CET 和可复现链接选项，不要求额外 Visual C++ 运行库。项目不会下载依赖；SILK SDK 源码已固定在仓库中。

如果要用本机真实样本做功能测试，可临时设置环境变量。测试只读取该文件，不会把它加入仓库：

```powershell
$env:QQ_SILK_TEST_INPUT = 'C:\路径\到\某个语音.amr'
ctest --test-dir build -C Release --output-on-failure
Remove-Item Env:QQ_SILK_TEST_INPUT
```

## 校验构建产物

构建包内有 `SHA256SUMS.txt`：

```powershell
Get-FileHash .\qq-silk.exe -Algorithm SHA256
Get-Content .\SHA256SUMS.txt
```

公开仓库的非 PR 构建还会生成 GitHub Artifact Attestation，可把二进制与仓库、提交和工作流绑定：

```powershell
gh attestation verify .\qq-silk-windows-x64.zip --repo 所有者/仓库名
```

构建来源证明可以提高供应链透明度，但它本身不等于“代码绝对安全”。

可选的本机 Defender 扫描：

```powershell
Start-MpScan -ScanType CustomScan -ScanPath (Resolve-Path .\qq-silk.exe)
```

若 Defender 把文件明确识别成恶意软件，可向[微软提交文件分析](https://www.microsoft.com/wdsi/filesubmission)。若只是 SmartScreen 显示“无法识别的应用”，那通常是下载量/签名信誉问题；微软说明未签名文件的信誉按每个新哈希重新积累，真正稳定降低提示需要可信代码签名或 Microsoft Store 分发。

## 源码与许可证

- SILK SDK 源码来自 [`kn007/silk-v3-decoder`](https://github.com/kn007/silk-v3-decoder)，固定提交：`507be6bca8ce1fb977a061481f1d79e8c610e309`。
- 上游仓库为 MIT 许可；SILK SDK 文件自身带有 Skype Limited 的 BSD 风格许可和专利免责声明。
- 完整归属和许可文本见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) 与 [`LICENSES/`](LICENSES/)。

本项目与腾讯、QQ、Skype、Microsoft 或 FFmpeg 项目没有隶属或背书关系。请只处理你有权访问和保存的聊天内容。

## 参考资料

- [上游 silk-v3-decoder 源码](https://github.com/kn007/silk-v3-decoder/tree/507be6bca8ce1fb977a061481f1d79e8c610e309/silk)
- [Microsoft：SmartScreen reputation for Windows app developers](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)
- [GitHub：Artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations)
- [GitHub-hosted Windows runner 说明](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
