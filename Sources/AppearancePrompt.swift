//
//  AppearancePrompt.swift
//  Mochi
//
//  A ready-to-paste prompt for generating a custom appearance pack with an
//  image model. Surfaced via 形象 → 复制生图 Prompt so anyone can grab it and
//  feed it to their favorite generator, then import the result as a pack.
//
//  The leading 铁律 block exists because models love to (1) pack every pose into
//  one contact sheet, (2) put it on a white background, and (3) bake in text
//  labels — all three break the import, so we forbid them up front.
//

enum AppearancePrompt {
    /// Copied to the clipboard by the menu action. Self-contained: hard rules,
    /// the five state poses, optional walk frames, and how to import the result.
    static let imageGen = """
    皮克斯 / 迪士尼 3D 动画电影风格的桌面宠物形象。

    【铁律·先看】
    - 一次只画一个姿势，一张图里只有一只猫。【绝对不要】把多个姿势拼进一张图，不要网格 / 连环图 / 九宫格 / 贴纸表。
    - 背景【真·透明】：输出带 alpha 通道的透明 PNG。【不要把灰白棋盘格、白底、或任何"透明效果"画进画面里】——那是假透明，贴到桌面会变成猫身后一个方块。不要背景、不要地面投影、不要描边。
    - 画面里【不要出现任何文字】：标签、文件名、帧号、说明、边框、水印都不要。
    - 全身入镜、居中、四周留白，不要裁到耳朵或脚。
    - 所有图保持【同一只猫】：同样的毛色花纹、脸、体型、配色、画风、镜头距离与大小。

    【角色】把参考图里的这只宠物（猫 / 狗 / 角色都行）做成可爱的皮克斯 3D 形象：又大又有神的眼睛、圆润讨喜的比例、柔软的次表面散射光、毛绒质感。（没有照片就描述：种类 / 花色 / 特征）

    【做法】先生成 companion 当基准，再把它当参考图，逐个生成其余状态——每次只说一个姿势，重复一句"和上一张同一只猫、同样画风、透明背景、画面无文字，现在是<某状态>"，一致性最好。

    【5 个状态·各生成一张】
    - companion（待机·主形象）：安静坐着，眼睛睁开、微微笑，正面略侧。
    - work（干活中）：趴或坐在一台小笔记本电脑前，前爪搭在键盘上，专注盯着屏幕，认真的小表情。
    - rest（睡觉）：蜷成一团闭眼打盹，放松安详。
    - slack（摸鱼）：四脚朝天或懒洋洋侧躺，发呆呆萌。
    - drag（被拎起）：身体竖直悬空、四肢自然下垂、前爪微抬，表情有点惊讶，像被拎在半空——【画面里不要画手或人】。

    【走路帧·可选·各生成一张·侧面朝右】
    身体 / 头 / 尾巴 / 大小 / 位置每帧【完全一致】，统一朝右，只有四条腿在变（否则循环会跳）。
    关键：相邻两帧必须是【相反的迈步相位】——把四条腿的前后位置整个对调，才会"交替迈步"而不是原地颠。
    最少 2 帧：帧1 一条前腿向前伸、另一条前腿收在身下，后腿相反；帧2 把每条腿的前/后【全部对调】（拿帧1当参考图，只改腿、其余不动）。
    想更顺滑出 4~6 帧：迈步 → 收拢过渡 → 反向迈步 → 再收拢。透明背景、画面无文字。

    【装进 app】状态图命名 companion/work/rest/slack/drag.png；走路帧命名 frame_00.png、frame_01.png… 放进 walk/ 子文件夹；把整个文件夹用「🍡 → 形象 → 导入形象包（文件夹）…」一次导入。
    """
}
