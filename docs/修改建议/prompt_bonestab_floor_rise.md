# 给主程序的提示词 —— 修复「底边骨刺向上升起」(BoneStab dir=1)

> 直接整段复制给主程序。目标仓库：`D:\stars\workspace\sans-fight`

---

## 任务

把「骨刺从战斗框**底边向上升起**」这一段（原作 `BoneStab`，`Direction = 1` / 南）
完全对齐参考仓库 `D:\c2-sans-fight-src`：几何、方向、伸出/停留/收回时序、命中矩形、三角形朝向。

## 一、要改的段落（工作区）

### 1) `lua/core.lua`

| 位置 | 现状 | 应改成 |
|---|---|---|
| `World:stabRect`（约 **L973–993**） | dir=1 已从底边升起（看着对），但请复核 dir 映射与 `distance` 取值 | 严格照原作几何（见下） |
| `World:stepStab`（约 **L949–969**） | `out` 用 `b.outDur or 0.1`；`in` 阶段**硬编码 0.1s** | 伸出/收回统一 = `distance*10`（=0.1s）；`outDur` 若保留为可调项需在文档标注为**有意差异** |
| `drawStab`（渲染） | 三角形朝向 | 与 `stabRect` 的 dir 映射**同源**，dir=1 时三角尖朝上 |
| 创建预警/骨刺的 CMD（`BoneStab` 命令处理） | — | 预警矩形按 dir 贴边，骨刺实体按 dir 生成 |

### 2) `lua/attacks.lua`

| 位置 | 脚本 | 说明 |
|---|---|---|
| 约 **L1026–1054** | `sans_bonestab1` | 原作 `BoneStab,$dir,25,0.4,0.33333`，Loop=9 |
| 约 **L1055–1083** | `sans_bonestab2` | 原作 `BoneStab,$dir,25,0.3,0.2`，Loop=9 |
| 约 **L1084–1117** | `sans_bonestab3` | 原作 `BoneStab,$dir,29,0.4,0`，Loop=9 |
| 约 **L136+** | `final` 阶段③ | `BoneStab,1,48,0.6,1`（含 dir=1 底边升起） |
| 约 **L1146** | `sans_intro` | `BoneStab,1,54,0.16666,1`（dir=1） |

> 工作区当前把三档的 `distance` 改成 9、`warn` 改成 1.2、`stay` 改成 0.25/0.33333/0.2，
> 并把 `Loop` 降到 6 —— 这些是**有意差异**，若要保持就**不要动脚本**，只改 core 的几何/时序逻辑。

## 二、回合号消歧（很重要）

「底边骨刺向上升起」= `BoneStab` 的 `Direction = 1`。它只出现在这些回合：

| 你说的 | HUD 号 | 内部 / HitAttempts 号 | 脚本 | 有 BoneStab？ |
|---|---|---|---|---|
| — | 1 | 0 | `sans_intro` | ✅ dir=1 固定 |
| （你说的 22） | 23 | 22 | `sans_bonestab3` | ✅ 随机 dir（含 1） |
| — | 18 | 17 | `sans_bonestab1` | ✅ 随机 dir（含 1） |
| — | 19 | 18 | `sans_bonestab2` | ✅ 随机 dir（含 1） |
| — | 24 | ≥23 | `final` 阶段③ | ✅ dir=1/3/2/0 各一次 |
| ⚠ 你说的 14 | 15 | 14 | `multi1` | ❌ 只有 BoneV，**没有骨刺升起** |
| ⚠ HUD 14 | 14 | 13 | `sans_spare`（休息回合） | ❌ 无 |

`core.lua` 的 `FIXED_SEQ`（约 **L1313–1322**）与 `scriptForRound`（约 **L1324**）是权威：
`[17]=sans_bonestab1, [18]=sans_bonestab2, [22]=sans_bonestab3, [23]=final`。
**所以「骨刺升起」应看 17 / 18 / 22 三档 + `final` / `sans_intro`；第 14 轮不含骨刺。**
（若你确实想改第 14 轮，请改向主程序说明你要的是哪个脚本。）

## 三、技术代码与权威来源（从这里取）

