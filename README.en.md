**English** | [简体中文](README.md)

# ms-install-script

**One-click installer that sets up ModSharp and StripperSharp for CS2.**

No SteamCMD setup, no config file editing, no following a 20-step guide — one command and it handles the rest.

> ⚠️ **Heads up: the installer's interface is in Chinese.** The script itself works perfectly regardless of your Windows language, but everything it prints is Chinese. See [Reading the Chinese output](#reading-the-chinese-output) below for a cheat sheet — you only need to recognise about six lines.

---

## Install

Open **PowerShell**, paste this one line, press Enter:

```powershell
irm https://raw.githubusercontent.com/kxnrl/ms-install-script/master/install.ps1 | iex
```

It asks you one question — making maps, or running a server — and then does everything else.

Afterwards:

- **Making maps**: just launch the game from Steam, nothing to type
- **Running a server**: copy-paste the command it prints

Once you're in the game (or the server is up), type `ms` in the console. If you see a version number, everything works.

> To skip the question and pick directly:
> ```powershell
> & ([scriptblock]::Create((irm https://raw.githubusercontent.com/kxnrl/ms-install-script/master/install.ps1))) mapper
> ```
> Replace `mapper` with `server` or `custom`.

---

## What that one question is

```
  [1] 做地图      —— install into your existing CS2, nothing extra to download
  [2] 开服务器    —— download a separate standalone server (~35 GB)
  [3] 自定义      —— choose everything yourself
```

**Making maps: pick 1.** It installs into the CS2 you already have — nothing extra to download, done in a few minutes. You can then iterate on your map and test it immediately, and with StripperSharp you can change entities in a map without recompiling it.

**Running a server: pick 2.** It downloads a completely separate copy of the server software, fully isolated from the game you play. The downside is roughly **35 GB**, so make sure you have the disk space and some patience. It installs to `C:\cs2server` by default — pick 3 if you want it elsewhere.

**Pick 3** to decide everything yourself: which kind of install, which directory, whether to include StripperSharp, fresh install or just a check.

### Before picking 1 (making maps): about VAC

It modifies the CS2 you actually play (one config line plus one new folder). The important part first:

**Making maps and testing locally does not involve VAC at all.**

- When you use Workshop Tools (`-tools`) to build maps, the game isn't in a VAC session
- Loading a map locally to test it is the same story — that isn't a **VAC-secured server**
- If you want to be extra safe, right-click CS2 in Steam → Properties → Launch Options and add `-insecure` to disable VAC explicitly

So going about your normal map-making workflow is fine.

**The one thing to avoid:** don't take this modified copy into **official matchmaking** or onto **someone else's live server**. Not because something is guaranteed to happen, but because there's no reason to — you wouldn't be using ModSharp there anyway.

**To fully revert:** either copy the `gameinfo.gi.bak` the installer made back over `gameinfo.gi`, or right-click CS2 in Steam → Properties → Installed Files → **Verify integrity of game files**.

> If you'd rather not touch your game at all, pick **2 (server)** — it downloads its own independent copy and never touches your installation.

---

## Reading the Chinese output

You only need to recognise a handful of lines:

| You'll see | It means |
|---|---|
| `[ OK ]` | This check passed |
| `[FAIL]` | This check failed — a suggestion follows on the next line |
| `[WARN]` | Warning, not fatal |
| `输入 y 继续, 其他任意键取消` | Type `y` and Enter to continue, anything else cancels |
| `请输入安装目录 (回车 = C:\cs2server)` | Enter an install directory, or just press Enter for the default |
| `自检全部通过` | All checks passed 🎉 |
| `部署完成, 祝你玩得开心` | Done — have fun |
| `出错了` | Something went wrong; the reason is printed underneath |
| `再跑一次那条安装命令` | Just run the one-liner again |

The self-check table at the end lists 10 items (11 if you have Workshop Tools installed). If they're all `[ OK ]`, you're good.

---

## After it's installed

### Starting it

**If you installed into your own game (picked 1): just launch from Steam.** ModSharp loads automatically — no commands to type.

