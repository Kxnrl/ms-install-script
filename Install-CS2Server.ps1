<#
.SYNOPSIS
    Windows 下一键部署 CS2 服务端并安装 ModSharp + StripperSharp。

.DESCRIPTION
    把手工部署的一长串步骤合成一条命令：检查运行环境、用 SteamCMD 拉取 CS2 专用服务端
    (或直接复用本机已安装的 CS2 游戏)、安装 .NET 10 运行时、修改 gameinfo.gi、
    下载并安装 ModSharp 与 StripperSharp 的最新 Release、最后逐项自检。

    最简用法 (复制下面这行到 PowerShell 窗口回车即可, 全程有中文向导):

        powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-CS2Server.ps1

    两种部署目标 (-Target):
      Dedicated  用 SteamCMD 下载独立的专用服务端 (约 35 GB), 与游戏安装完全隔离, 适合正式开服。
      Game       直接部署到本机已安装的 CS2 游戏目录, 零下载, 适合本地测试和模块开发。
                 会修改游戏文件, 存在 VAC 风险, 脚本会要求你显式确认。

    三种运行模式 (-Mode):
      Install    首次安装, 完整跑一遍。
      Update     更新 CS2 / ModSharp / StripperSharp, 保留 configs、data、stripper 等用户数据。
      Verify     只做检查, 不写任何文件。

.PARAMETER Target
    部署目标: Dedicated (SteamCMD 专用服务端) 或 Game (本机已装的 CS2 游戏)。不填则向导询问。

.PARAMETER InstallDir
    Dedicated: 服务端根目录, 例如 C:\cs2server。
    Game: CS2 游戏根目录 (含 game 子目录的那一层)。不填则自动探测 Steam 库。

.PARAMETER Mode
    Install / Update / Verify。不填则向导询问。

.PARAMETER SteamCmdDir
    SteamCMD 的存放目录, 仅 Dedicated 用。默认 <InstallDir>\..\steamcmd。

.PARAMETER DotNetChannel
    指定 .NET 运行时的 channel, 默认 10.0。ModSharp 要求主版本 >= 10。
    (这一行不能以 ".NET" 这样的点开头: comment-based help 会把行首的点当成关键字,
     一个无效关键字会让整个帮助块失效, Get-Help 就什么都读不到了。)

.PARAMETER ModSharpTag
    要安装的 ModSharp Release tag, 默认 latest。

.PARAMETER StripperTag
    要安装的 StripperSharp Release tag, 默认 latest。

.PARAMETER SkipCs2
    跳过 SteamCMD 下载/更新 CS2 (服务端已经就绪时用)。Game 模式下恒为真。

.PARAMETER SkipStripper
    不安装 StripperSharp。

.PARAMETER WithStripper
    明确要求安装 StripperSharp, 不再询问。
    交互模式下默认会问一句"要不要装 StripperSharp", 传了这个开关就跳过那次提问 ——
    给 install.ps1 的「做地图」「开服务器」这两档预设用, 让它们既能免掉多余提问,
    又保留 VC++ 运行库缺失时的交互安装能力 (那一步需要用户点 UAC)。

.PARAMETER SkipDotNet
    跳过 .NET 运行时安装。

.PARAMETER NonInteractive
    全部使用参数与默认值, 不做任何提问。Game 模式下必须同时传 -AcceptGameRisk。

.PARAMETER AcceptGameRisk
    仅 Game 模式: 预先确认已知悉 VAC / 游戏文件修改风险, 等价于交互时输入 y。

.PARAMETER Force
    强制重装 .NET 运行时 (即使已经检测到可用的 10.x)。
    ModSharp / StripperSharp 的包每次运行都会重新下载并同步, 不需要这个开关。

.PARAMETER LoadOnly
    仅供测试: 只定义函数, 不执行主流程 (配合 dot-source 使用)。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-CS2Server.ps1

    进入中文向导, 逐项询问后完成部署。推荐新手使用。

.EXAMPLE
    .\Install-CS2Server.ps1 -Target Dedicated -Mode Install -InstallDir C:\cs2server

    在 C:\cs2server 部署一套全新的专用服务端。

.EXAMPLE
    .\Install-CS2Server.ps1 -Target Game -Mode Install -AcceptGameRisk

    部署到本机已安装的 CS2 游戏 (自动探测路径), 并预先确认 VAC 风险。

.EXAMPLE
    .\Install-CS2Server.ps1 -Mode Update -InstallDir C:\cs2server -Target Dedicated

    更新 CS2 与两个模块, 保留 configs / data / stripper 下的用户数据。

.EXAMPLE
    .\Install-CS2Server.ps1 -Mode Verify -InstallDir C:\cs2server -Target Dedicated

    只检查现有部署是否完整, 不做任何修改。

.LINK
    https://docs.modsharp.net/docs/zh-cn/guides/getting-started.html
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [ValidateSet('Dedicated', 'Game')]
    [string] $Target,

    [string] $InstallDir,

    [ValidateSet('Install', 'Update', 'Verify')]
    [string] $Mode,

    [string] $SteamCmdDir,

    [string] $DotNetChannel = '10.0',

    [string] $ModSharpTag = 'latest',

    [string] $StripperTag = 'latest',

    [switch] $SkipCs2,

    [switch] $SkipStripper,

    [switch] $WithStripper,

    [switch] $SkipDotNet,

    [switch] $NonInteractive,

    [switch] $AcceptGameRisk,

    [switch] $Force,

    [switch] $LoadOnly
)

#region ── 兼容性与全局设置 ──────────────────────────────────────────────

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PS 5.1 下带进度条的 Invoke-WebRequest 会慢几十倍
$ProgressPreference = 'SilentlyContinue'

