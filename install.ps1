<#
    ！！这个文件必须保存为 UTF-8「无 BOM」！！

    它是专门给 `irm ... | iex` 用的入口：
      - irm 会按 HTTP 响应头的 charset=utf-8 解码，中文正常，完全不依赖 BOM；
      - 但 BOM (U+FEFF) 会原样留在字符串开头，而它不是合法的 PowerShell token，
        开头的 <# 会因此不被识别成注释，下面这段说明就被当成代码解析，
        报出指向某个中文标点的 "Missing argument in parameter list"。
      - 把 <# 挪到第二行也没用：BOM 会和后面的内容粘成一个 token 被当命令名。

    代价是这个文件只能通过上面那条命令使用，不能下载下来直接运行 —— PowerShell 5.1
    读无 BOM 的文件时会按系统 ANSI 代码页解释，中文变乱码后连引号都配不上，
    直接语法错误。这是有意的取舍：它就是给 irm|iex 用的。

    Install-CS2Server.ps1 正好相反：它以文件方式执行，必须带 BOM。

.SYNOPSIS
    ModSharp 一键安装。一条命令搞定, 不用下载解压。

.DESCRIPTION
    用法:

        irm https://raw.githubusercontent.com/kxnrl/ms-install-script/master/install.ps1 | iex

    它会问你一个问题 (做地图 / 开服 / 自定义), 然后把剩下的事全办了。

    想跳过那次询问, 直接指定:

        & ([scriptblock]::Create((irm https://raw.githubusercontent.com/kxnrl/ms-install-script/master/install.ps1))) mapper

.LINK
    https://github.com/kxnrl/ms-install-script
#>

#Requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# 只在系统默认里补上 TLS 1.2, 不整个覆写 SystemDefault (那会连带关掉 TLS 1.3)
try {
    if (([Net.ServicePointManager]::SecurityProtocol -band [Net.SecurityProtocolType]::Tls12) -eq 0) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
} catch { }

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch { }

$script:CoreRepo = 'kxnrl/ms-install-script'
$script:CoreName = 'Install-CS2Server.ps1'

function Get-WorkDirectory {
    <#
    .SYNOPSIS
        决定把核心脚本放哪。
    .NOTES
        用 irm|iex 跑的时候没有脚本文件, $PSScriptRoot 是空的, 没法"放在自己旁边"。
        这里固定用 %LOCALAPPDATA%\ms-install-script:
        位置可预期、不污染用户当前目录, 下次再跑还能直接复用。
    #>
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { return $PSScriptRoot }

    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) { $base = $env:TEMP }

    $dir = Join-Path $base 'ms-install-script'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    return $dir
}

function Assert-CoreScript {
    <#
    .SYNOPSIS
        校验下载到的核心脚本: 大小、BOM、语法、关键函数。
    #>
    param([Parameter(Mandatory = $true)][string] $Path)

    $bytes = [IO.File]::ReadAllBytes($Path)

    if ($bytes.Length -lt 20480) {
        throw "下载到的文件只有 $([math]::Round($bytes.Length/1KB,1)) KB, 不像是完整的部署核心 (可能下到了 404 页面)。"
    }
    if (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) {
        throw '下载到的文件缺少 UTF-8 BOM, PowerShell 5.1 读它会乱码。'
    }

    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref] $null, [ref] $errors) | Out-Null
    if ($null -ne $errors -and $errors.Count -gt 0) {
        throw "下载到的文件不是有效的 PowerShell 脚本 (第 $($errors[0].Extent.StartLineNumber) 行)。"
    }

    $text = [IO.File]::ReadAllText($Path)
    foreach ($fn in @('function Invoke-Main', 'function Confirm-GameTargetRisk', 'function Install-ModSharpPackage')) {
        if (-not $text.Contains($fn)) {
            throw "下载到的文件里找不到 '$fn', 内容不是预期的部署核心。"
        }
    }
}

