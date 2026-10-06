# Lua 逻辑核心移植记录（core.lua）

- 目标：把 `prototype/` 的 JS 原型（`attack-engine.js` + `attack-loader.js` + `game.js`）**完整移植**为纯 Lua 逻辑核心。
- 交付：`lua/core.lua`（逻辑）、`lua/attacks.lua`（数据，生成器产出）、`lua/core_selftest.lua`（L1 自测）、`tools/gen-attacks.mjs`、`tools/run-lua.mjs`。
- 迁移日期：2026-10-04
- 证据等级：**L1**（纯状态回放 + 自测）。不是模拟器证据，也不是真机证据。

## 1. 怎么跑

```powershell
cd D:\stars\workspace\sans-fight

# 目标运行时（Lua 5.3 语义）= fengari（本机装在 D:\my-dsh\profiles\web）
node tools/run-lua.mjs lua/core_selftest.lua      # 166 PASS / 0 FAIL
node tools/run-lua.mjs lua/_check.lua             # 适配层自检（父进程维护）

# 本机 Lua 5.1 也能跑（core.lua 的位运算层不依赖 5.3 的位运算符）
D:\5.1\lua.exe lua\core_selftest.lua              # 166 PASS / 0 FAIL

# 重新生成攻击脚本数据（改过 prototype/attacks/*.csv 之后必须跑）
node tools/gen-attacks.mjs
```

`tools/run-lua.mjs` 只做三件事：用 fengari 建状态、注入 `LUA_ROOT` 全局、把 `<ROOT>/?.lua` 与 `<ROOT>/lua/?.lua` 加进 `package.path`；**不改写被测脚本里的 `require`**（Windows 路径里的 `:` 不适合当 `LUA_PATH` 分隔符）。

## 2. 命令覆盖表（与 `prototype/attack-engine.js` 等价）

| 类别 | 命令 | 状态 |
|---|---|---|
| 弹幕 | `BoneV` `BoneH` `BoneVRepeat` `BoneHRepeat` `SineBones` `BoneStab` `GasterBlaster` | ✅ 全部实现 |
| 平台 | `Platform` `PlatformRepeat` | ✅ + 实现往返（`BooleanReverse`）与站立/阻挡 |
| 灵魂 | `HeartMode` `HeartTeleport` `HeartMaxFallSpeed` `SansSlam` `SansSlamDamage` `GetHeartPos` | ✅ |
| 战斗框 | `CombatZoneResize`(带 FinishAction) `CombatZoneResizeInstant` `CombatZoneSpeed` | ✅（另加扩展命令 `CombatZonePos`） |
| 流程 | `TLPause` `TLResume` `EndAttack` `BlackScreen` `Sound` `Music` | ✅ |
| 表现 | `SansAnimation` `SansHead` `SansBody` `SansTorso` `SansSweat` `SansX` `SansRepeat` `SansEndRepeat` `SansText` | ✅ |
| 运算 | `SET` `ADD` `SUB` `MUL` `DIV` `MOD` `FLOOR` `DEG` `RAD` `SIN` `COS` `ANGLE` `RND` | ✅ 13 个 |
| 跳转 | `JMPABS` `JMPREL`(相对) `JMPZ` `JMPNZ` `JMPE` `JMPNE` `JMPL` `JMPNL` `JMPG` `JMPNG` | ✅ 10 个 |
| 结构 | 标签 `:Name`（**占一行**）、变量 `$Var` | ✅ |

`M.cmdCount == 47`、`M.jumpCount == 10`（自测里断言）。

### 三个"曾经修过的跳转 bug"——本移植逐条对齐并有回归用例

1. **`JMPREL` 是相对偏移**：`pc = pc + off`，不是绝对行号。用例 `extra-jump-semantics`。
2. **跳转的测试参数不含目标行号**：测试参数取 `args[2..3]`（跳过第 1 个目标参数）。用例同上（`JMPE`）。
3. **`exec` 必须读 `line.cmd` / `line.rel`**，不能把命令名/偏移存进局部字符串变量。用例同上（`JMPNZ`）。
4. 额外补一条：**标签行占一行**（`JMPABS` 用 1-based 物理行号，标签行不能丢）。

### 移植中额外发现并修掉的 3 个真 bug（都在自测里有回归）