# PS 5.1 默认不启用 TLS 1.2, GitHub API 与 dot.net 都强制要求
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor `
        [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
} catch {
    # 某些精简环境不支持枚举组合, 忽略
}

# 保证中文提示 (尤其是 VAC 警示) 在旧版控制台里可读
try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch {
    # 重定向输出时可能失败, 不影响功能
}

$script:ScriptVersion = '1.0.0'
$script:Cs2AppId = 730
$script:MinDotNetMajor = 10

$script:RepoModSharp = 'Kxnrl/modsharp-public'
$script:RepoStripper = 'Kxnrl/StripperSharp'

$script:UrlSteamCmd = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
$script:UrlDotNetInstall = 'https://dot.net/v1/dotnet-install.ps1'
$script:UrlVcRedist = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'

# 更新时绝不触碰的目录 (用户数据)。
# 这不是一份"仅供参考"的清单 —— Sync-PackageDirectory 会用它做断言, 任何同步规则
# 一旦指向这里面的目录就直接抛错。之前这个常量是死的, 看着像有保护实际没有,
# 后来人往 -OverwriteDirs 里加一项就可能悄悄覆盖用户数据。
$script:PreservedDirs = @('data', 'logs', 'temp', 'stripper', 'runtime')

# 上游 CI 会给这些模块 touch 一个 .disabled 表示"默认禁用" (见 .github/workflows/release.yml),
# 但打包用的是 `zip -r ... *`, shell glob 不匹配点开头的文件, 所以 Release 包里并没有 .disabled。
# 这里在首次安装该模块时补上, 否则新手一启动就会看到 SQLStorage 拿占位连接串去连数据库的报错。
# 更新时不再补, 尊重用户手动启用的选择。
$script:DefaultDisabledModules = @('AdminCommands.SQLStorage')

#endregion

#region ── 输出辅助 ──────────────────────────────────────────────────────

function Write-Step {
    param([Parameter(Mandatory = $true)][string] $Message)
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Info {
    param([Parameter(Mandatory = $true)][string] $Message)
    Write-Host "    $Message" -ForegroundColor Gray
}

function Write-Good {
    param([Parameter(Mandatory = $true)][string] $Message)
    Write-Host "    [ OK ] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([Parameter(Mandatory = $true)][string] $Message)
    Write-Host "    [WARN] $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([Parameter(Mandatory = $true)][string] $Message)
    Write-Host "    [FAIL] $Message" -ForegroundColor Red
}

function Get-DisplayWidth {
    <#
    .SYNOPSIS
        计算字符串在等宽控制台里的显示宽度 (CJK 全角字符算 2 列)。
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string] $Text)

    $width = 0
    foreach ($char in $Text.ToCharArray()) {
        $code = [int] $char
        if (($code -ge 0x1100 -and $code -le 0x115F) -or
            ($code -ge 0x2E80 -and $code -le 0xA4CF) -or
            ($code -ge 0xAC00 -and $code -le 0xD7A3) -or
            ($code -ge 0xF900 -and $code -le 0xFAFF) -or
            ($code -ge 0xFE30 -and $code -le 0xFE6F) -or
            ($code -ge 0xFF00 -and $code -le 0xFF60) -or
            ($code -ge 0xFFE0 -and $code -le 0xFFE6)) {
            $width += 2
        } else {
            $width += 1
        }
    }

    return $width
}

function Format-PadRight {
    <#
    .SYNOPSIS
        按显示宽度右填充。PowerShell 的 "{0,-30}" 按字符数对齐, 中文表格会歪。
    #>
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Text,
        [Parameter(Mandatory = $true)][int] $Width
    )

    $pad = $Width - (Get-DisplayWidth -Text $Text)
    if ($pad -lt 1) { $pad = 1 }

    return ($Text + (' ' * $pad))
}

function Show-Banner {
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor DarkCyan
    Write-Host '    ModSharp + StripperSharp   Windows 一键部署脚本' -ForegroundColor Cyan
    Write-Host "    v$script:ScriptVersion   |   https://docs.modsharp.net/" -ForegroundColor DarkGray
    Write-Host '  ============================================================' -ForegroundColor DarkCyan
}

#endregion

#region ── 文件与网络工具 ────────────────────────────────────────────────

function Get-ErrorText {
    <#
    .SYNOPSIS
        从 ErrorRecord 里取一段一定非空的错误描述。
    .NOTES
        有些 cmdlet (例如 Expand-Archive 遇到损坏的包) 抛出的异常 Exception.Message 是空的,
        直接插值就会得到"回退解压错误: "这种没有信息量的提示。
    #>
    param([Parameter(Mandatory = $true)] $ErrorRecord)

    $text = ''
    if ($null -ne $ErrorRecord.Exception) { $text = [string] $ErrorRecord.Exception.Message }
    if ([string]::IsNullOrWhiteSpace($text)) { $text = [string] $ErrorRecord }
    if ([string]::IsNullOrWhiteSpace($text)) { $text = '(没有更多错误信息)' }

    return $text.Trim()
}

function Read-TextFile {
    param([Parameter(Mandatory = $true)][string] $Path)
    return [IO.File]::ReadAllText($Path)
}

function Assert-Utf8Decodable {
    <#
    .SYNOPSIS
        确认文件能按 UTF-8 无损解码; 不能就抛错, 绝不静默损坏。
    .NOTES
        Read-TextFile 用的 [IO.File]::ReadAllText 是"替换式"解码: 非 UTF-8 字节会被
        悄悄换成 U+FFFD, 再用 Write-TextFile 写回去就把原始字节永久销毁了。
        gameinfo.gi 常被用户用记事本加过 GBK 中文注释, 那样一跑就会把注释烧成乱码,
        而且全程不报错、自检全绿。这里在改写前先严格校验一次。
    #>
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $What
    )

    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) { return }

    try {
        # throwOnInvalidBytes = $true
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        [void] $strict.GetString($bytes)
    } catch {
        throw @"
$What 不是 UTF-8 编码, 脚本不能安全地改写它 (强行改写会把里面的非 UTF-8 内容烧成乱码)。
  文件: $Path
常见原因: 之前用旧版记事本给它加过中文注释, 保存成了 GBK/ANSI。
处理办法: 用 VSCode / Notepad++ 打开, 另存为 UTF-8 (无 BOM), 然后重新运行本脚本;
或者把这个文件恢复成游戏自带的原版 (Steam 里"验证游戏文件完整性")。
"@
    }
}

function Write-TextFile {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string] $Text
    )
    # 显式使用无 BOM 的 UTF-8: gameinfo.gi 带 BOM 会被引擎拒绝解析
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($Path, $Text, $encoding)
}

function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    return $Path
}

function Resolve-AbsolutePath {
    <#
    .SYNOPSIS
        把用户输入的路径规范成绝对路径 (去掉引号、去掉尾部反斜杠)。
    .NOTES
        必须在入口就转成绝对路径, 否则下游会以两种方式坏掉:
          - Split-Path -Parent 'cs2server' 返回空串, Join-Path 随即抛"参数为空字符串";
            Split-Path -Parent 'C:' 直接抛"path 的值无效"。
          - SteamCMD 的 +force_install_dir 按 steamcmd.exe 自己的工作目录解析相对路径,
            会把几十 GB 装到别处, 而脚本按自己的 cwd 去校验, 找不到就白跑三次重试。
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string] $Path)

    $trimmed = $Path.Trim().Trim('"').Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw '路径不能为空。'
    }

    # 相对路径必须按 PowerShell 的当前位置解析, 不能直接丢给 [IO.Path]::GetFullPath ——
    # 后者用 .NET 进程的 CurrentDirectory, 它跟 PowerShell 的 Get-Location 经常不同步
    # (Set-Location 不更新它), 那样 -InstallDir cs2server 会落到用户完全没预期的目录。
    $base = ''
    if ($null -ne $PWD -and $null -ne $PWD.Provider -and $PWD.Provider.Name -eq 'FileSystem') {
        $base = $PWD.ProviderPath
    }

    try {
        if ([string]::IsNullOrWhiteSpace($base)) {
            $full = [IO.Path]::GetFullPath($trimmed)
        } else {
            # Combine 在第二个参数已经是绝对路径时会直接返回它, 绝对/相对走同一条路
            $full = [IO.Path]::GetFullPath([IO.Path]::Combine($base, $trimmed))
        }
    } catch {
        throw "路径无效: $trimmed`n  $($_.Exception.Message)"
    }

    # 盘根既不适合装服务端, 也会让 Split-Path -Parent 抛错, 直接挡掉并给出可用的建议
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.TrimEnd('\') -eq $root.TrimEnd('\')) {
        throw "不能直接使用盘根目录 ($full)。请指定一个子目录, 例如 $($root.TrimEnd('\'))\cs2server。"
    }

    # 驱动器必须真的存在。PowerShell 的 Join-Path 碰到不存在的盘符会抛一句纯英文的
    # "Cannot find drive. A drive with the name 'Z' does not exist." (Test-Path 反而不会),
    # 而脚本里几十处 Join-Path 都会中招 —— 用户打错一个盘符就只能看到这句英文。
    if ($root -match '^([A-Za-z]):') {
        $driveLetter = $Matches[1]
        if (-not (Test-Path -LiteralPath "${driveLetter}:\")) {
            $available = (@([IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady } |
                ForEach-Object { $_.Name.TrimEnd('\') })) -join ' '
            throw @"
驱动器 ${driveLetter}: 不存在或当前不可用。
  你输入的路径: $full
当前可用的驱动器: $available
如果这是网络驱动器, 请先连接它; 如果只是打错了盘符, 换一个再试。
"@
        }
    }

    return $full.TrimEnd('\')
}

function Get-FreeSpaceGB {
    param([Parameter(Mandatory = $true)][string] $Path)
    try {
        $root = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path))
        if ([string]::IsNullOrWhiteSpace($root)) { return -1 }
        $drive = New-Object System.IO.DriveInfo($root)
        return [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
    } catch {
        return -1
    }
}

function Invoke-Download {
    param(
        [Parameter(Mandatory = $true)][string] $Uri,
        [Parameter(Mandatory = $true)][string] $OutFile,
        [string] $Description = '文件'
    )

    New-DirectoryIfMissing -Path (Split-Path -Parent $OutFile) | Out-Null

    Write-Info "下载 $Description ..."
    Write-Info "  $Uri"

    try {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
    } catch {
        throw "下载 $Description 失败: $($_.Exception.Message)`n    地址: $Uri`n    请检查网络连接 (国内网络访问 GitHub 可能需要代理)。"
    }

    if (-not (Test-Path -LiteralPath $OutFile)) {
        throw "下载 $Description 后找不到文件: $OutFile"
    }

    $sizeMB = [math]::Round((Get-Item -LiteralPath $OutFile).Length / 1MB, 2)
    Write-Good "$Description 下载完成 ($sizeMB MB)"
}

function Expand-ZipArchiveTo {
    param(
        [Parameter(Mandatory = $true)][string] $ZipPath,
        [Parameter(Mandatory = $true)][string] $Destination
    )

    New-DirectoryIfMissing -Path $Destination | Out-Null

    # ExtractToDirectory 比 PS 5.1 的 Expand-Archive 快得多, 但目标已有同名文件会抛异常,
    # 那种情况靠 Expand-Archive -Force 回退能解决。
    # 注意不要把 Add-Type / Resolve-Path 也包进同一个 try: 否则"包损坏""磁盘写满"
    # "无写权限"这些真实错误都会被一律报成"快速解压不可用", 原始诊断信息全部丢失。
    $fastAvailable = $true
    try {
        # Out-Null: Add-Type 会把已加载程序集的 GAC 表格吐进输出流, 污染控制台
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop | Out-Null
    } catch {
        $fastAvailable = $false
        Write-Info '当前环境没有 System.IO.Compression.FileSystem, 使用 Expand-Archive。'
    }

    if (-not $fastAvailable) {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force
        return
    }

    $zipFull = (Resolve-Path -LiteralPath $ZipPath).Path
    $dstFull = (Resolve-Path -LiteralPath $Destination).Path

    try {
        [IO.Compression.ZipFile]::ExtractToDirectory($zipFull, $dstFull)
        return
    } catch {
        $fastError = Get-ErrorText -ErrorRecord $_
    }

    Write-Info '快速解压失败, 尝试用 Expand-Archive 回退 ...'
    Write-Info "  原始错误: $fastError"

    try {
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $Destination -Force
    } catch {
        throw @"
解压失败: $ZipPath
  快速解压错误: $fastError
  回退解压错误: $(Get-ErrorText -ErrorRecord $_)
如果提示"压缩包损坏"或"文件结尾无效", 通常是下载不完整 (国内网络访问 GitHub 常见),
重新运行一次本脚本即可; 如果提示磁盘空间或权限问题, 请先处理对应问题。
"@
    }
}

function Copy-DirectoryMerged {
    <#
    .SYNOPSIS
        把 Source 的内容合并复制到 Destination: 同名文件覆盖, 目标独有的文件保留。
    #>
    param(
        [Parameter(Mandatory = $true)][string] $Source,
        [Parameter(Mandatory = $true)][string] $Destination,
        [string[]] $ExcludeNames = @()
    )

    if (-not (Test-Path -LiteralPath $Source)) { return 0 }

    New-DirectoryIfMissing -Path $Destination | Out-Null

    $count = 0
    foreach ($item in (Get-ChildItem -LiteralPath $Source -Force)) {
        if ($ExcludeNames -contains $item.Name) { continue }

        # 不叫 $target: PowerShell 变量名不区分大小写, 会遮蔽脚本参数 $Target
        $targetPath = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            $count += Copy-DirectoryMerged -Source $item.FullName -Destination $targetPath -ExcludeNames $ExcludeNames
        } else {
            try {
                Copy-Item -LiteralPath $item.FullName -Destination $targetPath -Force
            } catch [System.IO.IOException] {
                # 最常见的原因是服务器/游戏还开着, 把 dll 锁住了。原始异常是纯英文的
                # "The process cannot access the file ... being used by another process",
                # 对目标用户毫无意义, 这里翻译成能照做的提示。
                throw @"
文件被占用, 无法更新: $($item.Name)
  目标: $targetPath
几乎可以肯定是 CS2 还在运行 —— 请先完全退出游戏、并停掉正在跑的 CS2 服务器, 然后重新运行一次。
(原始错误: $($_.Exception.Message))
"@
            }
            $count++
        }
    }

    return $count
}

function Get-ObjectProperty {
    <#
    .SYNOPSIS
        StrictMode 下安全地读取对象属性, 不存在时返回默认值。
    #>
    param(
        $InputObject,
        [Parameter(Mandatory = $true)][string] $Name,
        $Default = $null
    )

    if ($null -eq $InputObject) { return $Default }

    $prop = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    if ($null -eq $prop.Value) { return $Default }

    return $prop.Value
}

#endregion

#region ── 交互向导 ──────────────────────────────────────────────────────

function Assert-InteractiveInput {
    <#
    .SYNOPSIS
        确认 stdin 真的能读到人的输入; 读不到就中止, 不要把"没人回答"当成"同意默认值"。
    .NOTES
        Read-Host 在 stdin 到达 EOF (被重定向、从计划任务启动、被别的脚本包起来调用)
        时立刻返回空串, 而本脚本所有提问都把空串当作"采用默认值"。后果非常实际:
        向导会静默选中 Dedicated + C:\cs2server 然后直接开始 35 GB 下载, 一句确认都没有。
        这不是 -NonInteractive, 用户根本没表达过任何意图, 所以必须挡住。
    #>
    param([Parameter(Mandatory = $true)][string] $Question)

    if (-not [Console]::IsInputRedirected) { return }

    throw @"
需要你回答一个问题, 但当前没有可交互的输入 (标准输入被重定向或为空):
  $Question
如果你是在计划任务 / CI / 管道里运行, 请改用参数明确指定, 例如:
  -Target Dedicated -Mode Install -InstallDir C:\cs2server -NonInteractive
在 PowerShell 窗口里正常运行则不会有这个问题。
"@
}

function Read-Menu {
    param(
        [Parameter(Mandatory = $true)][string] $Title,
        [Parameter(Mandatory = $true)][string[]] $Items,
        [int] $DefaultIndex = 0
    )

    Assert-InteractiveInput -Question $Title

    Write-Host ''
    Write-Host "  $Title" -ForegroundColor White
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $mark = '  '
        if ($i -eq $DefaultIndex) { $mark = ' *' }
        # 用拼接而不是 -f: 菜单项可能是用户磁盘上的真实路径, 里面合法的 {} 会让
        # -f 当成格式占位符并抛"输入字符串的格式不正确"。
        Write-Host ("  $mark [" + ($i + 1) + '] ' + $Items[$i])
    }

    while ($true) {
        $raw = Read-Host "     请输入序号 (回车 = $($DefaultIndex + 1))"
        if ([string]::IsNullOrWhiteSpace($raw)) { return $DefaultIndex }

        $picked = 0
        if ([int]::TryParse($raw.Trim(), [ref] $picked)) {
            if ($picked -ge 1 -and $picked -le $Items.Count) { return ($picked - 1) }
        }
        Write-Warn '输入无效, 请重新输入。'
    }
}

function Read-YesNo {
    param(
        [Parameter(Mandatory = $true)][string] $Question,
        [bool] $DefaultYes = $true
    )

    Assert-InteractiveInput -Question $Question

    $hint = 'Y/n'
    if (-not $DefaultYes) { $hint = 'y/N' }

    while ($true) {
        $raw = Read-Host "     $Question [$hint]"
        if ([string]::IsNullOrWhiteSpace($raw)) { return $DefaultYes }

        switch ($raw.Trim().ToLowerInvariant()) {
            'y' { return $true }
            'yes' { return $true }
            'n' { return $false }
            'no' { return $false }
            default { Write-Warn '请输入 y 或 n。' }
        }
    }
}

#endregion

#region ── 环境检查 ──────────────────────────────────────────────────────

function Test-Cs2Root {
    <#
    .SYNOPSIS
        判断一个目录是否是有效的 CS2 根目录 (专服和游戏本体结构一致)。
    #>
    param([string] $Root)

    if ([string]::IsNullOrWhiteSpace($Root)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'game\bin\win64\cs2.exe'))) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'game\csgo\gameinfo.gi'))) { return $false }

    return $true
}

