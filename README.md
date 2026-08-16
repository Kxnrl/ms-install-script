[English](README.en.md) | **简体中文**

# ms-install-script

**一键给 CS2 装好 ModSharp 和 StripperSharp。**

不用装 SteamCMD、不用改配置文件、不用查教程 —— 一条命令，剩下的它自己搞定。

---

## 开始装

打开 **PowerShell**，粘贴这一行，回车：

```powershell
irm https://raw.githubusercontent.com/kxnrl/ms-install-script/master/install.ps1 | iex
```

它会问你一句「做地图还是开服务器」，选完就自己装好了。全程中文。

装完以后：

- **做地图的**：直接从 Steam 开游戏就行，不用敲任何命令
- **开服务器的**：照着屏幕给的命令复制粘贴

进游戏或服务器起来以后，在控制台里输入 `ms` 回车。能看到版本号，就说明一切正常。

> 想跳过那次询问，直接指定：
> ```powershell
> & ([scriptblock]::Create((irm https://raw.githubusercontent.com/kxnrl/ms-install-script/master/install.ps1))) mapper
> ```
> 把最后的 `mapper` 换成 `server` 或 `custom` 即可。

---

## 那一句问的是什么

```
  [1] 做地图 —— 装进你已有的 CS2, 不用额外下载
  [2] 开服务器 —— 另外下一套独立服务端 (约 35 GB)
  [3] 自定义 —— 所有选项自己选
```

**做地图选 1。** 装到你电脑上已经有的那个 CS2 里，不用额外下载，几分钟就好。装完就能一边改地图一边测试，配合 StripperSharp 还能不重新编译地图就改里面的东西。

**开服选 2。** 会另外下载一整套服务器程序（和你玩的游戏完全分开，互不影响）。缺点是要下 **35 GB 左右**，比较久，记得留够硬盘空间。默认装到 `C:\cs2server`，想换位置就选 3。

**选 3** 则是所有选择都交给你：装到哪种环境、哪个目录、装不装 StripperSharp、是全新安装还是只检查一下。

### 选 1（做地图）之前，关于 VAC

它会改动你正在玩的那个 CS2（改一行配置 + 新增一个文件夹）。先把结论说清楚：

**做地图和本地测试，VAC 根本不参与，没有风险。**

- 用 Workshop Tools 做地图（`-tools`）时，游戏不在 VAC 会话里
- 自己在本地开图测试同理，那不是「受 VAC 保护的服务器」
- 想更保险的话，可以在 Steam 里右键 CS2 → 属性 → 启动选项，填上 `-insecure`（明确关掉 VAC）

所以你按正常流程做地图、测地图，完全不用担心。

**唯一需要注意的是：** 别拿这份改过的游戏去打**官方竞技匹配**或者连**别人的正式服务器**。倒不是说一定会出事，而是没必要 —— 你在那种场合本来也用不上 ModSharp。

**想彻底还原？** 两个办法：把脚本自动备份的 `gameinfo.gi.bak` 覆盖回 `gameinfo.gi`，或者在 Steam 里对 CS2 点「验证游戏文件完整性」。

> 如果你就是不想动自己的游戏，那就选 **2（开服务器）**，它下载一套完全独立的服务器程序，和你的游戏一点关系都没有。

---

## 装完以后

### 启动

**装到自己游戏里的（选了 1）：直接从 Steam 启动就行**，ModSharp 会自动加载，不用敲任何命令。

- **做地图**：Steam 库里右键 CS2 → 启动时选「Workshop Tools」
- **测试地图**：正常启动游戏，进去后在控制台执行 `map 你的地图名`

**装了独立服务端的（选了 2）：** 装完屏幕上会给你完整命令，大概长这样：

```powershell
Set-Location "C:\cs2server\game\bin\win64"
.\cs2.exe -dedicated +map de_dust2
```

⚠️ **第一行不能省。** ModSharp 是按「当前工作目录」去找自己的文件的，目录不对就加载不到（服务器能开起来，但模块一个都不工作）。

### 东西都装哪了

装完在 `game\sharp` 里，你平时可能会碰的就这几个：

