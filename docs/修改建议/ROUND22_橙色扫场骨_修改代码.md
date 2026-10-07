# ROUND 22 这一段：新增「从上往下扫的橙色骨头」——修改代码（**未落盘**）

- **工作区**：`D:\stars\workspace\sans-fight`（**本文只给代码，未改任何工作区文件**）
- **对应截图**：`ROUND 22 / 24`（内部号 21 = `multi3`）里「贴地骨带 + 两块平台」那一段 = `multi3` 的 **Attack5 / Attack5Other**
- **日期**：2026-10-07

## 0. 需求解读（先说清楚我的理解）

> 这一段每轮骨刺突起，增加**一根**从上往下扫的橙色骨头，覆盖整个战斗框。

- 「这一段」= `prototype/attacks/multi3.csv` 的 `:Attack5` 段（含 `:Attack5Other` 镜像分支）——即截图里那排贴地骨头所在的段；
- 「每轮骨刺突起」= 该段现有的"贴地骨带"表现（`BoneVRepeat,121,354,37,2,0,20,20`，20 根）——**新增内容放在这条线之后**，两条分支都会生效；
- 「一根…从上往下扫」= **一根**橙色横骨，宽度 = 整框宽，方向向下（`dir=1`）；
- 如果你其实想要"每 0.6s 再来一根"那种**周期性**扫场，见 §4 的方案 B/C（会改变该段时长）。

---

## 1. 修改代码（CSV，1 行）

**文件**：`prototype/attacks/multi3.csv`（`multi2` 没有这一段，不用改）

在 `0,BoneVRepeat,121,354,37,2,0,20,20` 这行**之后**、`0,RND,Side,2` 之前插入一行：

```csv
0,BoneH,121,266,405,1,160,2
```

插入后的上下文（`+` 是新增行）：

```csv
0,CombatZoneResizeInstant,121,276,526,391
0,HeartMode,1
0,HeartTeleport,330,304
0,Platform,309,314,41,0,0
0,Platform,309,354,41,0,0
0,BoneVRepeat,121,354,37,2,0,20,20      ← 贴地骨带（截图里那排）
+0,BoneH,121,266,405,1,160,2             ← 【新增】橙色横骨：从框顶上方扫下来，宽=整框
0,RND,Side,2
0,JMPZ,Attack5Other,$Side
0,BoneV,521,280,35,2,240
0,BoneV,1,319,65,0,240
1.2,JMPABS,RndAttack
```

> 必须插在 `RND,Side,2 / JMPZ,Attack5Other,$Side` **之前**，这样 `Attack5` 与 `Attack5Other` 两条随机分支都会出这根骨。
> 放在这条线之后也**不会破坏任何跳转**：multi3 用的是标签（`:Attack5` 等）与 `JMPREL,$Jump` 跳表，跳表紧跟 `JMPREL` 之后没有被动过。

## 2. 参数逐个说明（为什么是这几个数）

`BoneH` 的命令签名（`lua/core.lua:677-679`）：`BoneH,x,y,width,dir,speed,color`

| 参数 | 值 | 含义 / 依据 |
|---|---|---|
| `x` | **121** | 该段战斗框左边界（`CombatZoneResizeInstant,121,276,526,391`） |
| `y` | **266** | 框顶(276) 再上面 10px —— 骨头厚 10px，所以它的**下缘正好贴在框顶**，一起手就"进入"框内 |
| `width` | **405** | 526 − 121 = 框宽，**正好覆盖整个战斗框**（横骨只有 10px 厚，厚的是这一维） |
| `dir` | **1** | 1 = 向下（`core.lua:661`：`vy = (dir==1) and +spd`），所以是"从上往下扫" |
| `speed` | **160** | 160px/s → 0.72s 扫完 115px 高的框，0.84s 完全离开框底；该段总长 1.2s，来得及扫完（各难度实测见 §3） |
| `color` | **2** | 2 = **橙色**（`main.lua:31 BONE_COLORS = {白, 蓝 0xFF2F6BFF, 橙 0xFFFF7A18}`）；橙色语义 = **灵魂"不动"时才受伤**（`core.lua:2780-2781`） |

