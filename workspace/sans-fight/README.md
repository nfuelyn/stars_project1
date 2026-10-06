# 审判者战 · sans-fight（千星奇域 / 千星沙箱 · Lua 版 Undertale 最终 Sans Boss 战）

用**纯 Lua**在「千星奇域（千星沙箱 · Qianxing）」里复刻 Undertale 的最终 Sans 战：
标题页 → 20 个回合的弹幕/骨/龙骨炮/平台/蓝橙骨 → Sans 的收尾特殊攻击 → 击倒结局 / 死亡重开。

* 逻辑与外观**全部由 Lua 承担**：截图中看到的每一个 HUD 文字、心、骨头、龙骨炮、战斗框、菜单、
  标题页、虚拟摇杆，都是运行期用 7 个图元模板 `game.InstantiateClientUIControl()` 拼出来的；
  编辑器里不摆任何实体控件。
* 交付形式是可回读的**完整存档** `sans-fight.save.json`（服务端容器 + 客户端模板池 + **1 条自足脚本**），
  在模拟器里试玩，或导出成 GIA 整合包送上真机。
* 复刻依据是 jcw87 的 *Bad Time Simulator* 的攻击脚本（CSV 时序表）与公开攻略资料，
  坐标统一用原版 **640×480** 世界，再整幅等比缩放到画布；
  真机写法参考 nightingale-0/millastra-6nimmt（见 `docs/ref-millastra-6nimmt.md`）。

---

## 快速开始

```powershell
cd D:\stars\workspace\sans-fight

# 1) 一条命令跑完全部离线回归（Lua 5.3 语义，fengari）+ 重建存档 + 契约校验
node tools/verify-all.mjs            # 全量；--quick 跳过最慢的 _geometry/_pool；--no-build 只测不重建

# 2) 只重建存档（改完任何 .lua 都必须做，模拟器跑的是存档内嵌源码，不是工作区的 .lua）
node tools/build-save.mjs

# 3) 无头试玩（不需要 DSH 插件；用模拟器 Studio 同一套 Runtime，可出 PNG 截图）
node tools/play-capture.mjs --seconds 60 --shots 0,1,12,30,60
node tools/play-capture.mjs --canvas pc-16-9 --seconds 40 --shots 0,1,20,40
node tools/play-capture.mjs --round 19 --seconds 6 --shots 3        # 跳到指定回合验收
```

判据：启动日志里有 `main start: build=… pool=692`，且整场 `pool=` 一直是 692。

## 在模拟器里试玩 / 上真机

1. 打开「模拟器」标签 → 顶栏「工作区存档」或「导入」，选 `sans-fight.save.json`。
2. 点「试玩 ↗」：先看到标题页「弹幕审判」，点难度卡选档（再点一次开始）。
3. 上真机：顶栏「…」导出**资产包 GIA（整合包）**，导入千星真机。
   ⚠ **GIA 不保存脚本挂载关系**，导入后必须把 `boot` 脚本重新挂到客户端容器节点 `n1` 上。
   逐字段配置清单见 `docs/device-setup.md`。

## 目录

| 路径 | 作用 |
|---|---|
| `lua/boot.lua` | 挂在 `n1` 上的引导脚本，转发生命周期到模块层（存档里只有它带挂载点） |
| `lua/main.lua` | 适配层：控件池、绘制、输入、界面状态机、世界→画布映射 |
| `lua/core.lua` | 逻辑核心：回合/攻击脚本解释器、战斗框、灵魂、KR、菜单、结算 |
| `lua/attacks.lua` | 攻击脚本数据（由 `prototype/attacks/*.csv` 生成） |
| `sans-fight.save.json` | **交付物**：完整存档（version 4） |
| `tools/verify-all.mjs` | 一条命令跑完所有离线回归 + 重建存档 + 契约校验 |
| `tools/build-save.mjs` | 生成存档（模板池 + 服务端容器 + 4 条脚本） |
| `tools/play-capture.mjs` | 无头试玩 + PNG 截图（离线驱动 Studio Runtime；`--round N` 跳回合、`--outdir` 指定产物目录） |
| `tools/run-lua.mjs` | 用 fengari 跑 `lua/` 下的自测脚本 |
| `lua/_*.lua` | 各主题离线回归（见下表） |
| `prototype/` | JS 原型（攻击脚本引擎 + 攻击 CSV），Lua 版的数据源 |
| `tests/` | `qxqy-autotest` 用例（draft） |
| `docs/` | 策划案 `gdd.md`、真机清单 `device-setup.md`、API `api-2d-lua.md` 等 |
| `records/` | 移植记录、试玩记录、本轮接管的状态与证据 |