function Assert-Environment {
    param(
        [Parameter(Mandatory = $true)][string] $TargetKind,
        [Parameter(Mandatory = $true)][string] $Path,
        [bool] $Interactive = $true
    )

    Write-Step '检查运行环境'

    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'CS2 服务端只支持 64 位 Windows, 当前系统是 32 位。'
    }
    Write-Good "操作系统: 64 位 Windows ($([Environment]::OSVersion.Version))"

    $psv = $PSVersionTable.PSVersion
    if ($psv.Major -lt 5 -or ($psv.Major -eq 5 -and $psv.Minor -lt 1)) {
        throw "需要 PowerShell 5.1 或更高版本, 当前是 $psv。Windows 10 / Server 2016 及以上自带 5.1。"
    }
    Write-Good "PowerShell: $psv"

    # 专服要下 CS2 本体 (约 35 GB), 游戏本体只需放 sharp 与 .NET 运行时
    $requiredGB = 60
    if ($TargetKind -eq 'Game') { $requiredGB = 2 }

    $freeGB = Get-FreeSpaceGB -Path $Path
    if ($freeGB -lt 0) {
        Write-Warn "无法确定 $Path 所在磁盘的剩余空间, 跳过空间检查。"
    } elseif ($freeGB -lt $requiredGB) {
        Write-Warn "目标磁盘剩余 $freeGB GB, 建议至少 $requiredGB GB。"
        if (-not $Interactive) {
            throw "磁盘空间不足 (剩余 $freeGB GB, 需要 $requiredGB GB)。"
        }
        if (-not (Read-YesNo -Question '空间可能不够, 仍要继续?' -DefaultYes $false)) {
            throw '已取消: 磁盘空间不足。'
        }
    } else {
        Write-Good "磁盘剩余空间: $freeGB GB"
    }

    if ($Path -match '\s') {
        Write-Warn "路径包含空格: $Path"
        Write-Info '  SteamCMD 与部分工具对含空格的路径支持不佳, 建议换成不含空格的路径。'
    }

    # 超长路径在 PS 5.1 下不是报错而是"静默什么都不做": Test-Path 恒 False、
    # New-Item -Force 既不建目录也不抛异常, 最后表现为自检永远 FAIL 且提示让你重跑,
    # 重跑一百次结果一样。宁可现在就说清楚。
    $deepest = (Join-Path $Path 'game\sharp\modules\AdminCommands.SQLStorage\zh-Hans')
    if ($deepest.Length -ge 240) {
        throw @"
安装路径太深了, 装进去会有文件建不出来 (Windows 传统路径上限 260 字符)。
  当前路径: $Path  ($($Path.Length) 字符)
  实际要用到的最深路径已达 $($deepest.Length) 字符
请换一个更短的目录, 例如 C:\cs2server 或 D:\cs2server。
"@
    }

    # 正在运行的 CS2 会锁住 sharp\bin 下的 dll, 更新时会中途失败并留下新旧混装的目录
    try {
        $running = @(Get-Process -Name 'cs2' -ErrorAction SilentlyContinue)
        if ($running.Count -gt 0) {
            Write-Warn "检测到 CS2 正在运行 (PID: $(($running | ForEach-Object { $_.Id }) -join ', '))。"
            Write-Info '  更新会因为文件被占用而中途失败, 请先完全退出游戏 / 停掉服务器。'
            if ($Interactive) {
                if (-not (Read-YesNo -Question '已经关掉了吗? 继续?' -DefaultYes $false)) {
                    throw '已取消: 请先退出 CS2 再运行。'
                }
            }
        }
    } catch [System.Management.Automation.RuntimeException] {
        throw
    } catch {
        # Get-Process 本身出问题不影响主流程
    }
}

function Confirm-GameTargetRisk {
    <#
    .SYNOPSIS
        部署到游戏本体前的 VAC / 游戏文件风险确认。必须在任何写操作之前调用。
    .OUTPUTS
        $true 表示用户已确认可以继续; $false 表示用户取消。
    #>
    param(
        [Parameter(Mandatory = $true)][string] $Cs2Root,
        [bool] $Interactive = $true,
        [bool] $PreAccepted = $false,
        [bool] $AlreadyAcceptedBefore = $false
    )

    Write-Host ''
    Write-Host '  ------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host '   接下来会改动你正在玩的这份 CS2, 先说清楚会改什么' -ForegroundColor Yellow
    Write-Host '  ------------------------------------------------------------' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  目标游戏目录:' -ForegroundColor White
    Write-Host "    $Cs2Root" -ForegroundColor Gray
    Write-Host ''
    Write-Host '  1) 会做这两件事:' -ForegroundColor White
    Write-Host '     - 在 game\csgo\gameinfo.gi 里加一行配置 (会先备份成 gameinfo.gi.bak)'
    Write-Host '     - 在 game\ 下新增一个 sharp\ 文件夹, 放 ModSharp 本体'
    Write-Host ''
    Write-Host '  2) 关于 VAC —— 做地图和本地测试是不参与 VAC 的:' -ForegroundColor White
    Write-Host '     - 用 Workshop Tools 做地图 (-tools) 时, 游戏不在 VAC 会话里'
    Write-Host '     - 自己在本地开图测试同理, 那不是"受 VAC 保护的服务器"'
    Write-Host '     - 想更保险可以在 Steam 的启动选项里加 -insecure, 明确关掉 VAC'
    Write-Host '     所以按正常流程做地图、测地图, 不用担心。' -ForegroundColor Green
    Write-Host ''
    Write-Host '  3) 唯一要注意的:' -ForegroundColor White
    Write-Host '     别拿这份改过的游戏去打官方竞技匹配, 或连别人的正式服务器。'
    Write-Host '     倒不是说一定会出事, 而是那种场合你本来也用不上 ModSharp。'
    Write-Host ''
    Write-Host '  4) 完全不想动自己的游戏? 改用独立服务端:' -ForegroundColor White
    Write-Host '     重跑安装命令并选 [2] 开服务器 —— 它另外下一套, 跟你的游戏没关系' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  5) 想还原:' -ForegroundColor White
    Write-Host '     把 gameinfo.gi.bak 覆盖回 gameinfo.gi, 或者在 Steam 里对 CS2'
    Write-Host '     点「验证游戏文件完整性」, 都能恢复原样。'
    Write-Host ''
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkGray

    if ($PreAccepted) {
        Write-Warn '已通过 -AcceptGameRisk 预先确认, 继续执行。'
        return $true
    }

    if ($AlreadyAcceptedBefore) {
        Write-Warn '上次已经确认过了, 继续执行。'
        return $true
    }

    if (-not $Interactive) {
        throw '装到自己的游戏时, -NonInteractive 下必须显式传 -AcceptGameRisk, 表示你已经看过上面这些说明。'
    }

    # EOF 时不能沉默地当成"取消"就 exit 0 —— 自动化调用方会把 0 当成部署成功。
    # 这里明确要求传 -AcceptGameRisk 表态。
    Assert-InteractiveInput -Question '确认改动你的游戏? (需要 -AcceptGameRisk 或人工确认)'

    Write-Host ''
    $answer = Read-Host '  看明白了, 继续? 输入 y 继续, 其他任意键取消'

    if ($null -eq $answer) { return $false }

    $normalized = $answer.Trim().ToLowerInvariant()
    if ($normalized -eq 'y' -or $normalized -eq 'yes') {
        Write-Good '好, 开始部署。'
        return $true
    }

    return $false
}

function Test-VcRedist {
    $key = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\X64'

    try {
        $props = Get-ItemProperty -Path $key -ErrorAction Stop
        $installed = Get-ObjectProperty -InputObject $props -Name 'Installed' -Default 0
        $version = Get-ObjectProperty -InputObject $props -Name 'Version' -Default ''
        if ([int] $installed -eq 1) {
            return @{ Installed = $true; Version = [string] $version }
        }
    } catch {
        # 注册表项不存在 = 未安装
    }

    return @{ Installed = $false; Version = '' }
}

function Install-VcRedist {
    param(
        [Parameter(Mandatory = $true)][string] $WorkDir,
        [bool] $Interactive = $true
    )

    Write-Step '检查系统运行库'

    $state = Test-VcRedist
    if ($state.Installed) {
        Write-Good "系统运行库已就绪 $($state.Version)"
        return
    }

    Write-Warn '缺少一个微软的系统运行库 (Visual C++ x64), ModSharp 运行需要它。'

    # 安装器必须用 -Verb RunAs 提权, 那一定会弹 UAC 同意框。无人值守时没人点,
    # Start-Process -Wait 会永久阻塞 —— 所以非交互模式只能警告, 不能替用户去装。
    if (-not $Interactive) {
        Write-Warn '-NonInteractive 模式不会自动安装它: 安装器需要 UAC 授权, 无人值守会一直卡住。'
        Write-Info "  请手动安装后重新运行: $script:UrlVcRedist"
        Write-Info '  (后面的自检会把这一项标成 FAIL, 提醒你别忘了。)'
        return
    }

    if (-not (Read-YesNo -Question '现在自动下载安装? (会弹出管理员授权窗口)' -DefaultYes $true)) {
        Write-Warn "已跳过。请手动安装后再启动服务器: $script:UrlVcRedist"
        return
    }

    $exe = Join-Path $WorkDir 'vc_redist.x64.exe'

    try {
        Invoke-Download -Uri $script:UrlVcRedist -OutFile $exe -Description 'VC++ 运行库安装包'
        Write-Info '正在安装 (需要管理员权限, 请在弹窗中允许) ...'
        $proc = Start-Process -FilePath $exe -ArgumentList '/install', '/quiet', '/norestart' -Verb RunAs -Wait -PassThru

        $newState = Test-VcRedist
        if ($newState.Installed) {
            Write-Good "VC++ 运行库安装完成 $($newState.Version)"
        } else {
            Write-Warn "安装程序退出码 $($proc.ExitCode), 但未检测到安装结果。请手动安装: $script:UrlVcRedist"
        }
    } catch {
        Write-Warn "自动安装失败: $($_.Exception.Message)"
        Write-Info "  请手动下载安装: $script:UrlVcRedist"
    }
}