| # | 症状 | 根因 | 修法 |
|---|---|---|---|
| B1 | `0,BlackScreen,1` 清不掉弹幕、所有带空单元格的行参数整体左移 | `compile` 里照抄了 JS 的 `filter(a => a !== '')`，CSV 出现空单元格时位置语义就错了 | 参数**按位保留**（末尾空串才裁掉），`val('') -> 0` |
| B2 | `sine` 摆动位置与命中盒不一致（"看着躲开了却掉血"） | 命中盒固定 `y=240-gap/2`，渲染却按相位摆 | 新增 `sineGeom()`：命中盒与 render **共用同一份几何**（`centerY = baseY + amp*sin(phase)`） |
| B3 | `GasterBlaster` 的 `BlastTime=0` 被当成"0 秒开火" | `g.t >= 0` 第一帧就转 `done` | `BlastTime<=0` = **持续光束**，一直停在 `fire`，由 `EndAttack` 统一收束（`sans_final` 阶段④ 就靠这个） |

## 3. 与 JS 原型的差异（逐条）

### 3.1 架构差异：回合模式 vs 攻击脚本

- JS `game.js` 的 6 个回合是**内置模式生成器**（`spawnFloor`/`spawnWall`/`spawnBlue`/`spawnBlaster`…），它**根本没有 require `attack-engine.js`**。
- 本移植把两者**接起来**了：`world` 是唯一的战斗框参照，内置生成器与攻击脚本都往 `world.bones` 里放东西。
  - 回合 0（不意打ち）挂 `sans_intro`；最终回合三段分别挂 `sans_bluebone` / `sans_bonegap1` / `sans_intro`。
  - 回合 1–5 **没有**挂脚本（保持 `game.js` 的手感），但会通过 `ensureWorld()` 造一个"只有框"的 world，让坐标路径统一。
- 副作用（**已知、可接受**）：`sans_intro` 第 4 行是 `0,BlackScreen,1`，语义上会清空弹幕，所以回合 0 里 `startEnemy` 立刻生成的那一波"偷袭骨"会在第 1 帧被清掉 → 回合 0 **不会**出现 `wave_clear wave=1`。原版 `game.js`（没接引擎）那一波会活到 1.43s 才 clear。自测里两条断言按此改写（回合 0 只断言"前 1.6s 无伤"，`wave_clear` 放到第 1 回合验证）。

### 3.2 数值差异

| 项 | JS | Lua | 说明 |
|---|---|---|---|
| HP 上限 | 20 | 20（默认） | 与自测断言（HP=20、`hp=2` 的 KR 用例）一致。资料里的 **92** 是后续正式版的值，可用 `opts.hp` 覆盖；`main.lua` 现在传的就是 `hp=92` |
| 难度四档 | easy 0.60/1.60/1.45/1.00、normal 0.78/1.35/1.20/0.80、hard 1.00/1.00/1.00/0.55、original 1.25/1.00/1.00/0.15 | **照抄** | 自测断言相邻两波生成间隔 |
| 骨头四段生命 | peek 0.5 / extend 0.15 / hold 0.55 / retract 0.2 | 照抄 | 自测断言冒头实测 ∈ [0.45,0.60]s |
| 中场触发 | `round == 3` | `round == interludeAfter`（默认 3，可配） | 「原作第 12 次攻击后」→ 4×3=12，与现 JS 行为一致 |
| 最终回合 | 只有 `final` 布尔（第 6 回合后一次攻击定胜负） | **分三段**（契约要求）：① 重力蓝魂+平台 ② 横スク骨缝 ③ 骨墙+旋转光束 | 三段都 `final=true`（攻击必命中），每段 10/10/11s |
| 平台碰撞 | 无（`BooleanReverse` 解析了但不用） | 站立 + 阻挡 + 往返 | 往返范围 CSV 未给，取生成点 ±`PLATFORM_TRAVEL`(100px) |
| 砸击伤害 | `SansSlamDamage` 只存标志 | 同上（壁ドン 0 伤害：`w.slamDamage=false` 时砸击不扣血） | 自测有断言 |
| 正弦骨命中 | 无（引擎只有视觉） | 上下长骨之间的 `gap` 走廊为安全区，命中盒 = gap 中心的 19×19 | 见 B2 |

### 3.3 刻意保持一致的"怪癖"