function Get-CoreScript {
    param([Parameter(Mandatory = $true)][string] $Directory)

    $core = Join-Path $Directory $script:CoreName
    $temp = "$core.download"
    $lastError = ''
    $ok = $false

    Write-Host '  正在获取部署核心 ...' -ForegroundColor Cyan

    foreach ($branch in @('master', 'main')) {
        $url = "https://raw.githubusercontent.com/$script:CoreRepo/$branch/$script:CoreName"
        try {
            Invoke-WebRequest -Uri $url -OutFile $temp -UseBasicParsing -TimeoutSec 30 -MaximumRedirection 3
            $ok = $true
            break
        } catch {
            $lastError = $_.Exception.Message
        }
    }

    if (-not $ok) {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        # 网络不通时, 如果之前已经拉过一份能用的, 就接着用
        if (Test-Path -LiteralPath $core) {
            try {
                Assert-CoreScript -Path $core
                Write-Host '  连不上 GitHub, 使用上次下载的版本。' -ForegroundColor Yellow
                return $core
            } catch { }
        }
        throw @"
下载部署核心失败。
  仓库: https://github.com/$script:CoreRepo
  错误: $lastError
国内网络访问 GitHub 可能需要代理。
"@
    }

    try {
        Assert-CoreScript -Path $temp
    } catch {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        throw
    }

    Move-Item -LiteralPath $temp -Destination $core -Force
    Write-Host '  [ OK ] 部署核心已就绪' -ForegroundColor Green

    return $core
}

function Read-Choice {
    Write-Host ''
    Write-Host '  你想做什么?' -ForegroundColor White
    Write-Host ''
    Write-Host '    [1] 做地图 —— 装进你已有的 CS2, 不用额外下载' -ForegroundColor Gray
    Write-Host '    [2] 开服务器 —— 另外下一套独立服务端 (约 35 GB)' -ForegroundColor Gray
    Write-Host '    [3] 自定义 —— 所有选项自己选' -ForegroundColor Gray
    Write-Host ''

    while ($true) {
        $raw = Read-Host '  请输入 1 / 2 / 3 (回车 = 1)'
        if ([string]::IsNullOrWhiteSpace($raw)) { return 'mapper' }

        switch ($raw.Trim()) {
            '1' { return 'mapper' }
            '2' { return 'server' }
            '3' { return 'custom' }
            default { Write-Host '  输入无效, 请重新输入。' -ForegroundColor Yellow }
        }
    }
}

try {
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor DarkCyan
    Write-Host '    ModSharp + StripperSharp  一键安装' -ForegroundColor Cyan
    Write-Host '  ============================================================' -ForegroundColor DarkCyan

    # 支持 & ([scriptblock]::Create((irm ...))) mapper 这种直接指定的写法。
    # 只收一个选项, 多余的参数不静默吞掉。
    $choice = $null
    if ($args.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string] $args[0])) {
        $choice = ([string] $args[0]).Trim().ToLowerInvariant()
        if ($choice -notin @('mapper', 'server', 'custom')) {
            throw "不认识的选项 '$($args[0])'。可用: mapper / server / custom"
        }
    }

    if ($args.Count -gt 1) {
        throw @"
这个入口最多只接受一个选项 (mapper / server / custom), 但收到了: $($args -join ' ')
想精确控制每一项, 请直接用核心脚本, 例如:
  Install-CS2Server.ps1 -Target Dedicated -Mode Verify -InstallDir C:\cs2server -NonInteractive
"@
    }

    $dir = Get-WorkDirectory
    $core = Get-CoreScript -Directory $dir

    if ($null -eq $choice) { $choice = Read-Choice }

    switch ($choice) {
        'mapper' {
            # 装进已有的 CS2。核心脚本会自己探测路径, 并要求确认改动游戏
            & $core -Target Game -Mode Install -WithStripper
        }
        'server' {
            # 独立服务端。目录用默认值, 想换位置的人可以选 [3] 自定义
            & $core -Target Dedicated -Mode Install -InstallDir 'C:\cs2server' -WithStripper
        }
        default {
            # 完整向导, 什么都不预设
            & $core
        }
    }

    $code = 0
    if ((Test-Path 'variable:LASTEXITCODE') -and $null -ne $LASTEXITCODE) { $code = [int] $LASTEXITCODE }

    Write-Host ''
    Write-Host "  (部署核心存放在 $dir, 下次运行会直接复用)" -ForegroundColor DarkGray
    Write-Host ''

    exit $code
} catch {
    Write-Host ''
    Write-Host '  ------------------------------------------------------------' -ForegroundColor Red
    Write-Host '   出错了' -ForegroundColor Red
    Write-Host '  ------------------------------------------------------------' -ForegroundColor Red
    Write-Host ''
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  看不懂的话, 把这个窗口的完整内容发到 ModSharp 社区:' -ForegroundColor DarkGray
    Write-Host '  https://discord.gg/wKarAjHm2G' -ForegroundColor DarkGray
    Write-Host ''
    exit 1
}