#endregion

#region ── Steam 路径探测 ────────────────────────────────────────────────

function Get-SteamRootPath {
    <#
    .SYNOPSIS
        从注册表读取所有可能的 Steam 安装根目录。
    .NOTES
        返回 PowerShell 数组。去重用 -notcontains (对字符串不区分大小写),
        因为注册表里同一个目录的大小写常常不一致 (c:\app\steam vs C:\App\Steam),
        用 List.Contains 会把它们当成两个库, 导致重复扫描和重复选项。
    #>
    $roots = @()

    $candidates = @(
        @{ Path = 'HKCU:\Software\Valve\Steam'; Name = 'SteamPath' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Name = 'InstallPath' },
        @{ Path = 'HKLM:\SOFTWARE\Valve\Steam'; Name = 'InstallPath' }
    )

    foreach ($candidate in $candidates) {
        try {
            $props = Get-ItemProperty -Path $candidate.Path -ErrorAction Stop
            $value = Get-ObjectProperty -InputObject $props -Name $candidate.Name -Default ''
            if ([string]::IsNullOrWhiteSpace($value)) { continue }

            $path = ([string] $value).Replace('/', '\').TrimEnd('\')
            if (-not (Test-Path -LiteralPath $path)) { continue }

            try { $path = [IO.Path]::GetFullPath($path).TrimEnd('\') } catch { }

            if ($roots -notcontains $path) { $roots += $path }
        } catch {
            # 该注册表项不存在, 继续下一个
        }
    }

    return $roots
}

function Get-SteamLibraryPath {
    <#
    .SYNOPSIS
        解析 libraryfolders.vdf, 返回所有 Steam 库目录 (含 Steam 自身目录)。
    #>
    param([Parameter(Mandatory = $true)][string] $SteamRoot)

    $libs = @($SteamRoot.TrimEnd('\'))

    $vdf = Join-Path $SteamRoot 'steamapps\libraryfolders.vdf'
    if (-not (Test-Path -LiteralPath $vdf)) { return $libs }

    try {
        $text = Read-TextFile -Path $vdf
    } catch {
        return $libs
    }

    foreach ($match in [regex]::Matches($text, '"path"\s*"([^"]+)"')) {
        $path = $match.Groups[1].Value.Replace('\\', '\').Replace('/', '\').TrimEnd('\')
        if (-not (Test-Path -LiteralPath $path)) { continue }

        try { $path = [IO.Path]::GetFullPath($path).TrimEnd('\') } catch { }

        if ($libs -notcontains $path) { $libs += $path }
    }

    return $libs
}

function Find-Cs2GamePath {
    <#
    .SYNOPSIS
        探测本机已安装的 CS2 游戏目录。
    .OUTPUTS
        命中的根目录数组, 可能为空。调用方必须用 @() 包裹返回值:
        PowerShell 会把空集合展开成 $null, StrictMode 下 $null.Count 会抛异常。
    #>
    $found = @()

    foreach ($steamRoot in @(Get-SteamRootPath)) {
        foreach ($lib in @(Get-SteamLibraryPath -SteamRoot $steamRoot)) {
            $candidate = Join-Path $lib 'steamapps\common\Counter-Strike Global Offensive'
            if (-not (Test-Cs2Root -Root $candidate)) { continue }
            if ($found -notcontains $candidate) { $found += $candidate }
        }
    }

    return $found
}

#endregion

#region ── SteamCMD 与 CS2 本体 ──────────────────────────────────────────

function Install-SteamCmd {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $WorkDir
    )

    Write-Step '准备 SteamCMD'

    $exe = Join-Path $Path 'steamcmd.exe'
    if (Test-Path -LiteralPath $exe) {
        Write-Good "SteamCMD 已就绪: $exe"
        return $exe
    }

    $zip = Join-Path $WorkDir 'steamcmd.zip'
    Invoke-Download -Uri $script:UrlSteamCmd -OutFile $zip -Description 'SteamCMD'

    # 先解压到工作区里的空目录, 再合并进目标 —— 绝对不能对 $Path 做 Remove-Item -Recurse:
    # 这个路径可能来自用户手打的 -SteamCmdDir, 打错一个字就会把整棵目录树删掉。
    # 走暂存目录同时也绕开了 ExtractToDirectory"目标非空即抛异常"的限制。
    $staging = Join-Path $WorkDir 'steamcmd-extract'
    Expand-ZipArchiveTo -ZipPath $zip -Destination $staging

    New-DirectoryIfMissing -Path $Path | Out-Null
    Copy-DirectoryMerged -Source $staging -Destination $Path | Out-Null

    if (-not (Test-Path -LiteralPath $exe)) {
        throw "SteamCMD 解压后找不到 steamcmd.exe: $exe"
    }

    Write-Good "SteamCMD 已安装到 $Path"
    return $exe
}

function Update-Cs2Server {
    param(
        [Parameter(Mandatory = $true)][string] $SteamCmdExe,
        [Parameter(Mandatory = $true)][string] $Cs2Root
    )

    Write-Step "下载 / 更新 CS2 专用服务端 (app $script:Cs2AppId)"
    Write-Info '首次下载约 35 GB, 请耐心等待。SteamCMD 的输出会直接显示在下面。'

    New-DirectoryIfMissing -Path $Cs2Root | Out-Null

    $cs2Exe = Join-Path $Cs2Root 'game\bin\win64\cs2.exe'

    # force_install_dir 必须在 login 之前
    $arguments = @(
        '+force_install_dir', ('"' + $Cs2Root + '"'),
        '+login', 'anonymous',
        '+app_update', "$script:Cs2AppId", 'validate',
        '+quit'
    )

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Write-Info "第 $attempt 次运行 SteamCMD ..."

        $exitCode = -1
        try {
            $proc = Start-Process -FilePath $SteamCmdExe -ArgumentList $arguments -NoNewWindow -Wait -PassThru
            $exitCode = $proc.ExitCode
        } catch {
            Write-Warn "SteamCMD 启动失败: $($_.Exception.Message)"
        }

        if (Test-Path -LiteralPath $cs2Exe) {
            Write-Good "CS2 服务端已就绪 (SteamCMD 退出码 $exitCode)"
            return
        }

        # SteamCMD 首次运行会自更新并以非 0 退出, 属正常现象
        Write-Warn "本次未完成 (退出码 $exitCode), 准备重试 ..."
    }

    throw @"
CS2 服务端下载失败: 找不到 $cs2Exe
可能原因:
  - 网络中断或 Steam CDN 不可达
  - 磁盘空间不足
  - 安装路径含空格或中文
可以手动执行下面的命令排查:
  "$SteamCmdExe" +force_install_dir "$Cs2Root" +login anonymous +app_update $script:Cs2AppId validate +quit
"@
}

#endregion

#region ── .NET 运行时 ───────────────────────────────────────────────────

function Get-HostFxrVersion {
    <#
    .SYNOPSIS
        列出某个 host\fxr 目录下所有可用的 hostfxr 版本。
    #>
    param([Parameter(Mandatory = $true)][string] $FxrRoot)

    $versions = New-Object System.Collections.Generic.List[Version]

    if (-not (Test-Path -LiteralPath $FxrRoot)) { return $versions }

    $dirs = @()
    try {
        $dirs = Get-ChildItem -LiteralPath $FxrRoot -Directory -ErrorAction Stop
    } catch {
        return $versions
    }

    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir.FullName 'hostfxr.dll'))) { continue }

        # 目录名可能带预览后缀, 例如 10.0.0-preview.7
        $clean = ($dir.Name -replace '-.*$', '')
        $parsed = New-Object Version
        if ([Version]::TryParse($clean, [ref] $parsed)) {
            $versions.Add($parsed)
        }
    }

    return $versions
}

function Test-DotNetRuntime {
    <#
    .SYNOPSIS
        按 ModSharp 的搜索顺序找可用的 .NET 运行时 (见 Engine/src/CoreCLR/coreclr.cpp)。
    #>
    param([Parameter(Mandatory = $true)][string] $SharpDir)

    $searchPaths = @(
        (Join-Path $SharpDir 'runtime\host\fxr'),
        'C:\Program Files\dotnet\host\fxr'
    )

    foreach ($path in $searchPaths) {
        foreach ($version in (Get-HostFxrVersion -FxrRoot $path)) {
            if ($version.Major -ge $script:MinDotNetMajor) {
                return @{ Found = $true; Version = $version; Path = $path }
            }
        }
    }

    return @{ Found = $false; Version = $null; Path = '' }
}

function Install-DotNetRuntime {
    param(
        [Parameter(Mandatory = $true)][string] $SharpDir,
        [Parameter(Mandatory = $true)][string] $WorkDir,
        [Parameter(Mandatory = $true)][string] $Channel,
        [bool] $ForceReinstall = $false
    )

    Write-Step "检查 .NET 运行环境 ($Channel)"

    $existing = Test-DotNetRuntime -SharpDir $SharpDir
    if ($existing.Found -and -not $ForceReinstall) {
        Write-Good ".NET 运行环境已就绪: $($existing.Version)"
        return
    }

    $runtimeDir = Join-Path $SharpDir 'runtime'
    Write-Info "装到服务器自己的文件夹里, 不动你的系统设置"

    $installer = Join-Path $WorkDir 'dotnet-install.ps1'
    Invoke-Download -Uri $script:UrlDotNetInstall -OutFile $installer -Description '.NET 安装脚本'

    New-DirectoryIfMissing -Path $runtimeDir | Out-Null

    # dotnet-install.ps1 内部会调用 exit, 必须放在子进程里跑, 否则会终止当前会话
    $hostExe = 'powershell.exe'
    try {
        $current = (Get-Process -Id $PID).Path
        if (-not [string]::IsNullOrWhiteSpace($current)) { $hostExe = $current }
    } catch {
        # 拿不到宿主路径就用 powershell.exe
    }

    Write-Info '正在下载并解压 .NET 运行时 ...'
    & $hostExe -NoProfile -ExecutionPolicy Bypass -File $installer `
        -Channel $Channel -Runtime dotnet -InstallDir $runtimeDir -NoPath

    $result = Test-DotNetRuntime -SharpDir $SharpDir
    if (-not $result.Found) {
        # 注意别把 $installer 的路径写进提示: 它在临时工作目录里, 异常向上传播时
        # Invoke-Main 的 finally 已经把整个工作目录删掉了, 用户照着敲只会得到"找不到路径"。
        throw @"
.NET 运行时安装后仍未通过检查。
ModSharp 只会在这两个位置寻找 hostfxr (且主版本必须 >= $script:MinDotNetMajor):
  $runtimeDir\host\fxr
  C:\Program Files\dotnet\host\fxr
可以这样手动装 (在 PowerShell 里逐行执行):
  Invoke-WebRequest https://dot.net/v1/dotnet-install.ps1 -OutFile `$env:TEMP\dotnet-install.ps1 -UseBasicParsing
  & `$env:TEMP\dotnet-install.ps1 -Channel $Channel -Runtime dotnet -InstallDir "$runtimeDir" -NoPath
装完重新运行本脚本即可。
"@
    }

    Write-Good ".NET 运行环境安装完成: $($result.Version)"
}

#endregion

#region ── gameinfo.gi ───────────────────────────────────────────────────

function Update-GameInfo {
    <#
    .SYNOPSIS
        在 gameinfo.gi 的 SearchPaths 中插入 "Game sharp"。幂等: 已存在则不改动。
    .OUTPUTS
        $true 表示本次做了修改; $false 表示已配置无需修改。
    #>
    param([Parameter(Mandatory = $true)][string] $Cs2Root)

    Write-Step '配置 gameinfo.gi'

    $giPath = Join-Path $Cs2Root 'game\csgo\gameinfo.gi'
    if (-not (Test-Path -LiteralPath $giPath)) {
        throw "找不到 gameinfo.gi: $giPath`n请确认 CS2 已正确安装。"
    }

    # 改写前先确认能无损解码, 否则宁可停下来也不要把用户的 GBK 注释烧成乱码
    Assert-Utf8Decodable -Path $giPath -What 'gameinfo.gi'

    $text = Read-TextFile -Path $giPath

    # 只认 SearchPaths 块内的那一行。判据放宽到全文件会出两种错:
    #   1) 用户此前手工改错位置 (把 Game sharp 写进了 ToolsEnvironment 之类的块),
    #      脚本会认为"已配置"而跳过插入, 自检也跟着打绿灯 —— 结果就是十项全绿
    #      但 ModSharp 根本不会被加载, 正是最难排查的那种静默失败。
    #   2) 其它块里恰好有同名行时同样误判。
    $block = Get-SearchPathsBlock -Text $text
    if ($null -eq $block) {
        throw @"
无法在 gameinfo.gi 里定位 FileSystem -> SearchPaths 块, 为避免写坏文件, 脚本没有做任何修改。
请手动在 SearchPaths 中加入一行:
    Game    sharp
文件位置: $giPath
参考文档: https://docs.modsharp.net/docs/zh-cn/guides/getting-started.html
"@
    }

    if ($block.Content -match '(?m)^[ \t]*Game[ \t]+sharp[ \t]*(//[^\r\n]*)?\r?$') {
        Write-Good '游戏配置之前已经改好了, 这次不用动'
        return $false
    }

    # 提前提醒: 块外有 Game sharp 说明之前改错了地方, 那一行不起作用
    if ($text -match '(?m)^[ \t]*Game[ \t]+sharp[ \t]*(//[^\r\n]*)?\r?$') {
        Write-Warn 'gameinfo.gi 里有 "Game sharp", 但不在 SearchPaths 块内 —— 那样是不生效的。'
        Write-Info '  现在会在正确的位置补一行; 之前那一行建议你手动删掉。'
    }

    $newline = "`n"
    if ($text.Contains("`r`n")) { $newline = "`r`n" }

    # 锚点只在 SearchPaths 块内找, 索引再换算回整个文件
    $inner = $block.Content
    $anchorLowViolence = [regex]::Match($inner, '(?m)^([ \t]*)Game_LowViolence[ \t]+csgo_lv[^\r\n]*')
    $anchorCsgo = [regex]::Match($inner, '(?m)^([ \t]*)Game[ \t]+csgo[ \t]*\r?$')

    if (-not $anchorLowViolence.Success -and -not $anchorCsgo.Success) {
        throw @"
在 SearchPaths 块里找不到插入位置 (既没有 "Game_LowViolence csgo_lv" 也没有 "Game csgo")。
为避免写坏文件, 脚本没有做任何修改。请手动在 FileSystem -> SearchPaths 中加入一行:
    Game    sharp
文件位置: $giPath
参考文档: https://docs.modsharp.net/docs/zh-cn/guides/getting-started.html
"@
    }

    $backup = "$giPath.bak"
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $giPath -Destination $backup -Force
        Write-Info "已备份原文件 -> $backup"
    }

    if ($anchorLowViolence.Success) {
        $indent = $anchorLowViolence.Groups[1].Value
        $insertAt = $block.Start + $anchorLowViolence.Index + $anchorLowViolence.Length
        $addition = $newline + $newline + $indent + "Game`tsharp"
    } else {
        $indent = $anchorCsgo.Groups[1].Value
        $insertAt = $block.Start + $anchorCsgo.Index
        $addition = $indent + "Game`tsharp" + $newline + $newline
    }

    Write-TextFile -Path $giPath -Text $text.Insert($insertAt, $addition)
    Write-Good '游戏配置已改好 (在 SearchPaths 里加了 Game sharp 这一行)'

    return $true
}

