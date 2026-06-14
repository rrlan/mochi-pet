<div align="center">

# 🍡 Mochi — a tiny desktop pet for macOS

**A cute, code-drawn companion that lives on your desktop — and (soon) pairs with Claude Code & Codex.**

<img src="assets/mochi-hello.png" width="280" alt="Mochi saying hello"/>

No image assets · No Xcode required · ~Native, a few MB of RAM

[Features](#features) · [Quick start](#quick-start) · [How it works](#how-it-works) · [Roadmap](#roadmap) · [中文](#中文简介)

</div>

---

## Features

- 🟢 **Lives on your desktop** — a borderless, transparent, always-on-top window that floats above your other apps without stealing focus.
- 😴 **Has a life of its own** — breathes, blinks, strolls around, hops, looks around, and naps.
- 🖱️ **Interactive** — drag Mochi anywhere (it remembers where you left it); poke it and it reacts; or have it **follow your cursor**.
- 🎨 **Drawn entirely in code** — the character is pure SwiftUI vector shapes, so the whole app is a few MB and trivially restyleable. No sprite sheets to ship.
- 🧰 **Menu-bar controlled** — a 🍡 icon lets you poke it, put it to sleep, hide it, or quit.
- 🤖 **Talks to Claude Code / Codex** — double-click Mochi, type a message, and it routes to the `claude` or `codex` CLI and shows the reply in its speech bubble (with a "thinking" animation while it waits). Switch engines from the menu.
- ⚙️ **No full Xcode needed** — builds with the Command Line Tools via a single `swiftc` invocation.

> **The bigger idea:** Mochi is the *face of your AI coding sessions*. Chatting already works; next it will react to live agent activity — animating while an agent runs and notifying you when it finishes. See the [roadmap](#roadmap).

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
| **Chat with it** | **Double-click it** (or menu → 跟 Mochi 说话…), type, press Return |
| Follow the cursor | Menu → 跟随鼠标 (toggle) |
| Forget the chat | Menu → 忘掉刚才的对话 |
| Pick AI engine | Menu → AI 引擎 → Claude / Codex |
| Sleep / wake | Menu → 睡觉 / 起床 (or poke a sleeping Mochi) |
| Hide / show | Menu → 隐藏 / 显示 |
| Quit | Menu → 退出 Mochi |

> **Chat requires** the `claude` and/or `codex` CLI on your `PATH`. Mochi invokes them through a login shell, so whatever works in your terminal works here. Replies are kept short and cute via a prompt wrapper.

## Pairing with Claude Code / Codex

Mochi can react to your AI coding sessions: look busy while an agent is working,
celebrate (and post a notification) when it finishes, or relay any message.

It listens on a tiny event channel. The `mochi` CLI (in `bin/`) writes events;
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
├── AIService.swift        # runs the claude / codex CLI off-main, returns the reply
├── ChatInputPanel.swift   # the little floating text field you talk to Mochi with
└── MochiBridge.swift      # watches ~/.mochi/inbox.log for events from hooks/CLI
```

Design principles:

- **State is the single source of truth.** `PetController` mutates `PetState`; `PetView` is a pure function of it. Adding a behavior means adding a state + a way to render it.
- **No assets.** The blob, face, and bubble are vector shapes — change `Palette` in `PetView.swift` to reskin.
- **Interaction lives in AppKit.** `PetContainerView.hitTest` claims mouse events so SwiftUI never fights over them; clicks vs. drags are distinguished by movement.

## Roadmap

- [x] **P1 — Core pet:** floating window, breathing/blinking blob, drag, poke, menu bar.
- [x] **P2 — More life:** follow-the-cursor mode, more idle animations (hop, look-around), remembers its last position.
  - [ ] Further multi-monitor polish; sit on window edges / gravity.
- [ ] **P3 — Companion:** reminders (water / breaks / pomodoro / hourly chime) shown as speech bubbles + notifications.
- [ ] **P4 — AI pairing (the headline feature):**
  - [x] Talk to Mochi via a small input; route to the `claude` / `codex` CLIs and show replies in the bubble, with a "thinking" animation.
  - [x] React to live agent activity — busy while an agent runs, celebrate + notify when it finishes (via the `mochi` CLI + hooks).
  - [ ] Conversation memory / multi-turn context.
- [ ] **Skinning:** swap the code-drawn character for custom sprites; a simple theme format.
- [ ] **Packaging:** signed/notarized release, Homebrew cask.

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). Good first contributions: new idle animations, new expressions, a follow-cursor mode, or alternative characters/themes.

## License

[MIT](LICENSE) © 2026 yangran

---

## 中文简介

**Mochi 是一只用纯代码画出来的 macOS 桌面小宠物** —— 一个透明、置顶、不抢焦点的小浮窗，会呼吸、眨眼、在桌面上溜达、睡觉；你可以拖它、戳它，它会有反应。整只宠物是 SwiftUI 矢量图形，没有任何图片素材，所以体积极小、换皮极简单。

它的长期目标是成为**你 AI 编程会话的"具象化分身"**：当 Claude Code / Codex 在思考时它会有反应，跑完任务会提醒你，你还能通过头顶气泡直接跟它们对话（见上方 Roadmap 的 P4）。

**构建无需完整 Xcode**，只要 Command Line Tools：

```bash
./run.sh    # 构建并启动，菜单栏会出现 🍡 图标
```
