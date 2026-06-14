<div align="center">

# 🍡 Mochi — a tiny desktop pet for macOS

**A cute desktop companion for macOS that mirrors your Claude Code & Codex sessions — and you can swap how it looks.**

<img src="assets/mochi-hello.png" width="460" alt="Mochi's code-drawn default look next to a custom cat appearance"/>

Code-drawn by default · Swappable looks · No Xcode required · ~Native, a few MB of RAM

[Features](#features) · [Quick start](#quick-start) · [How it works](#how-it-works) · [Roadmap](#roadmap) · [中文](#中文简介)

</div>

---

## Features

- 🟢 **Lives on your desktop** — a borderless, transparent, always-on-top window that floats above your other apps without stealing focus.
- 😴 **Has a life of its own** — breathes, blinks, strolls around, hops, looks around, and naps.
- 🖱️ **Interactive** — drag Mochi anywhere (it remembers where you left it); poke it and it reacts; or have it **follow your cursor**.
- 🎨 **Swappable looks** — use the built-in code-drawn Mochi, import your own images, or generate a multi-state appearance pack from a few reference images.
- 🧰 **Menu-bar controlled** — a 🍡 icon lets you poke it, put it to sleep, hide it, or quit.
- 🤖 **Mirrors your AI sessions** — shows a bubble for each running Claude Code / Codex session with what it's doing; **click one to jump straight back to that session**.
- 📝 **Quick memos** — double-click Mochi for an action panel (open an app, jot a note into Apple Notes).
- ⚙️ **No full Xcode needed** — builds with the Command Line Tools via a single `swiftc` invocation.

> **The bigger idea:** Mochi is the *face of your AI coding sessions* — it shows what each running agent is doing and lets you click straight back to any session, even for a few minutes after it finishes. See the [roadmap](#roadmap).

## Quick start

Requirements: macOS 13+ and the Xcode **Command Line Tools** (`xcode-select --install`). Full Xcode is *not* required.

```bash
git clone <your-fork-url> desk-pet
cd desk-pet
./run.sh           # builds (if needed) and launches Mochi
```

Look for the 🍡 icon in your menu bar. Mochi appears near the bottom of the screen your cursor is on.

To build without running:

```bash
./build.sh         # produces build/Mochi.app
open build/Mochi.app
```

To quit: use the menu-bar 🍡 → **退出 Mochi**, or `pkill -x Mochi`.

## Usage

| Action | How |
| --- | --- |
| Move Mochi | Click & drag it (its position is remembered) |
| Poke it | Click it once (or menu → 戳一下) |
| Jump to a running session | Click that session's status bubble above Mochi |
| Pick an action | Double-click Mochi |
| Open Codex | Double-click Mochi → Codex, or menu → 打开 Codex |
| Open Claude | Menu → 打开 Claude |
| Quick memo | Double-click Mochi, type directly, press Return; or menu → 快速备忘… |
| Open memos | Double-click Mochi → 备忘录, or menu → 打开备忘录 |
| Follow the cursor | Menu → 跟随鼠标 (toggle) |
| Import appearances | Menu → 形象 → 导入形态图片… |
| Open appearance folder | Menu → 形象 → 打开形态文件夹 |
| Reset appearance | Menu → 形象 → 恢复默认 Mochi |
| Sleep / wake | Menu → 睡觉 / 起床 (or poke a sleeping Mochi) |
| Hide / show | Menu → 隐藏 / 显示 |
| Quit | Menu → 退出 Mochi |

Memos are appended to an Apple Notes note named `Mochi Memos`. Mochi does not send memo text to any AI service.

## Custom appearances

Mochi can swap its desktop body for a custom appearance pack while keeping the
same window, speech bubble, dragging, double-click action panel, and agent
awareness.

The app supports five image slots:

| Slot | Filename keywords | Used when |
| --- | --- | --- |
| `companion` | `陪伴`, `日常`, `默认`, `companion`, `idle` | Idle, walking, dragging, being poked |
| `work` | `工作`, `干活`, `忙`, `思考`, `work`, `busy` | AI agents are working or Mochi is thinking |
| `rest` | `休息`, `睡`, `困`, `rest`, `sleep` | Sleep mode |
| `slack` | `摸鱼`, `偷懒`, `发呆`, `slack`, `lazy` | Short idle break moments |
| `drag` | `拖拽`, `拖动`, `拎`, `站立`, `drag`, `stand` | While the pet is being dragged |

To import images manually, choose **形象 → 导入形态图片…** from the menu and
select one or more images. Mochi matches them by filename keywords; otherwise it
fills the slots in order. Imported images are stored in `~/.mochi/appearances/`.

To generate a pack from limited reference images, use the helper:

```bash
./tools/generate_appearance_pack.py \
  --image /path/to/cat-photo-1.png \
  --image /path/to/cat-photo-2.png \
  --install
```

The helper creates `companion.png`, `work.png`, `rest.png`, `slack.png`, and
`drag.png`, then installs them into `~/.mochi/appearances/` when `--install` is
set. It uses the local Codex image-generation CLI if available and requires
`OPENAI_API_KEY` for actual generation; without that key it prints a dry-run
plan only.

## Pairing with Claude Code / Codex

Mochi reacts to your AI coding sessions: looks busy while an agent is working,
celebrates (and posts a notification) when it finishes, or relays any message.

### Automatic (recommended) — works with the desktop apps too

Mochi **auto-detects** working agents by watching the session transcript files
they write — no setup required:

- Claude Code → `~/.claude/projects/**/*.jsonl`
- Codex → `~/.codex/sessions/**/*.jsonl`

A transcript that's actively growing means that agent is mid-turn; when it goes
quiet, the turn is done. This is the **only** approach that works across *all*
surfaces — CLI, ACP, **and the desktop apps (Claude Code desktop, Codex App)**,
which do not fire shell hooks. (CPU can't be used — LLM generation is
network-bound, near-zero CPU.)

Mochi shows one bubble per running session, labeled with its **project folder**
and a colored dot (🟠 Claude, 🔵 Codex) plus **what the agent is doing** right
now — e.g. `desk-pet · 运行 swift build` or `mochi · 编辑 PetView.swift`.
**Click a session's bubble to jump straight back to it** (`claude://resume` /
`codex://threads`); a finished session's bubble stays clickable for a few
minutes. Claude and Codex are tracked separately, so when both run at once you
see a bubble for each and Mochi stays busy until both finish.

Toggle it from the menu: **感知 AI 工作**. Caveat: Claude Code's *sandboxed*
desktop mode (Cowork) may write its transcript inside the sandbox rather than to
`~/.claude/projects`, in which case it can't be detected from outside.

### Manual / explicit (the `mochi` CLI + hooks)

You can also drive Mochi explicitly. The `mochi` CLI (in `bin/`) writes events;
Mochi reacts. Put `mochi` on your `PATH` first:

```bash
ln -sf "$PWD/bin/mochi" /usr/local/bin/mochi   # or any dir on your PATH
```

Then anything can drive the pet:

```bash
mochi busy claude          # → that source starts working
mochi done claude          # → that source finished → notify
mochi say "build is green"  # → Mochi says it
mochi alert "needs review" # → Mochi warns + posts a notification
```

Mochi tracks each **source** separately, so if Claude Code and Codex run at
the same time it stays in "working" mode until *both* finish, and notifies you
per agent as each one completes.

**Wire it into Claude Code** (`~/.claude/settings.json`) — busy while a turn
runs, done when it stops:

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "mochi busy claude" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "mochi done claude" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "mochi alert 需要你看一下" }] }]
  }
}
```

**Wire it into Codex** (`~/.codex/config.toml`) for the completion signal:

```toml
notify = ["mochi", "done", "codex"]
```

> Codex's `notify` fires on turn completion (the "done" signal). It has no
> matching "start" event, so Codex shows up as a completion/notification rather
> than a sustained "working" animation unless you wrap the `codex` command
> yourself with `mochi busy codex` / `mochi done codex`.

> Notifications use `osascript display notification`, which needs notifications
> allowed for Script Editor (and Focus / Do Not Disturb off) to show a banner.
> The pet's own speech bubble always works regardless.

> If you use the explicit hooks above, turn **off** the auto-detection
> (menu → 感知 AI 工作) for that tool, or both will fire and you'll get
> double busy/done events.

## How it works

Mochi uses the **AppKit** application lifecycle (not the SwiftUI `App` lifecycle) so it can own a borderless, non-activating, transparent floating panel — which is much easier in AppKit. The character itself is **SwiftUI**, hosted inside that panel.

```
Sources/
├── main.swift            # entry point — NSApplication + .accessory policy
├── AppDelegate.swift      # builds the window, hosts SwiftUI, status-bar menu
├── PetWindow.swift        # borderless NSPanel + mouse handling (drag / poke / double-click)
├── PetState.swift         # observable model the view renders from
├── PetController.swift     # the "brain": idle ↔ walk ↔ sleep ↔ think state machine
├── PetView.swift          # the SwiftUI character (blob, face, expressions, bubble)
├── AppearanceStore.swift  # custom appearance import/storage
├── ActionPanel.swift      # double-click action picker
├── MemoInputPanel.swift   # the little floating text field for quick memos
├── MemoStore.swift        # appends quick memos to Apple Notes
├── MochiBridge.swift      # watches ~/.mochi/inbox.log for events from hooks/CLI
└── AgentMonitor.swift     # auto-detects working agents via their transcript files
```

Design principles:

- **State is the single source of truth.** `PetController` mutates `PetState`; `PetView` is a pure function of it. Adding a behavior means adding a state + a way to render it.
- **Built-in vector fallback.** The default blob, face, and bubble are vector shapes; custom appearance packs are optional user data stored outside the app bundle.
- **Interaction lives in AppKit.** `PetContainerView.hitTest` claims mouse events so SwiftUI never fights over them; clicks vs. drags are distinguished by movement.

## Roadmap

- [x] **P1 — Core pet:** floating window, breathing/blinking blob, drag, poke, menu bar.
- [x] **P2 — More life:** follow-the-cursor mode, more idle animations (hop, look-around), remembers its last position.
  - [ ] Further multi-monitor polish; sit on window edges / gravity.
- [ ] **P3 — Companion:** reminders (water / breaks / pomodoro / hourly chime) shown as speech bubbles + notifications.
- [ ] **P4 — AI pairing (the headline feature):**
  - [x] Jump to the *exact* Claude / Codex session from Mochi's bubbles via deep links (not just the app).
  - [x] React to live agent activity — a bubble per running session showing what it's doing; celebrate + notify when it finishes; finished sessions stay clickable for a few minutes.
  - [x] Quick local memos.
- [x] **Skinning:** import custom multi-state appearance images; generate a draft pack from limited references.
- [ ] **Packaging:** signed/notarized release, Homebrew cask.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Good first contributions: new idle animations, new expressions, a follow-cursor mode, or alternative characters/themes.

## License

[MIT](LICENSE) © 2026 yangran

---

## 中文简介

**Mochi 是一只 macOS 桌面小宠物** —— 一个透明、置顶、不抢焦点的小浮窗，会呼吸、眨眼、在桌面上溜达、睡觉；你可以拖它、戳它，它会有反应。默认形象是 SwiftUI 纯矢量图形（零图片素材、体积极小），也可以一键换成你自己的形象包。

它是**你 AI 编程会话的"具象化分身"**：每个在跑的 Claude Code / Codex 会话都会在它头顶显示一个气泡（写着项目名 + 正在干什么），**点一下气泡就能跳回那条会话**；跑完后气泡还会保留几分钟、仍可点。双击宠物则弹出动作面板（打开 App、记备忘）。

**构建无需完整 Xcode**，只要 Command Line Tools：

```bash
./run.sh    # 构建并启动，菜单栏会出现 🍡 图标
```