function Get-SearchPathsBlock {
    <#
    .SYNOPSIS
        从 gameinfo.gi 全文里截出 SearchPaths { ... } 块的内容与起始偏移。
    .OUTPUTS
        @{ Start = <块内容在全文里的起始索引>; Content = <块内容> }; 找不到返回 $null。
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string] $Text)

    $head = [regex]::Match($Text, '(?m)^[ \t]*SearchPaths[ \t]*\r?\n?[ \t]*\{')
    if (-not $head.Success) { return $null }

    # 从 { 之后开始做花括号配对, 找到与之匹配的 }
    $open = $Text.IndexOf('{', $head.Index)
    if ($open -lt 0) { return $null }

    $depth = 0
    for ($i = $open; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]
        if ($ch -eq '{') { $depth++ }
        elseif ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) {
                $start = $open + 1
                return @{ Start = $start; Content = $Text.Substring($start, $i - $start) }
            }
        }
    }

    # 括号不配对 (文件被截断或写坏)
    return $null
}

function Initialize-ContentDirectory {
    <#
    .SYNOPSIS
        在 content\ 下建一个与 game\sharp 对应的 sharp 目录。
    .NOTES
        Workshop Tools 会按 gameinfo.gi 里的每个 Game 搜索路径去 content\ 下找同名目录
        (现有的 core / csgo / csgo_addons 都是这么对应的)。我们加了 Game sharp,
        少了 content\sharp 的话, 地图作者启动 Workshop Tools 时会报错。
        专用服务端不带 Workshop Tools, 根本没有 content\ 目录, 那种情况直接跳过。
    .OUTPUTS
        $true 表示这台机器需要该目录 (已存在或已创建); $false 表示不需要。
    #>
    param([Parameter(Mandatory = $true)][string] $Cs2Root)

    $content = Join-Path $Cs2Root 'content'
    if (-not (Test-Path -LiteralPath $content)) {
        return $false
    }

    $target = Join-Path $content 'sharp'
    if (Test-Path -LiteralPath $target) {
        Write-Good 'content\sharp 已存在 (Workshop Tools 需要它)'
        return $true
    }

    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Write-Good '已创建 content\sharp (Workshop Tools 需要它)'

    return $true
}

function Test-GameInfoPatched {
    param([Parameter(Mandatory = $true)][string] $Cs2Root)

    $giPath = Join-Path $Cs2Root 'game\csgo\gameinfo.gi'
    if (-not (Test-Path -LiteralPath $giPath)) { return $false }

    try {
        # 与 Update-GameInfo 用同一个判据: 只有 SearchPaths 块内的那一行才算数
        $block = Get-SearchPathsBlock -Text (Read-TextFile -Path $giPath)
        if ($null -eq $block) { return $false }
        return ($block.Content -match '(?m)^[ \t]*Game[ \t]+sharp[ \t]*(//[^\r\n]*)?\r?$')
    } catch {
        return $false
    }
}

#endregion

#region ── Release 下载与安装 ────────────────────────────────────────────

function Get-GitHubRelease {
    param(
        [Parameter(Mandatory = $true)][string] $Repo,
        [string] $Tag = 'latest'
    )

    if ([string]::IsNullOrWhiteSpace($Tag) -or $Tag -eq 'latest') {
        $uri = "https://api.github.com/repos/$Repo/releases/latest"
    } else {
        $uri = "https://api.github.com/repos/$Repo/releases/tags/$Tag"
    }

    $headers = @{
        'User-Agent' = "ModSharp-Installer/$script:ScriptVersion"
        'Accept'     = 'application/vnd.github+json'
    }

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -UseBasicParsing -TimeoutSec 30

        # 代理/运营商劫持可能返回 200 但空 body。放着不管的话, $null 会一路传到
        # Select-ReleaseAsset 的 Mandatory 参数上, 抛出一句纯英文的参数绑定错误。
        if ($null -eq $response) {
            throw "服务器返回了空响应 (通常是代理或运营商劫持了 api.github.com)。"
        }

        return $response
    } catch {
        throw @"
获取 $Repo 的 Release 信息失败 (tag: $Tag)。
  地址: $uri
  错误: $($_.Exception.Message)
可能原因: 网络不通 (国内访问 GitHub 可能需要代理)、指定的 tag 不存在、或 API 匿名限速 (每小时 60 次)。
"@
    }
}

function Select-ReleaseAsset {
    param(
        [Parameter(Mandatory = $true)] $Release,
        [Parameter(Mandatory = $true)][string] $Include,
        [string] $Exclude = ''
    )

    $assets = Get-ObjectProperty -InputObject $Release -Name 'assets' -Default @()

    foreach ($asset in $assets) {
        $name = Get-ObjectProperty -InputObject $asset -Name 'name' -Default ''
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($name -notlike $Include) { continue }
        if (-not [string]::IsNullOrWhiteSpace($Exclude) -and $name -like $Exclude) { continue }
        return $asset
    }

    return $null
}

