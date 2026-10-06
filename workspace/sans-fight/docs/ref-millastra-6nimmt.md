# 参考仓库学习笔记：nightingale-0/millastra-6nimmt

> 来源：<https://github.com/nightingale-0/millastra-6nimmt>（《6 nimmt! 牛头王》千星奇域版，纯 UI + Lua + 服务端节点图）。
> 本机快照：`D:\stars\workspace\_refs\millastra-6nimmt`（`git clone --depth 1`）。
> 读的是 `AGENTS.md` / `README.md` / `scripts/build.mjs` / `lua/client.lua` / `tests/simulator.test.mjs`。

这份仓库和我们的做法**结构完全不同**，但踩过的坑高度重合，所以直接拿来当"真机经验"用。

## 1. 它的制作方式（值得抄的骨架）

| 环节 | 6nimmt 的做法 | 我们的现状 |
|---|---|---|
| 界面来源 | **不手摆控件**：`scripts/build.mjs` 里的 `rect()/text()/card()` 等函数生成整套控件模板，控件**有名字**（`Background`/`Hand1`/`ResultReason`…） | 我们只有 7 个图元模板，全部运行时 `InstantiateClientUIControl` + 摆位 |
| 脚本挂载 | 只导出 `six/main` 一条，客户端 `root:FindChild(name)` 取控件 | 我们挂 `boot` + 3 条路径模块（本轮已改成单条内联，见下） |
| 逻辑真值 | `lua/core.lua` 纯规则引擎，节点图与它行为对照 | 我们 `lua/core.lua` 同理（+ `core_selftest`） |
| 回归 | `tests/simulator.test.mjs`：`createStudio(save)` → `playStart/playClick/playStep` → `renderScenePng` | 我们的 `tools/play-capture.mjs` 是同一套（本轮已对齐） |

## 2. 直接采纳进本项目的四条真机经验

### 2.1 客户端 Lua 沙箱**没有 `require`**（最重要）
> 原文：「The official client Lua sandbox has no `require` global (confirmed against the sandbox…
> six/main must not depend on cross-script `require('six/core')` resolving at runtime, so it carries
> its own tiny module table + local `require` shim and inlines core.lua unmodified inside it.」

我们原来 `boot.lua` 里是 `pcall(require, 'default_import_file/workspace/sans-fight/lua/main')` —— 在模拟器里
没问题（studio 的 Lua VM 实现了 require），但**真机可能直接跑不起来**（boot 静默失败 → 只有黑屏）。

**改法**（`tools/build-save.mjs`）：挂载脚本改成**自足单文件**，自带模块垫片：

```lua
local __modules = {}
local function require(p) return __modules[p] end
__modules['default_import_file/workspace/sans-fight/lua/core']    = (function() …core.lua… end)()
__modules['default_import_file/workspace/sans-fight/lua/attacks'] = (function() …attacks.lua… end)()
__modules['default_import_file/workspace/sans-fight/lua/main']    = (function() …main.lua… end)()
local M = __modules['default_import_file/workspace/sans-fight/lua/main']
function OnInit() … end   -- 生命周期照旧转发
```

存档里现在**只有 1 条脚本**（约 208 KB），真机不再依赖路径解析。模拟器实测 `mode=core` 正常。

### 2.2 背景要比画布大
> `scripts/build.mjs`：`rect('Background',640,360,3840,2160,color.bg)`（1280×720 的 3 倍），
> 注释写着「21:9 screens the background must reach past the 1280x720 box to hide the world」。

我们照做：`bgPanel` 改成 `put(bgPanel, -CW, -CH, CW*3, CH*3)`（3 倍画布居中），宽屏也不露宿主底色。

### 2.3 真机的同级层叠顺序可能与模拟器相反
> 「同级控件的层叠顺序和模拟器可能相反：构建时输出 `LAYERS`，启动时用 `SetAsFirstSibling` 显式排序。」

我们原来完全依赖**创建顺序**。现在 `OnStart` 末尾显式钉住两头：
`bgPanel:SetAsFirstSibling()`（最底）、`flash:SetAsLastSibling()`（最上）；
池内控件仍按创建顺序（同池后取的在上，这条是 `drawBone`/`drawBlaster` 的层叠依据）。

### 2.4 旋转只能运行时设
> 「GIA 写不进旋转：要倾斜的控件在 Lua 里设 `localRotationZ`。」

我们本来就是运行时 `SetLocalRotation`（`rrect` 的 `spin()`），一致 —— 记录一下，防止以后有人想在 GIA 里存角度。

## 3. 其它记录（未采纳，供以后需要时查）

- **文字贴顶**：「文字只能贴框顶，框矮了整行不显示」→ 他们的 `textBox()` 按顶部定位、字框给足高。
  我们的 `HUD_W=340` 文本框够高，暂不需要改；以后加窄条文字要留意。
- **大 cursor 组吞点击**：「大的 `cursor` 组会吞掉点击：大面板用普通矩形。」
  我们的全屏 `cursorArea` 是**唯一**的指针接收面（`AddCursorEventListener` 只挂在 cursor 上），
  是刻意设计而不是误用；如果以后加"面板内单独可点"的区域，要改成普通矩形 + 精确命中。
- **退出/聊天在界面下面**：他们用外观相同的装饰牌盖住（点击穿透）。我们没用到这一层。
- **节点图预算**：编辑器节点数 ≈ 编译结果的 2.1 倍、上限 3000；单次执行负载上限约 4400。
  我们只有 Lua，没有服务端节点图，暂时无关。