## 架构

```
服务端 UI：sc1 客户端控件容器 → n1 容器节点（showCursor=true，挂那条自足脚本）
客户端 UI：c1 根 → 7 个图元模板（rect / circle / text / ring / rot / rot-tri / cursor）
Lua 脚本：**1 条自足脚本**（构建时把 core.lua / attacks.lua / main.lua 内联 + 自带 require 垫片）
```

源码仍是 `lua/{boot,core,attacks,main}.lua` 四个文件，但 `tools/build-save.mjs` 会把它们**内联成一条脚本**
（千星客户端 Lua 沙箱没有 `require` 全局 —— 依据见 `docs/ref-millastra-6nimmt.md`），末尾定义 7 个生命周期函数。
逻辑层与官方运行时的边界、命令覆盖表见 `records/lua-port.md`（47 条攻击引擎命令 + 10 条跳转全部实现）。

## 当前状态（2026-10-05 接管轮）

全部离线回归通过，并把存档在模拟器 Runtime 里从标题页实跑到**击倒结局**：

| 套件 | 结果 |
|---|---|
| `_check` | 四档难度各 900 帧无错 |
| `_rounds` | 54 PASS / 0 FAIL（20 回合结构、随机抽模板、螺旋档） |
| `core_selftest` | 248 PASS / 0 FAIL（含 27 个攻击脚本空跑 + `clip-zone` 竖骨裁剪 + `blue-jump` 0.55s 上升/0.9s 下落/悬停/不能二段跳 + `intro-blaster` 0.6s 预警 + `fair-bone` 高骨公平性与颜色 + `blue-script-bone` 蓝骨语义） |
| `_tap` | 40 PASS / 0 FAIL |
| `_title` | 33 PASS / 0 FAIL |
| `_input` | 249 PASS / 0 FAIL |
| `_geometry` | 33 PASS / 0 FAIL（"绘制 == 判定"逐帧对账 41059 条；骨头的锚点/朝向/裁剪也在里面钉住） |
| `_pool` | 四档全部 `运行期追加=0`、`draw ERR=0`；OnStart 实例化 692 |
| `verify-client-pool` | PASS 7/7 |
| 无头试玩（模拟器 Runtime） | mobile-16-9 360s/420s 与 pc-16-9 40s 均 0 错误、`pool` 恒 692；标题页→20 回合→`阶段 attack → result (round=19)`→击倒结局→重开 全通 |

截图证据：`records/captures/**`（标题页 / 各回合 / 螺旋档 / 结局 / PC 画布）。

### 最近两轮改动（2026-10-05）

| 项 | 结果 |
|---|---|
| **骨头定位（真 bug）** | 脚本骨 `BoneV/BoneH` 的 `(X,Y)` 是**左上角**，旧实现按中心算 → 整根偏移 `(-w/2,-h/2)`：高骨戳出框顶、底部矮骨浮空、两侧骨缝错位。判定与渲染已同时改成左上角 |
| **骨群排布方向（真 bug）** | `BoneVRepeat/BoneHRepeat/PlatformRepeat` 的「间距」要排在**来向**（领头骨后面），旧实现四个方向全反 → 起手整排铺满屏幕。修完后骨头一根接一根**交错飞入**（`sans_boneslidev/bonegap*/multi*/final` 全部受益） |
| **sans 位置** | 从屏幕下方搬到**战斗框正上方**（脚踩框顶边、+6px 轻微重叠），对齐参考实现 |
| **sans 尺寸** | 横向 ×1.15、纵向 ×0.95 **分别**缩放（锚点=脚底）：宽一点、矮一点 |
| **背景** | 纯黑 + **3 倍画布**（21:9 也不露舞台）；`OnStart` 显式 `SetAsFirstSibling/SetAsLastSibling` 钉层序 |
| **脚本形态** | 存档脚本从 4 条改成**1 条自足内联包**（≈208 KB）——千星客户端沙箱没有 `require` |
| **HUD** | 等级/血量/KR 血条搬到**选项栏正上方**；黄色=HP、紫色=KR |
| **龙骨炮** | Size 0/1/2 骷髅 ×0.8/1.0/1.3；长吻头骨形象；开火停靠点不再压选项栏；光束加长 |
| **KR（蓝血）** | 治疗道具清 KR；攻击条阶段也继续燃烧 |
### 玩法修正（2026-10-05，按试玩反馈）