| 文件夹 | 放什么的 |
|---|---|
| `configs` | 配置文件，改设置来这里 |
| `modules` | 模块放这里 |
| `stripper` | StripperSharp 的地图修改配置放这里 |

其它文件夹是程序本体，不用管。

> 做地图的还会多一个 `content\sharp` 文件夹（和 `game` 平级）。Workshop Tools 要靠它才能正常启动，**别删**。

### 想更新？再跑一次那条命令

想升级到最新版，**把开头那条命令再跑一遍**就行，它会自动更新。

你改过的配置、装的第三方模块、stripper 配置**都会保留**，不会被覆盖。

> 💡 CS2 每次更新之后，ModSharp 可能会失效（游戏更新会把配置改回去）。这时候也是**再跑一次**就修好了。

---

## 遇到问题了？

### 提示「无法加载文件，因为在此系统上禁止运行脚本」

你的 PowerShell 禁止运行脚本。用这条命令跑（只对这一次生效，不改你的系统设置）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/kxnrl/ms-install-script/master/install.ps1 | iex"
```

### 卡在「正在获取部署核心」不动

在连 GitHub，国内网络可能连不上。挂个代理再试，或者等 30 秒它会自己报错并告诉你怎么手动处理。

### 下载 CS2 特别慢 / 中途断了

正常，35 GB 确实慢。断了也不要紧，**再跑一次那条命令会接着下**，不会从头开始。

### 服务器开起来了，但输入 `ms` 没反应

按顺序检查：

1. 如果你是**自己敲命令**启动的：启动前**有没有先切换到 `game\bin\win64` 文件夹**（最常见的原因）。从 Steam 启动的不用管这个
2. 再跑一次那条命令，让它检查一遍缺了什么
3. 还不行就看它最后那张检查表，哪一项是红的，照着提示做

### Workshop Tools 打不开 / 一启动就报错

多半是缺了 `content\sharp` 这个文件夹。再跑一次开头那条命令，它会自动建好。

### 更新的时候提示文件被占用

**先把游戏和服务器完全关掉**再更新。开着的时候文件改不了。

### 提示「驱动器不存在」

路径里的盘符打错了，或者那是个没连上的网络硬盘。换个路径再试。

### 提示配置文件编码不对

你的 `gameinfo.gi` 以前被人用记事本改过、存成了老编码。脚本不敢乱动它（硬改会把里面的中文变成乱码）。

解决办法：在 Steam 里对 CS2 点「验证游戏文件完整性」，让它恢复成原版，然后重新运行脚本。

### 数据库连接报错

`AdminCommands.SQLStorage` 这个模块默认是**关着的**，因为它要连数据库。如果你手动开了它，需要先在 `configs\core.json` 里填上真实的数据库地址。不用的话不用管。

### 还是搞不定

把整个窗口的内容截图或复制，发到 [ModSharp 的 Discord](https://discord.gg/wKarAjHm2G) 问一下。

---

## 需要什么条件

- **Windows 系统**（64 位，Win10 及以上）
- 开服的话，硬盘留 **60 GB** 以上；只是做地图测试的话留 2 GB 就够
- 装的过程中可能会弹一次「是否允许此应用更改你的设备」，点是就行（那是在装一个微软的运行库）

别的都不用准备，脚本会自己处理。

---

<details>
<summary><b>📦 进阶用法（会用命令行的人再看）</b></summary>

### 直接用核心脚本

开头那条命令跑的是 `install.ps1`，它只是替你选好参数；真正干活的是 `Install-CS2Server.ps1`。

跑过一次之后，核心脚本就存在 `%LOCALAPPDATA%\ms-install-script` 里了，可以直接调用它，自己控制每一项：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\ms-install-script\Install-CS2Server.ps1"
```

不带参数就是完整的中文向导（等同于在那条命令的菜单里选 3）。下面的例子为了好读，都简写成 `.\Install-CS2Server.ps1`。

### 参数

