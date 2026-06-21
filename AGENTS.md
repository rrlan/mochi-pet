# Mochi (desk-pet)

> 对外文档：`README.md`

## Project Overview

Mochi 是一只 macOS 桌面宠物：透明、置顶、不抢焦点的浮窗，纯代码绘制的薄荷绿史莱姆，会呼吸/眨眼/溜达/睡觉，可拖动、可戳。长期目标是接入 `claude` / `codex` CLI，成为 AI 编程会话的桌面化身。

技术栈：Swift + SwiftUI（渲染）+ AppKit（窗口与生命周期）。

## Build / Run

只需 Xcode Command Line Tools（无需完整 Xcode）。

```bash
./build.sh     # swiftc 编译 + 组装 build/Mochi.app + ad-hoc 签名
./run.sh       # 构建（如需）并启动；菜单栏出现 🍡
pkill -x Mochi # 停止
```

无测试套件；改动靠运行 + 截图验证。多显示器时宠物出现在「光标所在屏幕」。

## Architecture

```
Sources/
├── main.swift            # NSApplication 入口，.accessory 策略
├── AppDelegate.swift      # 建 colony、host SwiftUI、菜单栏、reconcileColony()
├── PetColony.swift        # PetUnit：window+state+controller 一只猫的捆绑单元
├── PetWindow.swift        # borderless nonactivating NSPanel + 鼠标处理
├── PetState.swift         # ObservableObject，渲染的单一事实源
├── PetController.swift     # 大脑：idle↔walk↔sleep 状态机 + 交互；role=avatar/ambient
├── PetView.swift          # SwiftUI 形象（blob/脸/表情/气泡）
├── AppearanceStore.swift  # 形象包库（~/.mochi/packs/<slug>/）：active=主猫，roamers=氛围猫
└── AppearancePicker.swift # 选角面板（缩略图：点=主猫，爪印=出来逛，✕=删）
```

数据流：`PetController` 改 `PetState` → `PetView` 是其纯函数。加行为 = 加 `PetAction` case + 在 controller 驱动 + 在 view 渲染。

**多猫 colony**：一只猫 = 一个 `PetUnit`（独立窗口）。`avatar`（active pack）感知 agent、有气泡；`ambient`（roamer packs，≤4）只跑自主 roam/rest 循环。`AppDelegate.reconcileColony()` 按形象库的 active/roamer 增删氛围窗口；角色二选一（主猫不同时再做氛围猫）。换主猫形象 = 选角面板点缩略图；自定义形象包 = `~/.mochi/packs/`。改默认矢量 Mochi = `PetView.swift` 的 `Palette` 与 shape。

## Conventions

- 保持**无美术素材**（矢量形状），除非做 opt-in 的自定义 sprite/主题系统。
- 保持**轻量**：除动画进行中（如走路），不要用高频定时器。
- 注释风格、结构与现有代码一致；一个 PR 一个聚焦改动；视觉改动附截图/短片。
- 提交信息：祈使句，必要时带 Co-Authored-By。

## Boundaries

- 不直接 push 到 main；不动 CI 配置（暂无）。
- 删文件 / 重置分支 / force push 前必须确认。

## Context

- Mochi 监听 `~/.claude/projects` 与 `~/.codex/sessions` 的会话 transcript 感知 agent 工作；点气泡用深链（`claude://resume?session=…` / `codex://threads/…`）跳回对应桌面 App 的会话。
- 可显式联动的 AI CLI：`claude`、`codex`。