- `startRound` 与 JS 一致：**只决定"开局打完回合 0 之后进哪一回合"**，开局永远是回合 0。自测注释里写明了，避免误用。
- `SURPRISE.p.interval` 在 `startEnemy` 里**不乘难度间隔**（JS 里也是裸值），否则简单档第 1 波会被拖到 2.24s。
- `spawnT` 初值：`bone_wall/mixed` 为 `1.6×interval ×`，其余 `0.8×interval`。
- 回合内`floorLock = peek + EXTEND + HOLD`，保证**致命窗口不重叠**（自测断言 peakLethal ≤ 1）。

## 4. 渲染契约（`M.render` 的唯一口径）

### 4.1 坐标：**只输出绝对 640×480**

内部有三套坐标，**只有 render 出口是绝对的**：

| 空间 | 谁在里面 |
|---|---|
| ① 脚本坐标（原版 640×480，CSV 逐字） | `world.zone`、`world` 里的骨头/骨刺/龙骨炮/正弦骨/平台 |
| ② 框内相对坐标 = ① − (240, 226) | `Game.box`、`Game.soul`、`walls`、内置弹幕 |
| ③ 绝对坐标 = ② + (240, 226) | **`M.render` 的输出**（适配层零猜测，不需要再判断 box.x < 50） |

- `M.BOX_OFF_X/BOX_OFF_Y = 240, 226`（导出，便于适配层对齐；**正常不需要用**）。
- world 实体由 `shiftAbs()` 统一平移（含 `x0/y0/endX/endY/centerY/baseY/gapTop/gapBottom` 与 `bars` 子表），避免逐处漏加偏移。
- **不做画面外裁剪**：BTS 引擎本来就允许实体在画面外（例如 `sans_intro` 的正弦骨从 x≈1040 起步飞入画面），引擎自己的 ±400px 出界清理才是唯一口径。适配层应能接受 `x` 超出 `[0,640]` 的命令（对象池 + `SetVisible` 即可）。

### 4.2 布局：框**在所有状态下同一位置**，按钮行画在框内

| 元素 | 绝对坐标 | 说明 |
|---|---|---|
| `box`（**所有状态**，含 enemy/menu/sub/attack/result） | 中心恒为 `(320, 308.5)`；内置回合按 `ROUND_DEF.bw/bh`（R6 = 600×340，其余 420×260，R0 = 165×165 来自脚本） | `cmd.shifted` 恒为 `false`；不再按状态上移 |
| `menu` 按钮行 | `MENU.y = 306`（**仅逻辑提示值**），`bw=110 bh=36 gap=10`，四连居中 | 原版按钮排在**框外下方** y≈400..440（默认框下沿 391）。适配层按 `min(box.y+box.h+12, 480-46)` 统一挪位并处理与移动摇杆的触摸优先级，所以 core 的 y 只是提示 |
| `sub` 面板 | **框内**：`pad=8`，`px,py = boxAbs.x+pad, boxAbs.y+pad`，`pw = boxAbs.w-16`，`ph = boxAbs.h-16`；`rowH = clamp(floor((ph-58)/rows), 24, 40)` | 面板矩形**保证在框内且在世界内**。曾经是 `y=348 + panelH`（4 行 = 348..560）掉出世界底边 80px、行被切掉 |
| `attackBar` | 框内水平中线 | |
| HUD | 320×240 的 0.5 倍版式：`LV 19`(20,22)、HP(160,21)、KR(160,32)、ROUND(右对齐 620,23)、台词(居中 320,86)、难度(20,50) | |

#### 框中心为什么是 308.5（踩过的坑）

`308.5 = 226 + 165/2` = **BTS 默认战斗框 `(240,226)-(400,391)` 的中心 y**。
- 曾经写 `183`（那是 HTML 原型 1280×720 设计板 640×366 折半来的，不是 640×480 世界的中心），
  结果**所有内置回合的框、以及被钳在框上的灵魂整体偏高 125.5px**。
- 内置回合的框曾经被写成**帧①（绝对坐标）**，而 `render` 又无条件 `+BOX_OFF` → **双平移**，
  框跑到世界外（round1 输出 `(350,279) 420x260`，右边缘 770 > 640）。现在统一按帧②写。
- 菜单态曾经把框上移到 `MENU_BOX_ABS_Y = 130` 去给按钮让位 —— 那只是掩盖上面两条，
  而且造成"框瞬移 96px"。**现在整块删掉**，框不再随状态移动。
- 框尺寸上限 `BOX_MAX_W/H = 620/340` 并 clamp + 打一次日志（中心 308.5 时最大对称框 640×343）。
  R6 / FINAL 第 1 段已从 660×400 下调到 **600×340**，所以 clamp 只是兜底。

