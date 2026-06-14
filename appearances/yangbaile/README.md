# 杨百乐 — 示例形象包 🐈

这是 [@rrlan](https://github.com/rrlan) 的猫 **杨百乐** 的一套 Mochi 形象包，开箱即用，
欢迎直接拿去用。

| 文件 | 状态 |
| --- | --- |
| `companion.png` | 陪伴 · 待机（主形象） |
| `work.png` | 工作中（agent 在跑） |
| `rest.png` | 休息 · 睡觉 |
| `slack.png` | 摸鱼 |
| `drag.png` | 被拖动 |
| `walk/frame_00–05.png` | 走路逐帧动画 |

## 直接用

```bash
mkdir -p ~/.mochi/appearances
cp -R appearances/yangbaile/. ~/.mochi/appearances/
pkill -x Mochi    # 重启生效（再打开 Mochi 即可）
```

之后菜单 **形象 → 恢复默认 Mochi** 可随时换回纯代码的薄荷史莱姆。

> 这些图片随本仓库一同以 MIT 授权，随意使用。想做自己的形象包，照着这个文件名结构放图即可。
