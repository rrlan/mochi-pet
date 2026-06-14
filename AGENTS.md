# Mochi (desk-pet)

> 战略规划与决策记录（人看的）：Obsidian `10_Projects/Mochi桌面宠物/`
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
├── main.swift          # NSApplication 入口，.accessory 策略
├── AppDelegate.swift    # 建窗口、host SwiftUI、菜单栏
├── PetWindow.swift      # borderless nonactivating NSPanel + 鼠标处理
├── PetState.swift       # ObservableObject，渲染的单一事实源
├── PetController.swift   # 大脑：idle↔walk↔sleep 状态机 + 交互反应
└── PetView.swift        # SwiftUI 形象（blob/脸/表情/气泡）
```

数据流：`PetController` 改 `PetState` → `PetView` 是其纯函数。加行为 = 加 `PetAction` case + 在 controller 驱动 + 在 view 渲染。换肤 = 改 `PetView.swift` 的 `Palette` 与 shape。

## Conventions

- 保持**无美术素材**（矢量形状），除非做 opt-in 的自定义 sprite/主题系统。
- 保持**轻量**：除动画进行中（如走路），不要用高频定时器。
- 注释风格、结构与现有代码一致；一个 PR 一个聚焦改动；视觉改动附截图/短片。
- 提交信息：祈使句，必要时带 Co-Authored-By。

## Boundaries

- 不直接 push 到 main；不动 CI 配置（暂无）。
- 删文件 / 重置分支 / force push 前必须确认。
- **实质产出（架构决策 / 路线变更 / 复盘）回写 vault** `10_Projects/Mochi桌面宠物/`：里程碑写 `journal/`，分叉拍板写 `decisions/`，并更新 MOC 的「下一步」和 `last_review`。

## Context

- 战略与路线图：vault `10_Projects/Mochi桌面宠物/plan.md`
- 历史决策：vault `10_Projects/Mochi桌面宠物/decisions/`
- 可用 AI CLI（P4 联动）：`claude`、`codex`、桥接 `~/.agents/bin/claudecode`