function Sync-PackageDirectory {
    <#
    .SYNOPSIS
        按"覆盖 / 保护 / 从不触碰"三类规则, 把解压出来的包同步进 game\sharp。
    #>
    param(
        [Parameter(Mandatory = $true)][string] $SourceRoot,
        [Parameter(Mandatory = $true)][string] $SharpDir,
        [string[]] $OverwriteDirs = @(),
        [switch] $MergeModules,
        [switch] $ProtectConfigs,
        [bool] $FirstDeployment = $false
    )

    $copied = 0

    # 断言: 任何同步规则都不许指向用户数据目录 (README 明文承诺这几个目录"完全不动")
    foreach ($name in $OverwriteDirs) {
        if ($script:PreservedDirs -contains $name) {
            throw "内部错误: 同步规则试图覆盖用户数据目录 '$name'。这几个目录必须保持不动: $($script:PreservedDirs -join ', ')"
        }
    }

    foreach ($name in $OverwriteDirs) {
        $src = Join-Path $SourceRoot $name
        if (-not (Test-Path -LiteralPath $src)) { continue }

        $copied += Copy-DirectoryMerged -Source $src -Destination (Join-Path $SharpDir $name)
        Write-Info "  已更新 $name\"
    }

    # 白名单是硬编码的, 上游哪天在包里新增一个顶层目录/文件就会被静默丢弃, 装出来是个
    # 缺文件的 ModSharp, 自检还查不出来。这里把没被任何规则覆盖到的顶层项报出来。
    $handled = @($OverwriteDirs)
    if ($MergeModules) { $handled += 'modules' }
    if ($ProtectConfigs) { $handled += 'configs' }

    foreach ($item in (Get-ChildItem -LiteralPath $SourceRoot -Force)) {
        if ($handled -contains $item.Name) { continue }
        if ($script:PreservedDirs -contains $item.Name) { continue }
        Write-Warn "包里的 $($item.Name)$(if ($item.PSIsContainer) { '\' }) 不在已知的同步规则内, 已跳过。"
        Write-Info '  如果这是 ModSharp 新增的内容, 说明本脚本需要更新了 —— 请到仓库反馈。'
    }

    if ($MergeModules) {
        $srcModules = Join-Path $SourceRoot 'modules'
        if (Test-Path -LiteralPath $srcModules) {
            $dstModules = New-DirectoryIfMissing -Path (Join-Path $SharpDir 'modules')

            foreach ($module in (Get-ChildItem -LiteralPath $srcModules -Directory)) {
                $dstModule = Join-Path $dstModules $module.Name
                $isFirstInstall = -not (Test-Path -LiteralPath $dstModule)

                # 模块目录已存在且用户已手动启用 (删掉了 .disabled) 时, 不要把 .disabled 重新塞回去
                $exclude = @()
                if (-not $isFirstInstall -and
                    -not (Test-Path -LiteralPath (Join-Path $dstModule '.disabled'))) {
                    $exclude = @('.disabled')
                }

                $copied += Copy-DirectoryMerged -Source $module.FullName -Destination $dstModule -ExcludeNames $exclude
                Write-Info "  已更新 modules\$($module.Name)\"

                # 补上 Release 包里丢掉的 .disabled (见 $script:DefaultDisabledModules 的说明)。
                # 判据不能只看"模块目录是不是刚创建": 用户先手工解压过 Release 包、
                # 或上次运行崩在创建目录与补 .disabled 之间, 目录都已存在, 那样就永远补不上了。
                # 这里改成"本机从没用脚本部署过 (没有 .deploy-state.json)"也一并补。
                if (($isFirstInstall -or $FirstDeployment) -and ($script:DefaultDisabledModules -contains $module.Name)) {
                    $disabledFlag = Join-Path $dstModule '.disabled'
                    if (-not (Test-Path -LiteralPath $disabledFlag)) {
                        New-Item -ItemType File -Path $disabledFlag -Force | Out-Null
                        Write-Info "    ^ 已默认禁用 (它需要数据库配置; 想启用就删掉里面的 .disabled)"
                    }
                }
            }
        }
    }

    if ($ProtectConfigs) {
        $srcConfigs = Join-Path $SourceRoot 'configs'
        if (Test-Path -LiteralPath $srcConfigs) {
            # 必须用 Get-Item 规范化后再做 Substring: $SourceRoot 源自 [IO.Path]::GetTempPath(),
            # 当 %TEMP% 是 8.3 短名 (C:\Users\ADMINI~1\...) 时, Get-ChildItem 返回的 FullName
            # 是展开后的长名, 直接按短名长度切会从长路径中间乱切, configs 会被写进一棵垃圾目录树。
            $srcConfigs = (Get-Item -LiteralPath $srcConfigs).FullName.TrimEnd('\')
            $dstConfigs = New-DirectoryIfMissing -Path (Join-Path $SharpDir 'configs')

            foreach ($file in (Get-ChildItem -LiteralPath $srcConfigs -File -Recurse)) {
                if (-not $file.FullName.StartsWith($srcConfigs, [StringComparison]::OrdinalIgnoreCase)) {
                    Write-Warn "跳过路径异常的配置文件: $($file.FullName)"
                    continue
                }
                $relative = $file.FullName.Substring($srcConfigs.Length).TrimStart('\')
                # 不叫 $target: PowerShell 变量名不区分大小写, 会遮蔽脚本参数 $Target
                $targetPath = Join-Path $dstConfigs $relative

                New-DirectoryIfMissing -Path (Split-Path -Parent $targetPath) | Out-Null

                # .example 是模板/文档, 用户不会改它, 直接覆盖 —— 否则每次更新都会堆一堆 .example.new
                $isTemplate = $file.Name -like '*.example'

                if ((Test-Path -LiteralPath $targetPath) -and -not $isTemplate) {
                    # 保留用户的配置, 新版另存为 .new 供比对
                    Copy-Item -LiteralPath $file.FullName -Destination "$targetPath.new" -Force
                    Write-Info "  保留 configs\$relative (新版另存为 $relative.new)"
                } else {
                    Copy-Item -LiteralPath $file.FullName -Destination $targetPath -Force
                    Write-Info "  已写入 configs\$relative"
                    $copied++
                }
            }
        }
    }

    return $copied
}

function Install-ModSharpPackage {
    param(
        [Parameter(Mandatory = $true)][string] $SharpDir,
        [Parameter(Mandatory = $true)][string] $WorkDir,
        [string] $Tag = 'latest',
        [bool] $FirstDeployment = $false
    )

    Write-Step '安装 ModSharp'

    $release = Get-GitHubRelease -Repo $script:RepoModSharp -Tag $Tag
    $tagName = Get-ObjectProperty -InputObject $release -Name 'tag_name' -Default $Tag

    # extensions 包只给模块开发者引用, 服务端运行时不需要
    $asset = Select-ReleaseAsset -Release $release -Include 'ModSharp-git*-windows.zip' -Exclude '*extensions*'
    if ($null -eq $asset) {
        throw "在 ModSharp Release $tagName 中找不到 Windows 包 (ModSharp-git*-windows.zip)。"
    }

    $assetName = Get-ObjectProperty -InputObject $asset -Name 'name' -Default 'ModSharp.zip'
    $assetUrl = Get-ObjectProperty -InputObject $asset -Name 'browser_download_url' -Default ''
    if ([string]::IsNullOrWhiteSpace($assetUrl)) {
        throw "ModSharp 资产 $assetName 没有下载地址。"
    }

    Write-Info "版本: $tagName ($assetName)"

    $zip = Join-Path $WorkDir $assetName
    Invoke-Download -Uri $assetUrl -OutFile $zip -Description 'ModSharp'

    $extract = Join-Path $WorkDir 'extract-modsharp'
    Expand-ZipArchiveTo -ZipPath $zip -Destination $extract

    # zip 顶层就是 sharp\
    $sourceRoot = Join-Path $extract 'sharp'
    if (-not (Test-Path -LiteralPath $sourceRoot)) {
        throw "ModSharp 包结构异常: 解压后找不到 sharp 目录 ($extract)。"
    }

    New-DirectoryIfMissing -Path $SharpDir | Out-Null

    $count = Sync-PackageDirectory -SourceRoot $sourceRoot -SharpDir $SharpDir `
        -OverwriteDirs @('bin', 'core', 'shared', 'gamedata', 'locales') `
        -MergeModules -ProtectConfigs -FirstDeployment $FirstDeployment

    # StripperSharp 的配置目录, 建出来让用户知道该往哪放
    New-DirectoryIfMissing -Path (Join-Path $SharpDir 'stripper') | Out-Null

    Write-Good "ModSharp $tagName 安装完成 (写入 $count 个文件)"

    return $tagName
}

function Install-StripperPackage {
    param(
        [Parameter(Mandatory = $true)][string] $SharpDir,
        [Parameter(Mandatory = $true)][string] $WorkDir,
        [string] $Tag = 'latest'
    )

    Write-Step '安装 StripperSharp'

    $release = Get-GitHubRelease -Repo $script:RepoStripper -Tag $Tag
    $tagName = Get-ObjectProperty -InputObject $release -Name 'tag_name' -Default $Tag

    $asset = Select-ReleaseAsset -Release $release -Include 'StripperSharp-git*-win.zip'
    if ($null -eq $asset) {
        throw "在 StripperSharp Release $tagName 中找不到 Windows 包 (StripperSharp-git*-win.zip)。"
    }

    $assetName = Get-ObjectProperty -InputObject $asset -Name 'name' -Default 'StripperSharp.zip'
    $assetUrl = Get-ObjectProperty -InputObject $asset -Name 'browser_download_url' -Default ''
    if ([string]::IsNullOrWhiteSpace($assetUrl)) {
        throw "StripperSharp 资产 $assetName 没有下载地址。"
    }

    Write-Info "版本: $tagName ($assetName)"

    $zip = Join-Path $WorkDir $assetName
    Invoke-Download -Uri $assetUrl -OutFile $zip -Description 'StripperSharp'

    $extract = Join-Path $WorkDir 'extract-stripper'
    Expand-ZipArchiveTo -ZipPath $zip -Destination $extract

    # zip 顶层是 gamedata\ 与 modules\, 直接合并进 sharp\
    $count = Sync-PackageDirectory -SourceRoot $extract -SharpDir $SharpDir `
        -OverwriteDirs @('gamedata') -MergeModules

    New-DirectoryIfMissing -Path (Join-Path $SharpDir 'stripper') | Out-Null

    Write-Good "StripperSharp $tagName 安装完成 (写入 $count 个文件)"

    return $tagName
}

#endregion

#region ── 部署状态 ──────────────────────────────────────────────────────

function Get-DeployState {
    param([Parameter(Mandatory = $true)][string] $SharpDir)

    $file = Join-Path $SharpDir '.deploy-state.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }

    try {
        return (Read-TextFile -Path $file | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Save-DeployState {
    param(
        [Parameter(Mandatory = $true)][string] $SharpDir,
        [Parameter(Mandatory = $true)][hashtable] $State
    )

    $file = Join-Path $SharpDir '.deploy-state.json'

    try {
        New-DirectoryIfMissing -Path $SharpDir | Out-Null
        Write-TextFile -Path $file -Text ($State | ConvertTo-Json -Depth 5)
    } catch {
        Write-Warn "写入部署状态失败 (不影响使用): $($_.Exception.Message)"
    }
}

#endregion

#region ── 自检 ──────────────────────────────────────────────────────────

function Test-Deployment {
    <#
    .SYNOPSIS
        逐项检查部署结果。
    .OUTPUTS
        $true 表示全部通过。
    #>
    param(
        [Parameter(Mandatory = $true)][string] $Cs2Root,
        [bool] $CheckStripper = $true
    )

    Write-Step '部署自检'

    $sharpDir = Join-Path $Cs2Root 'game\sharp'
    $checks = New-Object System.Collections.Generic.List[hashtable]

    $checks.Add(@{
        Name = 'CS2 主程序'
        Ok   = (Test-Path -LiteralPath (Join-Path $Cs2Root 'game\bin\win64\cs2.exe'))
        Path = 'game\bin\win64\cs2.exe'
        Hint = '找不到 CS2 的主程序。开服的话再跑一次那条安装命令; 用自己游戏的话在 Steam 里安装或修复 CS2。'
    })

    $checks.Add(@{
        Name = '游戏配置已改好'
        Ok   = (Test-GameInfoPatched -Cs2Root $Cs2Root)
        Path = 'game\csgo\gameinfo.gi'
        Hint = '这一步没做对的话, ModSharp 装了也不会生效。再跑一次那条安装命令就能补上; 游戏每次更新都会把它改回去。'
    })

    $checks.Add(@{
        Name = 'ModSharp 启动文件'
        Ok   = (Test-Path -LiteralPath (Join-Path $sharpDir 'bin\win64\server.dll'))
        Path = 'game\sharp\bin\win64\server.dll'
        Hint = '这个文件没装上, 再跑一次那条安装命令就会补齐。'
    })

    $checks.Add(@{
        Name = 'ModSharp 主程序'
        Ok   = (Test-Path -LiteralPath (Join-Path $sharpDir 'bin\modsharp.dll'))
        Path = 'game\sharp\bin\modsharp.dll'
        Hint = '这个文件没装上, 再跑一次那条安装命令就会补齐。'
    })

    # Loader 会用相对路径链式加载游戏自带的 server.dll 拿真正的 serverFactory
    # (loader.cpp:279)。少了它, 上面几项全绿但服务器一启动就挂, 用户无从判断。
    $checks.Add(@{
        Name = '游戏自带的程序文件'
        Ok   = (Test-Path -LiteralPath (Join-Path $Cs2Root 'game\csgo\bin\win64\server.dll'))
        Path = 'game\csgo\bin\win64\server.dll'
        Hint = 'Loader 需要链式加载它。不要照旧版 Metamod 教程去改名或删除它; 用 Steam「验证文件完整性」或 SteamCMD 的 app_update ... validate 修复。'
    })

    $coreOk = (Test-Path -LiteralPath (Join-Path $sharpDir 'core\Sharp.Core.dll')) -and
              (Test-Path -LiteralPath (Join-Path $sharpDir 'core\Sharp.Core.runtimeconfig.json'))
    $checks.Add(@{
        Name = 'ModSharp 核心组件'
        Ok   = $coreOk
        Path = 'game\sharp\core\Sharp.Core.dll'
        Hint = '这个文件没装上, 再跑一次那条安装命令就会补齐。'
    })

    $checks.Add(@{
        Name = 'ModSharp 配置文件'
        Ok   = (Test-Path -LiteralPath (Join-Path $sharpDir 'configs\core.json'))
        Path = 'game\sharp\configs\core.json'
        Hint = '配置文件没装上, 服务器起不来。再跑一次那条安装命令。'
    })

    $dotnet = Test-DotNetRuntime -SharpDir $sharpDir
    $dotnetDetail = 'game\sharp\runtime\host\fxr'
    if ($dotnet.Found) { $dotnetDetail = "$($dotnet.Version) @ $($dotnet.Path)" }
    $checks.Add(@{
        Name = ".NET 运行环境 (需要 $script:MinDotNetMajor 或更新)"
        Ok   = [bool] $dotnet.Found
        Path = $dotnetDetail
        Hint = "ModSharp 运行需要它, 而且必须装在特定位置。再运行一次本脚本会自动装; 仍不行就用核心脚本加 -Force 强制重装。"
    })

    $vc = Test-VcRedist
    $vcDetail = '未安装'
    if ($vc.Installed) { $vcDetail = $vc.Version }
    $checks.Add(@{
        Name = '系统运行库'
        Ok   = [bool] $vc.Installed
        Path = $vcDetail
        Hint = "ModSharp 运行需要这个微软的运行库。手动下载安装: $script:UrlVcRedist"
    })

    # 只有装了 Workshop Tools 的机器才有 content\ 目录, 专用服务端没有
    if (Test-Path -LiteralPath (Join-Path $Cs2Root 'content')) {
        $checks.Add(@{
            Name = 'Workshop Tools 目录'
            Ok   = (Test-Path -LiteralPath (Join-Path $Cs2Root 'content\sharp'))
            Path = 'content\sharp'
            Hint = '少了它, 用 Workshop Tools 做地图时会报错。再跑一次那条安装命令就会建好。'
        })
    }

    if ($CheckStripper) {
        $stripperOk = (Test-Path -LiteralPath (Join-Path $sharpDir 'modules\StripperSharp\StripperSharp.dll')) -and
                      (Test-Path -LiteralPath (Join-Path $sharpDir 'gamedata\stripper.games.jsonc'))
        $checks.Add(@{
            Name = 'StripperSharp'
            Ok   = $stripperOk
            Path = 'game\sharp\modules\StripperSharp\'
            Hint = 'StripperSharp 没装上, 再跑一次那条安装命令就会补齐。'
        })
    }

    Write-Host ''
    $failed = 0
    foreach ($check in $checks) {
        $label = Format-PadRight -Text $check.Name -Width 34
        if ($check.Ok) {
            Write-Host "    [ OK ] $label$($check.Path)" -ForegroundColor Green
        } else {
            Write-Host "    [FAIL] $label$($check.Path)" -ForegroundColor Red
            Write-Host "           -> $($check.Hint)" -ForegroundColor DarkYellow
            $failed++
        }
    }
    Write-Host ''

    if ($failed -eq 0) {
        Write-Good "自检全部通过 ($($checks.Count) 项)"
        return $true
    }

    Write-Fail "自检未通过: $failed / $($checks.Count) 项有问题"
    return $false
}

#endregion

#region ── 启动提示 ──────────────────────────────────────────────────────

function Show-StartupHint {
    param(
        [Parameter(Mandatory = $true)][string] $Cs2Root,
        [Parameter(Mandatory = $true)][string] $TargetKind
    )

    $binDir = Join-Path $Cs2Root 'game\bin\win64'

    Write-Host ''
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host '   如何启动' -ForegroundColor Cyan
    Write-Host '  ------------------------------------------------------------' -ForegroundColor DarkCyan
    Write-Host ''

    if ($TargetKind -eq 'Game') {
        Write-Host '  直接从 Steam 启动就行, ModSharp 会自动加载:' -ForegroundColor White
        Write-Host ''
        Write-Host '    做地图   : Steam 库里右键 CS2 -> 启动时选「Workshop Tools」' -ForegroundColor Gray
        Write-Host '    测试地图 : 正常启动游戏, 进去后在控制台执行  map 你的地图名' -ForegroundColor Gray
        Write-Host ''
        Write-Host '  不用敲命令行, 也不用管工作目录之类的东西。' -ForegroundColor DarkGray
    } else {
        Write-Host '  启动命令:' -ForegroundColor White
        Write-Host "    Set-Location `"$binDir`"" -ForegroundColor Gray
        Write-Host '    .\cs2.exe -dedicated +map de_dust2' -ForegroundColor Gray
    }

    Write-Host ''
    Write-Host '  必读:' -ForegroundColor Yellow

    if ($TargetKind -eq 'Dedicated') {
        Write-Host '    - 上面那行 Set-Location 不能省: ModSharp 是按"当前工作目录"'
        Write-Host '      去找自己的文件的, 目录不对就加载不到 (服务器能开, 但模块全都不工作)。'
    }

    Write-Host '    - 启动后在控制台输入 ms, 能看到版本信息说明 ModSharp 已正常工作。'

    if ($TargetKind -eq 'Dedicated') {
        Write-Host '    - 对公网开服还需要: 放行 UDP 27015, 并配置 GSLT'
        Write-Host '      (启动参数加 +sv_setsteamaccount <你的令牌>, 令牌在'
        Write-Host '      https://steamcommunity.com/dev/managegameservers 申请)。'
    } else {
        Write-Host '    - 本地做图、测图不涉及 VAC。想更保险的话, 可以在 Steam 里'
        Write-Host '      右键 CS2 -> 属性 -> 启动选项, 填上  -insecure  (明确关掉 VAC)。'
        Write-Host '      别拿这份游戏去打官方竞技匹配或连别人的正式服务器。' -ForegroundColor Yellow
        Write-Host '    - Steam 更新或「验证游戏文件完整性」会还原 gameinfo.gi,'
        Write-Host '      届时再跑一次那条安装命令即可。'
        Write-Host '    - 想还原: 把同目录下的 gameinfo.gi.bak 覆盖回 gameinfo.gi,'
        Write-Host '      或者在 Steam 里对 CS2 点「验证游戏文件完整性」。'
    }

    Write-Host ''
    Write-Host '  StripperSharp 配置目录:' -ForegroundColor White
    Write-Host "    $(Join-Path $Cs2Root 'game\sharp\stripper')" -ForegroundColor Gray
    Write-Host '    用法参考 https://github.com/fyscs/cs2/blob/master/.fys/Stripper.md' -ForegroundColor DarkGray

    Write-Host ''
    Write-Host '  文档: https://docs.modsharp.net/docs/zh-cn/guides/getting-started.html' -ForegroundColor DarkGray
    Write-Host '  社区: https://discord.gg/wKarAjHm2G' -ForegroundColor DarkGray

    # 顺手告诉用户怎么免掉每次的 -ExecutionPolicy Bypass
    try {
        $policy = Get-ExecutionPolicy -Scope CurrentUser
        if ($policy -eq 'Restricted' -or $policy -eq 'Undefined') {
            Write-Host ''
            Write-Host '  小提示: 想以后不用每次都加 -ExecutionPolicy Bypass, 可以执行 (不需要管理员):' -ForegroundColor DarkGray
            Write-Host '    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned' -ForegroundColor Gray
            Write-Host '    Unblock-File .\*.ps1' -ForegroundColor Gray
            # 第二行不能省: 从 GitHub 下载 zip 再用资源管理器解压出来的 .ps1 带
            # Mark-of-the-Web, RemoteSigned 恰恰会拒绝执行它 —— 只设 RemoteSigned
            # 反而会让用户下次撞上"未数字签名"的英文报错。
            Write-Host '  (第二行是必须的: 从网上下载的脚本带"来源标记", RemoteSigned 会拦下它)' -ForegroundColor DarkGray
        }
    } catch {
        # 拿不到策略就算了
    }

    Write-Host ''
}

#endregion

#region ── 主流程 ────────────────────────────────────────────────────────

function Resolve-TargetKind {
    param(
        [string] $Requested,
        [bool] $Interactive
    )

    if (-not [string]::IsNullOrWhiteSpace($Requested)) { return $Requested }

    if (-not $Interactive) {
        throw '未指定 -Target。请传 -Target Dedicated 或 -Target Game。'
    }

    $picked = Read-Menu -Title '请选择部署目标:' -Items @(
        'Dedicated - 用 SteamCMD 下载独立的专用服务端 (约 35 GB, 与游戏隔离, 适合正式开服)',
        'Game      - 部署到本机已安装的 CS2 游戏 (零下载, 适合本地测试; 有 VAC 风险)'
    ) -DefaultIndex 0

    if ($picked -eq 0) { return 'Dedicated' }
    return 'Game'
}

function Resolve-RunMode {
    param(
        [string] $Requested,
        [bool] $Interactive
    )

    if (-not [string]::IsNullOrWhiteSpace($Requested)) { return $Requested }
    if (-not $Interactive) { return 'Install' }

    $picked = Read-Menu -Title '请选择运行模式:' -Items @(
        'Install - 首次安装, 完整部署一遍',
        'Update  - 更新 CS2 与模块, 保留 configs / data / stripper 等用户数据',
        'Verify  - 只检查现有部署, 不修改任何文件'
    ) -DefaultIndex 0

    switch ($picked) {
        0 { return 'Install' }
        1 { return 'Update' }
        default { return 'Verify' }
    }
}

function Resolve-Cs2Root {
    param(
        [Parameter(Mandatory = $true)][string] $TargetKind,
        [string] $Requested,
        [bool] $Interactive
    )

    if ($TargetKind -eq 'Game') {
        if (-not [string]::IsNullOrWhiteSpace($Requested)) {
            $path = Resolve-AbsolutePath -Path $Requested
            if (-not (Test-Cs2Root -Root $path)) {
                throw "指定的路径不是有效的 CS2 游戏目录: $path`n应该是包含 game\bin\win64\cs2.exe 的那一层。"
            }
            return $path
        }

        Write-Step '探测本机已安装的 CS2'
        # 必须用 @() 包裹: 空集合会被 PowerShell 展开成 $null, StrictMode 下 .Count 会抛异常
        $candidates = @(Find-Cs2GamePath)

        if ($candidates.Count -eq 1) {
            Write-Good "找到 CS2: $($candidates[0])"
            if ($Interactive) {
                if (-not (Read-YesNo -Question '使用这个目录?' -DefaultYes $true)) {
                    return Read-Cs2RootManually -Interactive $Interactive
                }
            }
            return $candidates[0]
        }

        if ($candidates.Count -gt 1) {
            Write-Good "找到 $($candidates.Count) 个 CS2 安装"
            if (-not $Interactive) { return $candidates[0] }

            $items = @()
            foreach ($candidate in $candidates) { $items += $candidate }
            $picked = Read-Menu -Title '请选择要部署的 CS2 目录:' -Items $items -DefaultIndex 0
            return $candidates[$picked]
        }

        Write-Warn '没有自动找到 CS2 游戏安装 (未检测到 Steam 库中的 Counter-Strike Global Offensive)。'
        return Read-Cs2RootManually -Interactive $Interactive
    }

    # Dedicated
    if (-not [string]::IsNullOrWhiteSpace($Requested)) {
        return Resolve-AbsolutePath -Path $Requested
    }

    if (-not $Interactive) {
        throw '未指定 -InstallDir。请传 -InstallDir C:\cs2server 之类的服务端安装目录。'
    }

    Assert-InteractiveInput -Question '服务端安装目录'

    Write-Host ''
    Write-Host '  服务端安装目录 (建议用不含空格和中文的路径, 例如 C:\cs2server)' -ForegroundColor White
    while ($true) {
        $raw = Read-Host '     请输入安装目录 (回车 = C:\cs2server)'
        if ([string]::IsNullOrWhiteSpace($raw)) { return 'C:\cs2server' }

        try {
            return Resolve-AbsolutePath -Path $raw
        } catch {
            Write-Warn $_.Exception.Message
        }
    }
}

function Read-Cs2RootManually {
    param([bool] $Interactive)

    if (-not $Interactive) {
        throw '未能自动定位 CS2 游戏目录。请用 -InstallDir 显式指定 (包含 game\bin\win64\cs2.exe 的那一层)。'
    }

    Assert-InteractiveInput -Question 'CS2 游戏根目录'

    Write-Host ''
    Write-Host '  请手动输入 CS2 游戏根目录, 例如:' -ForegroundColor White
    Write-Host '    D:\SteamLibrary\steamapps\common\Counter-Strike Global Offensive' -ForegroundColor Gray

    while ($true) {
        $raw = Read-Host '     CS2 游戏目录 (直接回车放弃)'
        if ([string]::IsNullOrWhiteSpace($raw)) {
            throw '已取消: 没有提供 CS2 游戏目录。'
        }

        try {
            $path = Resolve-AbsolutePath -Path $raw
        } catch {
            Write-Warn $_.Exception.Message
            continue
        }

        if (Test-Cs2Root -Root $path) { return $path }

        Write-Warn "这个目录里找不到 game\bin\win64\cs2.exe, 请检查后重新输入。"
    }
}

function Invoke-Main {
    Show-Banner

    $interactive = -not $NonInteractive

    $targetKind = Resolve-TargetKind -Requested $Target -Interactive $interactive
    $runMode = Resolve-RunMode -Requested $Mode -Interactive $interactive
    $cs2Root = Resolve-Cs2Root -TargetKind $targetKind -Requested $InstallDir -Interactive $interactive

    $sharpDir = Join-Path $cs2Root 'game\sharp'
    $installStripper = -not $SkipStripper

    # -WithStripper 表示调用方已经替用户决定了, 不用再问 (预设入口脚本会传它)
    if ($interactive -and $runMode -ne 'Verify' -and -not $SkipStripper -and -not $WithStripper) {
        $installStripper = Read-YesNo -Question '同时安装 StripperSharp (地图实体修改工具)?' -DefaultYes $true
    }

    Write-Host ''
    Write-Info "部署目标 : $targetKind"
    Write-Info "运行模式 : $runMode"
    Write-Info "根目录   : $cs2Root"
    Write-Info "sharp    : $sharpDir"

    # ── Verify: 只读 ──
    if ($runMode -eq 'Verify') {
        if (-not (Test-Path -LiteralPath $cs2Root)) {
            Write-Warn "目录不存在: $cs2Root"
        }

        $ok = Test-Deployment -Cs2Root $cs2Root -CheckStripper $installStripper

        # 自检没过就不要给启动指引: 否则新手会照着去启动一个根本没装好的服务器,
        # 再撞上一串更看不懂的错误, 反而盖住了"先修上面那几项"这个真正的下一步。
        if (-not $ok) {
            Write-Host ''
            Write-Warn '自检未通过, 请先按上面每项后面的提示修复。'
            Write-Info '  多数情况再跑一次那条安装命令就能补齐缺失的文件。'
            Write-Host ''
            exit 1
        }

        Show-StartupHint -Cs2Root $cs2Root -TargetKind $targetKind
        return
    }

    Assert-Environment -TargetKind $targetKind -Path $cs2Root -Interactive $interactive

    # ── Game 模式: VAC 风险确认, 必须在任何写操作之前 ──
    if ($targetKind -eq 'Game') {
        $previous = Get-DeployState -SharpDir $sharpDir
        $acceptedBefore = [bool] (Get-ObjectProperty -InputObject $previous -Name 'acceptedGameRisk' -Default $false)

        $confirmed = Confirm-GameTargetRisk -Cs2Root $cs2Root `
            -Interactive $interactive `
            -PreAccepted ([bool] $AcceptGameRisk) `
            -AlreadyAcceptedBefore $acceptedBefore

        if (-not $confirmed) {
            Write-Host ''
            Write-Warn '已取消, 没有对你的游戏做任何修改。'
            Write-Info "不想动自己的游戏的话, 重跑安装命令并选 [2] 开服务器"
            Write-Host ''
            return
        }
    }

    $workDir = Join-Path ([IO.Path]::GetTempPath()) ("ms-deploy-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    New-DirectoryIfMissing -Path $workDir | Out-Null

    # 注意: 这两个变量名不能写成 $modsharpTag / $stripperTag ——
    # PowerShell 变量名不区分大小写, 那样会在本函数作用域里遮蔽脚本参数
    # $ModSharpTag / $StripperTag, 导致 -ModSharpTag / -StripperTag 静默失效, 永远装 latest。
    $installedModSharpTag = ''
    $installedStripperTag = ''

    try {
        Install-VcRedist -WorkDir $workDir -Interactive $interactive

        # ── CS2 本体 ──
        if ($targetKind -eq 'Dedicated' -and -not $SkipCs2) {
            if ([string]::IsNullOrWhiteSpace($SteamCmdDir)) {
                # $cs2Root 此时一定是绝对路径且不是盘根 (Resolve-AbsolutePath 保证),
                # 所以 Split-Path -Parent 不会返回空串或抛错
                $steamCmdPath = Join-Path (Split-Path -Parent $cs2Root) 'steamcmd'
            } else {
                $steamCmdPath = Resolve-AbsolutePath -Path $SteamCmdDir
            }

            $steamCmdExe = Install-SteamCmd -Path $steamCmdPath -WorkDir $workDir
            Update-Cs2Server -SteamCmdExe $steamCmdExe -Cs2Root $cs2Root
        } else {
            Write-Step '跳过 CS2 本体'
            if ($targetKind -eq 'Game') {
                Write-Info 'Game 模式下 CS2 由 Steam 客户端负责更新。'
            } else {
                Write-Info '已指定 -SkipCs2。'
            }

            if (-not (Test-Cs2Root -Root $cs2Root)) {
                throw "在 $cs2Root 找不到有效的 CS2 安装 (缺 game\bin\win64\cs2.exe)。"
            }
            Write-Good 'CS2 本体检查通过'
        }

        # ── .NET 运行时 ──
        if (-not $SkipDotNet) {
            Install-DotNetRuntime -SharpDir $sharpDir -WorkDir $workDir -Channel $DotNetChannel -ForceReinstall ([bool] $Force)
        } else {
            Write-Step '跳过 .NET 运行环境 (已指定 -SkipDotNet)'
        }

        # ── gameinfo.gi ──
        Update-GameInfo -Cs2Root $cs2Root | Out-Null

        # 有 Workshop Tools 的机器还要在 content\ 下建对应目录, 否则做图时会报错
        Initialize-ContentDirectory -Cs2Root $cs2Root | Out-Null

        # ── 模块包 ──
        # 没有 .deploy-state.json 说明这台机器从没用脚本部署过 (可能是用户手工解压过 Release
        # 包, 也可能是上次运行中途崩了), 这种情况下要重新补一次默认禁用标记
        $firstDeployment = ($null -eq (Get-DeployState -SharpDir $sharpDir))
        $installedModSharpTag = Install-ModSharpPackage -SharpDir $sharpDir -WorkDir $workDir -Tag $ModSharpTag -FirstDeployment $firstDeployment

        if ($installStripper) {
            $installedStripperTag = Install-StripperPackage -SharpDir $sharpDir -WorkDir $workDir -Tag $StripperTag
        } else {
            Write-Step '跳过 StripperSharp'
        }
    } finally {
        if (Test-Path -LiteralPath $workDir) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # ── 状态 ──
    $dotnetState = Test-DotNetRuntime -SharpDir $sharpDir
    $dotnetVersion = ''
    if ($dotnetState.Found) { $dotnetVersion = $dotnetState.Version.ToString() }

    Save-DeployState -SharpDir $sharpDir -State @{
        target           = $targetKind
        mode             = $runMode
        modsharpTag      = $installedModSharpTag
        stripperTag      = $installedStripperTag
        dotnetVersion    = $dotnetVersion
        installedAt      = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        scriptVersion    = $script:ScriptVersion
        acceptedGameRisk = ($targetKind -eq 'Game')
    }

    # ── 自检 ──
    $allOk = Test-Deployment -Cs2Root $cs2Root -CheckStripper $installStripper

    # 和 Verify 一致: 自检没过就不给启动指引, 免得用户照着去启动一个必然失败的服务器
    if (-not $allOk) {
        Write-Host ''
        Write-Warn '文件已安装, 但自检有未通过项 —— 现在启动服务器大概率会失败。'
        Write-Info '  请先按上面每项后面的提示处理, 然后再运行一次本脚本复查。'
        Write-Host ''
        exit 1
    }

    Show-StartupHint -Cs2Root $cs2Root -TargetKind $targetKind

    Write-Host '  部署完成, 祝你玩得开心。' -ForegroundColor Green
    Write-Host ''
}

#endregion

if (-not $LoadOnly) {
    try {
        Invoke-Main
        # 必须显式 exit 0: 否则成功路径根本不设置 $LASTEXITCODE, 调用方 (install.ps1)
        # 在 StrictMode 下读它会抛"变量未设置", 明明部署成功却报错退出。
        # 用户主动取消 (VAC 不确认) 也走这里, 同样算成功。
        exit 0
    } catch {
        Write-Host ''
        Write-Host '  ------------------------------------------------------------' -ForegroundColor Red
        Write-Host '   部署失败' -ForegroundColor Red
        Write-Host '  ------------------------------------------------------------' -ForegroundColor Red
        Write-Host ''
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  如果看不懂上面的错误, 可以把这个窗口的完整输出发到' -ForegroundColor DarkGray
        Write-Host '  ModSharp 社区求助: https://discord.gg/wKarAjHm2G' -ForegroundColor DarkGray
        Write-Host ''

        if ($VerbosePreference -ne 'SilentlyContinue') {
            Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
        }

        exit 1
    }
}
