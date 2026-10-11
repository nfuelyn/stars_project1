# main 脚本备份 —— 2026-10-08「文本渲染修复」版

> 备份时间：2026-10-08 深夜
> 工程：`D:\stars\workspace\sans-fight`（构建标记 `2026-10-08-sandbox-adapter`）
> 备份原因：原生文本框在真机渲染不出字形 → 迁入交接包的 CodeArt 矩形字形 + 独立字形层

## 文件说明

| 文件 | 是什么 | 怎么用 |
|---|---|---|
| `main_built_千星导入用.lua` | **自足单文件包**（core+attacks+fitdata+music+**textart**+config+main 全部内联，841 084 B） | 直接覆盖 `...\Beyond_Local_Save_Level\1073741827\external_lua_file\main.lua`，或按脚本映射导入 |
| `main_source_适配层.lua` | `lua/main.lua` 源码（渲染适配层，150 477 B） | 改逻辑时改它，再跑重建 |
| `config.lua` | 环境配置（模板索引 / 更新回调 / `textMode` / `keyDiag` / `textProbe`） | 放回 `lua/config.lua` |
| `textart_矩形字形库.lua` | 交接包的矩形字形数据（323 112 B，`height=20`、16px 基准） | 放回 `lua/textart.lua`（构建时会被内联） |

## 校验值（SHA-256）

```
85C32E7FA8463950AFA77DF33C17167BE4C1D8D17E9F3F30D017DB333BEF8FCF  main_built_千星导入用.lua
DEAA6EF102554F68CF3D4E9FF661AB391001B628DAC8AA9EA2385F0855417BAA  main_source_适配层.lua
E78EEFA265C18C634A8B448291AA89B2914BF167FCE17BAD9601A4769072016B  config.lua
649B12AFCBB81003A44E1790B7F9B87DEC8AA7E1612BD0778FBFBB3B8287B9AB  textart_矩形字形库.lua
```

## 这一版包含的关键改动（按时间顺序）

1. **沙箱接轨层重写**：`script.object` 当 root；模板索引**候选列表**；容器包装模板**按叶子接口**判类型 + 拉伸包装层 + 叶子归一化；颜色走 `Color()`；`OnStart` 幂等；`OnDestroy` 摘监听（不再销毁控件）。
2. **接口类型修正**（真机日志实证）：`AddKeyEventListener` 要 `Enum.KeyEventType.*`、`AddCursorEventListener` 要 `Enum.CursorEventType.*`、
   `horizontalAlignment` 要 `Enum.TextHorizontalAlignment.*` —— 统一"先字符串、抛错再枚举"双通道；确认/取消改成**多来源聚合**（真机键盘枚举里没有 `KeyboardMenuConfirmKey`）。
3. **黑底两层铺满**：`bgPanel`（stretch 铺满 Root）+ `bgOver`（stretch、尺寸差 +2CW/+2CH 外扩）；`OnStart` 把 root 也拉成铺满画布。
4. **锚点/pivot 无条件归一化**（真机默认是 Unity 的中心锚点）：轴对齐件 (0,0)、旋转件 (0.5,0.5)、全屏件拉伸。
5. **CodeArt 像素块改绝对几何**：比例锚点 + `sizeDelta=0` 在真机不可靠 → 改为左下锚点 + 绝对位置 + 绝对尺寸（与战斗框/HUD 同一套 API）。
6. **文字改用 CodeArt 矩形字形**（本版重点）：
   - 原生文本框在本机**渲染不出字形**（白条能画、字段回读全对、几何正确、独立层置顶后仍无字 → 已排除写入/层级）；
   - `text()` 保留原签名，改走 `lua/textart.lua` 的字形配方（按 码点+颜色 缓存，`useBakedCorner → bakeInstance → newBakedInstance` 烘焙路径）；
   - 新增**独立字形层** `G_REAL.glyphLayer`，`draw()` 每帧整层置顶（否则被按需创建的池矩形/面板底板压住 → 文字发灰）；
   - 子面板行字号改为 `min(15, max(11, rowH*0.58))`，避免 CodeArt 墨迹比原字体满导致的行间粘连；
   - `C.textMode = 'art'`（默认）/ `'control'`（切回原生文本框做对照）。
7. **诊断开关**：`C.keyDiag`（全量按键监听，查真机物理键对应的事件名）、`C.textProbe`（隔离文本探针：白条 + 4 行脚本文本 + 观察画布内手放的 `TextProbe`）。

## 重建（改了源码之后）

```powershell
cd D:\stars\workspace\sans-fight
node tools/build-save.mjs        # 重新生成 sans-fight.save.json（内联脚本）
node tools/verify-all.mjs --quick # 离线回归（期望 9/9；沙箱接轨探针 68 PASS / 0 FAIL）
# 然后把 sans-fight.save.json 里 assets.scripts[1073742105].source 写到
#   C:\Users\19637\AppData\LocalLow\miHoYo\原神\BeyondLocal\248255821\Beyond_Local_Save_Level\1073741827\external_lua_file\main.lua
```

真机日志抽取（不用手抄）：

```powershell
node D:\stars\workspace\sans-fight\tools\read-beyond-log.mjs --grep "diag|geom|警告|ERR|阶段"
```