1. **原始事件逻辑**：`D:\c2-sans-fight-src\Event sheets\Battle.xml` → 事件组 **BoneStab**
   - `BoneStab(dir,distance,warnTime,stayTime)`：先 `BoneStabWarn`，倒计时归零后生成
     `BoneStabV`/`BoneStabH`，`speed = Distance*10` 滑到 Dest，停留 `StayTime`，再 `Reverse` 退回、出屏销毁。
2. **原始脚本数据**：
   - `D:\c2-sans-fight-src\Files\sans_bonestab1.csv` / `sans_bonestab2.csv` / `sans_bonestab3.csv`
   - `D:\c2-sans-fight-src\Files\sans_final.csv`（阶段③）、`sans_intro.csv`
3. **已校验的可运行参考实现**（建议直接用它对拍）：
   - `D:\stars\reference\lua\bonestab_floor_rise.lua` ← 本段 1:1 复刻（几何 + warn/out/stay/in + dir=1 逐帧轨迹）
   - `D:\stars\reference\lua\bone_battle.lua` ← BoneStab/骨墙/时间轴命令（更完整的引擎版）
4. **既有分析文档**：
   - `D:\stars\docs\修改建议\Sans_Fight_审判眼拖拽灵魂_机制总结与修改建议.md` §1.6「BoneStab：单侧骨刺」
   - `D:\stars\docs\修改建议\Sans_Fight_回合差异与蓝心物理_修改意见.md` §2.6 / §2.7（方向一致性、升起时间）

## 四、原作几何（dir=1 底边向上升起）

设战斗框 `(l,t,r,b)`，`distance = d`：

```
预警矩形 BoneStabWarn：
    w = (r - l) - 16
    h = d - 3
    x = l + 8
    y = b - h - 8            -- 贴框底内侧

骨刺实体 BoneStabV：
    w = (r - l)
    h = d + 8
    x = l
    y = b - 5                -- 起始：顶边在框底-5（露在外面）
    destY = b - 5 - d        -- 终点：顶边升到框底-5-d  => 向上探出 d px

运动：
    speed = d * 10           -- 0.1s 到位
    out  : 顶边 y 从 (b-5) → destY
    stay : 停在 destY 共 stayTime 秒
    in   : 沿 +y 退回，直到出屏销毁
```

对照（其余三向，确认映射没接反）：

| dir | 起始贴边 | 骨刺类型 | Dest |
|---|---|---|---|
| 0 东(右) | `x=r-5`, `y=t` | BoneStabH (`w=d+8`,`h=b-t`) | `destX=r-5-d`（向左刺 d） |
| 1 南(底) | `x=l`, `y=b-5` | BoneStabV (`w=r-l`,`h=d+8`) | `destY=b-5-d`（**向上**升 d） |
| 2 西(左) | `x=l+5-w`, `y=t` | BoneStabH | `destX=x+d`（向右刺 d） |
| 3 北(顶) | `x=l`, `y=t+5-h` | BoneStabV | `destY=y+d`（向下刺 d） |

## 五、验收标准

先跑基准：

```powershell
cd D:\stars
D:\5.1\lua.exe bonestab_floor_rise.lua
```

应看到（框 241,226,406,391，d=29）：

```
框底 y=391；起点 y=386；DestY=357  => 向上探出 29px
out 阶段 0.1s 内从 386 升到 357（每帧 29*10*dt）
stay 阶段停在 357
in 阶段原路退回并出屏销毁
```

工作区需满足：
- [ ] `dir=1` 的预警矩形贴**框底内侧**（x=l+8, y=b-h-8），骨刺从**框底**升起，不贴错边。
- [ ] 伸出 = `distance` px；伸出速度 = `distance*10`（0.1s）。
- [ ] 停留 = 脚本的 `StayTime`（bonestab3 原作是 0，工作区若改 0.25 需标注有意差异）。
- [ ] 收回沿原路，出屏销毁。
- [ ] `stabRect` 与 `drawStab` 的 dir 映射一致（dir=1 三角尖朝上）。
- [ ] 补一个确定性探针：固定 dt、固定 dir=1、d=29，断言 out 用 0.1s、终态 y = 框底-5-29。

## 六、不要做的事

- 不要把 dir 映射再写成反向（历史 bug：0↔2、1↔3）。
- 不要用「整条边升一排骨头」的 ArrowBone 覆盖单条 BoneStab（两者是不同机制）。
- 不要改动攻击延时政策范围内的数值（除非明确要求对齐原作）。