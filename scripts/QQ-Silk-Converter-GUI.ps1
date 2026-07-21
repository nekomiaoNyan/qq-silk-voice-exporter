[CmdletBinding()]
param(
    [switch] $SelfTest,
    [string] $DecoderPath,
    [string] $WeChatExtractorPath,
    [string] $RenderPath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Resolve-CompanionFile {
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $candidates = @(
        (Join-Path $PSScriptRoot $Name),
        (Join-Path $PSScriptRoot "..\$Name"),
        (Join-Path $PSScriptRoot "..\scripts\$Name")
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "$Name was not found next to the GUI script."
}

function Resolve-GuiDecoder {
    param([string] $RequestedPath)

    if ($RequestedPath) {
        return (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path
    }

    $candidates = @(
        (Join-Path $PSScriptRoot 'qq-silk.exe'),
        (Join-Path $PSScriptRoot '..\qq-silk.exe'),
        (Join-Path $PSScriptRoot '..\build\Release\qq-silk.exe'),
        (Join-Path $PSScriptRoot '..\build\qq-silk.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw 'qq-silk.exe was not found next to the GUI script.'
}

function Resolve-GuiWeChatExtractor {
    param([string] $RequestedPath)

    if ($RequestedPath) {
        return (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path
    }

    $candidates = @(
        (Join-Path $PSScriptRoot 'wechat-voice.exe'),
        (Join-Path $PSScriptRoot '..\wechat-voice.exe'),
        (Join-Path $PSScriptRoot '..\build\Release\wechat-voice.exe'),
        (Join-Path $PSScriptRoot '..\build\wechat-voice.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw 'wechat-voice.exe was not found next to the GUI script.'
}

function Resolve-GuiFfmpeg {
    $localCandidates = @(
        (Join-Path $PSScriptRoot 'ffmpeg.exe'),
        (Join-Path $PSScriptRoot '..\ffmpeg.exe')
    )
    foreach ($candidate in $localCandidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $command = Get-Command ffmpeg.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    return $null
}

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string] $Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object Text.StringBuilder
    [void] $builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            if ($backslashes -gt 0) {
                [void] $builder.Append(('\' * ($backslashes * 2)))
            }
            [void] $builder.Append('\"')
        }
        else {
            if ($backslashes -gt 0) {
                [void] $builder.Append(('\' * $backslashes))
            }
            [void] $builder.Append($character)
        }
        $backslashes = 0
    }
    if ($backslashes -gt 0) {
        [void] $builder.Append(('\' * ($backslashes * 2)))
    }
    [void] $builder.Append('"')
    return $builder.ToString()
}

$script:batchScript = Resolve-CompanionFile -Name 'Convert-QQVoice.ps1'
$script:weChatExportScript = Resolve-CompanionFile -Name 'Export-WeChatVoice.ps1'
$script:decoder = Resolve-GuiDecoder -RequestedPath $DecoderPath
$script:weChatExtractor = Resolve-GuiWeChatExtractor -RequestedPath $WeChatExtractorPath
$script:defaultFfmpeg = Resolve-GuiFfmpeg
$script:supportedExtensions = @('.amr', '.slk', '.silk', '.aud')
$script:supportedRates = @(8000, 12000, 16000, 24000, 32000, 44100, 48000)

if ($SelfTest) {
    [PSCustomObject]@{
        GuiAssembliesLoaded = $true
        BatchScriptFound = Test-Path -LiteralPath $script:batchScript -PathType Leaf
        WeChatScriptFound = Test-Path -LiteralPath $script:weChatExportScript -PathType Leaf
        DecoderFound = Test-Path -LiteralPath $script:decoder -PathType Leaf
        WeChatExtractorFound = Test-Path -LiteralPath $script:weChatExtractor -PathType Leaf
        SampleRates = $script:supportedRates -join ','
        Mp3Qualities = '2,4,6'
        FfmpegFound = [bool]$script:defaultFfmpeg
        FfmpegPath = $script:defaultFfmpeg
    }
    return
}

[Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object Windows.Forms.Form
$form.Text = 'QQ / 微信 SILK 语音转换器 / Voice Converter'
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object Drawing.Size(900, 820)
$form.MinimumSize = New-Object Drawing.Size(800, 740)
$form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)
$form.BackColor = [Drawing.Color]::FromArgb(248, 249, 251)
$form.AllowDrop = $true
$form.AutoScaleMode = 'Dpi'

$titleLabel = New-Object Windows.Forms.Label
$titleLabel.Text = 'QQ / 微信 SILK 语音转换器'
$titleLabel.Font = New-Object Drawing.Font('Microsoft YaHei UI', 17, [Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [Drawing.Color]::FromArgb(32, 42, 56)
$titleLabel.Location = New-Object Drawing.Point(18, 14)
$titleLabel.AutoSize = $true
$form.Controls.Add($titleLabel)

$subtitleLabel = New-Object Windows.Forms.Label
$subtitleLabel.Text = '导入 QQ 语音文件或已解密的微信媒体库，然后直接转换 / Import QQ files or a decrypted WeChat media database.'
$subtitleLabel.ForeColor = [Drawing.Color]::FromArgb(90, 100, 115)
$subtitleLabel.Location = New-Object Drawing.Point(20, 51)
$subtitleLabel.AutoSize = $true
$form.Controls.Add($subtitleLabel)

$inputGroup = New-Object Windows.Forms.GroupBox
$inputGroup.Text = '1. 输入文件 / Input files'
$inputGroup.Location = New-Object Drawing.Point(15, 78)
$inputGroup.Size = New-Object Drawing.Size(870, 315)
$inputGroup.Anchor = 'Top,Left,Right'
$form.Controls.Add($inputGroup)

$addFilesButton = New-Object Windows.Forms.Button
$addFilesButton.Text = '添加文件 / Add files'
$addFilesButton.Location = New-Object Drawing.Point(15, 28)
$addFilesButton.Size = New-Object Drawing.Size(120, 32)
$inputGroup.Controls.Add($addFilesButton)

$addFolderButton = New-Object Windows.Forms.Button
$addFolderButton.Text = '添加文件夹 / Folder'
$addFolderButton.Location = New-Object Drawing.Point(142, 28)
$addFolderButton.Size = New-Object Drawing.Size(120, 32)
$inputGroup.Controls.Add($addFolderButton)

$weChatDatabaseButton = New-Object Windows.Forms.Button
$weChatDatabaseButton.Text = '导入微信 DB / WeChat DB'
$weChatDatabaseButton.Location = New-Object Drawing.Point(269, 28)
$weChatDatabaseButton.Size = New-Object Drawing.Size(170, 32)
$inputGroup.Controls.Add($weChatDatabaseButton)

$removeButton = New-Object Windows.Forms.Button
$removeButton.Text = '移除选中 / Remove'
$removeButton.Location = New-Object Drawing.Point(446, 28)
$removeButton.Size = New-Object Drawing.Size(125, 32)
$inputGroup.Controls.Add($removeButton)

$clearButton = New-Object Windows.Forms.Button
$clearButton.Text = '清空 / Clear'
$clearButton.Location = New-Object Drawing.Point(578, 28)
$clearButton.Size = New-Object Drawing.Size(90, 32)
$inputGroup.Controls.Add($clearButton)

$recurseCheck = New-Object Windows.Forms.CheckBox
$recurseCheck.Text = '含子目录 / Recurse'
$recurseCheck.Location = New-Object Drawing.Point(680, 34)
$recurseCheck.Size = New-Object Drawing.Size(170, 24)
$inputGroup.Controls.Add($recurseCheck)

$fileList = New-Object Windows.Forms.ListView
$fileList.View = 'Details'
$fileList.FullRowSelect = $true
$fileList.GridLines = $true
$fileList.HideSelection = $false
$fileList.Location = New-Object Drawing.Point(15, 70)
$fileList.Size = New-Object Drawing.Size(838, 150)
$fileList.Anchor = 'Top,Bottom,Left,Right'
[void] $fileList.Columns.Add('文件 / File', 285)
[void] $fileList.Columns.Add('目录 / Folder', 525)
$inputGroup.Controls.Add($fileList)

$countLabel = New-Object Windows.Forms.Label
$countLabel.Text = '已选择 0 个文件 / 0 files selected'
$countLabel.Location = New-Object Drawing.Point(17, 230)
$countLabel.AutoSize = $true
$inputGroup.Controls.Add($countLabel)

$dropHint = New-Object Windows.Forms.Label
$dropHint.Text = '支持 .amr .slk .silk .aud，也可拖放文件或文件夹'
$dropHint.ForeColor = [Drawing.Color]::FromArgb(95, 105, 120)
$dropHint.Location = New-Object Drawing.Point(500, 230)
$dropHint.AutoSize = $true
$inputGroup.Controls.Add($dropHint)

$locationHint = New-Object Windows.Forms.Label
$locationHint.Text = 'QQ: 文档\Tencent Files\<QQ号>\nt_qq\nt_data\Ptt\YYYY-MM\Ori'
$locationHint.ForeColor = [Drawing.Color]::FromArgb(60, 90, 135)
$locationHint.Location = New-Object Drawing.Point(17, 254)
$locationHint.AutoSize = $true
$inputGroup.Controls.Add($locationHint)

$dateHint = New-Object Windows.Forms.Label
$dateHint.Text = '微信 3.x：...\FileStorage\MsgAttach\...\Audio\YYYY-MM（.aud 直接添加）；4.x：导入已解密 media_*.db'
$dateHint.ForeColor = [Drawing.Color]::FromArgb(95, 105, 120)
$dateHint.Location = New-Object Drawing.Point(17, 277)
$dateHint.AutoSize = $true
$inputGroup.Controls.Add($dateHint)

$optionsGroup = New-Object Windows.Forms.GroupBox
$optionsGroup.Text = '2. 转换参数 / Conversion options'
$optionsGroup.Location = New-Object Drawing.Point(15, 403)
$optionsGroup.Size = New-Object Drawing.Size(870, 190)
$optionsGroup.Anchor = 'Top,Left,Right'
$form.Controls.Add($optionsGroup)

$outputLabel = New-Object Windows.Forms.Label
$outputLabel.Text = '输出目录 / Output'
$outputLabel.Location = New-Object Drawing.Point(17, 34)
$outputLabel.AutoSize = $true
$optionsGroup.Controls.Add($outputLabel)

$outputText = New-Object Windows.Forms.TextBox
$documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
$outputText.Text = Join-Path (Join-Path $documents 'QQ Voice Export') 'Manual'
$outputText.Location = New-Object Drawing.Point(145, 31)
$outputText.Size = New-Object Drawing.Size(590, 25)
$outputText.Anchor = 'Top,Left,Right'
$optionsGroup.Controls.Add($outputText)

$browseOutputButton = New-Object Windows.Forms.Button
$browseOutputButton.Text = '浏览 / Browse'
$browseOutputButton.Location = New-Object Drawing.Point(744, 28)
$browseOutputButton.Size = New-Object Drawing.Size(109, 30)
$browseOutputButton.Anchor = 'Top,Right'
$optionsGroup.Controls.Add($browseOutputButton)

$formatLabel = New-Object Windows.Forms.Label
$formatLabel.Text = '格式 / Format'
$formatLabel.Location = New-Object Drawing.Point(17, 78)
$formatLabel.AutoSize = $true
$optionsGroup.Controls.Add($formatLabel)

$formatCombo = New-Object Windows.Forms.ComboBox
$formatCombo.DropDownStyle = 'DropDownList'
$formatCombo.Location = New-Object Drawing.Point(145, 74)
$formatCombo.Size = New-Object Drawing.Size(115, 26)
[void] $formatCombo.Items.AddRange(@('WAV', 'MP3'))
$formatCombo.SelectedIndex = 0
$optionsGroup.Controls.Add($formatCombo)

$rateLabel = New-Object Windows.Forms.Label
$rateLabel.Text = '采样率 / Sample rate'
$rateLabel.Location = New-Object Drawing.Point(286, 78)
$rateLabel.AutoSize = $true
$optionsGroup.Controls.Add($rateLabel)

$rateCombo = New-Object Windows.Forms.ComboBox
$rateCombo.DropDownStyle = 'DropDownList'
$rateCombo.Location = New-Object Drawing.Point(438, 74)
$rateCombo.Size = New-Object Drawing.Size(118, 26)
foreach ($rate in $script:supportedRates) {
    [void] $rateCombo.Items.Add("$rate Hz")
}
$rateCombo.SelectedIndex = 3
$optionsGroup.Controls.Add($rateCombo)

$qualityLabel = New-Object Windows.Forms.Label
$qualityLabel.Text = 'MP3 质量 / Quality'
$qualityLabel.Location = New-Object Drawing.Point(590, 78)
$qualityLabel.AutoSize = $true
$optionsGroup.Controls.Add($qualityLabel)

$qualityCombo = New-Object Windows.Forms.ComboBox
$qualityCombo.DropDownStyle = 'DropDownList'
$qualityCombo.Location = New-Object Drawing.Point(716, 74)
$qualityCombo.Size = New-Object Drawing.Size(137, 26)
[void] $qualityCombo.Items.AddRange(@('q2 高 / High', 'q4 平衡 / Balanced', 'q6 小 / Smaller'))
$qualityCombo.SelectedIndex = 0
$qualityCombo.Enabled = $false
$optionsGroup.Controls.Add($qualityCombo)

$ffmpegLabel = New-Object Windows.Forms.Label
$ffmpegLabel.Text = 'FFmpeg（仅 MP3）'
$ffmpegLabel.Location = New-Object Drawing.Point(17, 123)
$ffmpegLabel.AutoSize = $true
$optionsGroup.Controls.Add($ffmpegLabel)

$ffmpegText = New-Object Windows.Forms.TextBox
$ffmpegText.Location = New-Object Drawing.Point(145, 119)
$ffmpegText.Size = New-Object Drawing.Size(590, 25)
$ffmpegText.Anchor = 'Top,Left,Right'
$ffmpegText.Enabled = $false
if ($script:defaultFfmpeg) {
    $ffmpegText.Text = $script:defaultFfmpeg
}
$optionsGroup.Controls.Add($ffmpegText)

$browseFfmpegButton = New-Object Windows.Forms.Button
$browseFfmpegButton.Text = '选择 / Select'
$browseFfmpegButton.Location = New-Object Drawing.Point(744, 116)
$browseFfmpegButton.Size = New-Object Drawing.Size(109, 30)
$browseFfmpegButton.Anchor = 'Top,Right'
$browseFfmpegButton.Enabled = $false
$optionsGroup.Controls.Add($browseFfmpegButton)

$overwriteCheck = New-Object Windows.Forms.CheckBox
$overwriteCheck.Text = '覆盖已有文件 / Overwrite existing files'
$overwriteCheck.Location = New-Object Drawing.Point(145, 157)
$overwriteCheck.Size = New-Object Drawing.Size(265, 25)
$optionsGroup.Controls.Add($overwriteCheck)

$optionHint = New-Object Windows.Forms.Label
$optionHint.Text = 'FFmpeg：同目录/PATH 自动查找；源文件只读。 / Auto-detect; source read-only.'
$optionHint.ForeColor = [Drawing.Color]::FromArgb(90, 100, 115)
$optionHint.Location = New-Object Drawing.Point(420, 159)
$optionHint.AutoSize = $true
$optionsGroup.Controls.Add($optionHint)

$convertButton = New-Object Windows.Forms.Button
$convertButton.Text = '开始转换 / Convert'
$convertButton.Location = New-Object Drawing.Point(15, 608)
$convertButton.Size = New-Object Drawing.Size(165, 40)
$convertButton.BackColor = [Drawing.Color]::FromArgb(0, 120, 215)
$convertButton.ForeColor = [Drawing.Color]::White
$convertButton.FlatStyle = 'Flat'
$convertButton.Font = New-Object Drawing.Font('Microsoft YaHei UI', 10, [Drawing.FontStyle]::Bold)
$form.Controls.Add($convertButton)

$cancelButton = New-Object Windows.Forms.Button
$cancelButton.Text = '取消 / Cancel'
$cancelButton.Location = New-Object Drawing.Point(190, 608)
$cancelButton.Size = New-Object Drawing.Size(120, 40)
$cancelButton.Enabled = $false
$form.Controls.Add($cancelButton)

$openOutputButton = New-Object Windows.Forms.Button
$openOutputButton.Text = '打开输出目录 / Open output'
$openOutputButton.Location = New-Object Drawing.Point(320, 608)
$openOutputButton.Size = New-Object Drawing.Size(190, 40)
$form.Controls.Add($openOutputButton)

$progressBar = New-Object Windows.Forms.ProgressBar
$progressBar.Location = New-Object Drawing.Point(15, 661)
$progressBar.Size = New-Object Drawing.Size(870, 20)
$progressBar.Anchor = 'Top,Left,Right'
$form.Controls.Add($progressBar)

$statusLabel = New-Object Windows.Forms.Label
$statusLabel.Text = '就绪 / Ready'
$statusLabel.Location = New-Object Drawing.Point(17, 687)
$statusLabel.AutoSize = $true
$form.Controls.Add($statusLabel)

$logText = New-Object Windows.Forms.TextBox
$logText.Location = New-Object Drawing.Point(15, 713)
$logText.Size = New-Object Drawing.Size(870, 88)
$logText.Anchor = 'Top,Bottom,Left,Right'
$logText.Multiline = $true
$logText.ReadOnly = $true
$logText.ScrollBars = 'Vertical'
$logText.BackColor = [Drawing.Color]::White
$form.Controls.Add($logText)

$script:selectedFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$script:queue = [Collections.Generic.Queue[string]]::new()
$script:activeProcess = $null
$script:activeFile = $null
$script:cancelRequested = $false
$script:processed = 0
$script:converted = 0
$script:skipped = 0
$script:failed = 0
$script:conversionOptions = $null

function Write-GuiLog {
    param([string] $Message)
    $logText.AppendText("[$(Get-Date -Format 'HH:mm:ss')] $Message`r`n")
}

function Update-FileCount {
    $countLabel.Text = "已选择 $($fileList.Items.Count) 个文件 / $($fileList.Items.Count) files selected"
}

function Add-GuiFile {
    param([string] $Path)

    try {
        $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            return
        }
        if (-not $script:selectedFiles.Add($resolved)) {
            return
        }
        $item = New-Object Windows.Forms.ListViewItem([IO.Path]::GetFileName($resolved))
        [void] $item.SubItems.Add([IO.Path]::GetDirectoryName($resolved))
        $item.Tag = $resolved
        [void] $fileList.Items.Add($item)
    }
    catch {
        Write-GuiLog "无法添加 / Could not add: $Path"
    }
    Update-FileCount
}

function Add-GuiPath {
    param([string] $Path)

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $parameters = @{
            LiteralPath = $Path
            File = $true
            ErrorAction = 'SilentlyContinue'
        }
        if ($recurseCheck.Checked) {
            $parameters.Recurse = $true
        }
        Get-ChildItem @parameters |
            Where-Object { $script:supportedExtensions -contains $_.Extension.ToLowerInvariant() } |
            ForEach-Object { Add-GuiFile -Path $_.FullName }
    }
    elseif ([IO.Path]::GetExtension($Path).Equals('.db', [StringComparison]::OrdinalIgnoreCase)) {
        Import-WeChatDatabase -DatabasePath $Path
    }
    else {
        Add-GuiFile -Path $Path
    }
}

function Show-WeChatImportDialog {
    param([string] $DatabasePath)

    $dialogForm = New-Object Windows.Forms.Form
    $dialogForm.Text = '导入微信 4.x 语音 / Import WeChat voices'
    $dialogForm.StartPosition = 'CenterParent'
    $dialogForm.ClientSize = New-Object Drawing.Size(650, 330)
    $dialogForm.FormBorderStyle = 'FixedDialog'
    $dialogForm.MaximizeBox = $false
    $dialogForm.MinimizeBox = $false
    $dialogForm.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)

    $databaseLabel = New-Object Windows.Forms.Label
    $databaseLabel.Text = '数据库 / Database'
    $databaseLabel.Location = New-Object Drawing.Point(18, 20)
    $databaseLabel.AutoSize = $true
    $dialogForm.Controls.Add($databaseLabel)

    $databaseText = New-Object Windows.Forms.TextBox
    $databaseText.Text = $DatabasePath
    $databaseText.Location = New-Object Drawing.Point(145, 17)
    $databaseText.Size = New-Object Drawing.Size(480, 25)
    $databaseText.ReadOnly = $true
    $dialogForm.Controls.Add($databaseText)

    $dateCheck = New-Object Windows.Forms.CheckBox
    $dateCheck.Text = '按日期筛选 / Filter by date'
    $dateCheck.Location = New-Object Drawing.Point(20, 62)
    $dateCheck.Size = New-Object Drawing.Size(225, 25)
    $dateCheck.Checked = $true
    $dialogForm.Controls.Add($dateCheck)

    $startLabel = New-Object Windows.Forms.Label
    $startLabel.Text = '从 / From'
    $startLabel.Location = New-Object Drawing.Point(42, 101)
    $startLabel.AutoSize = $true
    $dialogForm.Controls.Add($startLabel)

    $startPicker = New-Object Windows.Forms.DateTimePicker
    $startPicker.Format = 'Custom'
    $startPicker.CustomFormat = 'yyyy-MM-dd'
    $startPicker.Location = New-Object Drawing.Point(145, 96)
    $startPicker.Size = New-Object Drawing.Size(150, 26)
    $startPicker.Value = (Get-Date).Date.AddDays(-30)
    $dialogForm.Controls.Add($startPicker)

    $endLabel = New-Object Windows.Forms.Label
    $endLabel.Text = '到 / To'
    $endLabel.Location = New-Object Drawing.Point(325, 101)
    $endLabel.AutoSize = $true
    $dialogForm.Controls.Add($endLabel)

    $endPicker = New-Object Windows.Forms.DateTimePicker
    $endPicker.Format = 'Custom'
    $endPicker.CustomFormat = 'yyyy-MM-dd'
    $endPicker.Location = New-Object Drawing.Point(405, 96)
    $endPicker.Size = New-Object Drawing.Size(150, 26)
    $endPicker.Value = (Get-Date).Date
    $dialogForm.Controls.Add($endPicker)

    $limitLabel = New-Object Windows.Forms.Label
    $limitLabel.Text = '最多条数 / Limit'
    $limitLabel.Location = New-Object Drawing.Point(20, 145)
    $limitLabel.AutoSize = $true
    $dialogForm.Controls.Add($limitLabel)

    $limitControl = New-Object Windows.Forms.NumericUpDown
    $limitControl.Location = New-Object Drawing.Point(145, 141)
    $limitControl.Size = New-Object Drawing.Size(150, 26)
    $limitControl.Minimum = 1
    $limitControl.Maximum = 1000000
    $limitControl.Value = 10000
    $dialogForm.Controls.Add($limitControl)

    $rawLabel = New-Object Windows.Forms.Label
    $rawLabel.Text = 'SILK 临时导出 / Raw'
    $rawLabel.Location = New-Object Drawing.Point(20, 188)
    $rawLabel.AutoSize = $true
    $dialogForm.Controls.Add($rawLabel)

    $rawText = New-Object Windows.Forms.TextBox
    $rawText.Text = Join-Path (Join-Path $documents 'WeChat Voice Export') 'Raw'
    $rawText.Location = New-Object Drawing.Point(145, 184)
    $rawText.Size = New-Object Drawing.Size(370, 25)
    $dialogForm.Controls.Add($rawText)

    $rawBrowseButton = New-Object Windows.Forms.Button
    $rawBrowseButton.Text = '浏览 / Browse'
    $rawBrowseButton.Location = New-Object Drawing.Point(523, 181)
    $rawBrowseButton.Size = New-Object Drawing.Size(102, 30)
    $dialogForm.Controls.Add($rawBrowseButton)

    $noticeLabel = New-Object Windows.Forms.Label
    $noticeLabel.Text = '仅支持已解密的 SQLite 副本。官方 media_*.db 通常是加密的；本项目不会读取微信进程内存、提取密钥或联网。'
    $noticeLabel.ForeColor = [Drawing.Color]::FromArgb(125, 78, 25)
    $noticeLabel.Location = New-Object Drawing.Point(20, 225)
    $noticeLabel.Size = New-Object Drawing.Size(605, 42)
    $dialogForm.Controls.Add($noticeLabel)

    $okButton = New-Object Windows.Forms.Button
    $okButton.Text = '导入 / Import'
    $okButton.Location = New-Object Drawing.Point(405, 282)
    $okButton.Size = New-Object Drawing.Size(105, 32)
    $okButton.DialogResult = [Windows.Forms.DialogResult]::OK
    $dialogForm.Controls.Add($okButton)

    $closeButton = New-Object Windows.Forms.Button
    $closeButton.Text = '取消 / Cancel'
    $closeButton.Location = New-Object Drawing.Point(520, 282)
    $closeButton.Size = New-Object Drawing.Size(105, 32)
    $closeButton.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $dialogForm.Controls.Add($closeButton)

    $dateCheck.Add_CheckedChanged({
        $startPicker.Enabled = $dateCheck.Checked
        $endPicker.Enabled = $dateCheck.Checked
    })
    $rawBrowseButton.Add_Click({
        $folderDialog = New-Object Windows.Forms.FolderBrowserDialog
        $folderDialog.Description = '选择原始 SILK 导出目录 / Select raw SILK output folder'
        $folderDialog.ShowNewFolderButton = $true
        if (Test-Path -LiteralPath $rawText.Text -PathType Container) {
            $folderDialog.SelectedPath = $rawText.Text
        }
        if ($folderDialog.ShowDialog($dialogForm) -eq [Windows.Forms.DialogResult]::OK) {
            $rawText.Text = $folderDialog.SelectedPath
        }
        $folderDialog.Dispose()
    })

    $dialogForm.AcceptButton = $okButton
    $dialogForm.CancelButton = $closeButton
    try {
        if ($dialogForm.ShowDialog($form) -ne [Windows.Forms.DialogResult]::OK) {
            return $null
        }
        if ([string]::IsNullOrWhiteSpace($rawText.Text)) {
            throw '请选择原始 SILK 导出目录。 / Select a raw SILK output folder.'
        }
        return [PSCustomObject]@{
            FilterByDate = $dateCheck.Checked
            StartTime = $startPicker.Value.Date
            EndTime = $endPicker.Value.Date.AddDays(1).AddTicks(-1)
            Limit = [int]$limitControl.Value
            RawOutput = [IO.Path]::GetFullPath($rawText.Text)
        }
    }
    finally {
        $dialogForm.Dispose()
    }
}

function Import-WeChatDatabase {
    param([string] $DatabasePath)

    $settings = Show-WeChatImportDialog -DatabasePath $DatabasePath
    if (-not $settings) {
        return
    }

    $hadFiles = $fileList.Items.Count -gt 0
    $form.UseWaitCursor = $true
    $weChatDatabaseButton.Enabled = $false
    $statusLabel.Text = '正在只读提取微信语音 / Extracting WeChat voices...'
    [Windows.Forms.Application]::DoEvents()
    try {
        $parameters = @{
            DatabasePath = $DatabasePath
            OutputPath = $settings.RawOutput
            Limit = $settings.Limit
            ExtractorPath = $script:weChatExtractor
            Force = $true
            PassThru = $true
        }
        if ($settings.FilterByDate) {
            $parameters.StartTime = $settings.StartTime
            $parameters.EndTime = $settings.EndTime
        }
        $files = @(& $script:weChatExportScript @parameters)
        foreach ($file in $files) {
            if ($file -is [IO.FileInfo]) {
                Add-GuiFile -Path $file.FullName
            }
        }
        if (-not $hadFiles -and $fileList.Items.Count -gt 0) {
            $outputText.Text = Join-Path (Join-Path $documents 'WeChat Voice Export') 'Converted'
        }
        $statusLabel.Text = "微信导入完成：$($files.Count) 个文件 / WeChat import complete"
        Write-GuiLog $statusLabel.Text
        if ($files.Count -eq 0) {
            [void] [Windows.Forms.MessageBox]::Show(
                $form,
                '所选日期范围内没有找到可用的 SILK 语音。 / No SILK voices were found in the selected date range.',
                'QQ / WeChat SILK Converter',
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Information
            )
        }
    }
    finally {
        $weChatDatabaseButton.Enabled = $true
        $form.UseWaitCursor = $false
    }
}

function Set-GuiBusy {
    param([bool] $Busy)

    foreach ($control in @(
        $addFilesButton, $addFolderButton, $weChatDatabaseButton, $removeButton, $clearButton, $recurseCheck,
        $fileList, $outputText, $browseOutputButton, $formatCombo, $rateCombo,
        $qualityCombo, $overwriteCheck, $ffmpegText, $browseFfmpegButton, $convertButton
    )) {
        $control.Enabled = -not $Busy
    }
    if (-not $Busy -and $formatCombo.SelectedItem -eq 'WAV') {
        $ffmpegText.Enabled = $false
        $browseFfmpegButton.Enabled = $false
        $qualityCombo.Enabled = $false
    }
    $cancelButton.Enabled = $Busy
}

function Complete-GuiConversion {
    $timer.Stop()
    if ($script:activeProcess) {
        $script:activeProcess.Dispose()
        $script:activeProcess = $null
    }
    Set-GuiBusy -Busy $false
    $statusLabel.Text = "完成：$($script:converted) 成功，$($script:skipped) 跳过，$($script:failed) 失败 / Done"
    Write-GuiLog $statusLabel.Text
    $message = "转换完成。`r`n`r`n成功 / Converted: $($script:converted)`r`n跳过 / Skipped: $($script:skipped)`r`n失败 / Failed: $($script:failed)"
    if ($script:cancelRequested) {
        $message = "操作已取消。`r`n`r`n" + $message
    }
    [void] [Windows.Forms.MessageBox]::Show(
        $form,
        $message,
        'QQ / WeChat SILK Converter',
        [Windows.Forms.MessageBoxButtons]::OK,
        $(if ($script:failed -gt 0) { [Windows.Forms.MessageBoxIcon]::Warning } else { [Windows.Forms.MessageBoxIcon]::Information })
    )
}

function Start-NextGuiConversion {
    if ($script:cancelRequested -or $script:queue.Count -eq 0) {
        Complete-GuiConversion
        return
    }

    $script:activeFile = $script:queue.Dequeue()
    $statusLabel.Text = "正在转换 / Converting: $([IO.Path]::GetFileName($script:activeFile))"
    Write-GuiLog $statusLabel.Text

    $arguments = [Collections.Generic.List[string]]::new()
    foreach ($value in @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $script:batchScript,
        '-InputPath', $script:activeFile,
        '-OutputPath', $script:conversionOptions.OutputPath,
        '-Format', $script:conversionOptions.Format,
        '-SampleRate', [string]$script:conversionOptions.SampleRate,
        '-DecoderPath', $script:decoder
    )) {
        [void] $arguments.Add([string]$value)
    }
    if ($script:conversionOptions.Force) {
        [void] $arguments.Add('-Force')
    }
    if ($script:conversionOptions.Format -eq 'mp3') {
        [void] $arguments.Add('-Mp3Quality')
        [void] $arguments.Add([string]$script:conversionOptions.Mp3Quality)
        [void] $arguments.Add('-FfmpegPath')
        [void] $arguments.Add($script:conversionOptions.FfmpegPath)
    }

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = (Get-Command powershell.exe -CommandType Application).Source
    $startInfo.Arguments = (($arguments | ForEach-Object { ConvertTo-NativeArgument -Value $_ }) -join ' ')
    $startInfo.WorkingDirectory = $PSScriptRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    try {
        $script:activeProcess = New-Object Diagnostics.Process
        $script:activeProcess.StartInfo = $startInfo
        if (-not $script:activeProcess.Start()) {
            throw 'Process did not start.'
        }
    }
    catch {
        $script:failed++
        $script:processed++
        $progressBar.Value = [Math]::Min($script:processed, $progressBar.Maximum)
        Write-GuiLog "启动失败 / Start failed: $($_.Exception.Message)"
        $script:activeProcess = $null
        Start-NextGuiConversion
    }
}

$timer = New-Object Windows.Forms.Timer
$timer.Interval = 150
$timer.Add_Tick({
    if (-not $script:activeProcess -or -not $script:activeProcess.HasExited) {
        return
    }

    $stdout = $script:activeProcess.StandardOutput.ReadToEnd().Trim()
    $stderr = $script:activeProcess.StandardError.ReadToEnd().Trim()
    $exitCode = $script:activeProcess.ExitCode
    $script:activeProcess.Dispose()
    $script:activeProcess = $null

    if ($stdout) {
        foreach ($line in ($stdout -split "`r?`n")) {
            Write-GuiLog $line
        }
    }
    if ($stderr) {
        foreach ($line in ($stderr -split "`r?`n")) {
            Write-GuiLog $line
        }
    }

    if ($script:cancelRequested) {
        Write-GuiLog '当前转换已取消 / Current conversion cancelled.'
    }
    elseif ($exitCode -ne 0) {
        $script:failed++
    }
    elseif ($stdout -match '(?m)^Exported:') {
        $script:converted++
    }
    else {
        $script:skipped++
    }

    $script:processed++
    $progressBar.Value = [Math]::Min($script:processed, $progressBar.Maximum)
    Start-NextGuiConversion
})

$addFilesButton.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = '选择 QQ / SILK 语音文件 / Select voice files'
    $dialog.Filter = 'QQ/WeChat SILK voice (*.amr;*.slk;*.silk;*.aud)|*.amr;*.slk;*.silk;*.aud|All files (*.*)|*.*'
    $dialog.Multiselect = $true
    if ($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) {
        foreach ($path in $dialog.FileNames) {
            Add-GuiFile -Path $path
        }
    }
    $dialog.Dispose()
})

$addFolderButton.Add_Click({
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description = '选择包含 QQ 语音的文件夹 / Select a folder containing voice files'
    $dialog.ShowNewFolderButton = $false
    if ($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) {
        Add-GuiPath -Path $dialog.SelectedPath
    }
    $dialog.Dispose()
})

$weChatDatabaseButton.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = '选择已解密的微信 media_*.db / Select a decrypted WeChat media database'
    $dialog.Filter = 'WeChat media database (media_*.db)|media_*.db|SQLite database (*.db)|*.db|All files (*.*)|*.*'
    $dialog.Multiselect = $false
    if (Test-Path -LiteralPath $documents -PathType Container) {
        $dialog.InitialDirectory = $documents
    }
    try {
        if ($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) {
            Import-WeChatDatabase -DatabasePath $dialog.FileName
        }
    }
    catch {
        $statusLabel.Text = '微信导入失败 / WeChat import failed'
        Write-GuiLog $_.Exception.Message
        [void] [Windows.Forms.MessageBox]::Show(
            $form,
            $_.Exception.Message,
            'QQ / WeChat SILK Converter',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Warning
        )
    }
    finally {
        $dialog.Dispose()
    }
})

$removeButton.Add_Click({
    foreach ($item in @($fileList.SelectedItems)) {
        [void] $script:selectedFiles.Remove([string]$item.Tag)
        $fileList.Items.Remove($item)
    }
    Update-FileCount
})

$clearButton.Add_Click({
    $script:selectedFiles.Clear()
    $fileList.Items.Clear()
    Update-FileCount
})

$browseOutputButton.Add_Click({
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description = '选择输出目录 / Select output folder'
    $dialog.ShowNewFolderButton = $true
    if (Test-Path -LiteralPath $outputText.Text -PathType Container) {
        $dialog.SelectedPath = $outputText.Text
    }
    if ($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) {
        $outputText.Text = $dialog.SelectedPath
    }
    $dialog.Dispose()
})

$browseFfmpegButton.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = '选择 ffmpeg.exe / Select ffmpeg.exe'
    $dialog.Filter = 'ffmpeg.exe|ffmpeg.exe|Executable (*.exe)|*.exe'
    $dialog.Multiselect = $false
    if ($dialog.ShowDialog($form) -eq [Windows.Forms.DialogResult]::OK) {
        $ffmpegText.Text = $dialog.FileName
    }
    $dialog.Dispose()
})

$formatCombo.Add_SelectedIndexChanged({
    $mp3 = $formatCombo.SelectedItem -eq 'MP3'
    $ffmpegText.Enabled = $mp3
    $browseFfmpegButton.Enabled = $mp3
    $qualityCombo.Enabled = $mp3
})

$openOutputButton.Add_Click({
    try {
        $path = [IO.Path]::GetFullPath($outputText.Text)
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
        Start-Process explorer.exe -ArgumentList (ConvertTo-NativeArgument -Value $path)
    }
    catch {
        [void] [Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, 'QQ / WeChat SILK Converter', 'OK', 'Error')
    }
})

$convertButton.Add_Click({
    try {
        if ($fileList.Items.Count -eq 0) {
            throw '请先添加至少一个文件。 / Add at least one input file.'
        }
        if ([string]::IsNullOrWhiteSpace($outputText.Text)) {
            throw '请选择输出目录。 / Select an output folder.'
        }
        $outputPath = [IO.Path]::GetFullPath($outputText.Text)
        $format = $formatCombo.SelectedItem.ToString().ToLowerInvariant()
        $rate = [int]($rateCombo.SelectedItem.ToString().Split(' ')[0])
        $mp3Quality = [int]($qualityCombo.SelectedItem.ToString().Substring(1, 1))
        $ffmpegPath = $null
        if ($format -eq 'mp3') {
            if ([string]::IsNullOrWhiteSpace($ffmpegText.Text)) {
                throw 'MP3 转换需要选择 ffmpeg.exe。 / Select ffmpeg.exe for MP3 output.'
            }
            $ffmpegPath = (Resolve-Path -LiteralPath $ffmpegText.Text -ErrorAction Stop).Path
        }

        $script:queue.Clear()
        foreach ($item in $fileList.Items) {
            $script:queue.Enqueue([string]$item.Tag)
        }
        $script:conversionOptions = [PSCustomObject]@{
            OutputPath = $outputPath
            Format = $format
            SampleRate = $rate
            Mp3Quality = $mp3Quality
            Force = $overwriteCheck.Checked
            FfmpegPath = $ffmpegPath
        }
        $script:cancelRequested = $false
        $script:processed = 0
        $script:converted = 0
        $script:skipped = 0
        $script:failed = 0
        $progressBar.Minimum = 0
        $progressBar.Maximum = $fileList.Items.Count
        $progressBar.Value = 0
        $logText.Clear()
        Set-GuiBusy -Busy $true
        $timer.Start()
        Start-NextGuiConversion
    }
    catch {
        [void] [Windows.Forms.MessageBox]::Show(
            $form,
            $_.Exception.Message,
            'QQ / WeChat SILK Converter',
            [Windows.Forms.MessageBoxButtons]::OK,
            [Windows.Forms.MessageBoxIcon]::Warning
        )
    }
})

$cancelButton.Add_Click({
    $script:cancelRequested = $true
    $script:queue.Clear()
    if ($script:activeProcess -and -not $script:activeProcess.HasExited) {
        try { $script:activeProcess.Kill() } catch { }
    }
    $statusLabel.Text = '正在取消 / Cancelling...'
})

$form.Add_DragEnter({
    param($sender, $eventArgs)
    if ($eventArgs.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) {
        $eventArgs.Effect = [Windows.Forms.DragDropEffects]::Copy
    }
})

$form.Add_DragDrop({
    param($sender, $eventArgs)
    foreach ($path in [string[]]$eventArgs.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) {
        Add-GuiPath -Path $path
    }
})

$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($script:activeProcess -and -not $script:activeProcess.HasExited) {
        $answer = [Windows.Forms.MessageBox]::Show(
            $form,
            '转换仍在进行，确定退出吗？ / Conversion is running. Exit?',
            'QQ / WeChat SILK Converter',
            [Windows.Forms.MessageBoxButtons]::YesNo,
            [Windows.Forms.MessageBoxIcon]::Question
        )
        if ($answer -ne [Windows.Forms.DialogResult]::Yes) {
            $eventArgs.Cancel = $true
            return
        }
        try { $script:activeProcess.Kill() } catch { }
    }
})

Write-GuiLog '就绪。添加 QQ/SILK 文件，或导入已解密的微信媒体库。 / Ready for QQ files or a decrypted WeChat database.'
if ($RenderPath) {
    $renderTarget = [IO.Path]::GetFullPath($RenderPath)
    $renderDirectory = [IO.Path]::GetDirectoryName($renderTarget)
    if (-not (Test-Path -LiteralPath $renderDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $renderDirectory -Force | Out-Null
    }
    $form.ShowInTaskbar = $false
    $form.StartPosition = 'Manual'
    $form.Location = New-Object Drawing.Point(-32000, -32000)
    $form.Show()
    [Windows.Forms.Application]::DoEvents()
    $form.PerformLayout()
    $bitmap = New-Object Drawing.Bitmap($form.ClientSize.Width, $form.ClientSize.Height)
    try {
        $rectangle = New-Object Drawing.Rectangle([Drawing.Point]::Empty, $form.ClientSize)
        $form.DrawToBitmap($bitmap, $rectangle)
        $bitmap.Save($renderTarget, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $form.Hide()
        $bitmap.Dispose()
        $timer.Dispose()
        $form.Dispose()
    }
    return
}
[void] $form.ShowDialog()
$timer.Dispose()
$form.Dispose()