- **Making maps**: right-click CS2 in your Steam library → choose **Workshop Tools** when launching
- **Testing a map**: launch the game normally, then run `map yourmapname` in the console

**If you installed a standalone server (picked 2):** the installer prints the full command. It looks roughly like this:

```powershell
Set-Location "C:\cs2server\game\bin\win64"
.\cs2.exe -dedicated +map de_dust2
```

⚠️ **Don't skip the first line.** ModSharp locates its own files relative to the *current working directory*, so if that's wrong it simply won't load (the server starts fine, but no module does anything).

### Where everything went

Everything lives under `game\sharp`. These are the only folders you're likely to touch:

| Folder | What's in it |
|---|---|
| `configs` | Configuration files — change settings here |
| `modules` | Modules go here |
| `stripper` | StripperSharp's map-editing configs go here |

The rest is the program itself; leave it alone.

> If you make maps, there's also a `content\sharp` folder (next to `game`). Workshop Tools needs it to start properly — **don't delete it**.

### Updating: just run that command again

To update to the latest version, **run the same one-liner again**. It updates in place.

Your edited configs, third-party modules and stripper configs are **all preserved**.

> 💡 After a CS2 update, ModSharp may stop working (game updates reset the config file). Same fix — **run it again**.

---

## Troubleshooting

### "running scripts is disabled on this system"