### 4.3 输出实体（`kind`）

规定的 9 种 + 适配层需要的 4 种扩展：

| kind | 字段 | 备注 |
|---|---|---|
| `box` | `x,y,w,h,baseY,shifted` | 绝对坐标 |
| `bone` | `x,y,w,h,vertical,color(0白/1蓝/2橙),alpha,phase,lethal,telegraph,wave` | `phase` ∈ peek/extend/hold/retract；`telegraph=true` 表示"冒头预示"，适配层画占位框 |
| `blaster` | `x,y,dir(0东/1南/2西/3北),ang,size,w,charge,fire,alpha,state` | `ang` = 朝向角（度）；脚本炮从炮口沿 `ang` 射 2000px；`w` = Size 对应 20/36/56 |
| `soul` | `x,y,mode("red"/"blue"),invuln,visible` | 闪烁由 `visible=false` 给出（0.05s 交替） |
| `platform` | `x,y,w,h,dir,speed,reverse` | |
| `hudText` | `text,x,y,size,color,align` | **中文按字符截断**（UTF-8 安全） |
| `flash` | `alpha` | 受伤红闪 |
| `menu` | `x,y,w,h,items,index,visible,active,interlude` | |
| `wall` | `x,y,w,h,lanes,gapStart,gapW,hCur,phase,boxY,boxH` | 骨墙：缺口段 `[gapStart, gapStart+gapW)` 不画 |
| `sine` | `x,y,w,h,vertical,centerY,baseY,amp,gap,phase,speed,bars[],barThickness,gapTop,gapBottom,hit` | 见 §4.4：`bars` 是**两根竖长骨**（视觉实体，不是命中盒）；`hit` 才是命中盒 |
| `stab` | `x,y,w,h,dir,phase,phaseRaw,lethal` | `phase` 固定为 **peek/extend/hold/retract**（GDD C14 口径） |
| `sub` | `x,y,w,h,rowH,title,rows[],index,notes[],desc` | |
| `attackBar` | `x,y,w,h,cursor,result` | |

> 未输出：Sans 本体（适配层自绘）、`Sound`/`Music`（进 `world.log`，名字在 `M.debug`）。

### 4.4 正弦骨几何（B2 的口径）

**先说坐标系，这里踩过两次坑**：`sine` 的所有 y 都在 **「脚本绝对坐标帧」**，
也就是和 `box` 命令、`world.zone` **同一帧**（`zone.t` 本身就是脚本绝对坐标 226/279…，
**不是**框内相对坐标 0）。它**不经过 `shiftAbs()`**（带着 `abs = true` 跳过平移）——
曾经被平移过一次，导致 `bars[1].y = 452 = 226 + 226`、判定离灵魂 226px，
正弦骨完全不造成伤害。**判断口诀：`bars[1].y` 必须 == `zone.t`。**

```
half    = |gap| / 2               （gap 来自 SineBones 的第 4 参：走廊高度）
amp     = |gap| * 0.5
baseY   = (zone.t + zone.b) / 2    ← 战斗框的水平中线（脚本绝对帧）
centerY = clamp(baseY + amp*sin(phase), zone.t + half, zone.b - half)
phase  += speed * dt * 0.5         （每帧推进）
```

`M.render` 里 `kind='sine'` 的输出分三块，**别混**：

| 字段 | 含义 |
|---|---|
| `centerY` | 当前走廊中心的 y（**脚本绝对帧**） |
| `gapTop` / `gapBottom` | 走廊上下口（= `centerY ∓ half`） |
| `bars[1..2]` | **两根竖长骨**：厚度 = `w`（=19）、长度 = `h`，`vertical=true`。`bars[1]`（上）：`y = zone.t`、`h = (centerY-half) - zone.t`；`bars[2]`（下）：`y = centerY+half`、`h = zone.b - (centerY+half)`。**`h <= 0` 时该根不输出** → `bars` 可能只有 1 项甚至空表，请 `for i = 1, #bars` 画 |
| `hit` | 走廊中心的 19×19 标记矩形，**仅供调试/可视化** |
| `x,y,w,h`（外层） | = `bars[1]`（上长骨）的矩形 |

#### 判定口径（重要，与"命中盒"旧说法不同）