| 项 | 结果 |
|---|---|
| **低血量「受击判定消失」** | KR 增量原来按 `hp-1` 截断（血量 2~3 时紫条几乎不动）→ 改成每次命中都加满 KR，「不致死」由 KR 烧到 1 血的下限保证 |
| **蓝心变高跳** | 轻点≈105px、按住最高≈131px（上限 = 半个战斗框高），落地重置；所有蓝魂关卡通用 |
| **攻击模板叠加** | `BlackScreen` 现在连平台一起清（multi2/3 的落脚板不再跨段残留） |
| **浮空板关卡底骨** | `platforms4/4hard` 的底部骨毯改**静止**、29 根正好铺满框宽（113..548），不再横扫出框 |
| **sans 位置** | 再上移 16px，站在战斗框上方留空隙，不再贴着框 |
| **红心碰撞箱** | 心以 `(x,y)` 为中心、外接半径 8，与 `SOUL_R` 同口径 —— 贴框时不再露出去 |
| **砸击方向箭头** | 蓝眼/砸击预警时在 sans 右侧画黄色箭头指出砸击方向（东/南/西/北） |
### 灵魂 / 判定修正（2026-10-05，按截图反馈）

| 项 | 结果 |
|---|---|
| **蓝魂关卡变成红魂** | 脚本的 `HeartTeleport / HeartMode / SansSlam / HeartMaxFallSpeed` 原来被 `startEnemy` 的默认值覆盖 → 现在脚本是权威：这些蓝魂关卡真的变**带重力的蓝心**，红魂回合仍是红心 |
| **骨头判定偏差** | `drawBone` 圆帽以前偏左半个骨头（视觉 `x-6.5..x+12.5`、判定 `x..x+19`）→ 现在圆帽正好铺满判定矩形 |
### 旋转 / 跳跃 / 碰撞修正（2026-10-05）

| 项 | 结果 |
|---|---|
| **上下龙骨炮没有发射动画** | 根因是所有旋转件都没转：`SetLocalRotation` 少传了 y/z（角度写进 X 轴）→ 改成 `SetLocalRotation(0,0,deg)`，斜/竖光束恢复正常 |
| **蓝心跳跃** | 轻按 = 1/5 框高、按住 1s = 1/2 框高、中间**线性**（弹道伺服实现）；松手即冻结目标高度 |
| **蓝心碰撞箱** | 骨头/平台碰撞本就生效；额外在 `HeartTeleport` 后把灵魂钳回框内，避免瞬移出框时整段跳过碰撞 |
### 脚本骨判定 / 心形图元（2026-10-05）

| 项 | 结果 |
|---|---|
| **脚本骨全部穿人** | `pushBone` 漏写 `lethal`，而碰撞循环只判 `bn.lethal` → bonegap/boneslide/platforms/multi/final 这些脚本骨全都不伤人。现在脚本骨 `lethal=true`（实测同一回合 HP 67→25） |
| **心形图案歪** | `circle(x,y,d)` 的坐标是**左上角**，两瓣被整体右下偏 (4.5,4.5) → 改成按圆心摆位，红/蓝心都是标准心形（菜单小红心一并修） |
| **红蓝心碰撞箱绑定** | 判定半径同为 `SOUL_R=8`，视觉外接盒也收成 ±8 → 同一个碰撞箱、且和形状一致 |
### 可躲避性 / 跳跃速度 / 平台 / 初见杀（2026-10-05）

| 项 | 结果 |
|---|---|
| **bonegap 包围型攻击** | 判定盒从 16×16 收到 **8×8**（原版口径）→ 14px 骨缝能钻过去；轻按跳 28px 正好落进骨缝 |
| **蓝心跳跃** | 改成**匀速上升**（速度=框高×0.5/1s，大小跳同速）：轻按 1/5 框高、按住 1s 到 1/2 框高、中间线性，空中不会重复起跳 |
| **平台攻击** | 站上移动平台会被平台带着走（仿原作） |
| **初见杀节奏** | `sans_intro` 四组龙骨炮间隔各 +0.1s |
### 还没做的（不要当成已通过）

* **千星真机**没跑过：`qxqy_script_sync` 的 `config` 仍是 `null`，本机没找到客户端导入目录。
* GIA 导出后**手工补挂 boot → n1**这一步必须在真机编辑器里做（GIA 不存挂载关系）。
* 无头试玩只在 `mobile-16-9` / `pc-16-9` 上跑过；`mobile-19.5-9` / `mobile-4-3` / `pc-21-9`
  只有离线几何覆盖，没有模拟器截图。
* 音效/音乐不实现（`Sound`/`Music` 只记日志）。

细节与复现命令见 `records/status-and-handoff.md`、`records/playtest.md`、`docs/device-setup.md`。

