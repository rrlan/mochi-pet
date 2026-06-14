<div align="center">

# 🍡 Mochi — 桌面上的 AI 编程伙伴

**一只常驻 macOS 桌面的小宠物，实时映射你的 Claude Code / Codex 会话 —— 形象还能随你换。**

<img src="assets/mochi-hello.png" width="460" alt="默认薄荷史莱姆，以及换成自定义猫咪形象的样子"/>

默认纯代码绘制 · 形象可更换 · 无需完整 Xcode · 原生、几 MB 内存

</div>

---

## 能做什么

- 🟢 **常驻桌面** —— 透明、置顶、不抢焦点的小浮窗，浮在其它窗口之上。
- 😴 **有自己的小生活** —— 会呼吸、眨眼、在桌面溜达、蹦跳、东张西望、打盹。
- 🖱️ **可交互** —— 拖到任意位置（会记住），戳一下有反应，还能让它**跟随鼠标**。
- 🤖 **映射你的 AI 会话** —— 每个正在跑的 Claude Code / Codex 会话，在它头顶显示一个气泡（写着项目名 + 正在干什么）；**点气泡直接跳回那条会话**，跑完后气泡还会保留几分钟、仍可点。
- 📝 **快速备忘** —— 双击宠物弹出动作面板，直接打字回车存进 Apple 备忘录，或打开 Claude / Codex。
- 🎨 **形象可更换** —— 默认是纯代码画的薄荷史莱姆；也能导入自己的图片，或用几张参考图生成一套多状态形象包（上图右边的猫咪，就是换过的自定义形象）。
- ⚙️ **无需完整 Xcode** —— 只用 Command Line Tools，一条 `swiftc` 命令构建。

## 快速开始

需要 macOS 13+ 和 Xcode **Command Line Tools**（`xcode-select --install`），**不需要**完整 Xcode。

```bash
git clone https://github.com/rrlan/mochi-pet.git desk-pet
cd desk-pet
./run.sh           # 构建（如需）并启动
```

菜单栏会出现 🍡 图标，Mochi 出现在你光标所在屏幕的底部附近。

只构建不运行：

```bash
./build.sh         # 产出 build/Mochi.app
open build/Mochi.app
```

退出：菜单栏 🍡 → **退出 Mochi**，或 `pkill -x Mochi`。

## 怎么用

| 操作 | 方式 |
| --- | --- |
| 移动 | 拖动它（位置会被记住） |
| 戳一下 | 单击它（或菜单 → 戳一下） |
| 跳回某个会话 | 点它头顶对应会话的气泡 |
| 动作面板 | 双击它（打开 Claude / Codex、直接写备忘） |
| 跟随鼠标 | 菜单 → 跟随鼠标（开关） |
| 导入形象 | 菜单 → 形象 → 导入形态图片… |
| 恢复默认形象 | 菜单 → 形象 → 恢复默认 Mochi |
| 睡觉 / 起床 | 菜单 → 睡觉 / 起床（或戳醒睡着的它） |
| 隐藏 / 显示 | 菜单 → 隐藏 / 显示 |
| 退出 | 菜单 → 退出 Mochi |

备忘会追加到名为 `Mochi Memos` 的 Apple 备忘录笔记里。Mochi 不会把备忘内容发给任何 AI 服务。

## 换形象

Mochi 默认是纯代码绘制的薄荷史莱姆。你可以把它的桌面形象换成自定义形象包，窗口、气泡、拖动、双击、AI 感知都不变。支持五个图片槽位：

| 槽位 | 文件名关键词 | 何时显示 |
| --- | --- | --- |
| `companion` | `陪伴` / `默认` / `companion` / `idle` | 待机、走路、被拖、被戳 |
| `work` | `工作` / `忙` / `思考` / `work` / `busy` | AI 在跑 / 思考时 |
| `rest` | `休息` / `睡` / `rest` / `sleep` | 睡眠 |
| `slack` | `摸鱼` / `发呆` / `slack` | 短暂偷懒 |
| `drag` | `拖动` / `站立` / `drag` | 被拖动时 |

手动导入：菜单 **形象 → 导入形态图片…**，选一张或多张图。Mochi 按文件名关键词匹配槽位，否则按顺序填入。图片存到 `~/.mochi/appearances/`。

也可以从少量参考图生成一套：

```bash
./tools/generate_appearance_pack.py \
  --image /path/to/cat-1.png \
  --image /path/to/cat-2.png \
  --install
```

它会生成 `companion/work/rest/slack/drag.png`，并在加 `--install` 时装到 `~/.mochi/appearances/`。需要本地的 Codex 图像生成 CLI，且设了 `OPENAI_API_KEY` 才会真正生成，否则只打印计划（dry-run）。

## 联动 Claude Code / Codex

Mochi 会对你的 AI 编程会话做出反应：有 agent 在跑时显示忙碌气泡，跑完弹通知。

### 自动（推荐）—— 桌面版也支持

Mochi **自动监听** agent 写的会话 transcript 文件，无需任何配置：

- Claude Code → `~/.claude/projects/**/*.jsonl`
- Codex → `~/.codex/sessions/**/*.jsonl`

文件在增长 = 该 agent 正在这一轮；安静下来 = 这一轮结束。这是**唯一**能覆盖所有形态的方式 —— CLI、ACP、以及**桌面版（Claude Code desktop、Codex App）**，后者不触发 shell hooks。

气泡按会话显示，写着**项目名** + 颜色圆点（🟠 Claude，🔵 Codex）+ 正在干什么，例如 `desk-pet · 运行 swift build`。**点气泡跳回那条会话**（`claude://resume` / `codex://threads`）；跑完后气泡保留几分钟、仍可点。Claude 和 Codex 分开计数，两个一起跑时各显示一个气泡，直到都结束。

菜单开关：**感知 AI 工作**。注意：Claude Code 的*沙箱* Cowork 模式可能把 transcript 写在沙箱内、`~/.claude/projects` 之外，那种情况从外部检测不到。

### 手动 / 显式（`mochi` CLI + hooks）

也可以显式驱动。`mochi` CLI（在 `bin/`）写事件，Mochi 读。先把它放到 `PATH`：

```bash
ln -sf "$PWD/bin/mochi" /usr/local/bin/mochi
```

```bash
mochi busy claude          # 某来源开始工作
mochi done claude          # 某来源结束 → 通知
mochi say "构建通过了"      # 让它说一句
mochi alert "需要 review"  # 警告 + 通知
```

接进 Claude Code（`~/.claude/settings.json`）：

```json
{
  "hooks": {
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "mochi busy claude" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "mochi done claude" }] }]
  }
}
```

接进 Codex（`~/.codex/config.toml`）：

```toml
notify = ["mochi", "done", "codex"]
```

> 用了显式 hooks，就把对应工具的**自动监听关掉**（菜单 → 感知 AI 工作），否则会重复触发。

## 工作原理

Mochi 用 **AppKit** 的应用生命周期（不是 SwiftUI 的 `App`）来掌控一个无边框、不激活、透明的浮动面板；宠物形象本身是 **SwiftUI**，host 在这个面板里。状态是单一事实源：`PetController` 改 `PetState`，`PetView` 是它的纯函数；默认形象、脸、气泡都是矢量图形，自定义形象包是 app 外的可选用户数据。

## License

[MIT](LICENSE) © 2026 rrlan