> 想更快/更慢只改 `speed`：100 → 1.15s 扫完；200 → 0.58s 扫完。（速度还会照常乘难度倍率 `w:spd()`。）

## 3. 我做的实测（**未改工作区**，用内存里 patch 过的 CSV 跑真实 `World`）

探针：`D:\stars\_analysis\probe_orange_sweep.lua`（临时文件，只读工作区的 `core.lua`/`attacks.lua`）

```
框 = x 121..526 (宽405)  y 276..391 (高115)
橙骨 宽=405（= 框宽 ✓）  起始 y=266
进入框顶 t=0.02s   完全划过框底 t=0.78s   被清 t=1.22s（段末 BlackScreen）
轨迹：t=0.25 y=306..316 / t=0.50 y=346..356 / t=0.75 y=386..396 / t=1.00 y=426..436
```

- **0 → 0.78s**：橙骨从框顶扫到框底，这段时间"整个框"都被它扫过；
- **1.22s**：被下一段的 `BlackScreen,1` 清掉（`core.lua:812-819`）；
- 四档难度下也都能扫完（速度×难度、段长×难度同向变化）：简单 96px/s × 1.92s 行程 184px ✓、普通 125px/s × 1.62s 行程 202px ✓。

### 3.1 ⚠ 两条必须知道的口径

1. **橙色判定用的是"按方向键"，不是"真的在位移"**：`core.lua:2488`
   `local moved = (self.keys.left or self.keys.right or self.keys.up or self.keys.down)`
   —— 而**蓝魂跳跃键是"确认键"（Enter/Z/空格）**（`core.lua:2913、2928`），**不算 `moved`**。
   所以：玩家必须**按住 WASD 任一方向键**才是"移动"；只按 Enter 起跳反而会被橙骨打。
   （这也意味着按住 UP/DOWN 但人没挪动时，本端口算"移动"——与原版 C2 的 `Is moving`（真实速度≠0）不一致；要不要统一是另一件事，会牵动 3 号轮蓝骨关，**本次不动**。）
2. **横骨不裁剪进战斗框**：`core.lua` 只对竖骨做 `clipVZone`，所以 0.78s 之后它会**继续往下画到框外**（到 y≈468），大约 0.44s 会经过框下沿以外的区域；HUD（HP/ROUND 那行）在它之后绘制 → 会被 HUD 盖住，观感上属于"扫出去了"。若不想要这 0.44s，见 §5。

## 4. 变体：如果你要的是"每 0.6s 再来一根"

**方案 B（两根，+0.6s 段长）**：在 §1 的那行下面再加一行带延时的同款骨：

```csv
0,BoneH,121,266,405,1,160,2
0.6,BoneH,121,266,405,1,160,2
```

- 第 2 根在 0.6s 后生成（错开一层）；
- **代价**：延迟会顺延后面的行 → 该段总长从 1.2s 变 **1.8s**（多 0.6s）。若你要保持 1.2s，就把末尾的 `1.2,JMPABS,RndAttack` 相应改成 `0.6,...`（但这就是"改现有延时"，需要你点头）。

**方案 C（循环 N 根）**：

```csv
0,SET,S,0
:OrangeSweep
0,BoneH,121,266,405,1,160,2
0.7,ADD,S,$S,1
0,JMPL,OrangeSweep,$S,3
```

→ 0 / 0.7 / 1.4s 各一根，段长 +1.4s。

> 结论：**默认用 §1 的"一根"版本**（不改任何现有延时、段长不变）；要周期性扫场再选 B/C。

## 5. 【可选】只让这一根"出框即灭"（避免画到框外）

如果那 0.44s 的框外段不能接受，可以给骨头加一个**只在本根生效**的标记（默认 nil = 完全不影响其它骨头）：

`lua/core.lua`（2 处）：

