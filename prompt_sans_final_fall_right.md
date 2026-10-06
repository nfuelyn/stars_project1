# 给主程序的提示词 —— 修复 sans_final「长框段 · 蓝心持续向右坠落」

> 直接整段复制给主程序即可。目标仓库：`D:\stars\workspace\sans-fight`

---

## 任务

修好 Sans 终盘 `sans_final` 的「长框段」，让 `dir=0`（重力向右）的蓝心行为与
原作 `D:\c2-sans-fight-src` 一致：终端速度由 `HeartMaxFallSpeed` 控制，
依次经历 **450 → -300 → 0 → 330**，最后以 **+330 px/s 持续向右坠落**并撞右框停住。

## 一、要改的段落（工作区）

### 1) 脚本数据 `lua/attacks.lua` 第 62–132 行（sans_final 长框段）

| 行 | 当前内容 | 期望 |
|---|---|---|
| 62 | `0.5,HeartMode,0` | 红魂，保持 |
| 64 | `0.2,SansSlam,2` | 应表现为「切蓝 + dir=2 + 沿 dir 满速甩出」 |
| 66 | `0.2,HeartMaxFallSpeed,450` | 终端速度 450，保持 |
| 67 | `0,HeartDir,0` | 只改重力方向为 0（向右），**不给初速** —— 这是本项目口径，保留 |
| 70 | `0,CombatZoneResize,241,226,650,391` | 框右边界拉到 650，保持 |
| 71 | `0.33333,HeartMaxFallSpeed,-300` | 负值必须生效：把沿 dir 速度钳到 **-300** |
| 78 | `0,HeartTeleport,40,$HeartY` | 心定位到 x=40，保持 |
| 79 | `0,HeartMaxFallSpeed,0` | 终端速度 0 → 重力向右但 vx 钳成 0（钉住） |
| 80 | `0,SansSlam,0` | 原版此处给 +0 初速（=0），保持语义 |
| 128 | `8,HeartMaxFallSpeed,330` | 8 秒后终端速度 330 |
| 129 | `0,SansSlam,0` | ★ 必须给出 **+330 初速** → 持续右坠 |
| 131 | `0,CombatZoneResize,-10,264,410,369` | 右边框 650 → 410 收拢 |

### 2) 核心逻辑 `lua/core.lua`

- **`CMD.SansSlam`（约 L590）** —— 当前是「瞬移到那一侧边界 + 速度清零」，需改为原版语义：
  ```
  ① 强制切蓝魂（HeartMode = HEARTMODE_BLUE）
  ② heart.dir = floor(param0)（0/1/2/3 = 东/南/西/北）
  ③ heart.vx = DX[dir] * heart.maxFall ;  heart.vy = DY[dir] * heart.maxFall
  ④ heart.slammed = true
  ```
  不要瞬移、不要清零速度。
- **`CMD.HeartDir`（约 L611）** —— 只改 `heart.dir`，**不强制蓝魂、不改速度**。保留（L67 要用）。
- **`CMD.HeartMaxFallSpeed`（约 L589）** —— 沿 dir 的终端速度，**必须支持负值**。
- **`Game:update` 蓝魂段（约 L2201 起）** —— 目前被拆成
  「`if slammed then` 专用甩击物理 + `else` 普通跳跃物理」两套。
  需**合并为一套**：
  - 重力永远沿 `heart.dir` 施加（4 档曲线见下）；
  - 每帧先加重力，再做 `if 沿dir速度 > maxFall then = maxFall end` 的钳位；
  - `slammed` **只用于撞墙伤害/抖屏判定**，不再单独走一套物理；
  - 跳跃方向 = **-dir**。
- **重力常量（L57 / L97-100）** —— 4 档曲线要对齐原作（`DownSpeed` = 速度在 dir 上的投影，沿重力为正）：
  ```
  15 < DownSpeed < 240   -> 540
  -30 < DownSpeed <= 15  -> 180
  -120 < DownSpeed <= -30 -> 450
  DownSpeed <= -120      -> 180
  ```
  ⚠ 注意：`core.lua` L62-66 现有注释用 `DownSpeed = -dy` 并把 540 标成「上升中」，
  **方向写反了**，请一并按原作修正。

## 二、技术代码与权威来源（从这里取）

1. **原始脚本数据**
   `D:\c2-sans-fight-src\Files\sans_final.csv` —— 第 **28–98 行** 就是本段。
2. **原始事件逻辑**
   `D:\c2-sans-fight-src\Event sheets\Battle.xml`
   - `PlayerMovement` 组：蓝魂重力分档、`MaxFallSpeed` 钳位、`HeartJump`
   - `SansSlam` 函数（切蓝 + 设角度 + 满速甩出 + `Slammed`）
   - `HeartMode` / `HeartMaxFallSpeed` 函数
   - `CombatZone` 组：框伸缩 + 每帧把灵魂夹回框内
3. **已校验的可运行参考实现（建议直接照它对齐）**
   - `D:\stars\sans_final_fall_right.lua` —— 本段 1:1 复刻 + 逐帧轨迹，**作为验收基准**
   - `D:\stars\blue_soul.lua` —— 蓝魂方向重力 / 4 档曲线 / 终端速度钳位 / 跳跃
   - `D:\stars\bone_battle.lua` —— 骨墙（BoneV / BoneVRepeat）与时间轴命令
4. **既有分析文档**
   - `D:\stars\Sans_Fight_审判眼拖拽灵魂_机制总结与修改建议.md`（SansSlam 五步、蓝魂 4 方向重力）
   - `D:\stars\Sans_Fight_回合差异与蓝心物理_修改意见.md` §3.1 / §3.2（合并单一方向重力）
   - `D:\stars\Sans_Fight_差距与修改文档.md` 第 186–190 行（负数 `HeartMaxFallSpeed` 语义）

## 三、验收标准

先跑基准（输出期望轨迹）：

```powershell
cd D:\stars
D:\5.1\lua.exe sans_final_fall_right.lua
```

基准逐帧结果：

```
t=3.20   dir=0(重力向右)  maxFall=450   vx=+450     （SansSlam,0 右甩）
t=3.53   maxFall=-300                  vx=-300     （钳位反向）
t=4.73   maxFall=0                     vx=0        （钉在 x=40，重力向右但被终端速度钳住）
t=12.73  maxFall=330                   vx=+330     ★ 持续向右坠落
t=13.80  撞右边框 |v|=330              x≈397 停稳  （SansSlamDamage=0，不扣 HP，仅抖屏）
```

工作区需复现以上全部条目，且满足：

- [ ] `dir=0` 时重力沿 +x；跳跃键沿 **-x**（向左）仍可用，能跳出。
- [ ] `HeartMaxFallSpeed` 为负值时钳位语义正确（`-300` → 持续向左）。
- [ ] `HeartMaxFallSpeed=0` 时**只能向左/上下动，无法向右移动**。
- [ ] `SansSlam` 会强制切蓝、设 dir、给满速初速，且 `slammed` 撞墙（|v|≥330）触发抖屏并按 `slamDamage` 决定是否 -1 HP。
- [ ] 骨墙（`BoneV` / `BoneVRepeat`，speed=900 向左）在 8 秒钉住期间持续扫过，能正常命中。
- [ ] 补一个确定性探针（固定 dt、固定随机种子），断言 t=4.73~12.73 期间 `vx==0`、t=12.73 之后 `vx==330`。

## 四、不要做的事

- 不要为「甩击」再留一套独立物理（那是当前 bug 根源）。
- 不要改动 8 秒骨墙段的数据（延时/数量/速度保持现状）。
- 不要用「瞬移到边界」替代原版的方向重力。