Your PowerShell blocks scripts. Use this instead (affects this one run only, doesn't change your system settings):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/kxnrl/ms-install-script/master/install.ps1 | iex"
```

### Stuck at `首次运行, 正在获取部署核心`

It's fetching from GitHub. If your network can't reach it, use a proxy — or wait 30 seconds and it will fail with instructions for doing it manually.

### The CS2 download is very slow / got interrupted

Normal — it's 35 GB. If it breaks off, **just run the command again**; it resumes rather than starting over.

### Server runs but typing `ms` does nothing

In order:

1. If you launched it **yourself from a shell**: did you **switch into `game\bin\win64` first**? (most common cause by far). Not relevant if you launched from Steam
2. Run the command again and let it re-check what's missing
3. Still nothing — look at the final check table and act on whichever line is red

### Workshop Tools won't open / errors on startup

Most likely the `content\sharp` folder is missing. Run the one-liner again and it will create it.

### "file is in use" during an update

**Fully close the game and stop any running server** first. Files can't be replaced while they're open.

### "驱动器不存在" (drive does not exist)

The drive letter in your path is wrong, or it's a network drive that isn't connected. Use a different path.

### Complaint about the config file encoding

Your `gameinfo.gi` was edited with Notepad at some point and saved in a legacy encoding. The installer refuses to touch it, because rewriting it would turn the existing text into garbage.

Fix: in Steam, right-click CS2 → Properties → Installed Files → **Verify integrity of game files** to restore the original, then run the installer again.

### Database connection errors

The `AdminCommands.SQLStorage` module ships **disabled** because it needs a database. If you enabled it yourself, fill in a real connection string in `configs\core.json` first. Otherwise you can ignore it.

### Still stuck

Copy or screenshot the whole window and ask in the [ModSharp Discord](https://discord.gg/wKarAjHm2G).

---

## Requirements

- **Windows** (64-bit, Windows 10 or newer)
- For a server: **60 GB+** free disk space. For map testing only: 2 GB is plenty
- You may get one UAC prompt ("Do you want to allow this app to make changes?") — that's a Microsoft runtime library being installed. Click yes

Nothing else to prepare; the installer handles it.

---

<details>
<summary><b>📦 Advanced usage (command line)</b></summary>

### Using the core script directly

The one-liner runs `install.ps1`, which just picks the options for you. The real work is done by `Install-CS2Server.ps1`.

Once you've run it, the core script lives in `%LOCALAPPDATA%\ms-install-script` — call it directly for full control:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\ms-install-script\Install-CS2Server.ps1"
```

With no arguments it runs the full interactive wizard (same as picking 3 in the menu). The examples below abbreviate it to `.\Install-CS2Server.ps1` for readability.

### Parameters

| Parameter | Description |
|---|---|
| `-Target` | `Dedicated` (standalone server) or `Game` (your existing install) |
| `-InstallDir` | Install directory; auto-detected in `Game` mode if omitted |
| `-Mode` | `Install` / `Update` / `Verify` (check only, writes nothing) |
| `-SteamCmdDir` | Where to keep SteamCMD; defaults to next to the install dir |
| `-DotNetChannel` | .NET runtime channel, default `10.0` |
| `-ModSharpTag` | Pin a ModSharp version, e.g. `git-137` |
| `-StripperTag` | Pin a StripperSharp version, e.g. `v13` |
| `-SkipCs2` | Don't download the CS2 server files |
| `-SkipStripper` | Don't install StripperSharp |
| `-WithStripper` | Definitely install StripperSharp, don't ask |
| `-SkipDotNet` | Don't install the .NET runtime |
| `-NonInteractive` | Never prompt — for automation |
| `-AcceptGameRisk` | Pre-confirm modifying your own game (`Game` mode only) |
| `-Force` | Force-reinstall the .NET runtime |
| `-LoadOnly` | Load functions without running anything (for testing) |

```powershell
# Fresh standalone server
.\Install-CS2Server.ps1 -Target Dedicated -Mode Install -InstallDir C:\cs2server

# Only check an existing install
.\Install-CS2Server.ps1 -Target Dedicated -Mode Verify -InstallDir C:\cs2server

# Pin a specific version
.\Install-CS2Server.ps1 -Target Dedicated -InstallDir C:\cs2server -ModSharpTag git-137

# Unattended
.\Install-CS2Server.ps1 -Target Dedicated -InstallDir C:\cs2server -NonInteractive
```

### What's in the repo

```text
install.ps1                 ← what the one-liner runs; asks one question, then calls the core script
Install-CS2Server.ps1       the core script — all the actual logic lives here
README.md / README.en.md
```

Only `Install-CS2Server.ps1` does real work; `install.ps1` is a thin wrapper that presets its arguments.

### About Install vs Update

These two modes **behave identically**. The script always acts on the actual state of the target directory, so re-running is always safe and always preserves your configs. The mode name only affects how the output reads.

For fully unattended runs (scheduled tasks / CI), use the core script with `-NonInteractive`. The one-liner deliberately doesn't pass it, so that the "install the missing runtime for you" UAC step still works.

### What gets overwritten on update

| Directory | Handling |
|---|---|
| `bin` `core` `shared` `gamedata` `locales` | Overwritten |
| `modules\<official module>` | Overwritten; your own third-party modules are **never deleted** |
| `configs\core.json`, `admins.jsonc` | **Yours is kept**; the new version is saved as `.new` |
| `configs\*.example` | Overwritten (templates) |
| `data` `logs` `temp` `stripper` `runtime` | **Never touched** |

### What the self-check verifies

10 items (11 with Workshop Tools installed): the CS2 binary, whether the game config was patched correctly, each part of ModSharp, the .NET runtime, the system runtime library, StripperSharp, and — on machines with Workshop Tools — the `content\sharp` directory. Every failure comes with a specific suggested fix.

### Doing it by hand

Without this installer you'd need to: install the system runtime → install SteamCMD and pull the server files → install the .NET 10 **runtime** (into one specific location, or ModSharp won't find it) → edit `game/csgo/gameinfo.gi` to add `Game sharp` inside `SearchPaths` → download the ModSharp release and extract it into `game` → download StripperSharp and **merge** it in (a plain overwrite clobbers files from the previous step) → and always `cd` into `game/bin/win64` before launching.

The .NET location and the config edit are where people get stuck most often.

</details>

---

## Links

- [ModSharp](https://github.com/Kxnrl/modsharp-public) · [Documentation](https://docs.modsharp.net/) · [Getting started](https://docs.modsharp.net/docs/en-us/guides/getting-started.html)
- [StripperSharp](https://github.com/Kxnrl/StripperSharp) · [Usage](https://github.com/fyscs/cs2/blob/master/.fys/Stripper.md)
- [Discord](https://discord.gg/wKarAjHm2G)