```lua
-- (1) CMD.BoneH 增加第 8 个参数 boxClip，并把它挂到刚生成的这根骨头上
CMD.BoneH = function(w, x, y, wd, dir, speed, color, boxClip)
  pushBone(w, x, y, wd, 'h', tonumber(dir), tonumber(speed), color)
  local bc = tonumber(boxClip)
  if bc ~= nil and bc ~= 0 then w.bones[#w.bones].boxClip = true end
end

-- (2) World:update 的运动分支里，与"出屏销毁"并排加一条（只对有标记的骨生效）
      if b.boxClip then
        local zz = self.zone
        if b.y > zz.b or (b.y + b.h) < zz.t or b.x > zz.r or (b.x + b.w) < zz.l then kill = true end
      end
```

对应 CSV 改成 8 个参数：

```csv
0,BoneH,121,266,405,1,160,2,1
```

效果：橙骨下缘一过框底（y>391）立刻消失，框外不再有多余的 0.44s；其它横骨（`final` 阶段①的 `BoneHRepeat` 等）**完全不受影响**（没打标记）。

## 6. 落地与验收（等你确认后由主程序执行）

```powershell
cd D:\stars\workspace\sans-fight
node tools/gen-attacks.mjs      # 改了 CSV 必须跑
node tools/build-save.mjs
node tools/run-lua.mjs lua/core_selftest.lua     # 期望 PASS（当前 296 / 0）
node tools/verify-all.mjs --quick
```

| 验收 | 期望 |
|---|---|
| multi3 Attack5/5Other | 该段起手即出现 1 根橙色横骨，`x 121..526`、`y` 从 266 向下 |
| 覆盖 | 骨宽 = 405 = 框宽（`zone.r - zone.l`） |
| 时序 | 0.78s 扫过框底；1.2s 段末被黑屏清掉（方案 A） |
| 判定 | 灵魂**按住方向键**时不掉血；**完全静止**（含只按 Enter 跳）时会掉血 |
| 无回归 | 其它回合/其它段、竖骨的中轴引信、终盘骨刺/旋转龙骨炮全部不受影响 |

---

*本文只提供修改代码，**未修改工作区任何文件**；§3 的时序数据来自内存 patch 版 CSV 的真实 `World` 运行（探针位于 `D:\stars\_analysis\`，不属工作区）。*

---

# 【订正·2026-10-07】橙骨位置改到「骨刺阶段」，每轮一根

你的澄清：
> 我需要在这个阶段的**每轮骨刺**增加橙骨；主程序把橙骨加到了 round22 **首段**，请删掉首段那根，改到**骨刺阶段**。

## 1. 已删除：首段（multi3 Attack5 贴地骨带）那根

`prototype/attacks/multi3.csv` 里新增过的那行已移除：

```diff
 0,BoneVRepeat,121,354,37,2,0,20,20
-0,BoneH,121,266,405,1,160,2
 0,RND,Side,2
```

（相应删掉了 `lua/_rounds.lua` 里那条 `HUD22 新增…橙色横骨` 登记）

## 2. 已新增：骨刺阶段（`sans_bonestab3`）**每轮一根**

`prototype/attacks/sans_bonestab3.csv`（该脚本一轮 = SansSlam + BoneStab，循环 6 轮）：

```diff
 0.26666,SansSlam,$Direction
+0,BoneH,241,216,165,1,180,2        ← 橙色横骨：整框宽、从上往下扫
 0,BoneStab,$Direction,9,1.2,0.25
 1.23333,JMPABS,6