**打的就是看得见的两根长骨**（`sineHitTest` 逐个 `bars` 做圆-矩形判定），
`gap` 中间的走廊安全。理由：SineBones 的视觉就是"两根长骨夹一条走廊"，
玩家靠**看**判断该不该躲；旧写法让"站在骨头上不掉血"、只在一个隐形小方块上掉血，
视觉与判定不一致。**难度没有变高**：走廊宽度 = `gap` 不变（旧写法只覆盖 gap 中间
一条缝，反而更宽松）。

- `w.sine` 是**独立实体表**，不在 `w.bones` 里 —— 碰撞循环必须单独遍历它
  （曾经的 bug：只判 `w.bones`，正弦骨"有视觉、无判定"）。
- 原版 CSV **没有给基准 Y**，所以取"框的中线"；`centerY` 还夹在框内，避免"躲不开的必死走廊"。
- 适配层请用 `centerY`/`gapTop`/`gapBottom`/`bars`，**不要**自己按 `amp=10` 假设（实际 `amp = gap/2`）。

行为回归（自测里真跑 `core.update` 断言 HP，不只看几何）：
站在长骨上 → 掉血；站在走廊中心 → **不**掉血；且 `bars[1].y == zone.t`。

## 5. UTF-8 打字机（真机必修）

**症状**：真机第 1 帧 `main: draw ERR :: cannot convert invalid utf8 to javascript string`，之后每帧报错、整屏不渲染。

**根因**：台词是全中文，而 `string.sub` 是**按字节**切的；`lineShown` 落在多字节字符中间就切出非法 UTF-8，写进控件 `text` 时 JS 侧抛错（整帧 draw 中断）。

**修法**（core 侧治本）：
1. `lineShown` 的单位改成**字符**（不是字节）：上界 = `utf8len(line)`，速度仍是每 0.028s 一个字，最终**正好等于整句字符数**（不会少显示最后几个字）。
2. 新增 `utf8len()` / `utf8sub()`：优先用标准 `utf8` 库（Lua 5.3 / fengari 自带），缺失时按首字节判定长度（`<0x80`→1、`>=0xF0`→4、`>=0xE0`→3、`>=0xC0`→2）自己数。
3. `M.render` 里台词改用 `utf8sub(g.line, g.lineShown)`；两个函数也从 `M` 导出，适配层可复用。
4. 全文自查：core 里没有其它对中文做按字节 `sub`/`#` 的地方（菜单项名、`SansText`、`subRowNote` 都是整串透传，不截断）。

## 6. 性能与确定性

- **确定性**：`mulberry32` 与 `attack-engine.js` **逐值一致**（4 个 seed × 6 个值，自测断言）。运动全部显式消费 `dt`，同 seed + 同输入 → 同日志。
  - 移植时踩过 4 个坑（都写进注释了）：`>>>` 是**零填充**右移；`61 | t` 是"或"；`t + imul(...) ^ t` 的 `^ t` 作用在**整个和**上；每个 `^` 之后要折回 int32。
  - 位运算层**整层用纯 double 算术**（`% 2^32` + 逐位），因为 Lua 5.3 的 `&`/`>>` 与 Lua 5.1 语义不同、且 `a*b` 会超 double 精度（`Math.imul` 用 16 位拆分实现）。
- **每帧只推进一步战斗框变形**：曾经 `paused` 分支里调一次、下面又无条件调一次，导致 11 个靠 `CombatZoneResize...TLResume` 起手的关卡框体按 2 倍速完成。

## 7. 未验证项（重要）

| 项 | 状态 | 说明 |
|---|---|---|
| 真机渲染 | ❌ 未验证 | 本移植只出逻辑与绘制指令；模拟器/真机截图由适配层负责 |
| 24 个 BTS 攻击脚本的**完整往返** | ⚠️ 部分 | 自测只空跑了 11 个"已接线"的脚本（与 `attack-selftest.js` 同口径）；其余 13 个（platforms*/randomblaster*/multi*/final 等）**能编译、能加载**，但未逐个空跑断言（`final` 脚本 200+ 行，超时上限 60s 内未必 EndAttack） |
| 正弦骨的**基准 Y 与振幅** | ⚠️ 推定 | 原版 CSV 的 `SineBones` 只给 Count/Spacing/Speed/Height，没有基准 Y。本移植取 `baseY=VH/2`、`amp=Height*0.5`（见 §4.4），**需视觉确认** |
| 平台往返范围 | ⚠️ 推定 | CSV 未给边界，取生成点 ±100px |
| 平台在红魂回合的站立 | ⚠️ 设计取舍 | 红魂**没有重力**（与 JS 一致），所以红魂只会被平台挡住；蓝魂才有"掉到平台顶面站住" |
| `SansSlam` 的砸击伤害 | ⚠️ 未接线 | 引擎记录了 `slamDamage`，但 `Game` 侧没有消费它（JS 也没有）；"壁ドン 0 伤害"目前只是标志位 + 自测断言 |
| 最终回合三段的**具体脚本内容** | ⚠️ 复用既有脚本 | 契约只要求"分三段"，本移植复用 `sans_bluebone`/`sans_bonegap1`/`sans_intro`；原版 `sans_final` 的四阶段编排**未接**（脚本已在 `attacks.lua` 里，可直接换） |
| 音效/音乐 | ❌ 不实现 | `Sound`/`Music` 只记日志 |
| HP 92 档 | ⚠️ 未跑自测 | 自测用的是 JS 基准 20；`main.lua` 用 `hp=92` 时**规则不变**（KR 上限、每 0.5s 扣 1 等都与上限无关），但没有针对 92 的断言 |