| 参数 | 说明 |
|---|---|
| `-Target` | `Dedicated`（独立服务端）或 `Game`（你已装的游戏） |
| `-InstallDir` | 安装目录；Game 模式不填会自动找 |
| `-Mode` | `Install` / `Update` / `Verify`（只检查不动文件） |
| `-SteamCmdDir` | SteamCMD 存放目录，默认在安装目录旁边 |
| `-DotNetChannel` | .NET 运行时版本，默认 `10.0` |
| `-ModSharpTag` | 装指定版本的 ModSharp，如 `git-137` |
| `-StripperTag` | 装指定版本的 StripperSharp，如 `v13` |
| `-SkipCs2` | 不下载 CS2 本体 |
| `-SkipStripper` | 不装 StripperSharp |
| `-WithStripper` | 一定要装 StripperSharp，不询问 |
| `-SkipDotNet` | 不装 .NET 运行时 |
| `-NonInteractive` | 全程不提问，适合自动化 |
| `-AcceptGameRisk` | 预先同意改动自己的游戏（仅 Game 模式） |
| `-Force` | 强制重装 .NET 运行时 |
| `-LoadOnly` | 只加载函数不执行，供测试用 |

```powershell
# 全新装一套服务端
.\Install-CS2Server.ps1 -Target Dedicated -Mode Install -InstallDir C:\cs2server

# 只检查现有安装完不完整
.\Install-CS2Server.ps1 -Target Dedicated -Mode Verify -InstallDir C:\cs2server

# 钉住某个版本
.\Install-CS2Server.ps1 -Target Dedicated -InstallDir C:\cs2server -ModSharpTag git-137

# 无人值守
.\Install-CS2Server.ps1 -Target Dedicated -InstallDir C:\cs2server -NonInteractive
```

### 仓库里都有什么

```text
install.ps1                 ← 一条命令跑的就是它，问你一句然后调用下面的核心脚本
Install-CS2Server.ps1       核心脚本，所有实际逻辑都在这里
README.md / README.en.md
```

真正干活的只有 `Install-CS2Server.ps1` 一个文件，`install.ps1` 只是替你选好参数的薄包装。

### 关于 Install 和 Update

这两个模式**实际行为完全一样** —— 脚本永远按目标目录的真实状态做事，所以重复运行永远安全，也永远保留你的配置。模式名只是让输出好读一点。

想完全无人值守（计划任务 / CI）请用核心脚本加 `-NonInteractive`。一条命令的方式刻意不传这个开关，因为要保留「缺运行库时弹窗帮你装」这一步。

### 更新时的文件处理规则

| 目录 | 怎么处理 |
|---|---|
| `bin` `core` `shared` `gamedata` `locales` | 覆盖为新版 |
| `modules\<官方模块>` | 覆盖为新版；**不删**你自己装的第三方模块 |
| `configs\core.json`、`admins.jsonc` | **保留你的**，新版另存为 `.new` |
| `configs\*.example` | 覆盖（模板文件） |
| `data` `logs` `temp` `stripper` `runtime` | **完全不动** |

### 自检查什么

装完会输出一张检查表（10 项；装了 Workshop Tools 的机器多一项 `content\sharp`），涵盖：CS2 本体、游戏配置是否改好、ModSharp 各部分文件、.NET 运行环境、系统运行库、StripperSharp。每项没过都会告诉你具体怎么办。

### 手工装的话要做什么

不用这个脚本的话，你需要：装系统运行库 → 装 SteamCMD 拉服务端 → 装 .NET 10 **运行时**（而且必须装在特定位置，否则 ModSharp 找不到）→ 改 `game/csgo/gameinfo.gi` 在 `SearchPaths` 里加一行 `Game sharp` → 下载 ModSharp 的 Release 解压到 `game` → 下载 StripperSharp **合并**进去（直接覆盖会冲掉前面的文件）→ 启动时必须先切到 `game/bin/win64` 目录。

其中「.NET 装哪」和「配置怎么改」是翻车最多的两步。

</details>

---

## 相关链接

- [ModSharp](https://github.com/Kxnrl/modsharp-public) · [官方文档](https://docs.modsharp.net/) · [快速上手](https://docs.modsharp.net/docs/zh-cn/guides/getting-started.html)
- [StripperSharp](https://github.com/Kxnrl/StripperSharp) · [怎么用](https://github.com/fyscs/cs2/blob/master/.fys/Stripper.md)
- [Discord 社区](https://discord.gg/wKarAjHm2G)