```

**同时必须改的 1 处跳转**（插入 1 行后 `EndAttack` 从第 26 行变成第 27 行）：

```diff
-0,JMPZ,26,$Loop
+0,JMPZ,27,$Loop
```

参数依据（该段框 = `241..406 × 226..391`，宽 165、高 165）：

| 参数 | 值 | 依据 |
|---|---|---|
| x / 宽 | **241 / 165** | 正好等于框宽（覆盖整个战斗框） |
| y | **216** | 框顶 226 上方 10px（骨厚 10），起手即进入框内 |
| dir | **1** | 向下 = 从上往下扫 |
| speed | **180** | 0.97s 扫过框高、1.47s 飞出屏 < 每轮 1.5s → **每轮只有一根在场** |
| color | **2** | 橙色：灵魂"不动"时才受伤（本段是红心自由移动，必须一直按 WASD） |

## 3. 实测（真实脚本，未改渲染）

`D:\stars\_analysis\probe_bonestab3_orange.lua`：

```
t=0.32 橙骨#1 … y=219 vy=180   骨刺#1 dir=2
t=1.82 橙骨#2 … y=219 vy=180   骨刺#2 dir=1
t=3.32 橙骨#3                  骨刺#3 dir=1
t=4.82 橙骨#4                  骨刺#4 dir=0
t=6.32 橙骨#5                  骨刺#5 dir=1
t=7.82 橙骨#6                  骨刺#6 dir=2
t=9.05 脚本 EndAttack（共 6 轮）
框 = x 241..406（宽 165）  骨刺 6 根 / 橙骨 6 根
橙骨宽度 = 框宽？ 一致 ✓（165 vs 165）
```

## 4. 验收

```
core_selftest       309 PASS / 0 FAIL   （新增 round22-orange-stab 组 3 条：骨刺段有橙骨 / JMPZ 26→27 / multi3 首段已无橙骨）
_rounds              75 PASS / 0 FAIL
verify-all --quick    8 / 8 通过
```

> 口径提醒：橙色判定用**方向键**（`core.lua:2488 moved = keys.left/right/up/down`），跳跃/确认键不计入 —— 这一段是红心自由移动，所以"一直按方向键"才是安全的。

---

# 【最终口径·2026-10-07】橙骨放两处（机制相同）

你的澄清：
> 你的 round22（内部 22 = `sans_bonestab3`）是我玩到的 **ROUND 23**；请在我玩到的 **ROUND 22**（= 内部 21 = `multi3`）**末尾的骨带段**也加上橙骨，机制一样。

即：**两处都要，都是同一套"橙色横骨从上往下扫、覆盖整个战斗框"的机制**。

| # | 玩家的回合 | 内部号 | 脚本 / 段 | 橙骨行 | 数量 |
|---|---|---|---|---|---|
| ① | **ROUND 23 / 24** | 22 | `sans_bonestab3`（骨刺阶段） | `0,BoneH,241,216,165,1,180,2` | **每轮骨刺各 1 根，共 6 根** |
| ② | **ROUND 22 / 24** | 21 | `multi3`（`Attack5` / `Attack5Other` 末尾贴地骨带段） | `0,BoneH,121,266,405,1,160,2` | 该段每次播放 1 根 |

两处参数都取自各自段自己的战斗框：

| 项 | ① `sans_bonestab3` | ② `multi3` 骨带段 |
|---|---|---|
| 框 | `241..406 × 226..391`（165×165） | `121..526 × 276..391`（405×115） |
| x / 宽 | 241 / **165**（整框宽） | 121 / **405**（整框宽） |
| y | 216（框顶−10） | 266（框顶−10） |
| dir / color | 1（向下）/ 2（橙） | 1（向下）/ 2（橙） |
| speed | 180（0.97s 扫完框高，1.47s 飞出屏 < 每轮 1.5s） | 160（0.72s 扫完框高，段末 1.2s 清场） |
| 判定 | 不动（不按方向键）才受伤 —— 同 `core.lua:2488` 的 `moved` | 同左 |

**实测**

```
① sans_bonestab3：骨刺 6 根 / 橙骨 6 根，橙骨宽 165 = 框宽 ✓（D:\stars\_analysis\probe_bonestab3_orange.lua）
② multi3 Attack5：橙骨 x 121..526（宽 405 = 框宽 ✓）0.02s 进框、0.78s 划过框底、1.22s 段末清场
```

**验收**：`core_selftest` 309 PASS / 0 FAIL（`orange-sweep` 组同时钉住 ① 6 根/轮、② 单根）· `_rounds` 76 PASS / 0 FAIL · `verify-all --quick` 8 / 8 通过 · `sans-fight.save.json` 已重建。