## 8. 自测清单（166 条）

| 组 | 条数 | 对应 |
|---|---|---|
| boot / first-success / bone-telegraph | 3+3+3 | C9/C10/C17、C5/C8、C14 |
| kr-floor / hp-integer / iframes / first-fail / restart | 6+2+2+2+4 | C1–C4、C18、C9 |
| blue-bone-still / orange-bone（含白骨对照） | 5+6 | C6/C19 |
| determinism / loop / submenus / interlude / bone_wall / difficulty | 2+8+12+7+4+4 | C10、C5/C8、C13、C16、C11、C12 |
| attack-scripts（11 脚本 × 2 断言） | 22 | 命令覆盖 + 能 EndAttack |
| extra-final / extra-spare / extra-wall-slam / extra-cmd-coverage / extra-jump-semantics / extra-rng / extra-hud | 5+2+3+2+4+2+3 | 契约补充项与回归 |
| extra-render（render 纯函数 + 覆盖 13 种 kind + **sine 几何契约 8 条 + sine 行为回归 4 条**） | 13 | 见 §4.4 |
| extra-box-bounds（**全部 ROUND_DEF/SURPRISE/FINAL_PHASES + 菜单类状态 + 跑满一整轮**：世界内、中心恒 (320,308.5)、各状态 y 相同） | 4 | 见 §4.2 |
| extra-sub-panel（act/item/mercy 面板：矩形在框内且在世界内、`rowH >= 24`、内容放得下） | 8 | 见 §4.2 |

命令与结果：

```
node tools/run-lua.mjs lua/core_selftest.lua   →  PASS 166 / FAIL 0   （fengari，Lua 5.3 语义）
D:\5.1\lua.exe lua\core_selftest.lua           →  PASS 166 / FAIL 0   （Lua 5.1）
node tools/run-lua.mjs lua/_check.lua          →  无 RUN FAIL
node tools/run-lua.mjs lua/_flow.lua           →  框变化 31 次，绘制框最大溢出 0.0px、灵魂出框 0.0px、错误 0
```

`box` 契约断言：每相 box 满足 `x,y >= 0 且 x+w <= 640 且 y+h <= 480`、中心恒 `(320,308.5)`
（±1px），且 `menu/sub/attack/result` 的框 y **与 enemy 完全相同**（不再上移）。
覆盖 `ROUND_DEF` 0..6、`FINAL_PHASES` 1..3、菜单四态，以及 seed=7 跑满 600 帧的真实流程。

`sine` 几何契约断言（防"bars 又变成命中盒"）：`bars[1]` 最大边 ≥ 30、厚度 = `w` = 19、
`bars[1]` 底边 == `gapTop`、`bars[2]` 顶边 == `gapBottom`（或只输出 1 根）、
**`bars[1].y == zone.t`（防又被平移一次）**。

`sine` **行为回归**（真跑 `core.update` 断言 HP，不只看几何）：
`phase=0` 时 `centerY == 框中线`、站在长骨上 → 掉血、站在走廊中心 → 不掉血。

隔离夹具：`noSpawn` 只关掉"模式生成器"，本移植还挂了攻击脚本（回合 0 = `sans_intro`），
所以 KR/生命类用例要额外调 `clearHazards(g)`（清空 `world.bones/sine/blasters` 并把 pc 推到末尾），
否则会被脚本弹幕污染出假失败。

`easy/normal/hard/original` 四档 900 帧空跑均无报错，`hud.phase` 正常推进。
