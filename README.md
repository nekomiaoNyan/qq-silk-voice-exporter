# QQ / 微信 SILK 语音导出工具

[English](README.en.md) | 简体中文

在 Windows 上导入和转换 QQ SILK V3 语音；微信 4.x 用户也可以直接录制正在播放的语音，或从**已解密的媒体数据库副本**中只读提取。项目只包含可审计源码和可复现构建流程，不包含 AutoIt、UPX、安装器、自解压程序、遥测或联网功能。

## 项目缘起

目前广泛使用的 [`silk-v3-decoder`](https://github.com/kn007/silk-v3-decoder/tree/master/windows) 在 Windows 端提供的旧工具包包含由 AutoIt3 编译的 `silk2mp3.exe`；上游 README 也明确提醒，部分杀毒软件可能产生误报。误报不代表上游程序含有恶意代码，但对只想提取 QQ 语音的普通用户来说，“文件到底是否安全”的不确定性会带来很高的使用门槛。

**本项目正是为解决热门 `silk-v3-decoder` Windows 工具可能报毒的问题而诞生的完全开源替代方案。** 目标是让正常发布包尽可能不再触发误报，同时让任何人都能检查源码、构建过程和最终文件。项目从固定版本的 SILK SDK 源码重新构建解码器，不沿用旧 Windows 二进制，不使用 AutoIt、UPX、壳、安装器或自解压包，并通过 GitHub Actions、SHA-256 校验和 Artifact Attestation 公开发布。

> 更准确的承诺是“完全开源、可审计，并尽量减少误报”，而不是“任何杀毒软件永远不会报警”。安全软件规则和文件信誉会变化；全新的未签名程序即使没有恶意代码，仍可能出现 SmartScreen 的“未知应用”提示。

## 实现方式

QQ 目录中的文件扩展名经常是 `.amr`，但实际内容可能是腾讯前缀 `0x02` 加 `#!SILK_V3` 的 SILK 数据。本项目的原生程序 `qq-silk.exe` 负责把这类文件解码为 24 kHz、16-bit、单声道 WAV；`wechat-record.exe` 使用 Windows WASAPI 按进程回环，默认只录制微信及其子进程主动播放的声音；`wechat-voice.exe` 使用 Windows 自带的 `winsqlite3.dll`，从用户明确选择的、已解密微信 `media_*.db` 副本中只读导出 `VoiceInfo.voice_data`。可阅读的 PowerShell 脚本负责图形界面、筛选和批量转换。

与旧 Windows 工具相比，这里有意避免：

- AutoIt GUI 和打包器；
- UPX、壳、混淆、自解压或静默下载；
- 把 FFmpeg 或其他预编译程序塞进仓库；
- 删除或上传任何 QQ/微信聊天内容；
- 扫描 `Weixin.exe` 进程内存、提取数据库密钥或绕过微信数据库加密；
- 固定长度路径缓冲区和未校验的 SILK 包长度。

## 快速使用

系统要求：64 位 Windows 10/11，PowerShell 5.1 或更高版本。

1. 从 [Releases](https://github.com/nekomiaoNyan/qq-silk-voice-exporter/releases/latest) 下载 `qq-silk-windows-x64.zip`。普通用户不需要安装编译器。
2. 解压全部文件，双击唯一的启动入口 `Start-VoiceConverter.cmd`。
3. QQ 用户点击“添加文件”或拖入文件/文件夹；微信用户点击“微信语音”，再选择“播放录音（推荐）”或“已解密 DB（高级）”。

图形界面支持：

- 一次选择多个文件，或添加整个文件夹；
- 在微信 4.x 中播放语音并保存为本地 WAV，默认只录微信声音，不读取微信数据库；
- 从已解密的微信媒体库按起止日期和最大条数导入语音；
- WAV/MP3 输出；
- 8、12、16、24、32、44.1、48 kHz 采样率（默认和推荐为 24 kHz）；
- 选择输出目录、是否覆盖已有文件、MP3 质量，以及 MP3 所需的 `ffmpeg.exe`；
- 转换进度、取消操作和本地日志。

QQ 语音文件通常位于：

```text
文档\Tencent Files\<QQ号>\nt_qq\nt_data\Ptt\YYYY-MM\Ori
```

在文件选择窗口中可以按“修改日期”排序或筛选。如果没有找到目标文件，可以先回到 QQ 播放一次对应语音，再刷新或重新打开该文件夹。

### 微信支持范围

微信 3.x 及部分旧版客户端会把语音保存为独立的 `.aud` 文件，常见位置是：

```text
文档\WeChat Files\<微信账号>\FileStorage\MsgAttach\<会话目录>\Audio\YYYY-MM
```

这类 `.aud` 文件可以直接拖进窗口，或用“添加文件夹”批量加入；它们与 QQ 的 SILK 文件使用同一个本地解码流程。

#### 微信 4.x

新版微信的数据根目录通常是：

```text
文档\xwechat_files\<微信账号>\db_storage\message\media_*.db
```

微信 4.x 的语音通常不是独立文件，而是保存在加密数据库中。最简单、安全的使用方式是录制你主动播放的语音：

1. 先启动并登录微信；主界面点击“微信语音”，选择“播放录音（推荐）”。
2. 录音范围保持默认的“仅微信及子进程（推荐）”，点击“开始录音”。
3. 回到微信播放目标语音；播放结束后点击“停止并保存”。
4. 工具通过 Windows WASAPI 按进程回环，只把微信进程树播放的声音保存为 WAV；其他应用的音乐、通知声不会进入文件。文件名默认只含日期时间，不含联系人或群名称。

“仅微信”需要 Windows 10 Build 20348 或更高版本（通常是 Windows 11 或较新的 Windows 10/Server）。如果微信当时没有播放声音，录音内容会是静音。旧版 Windows 可以由用户明确选择“全部系统声音（旧系统兼容）”；该模式会录入通知、音乐和其他应用，程序**不会自动降级到它**。播放录音需要逐条进行，音频会经过微信播放链路，但不读取微信文件、聊天数据库、进程内存、账号信息或密钥；程序只读取目标进程 ID 来限定录音范围。

#### 已解密数据库（高级）

本项目也支持**已解密的 SQLite 数据库副本**，但不直接读取仍加密的官方 `media_*.db`：

1. 使用你信任、可审计的本地方式制作一份已解密数据库副本；不要把数据库、密钥或聊天样本放进本仓库。
2. 在图形界面点击“微信语音”→“已解密 DB（高级）”，选择副本。
3. 可按日期筛选并限制导入条数。程序先把原始语音保存为数字编号的 `.silk`，不在文件名中写入联系人或群名称，然后加入转换列表。
4. 选择 WAV/MP3 和输出目录，点击“开始转换”。

为保持低误报、可审计和版本稳定性，发布包不会扫描 `Weixin.exe` 进程内存，也不会自动获取或保存数据库密钥。**自动提取密钥的功能可能因权利方主张而导致仓库、Fork 或 Release 被平台下架，因此本项目不提供、集成或发布这类功能。** GitHub 于 2026-07-13 公布的一份 [DMCA 下架通知](https://github.com/github/dmca/blob/master/2026/07/2026-07-13-wechat.md) 显示，同类密钥提取/解密项目及其仓库网络已被下架；该页面记录的是权利方主张和平台处理，并不是法院判决。误选仍加密的官方数据库时，界面会用中文说明可行方案并明确拒绝，不会修改它。

播放录音器也可单独使用；下面第一种方式只录微信进程树，第二种方式才是全部系统声音。开始后按 Enter 停止并写完 WAV 文件头：

```powershell
$wechat = Get-Process Weixin | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1
.\wechat-record.exe record-process $wechat.Id 'D:\微信语音\wechat-only.wav'

# 仅用于不支持按进程录音的旧系统：
.\wechat-record.exe record 'D:\微信语音\wechat-voice.wav'
```

命令行提取示例：

```powershell
.\Export-WeChatVoice.ps1 `
  -DatabasePath 'D:\微信数据库副本\media_0.db' `
  -OutputPath 'D:\微信语音\Raw' `
  -StartTime '2026-07-01' `
  -EndTime '2026-07-31 23:59:59' `
  -PassThru
```

原生检查和提取器也可单独使用：

```powershell
.\wechat-voice.exe check 'D:\微信数据库副本\media_0.db'
.\wechat-voice.exe export 'D:\微信数据库副本\media_0.db' 'D:\微信语音\Raw' --limit 1000
```

改变输出采样率不会恢复源语音中原本不存在的音质。MP3 仍需要用户自行提供可信来源的 FFmpeg。

如果双击启动器失败，也可在解压目录中运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\QQ-Silk-Converter-GUI.ps1
```

### 命令行批量导出

不选择文件、直接自动导出本月 QQ 语音时，可以使用原有脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Convert-QQVoice.ps1
```

脚本默认输出到“文档\QQ Voice Export\当前月份”，不会改动源文件。也可以明确指定目录：

```powershell
.\Convert-QQVoice.ps1 `
  -InputPath 'C:\Users\你的用户名\Documents\Tencent Files\QQ号\nt_qq\nt_data\Ptt\YYYY-MM\Ori' `
  -OutputPath 'D:\QQ语音备份' `
  -Format wav `
  -SampleRate 24000
```

已有目标默认跳过。确认需要覆盖时加 `-Force`；只查看将执行什么可加 `-WhatIf`。

### 输出 MP3

WAV 不需要额外程序。GUI 会先自动查找与转换器放在同一目录的 `ffmpeg.exe`，再查找系统 `PATH`；找到后会自动填入。若仍未找到，MP3 模式下可以点击“选择”手动指定可信来源的 FFmpeg。命令行也可明确指定：

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
gh attestation verify .\qq-silk-windows-x64.zip --repo nekomiaoNyan/qq-silk-voice-exporter
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
- [Microsoft：WASAPI 回环录音](https://learn.microsoft.com/windows/win32/coreaudio/loopback-recording)
- [Microsoft：SmartScreen reputation for Windows app developers](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)
- [GitHub：Artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations)
- [GitHub-hosted Windows runner 说明](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
