# 《Bad Time Simulator (Sans Fight)》差距盘点与修改文档

- **源工程**：`D:\c2-sans-fight-src`（Construct 2 / HTML5，640×480，参考 30 FPS）
- **分析覆盖**：`Bad Time Simulator (Sans Fight).caproj`、`Event sheets\*.xml`（10 张事件表）、`Layouts\*.xml`、`Files\*.csv`（24 个攻击脚本）、`Documentation\*`、`Animations\*`、`Textures\*`
- **可读化转储**（由事件表 XML 转换，供复查）：`D:\stars\_analysis\*.xml.txt`
- **文档生成日期**：2026-10-05

---

## 0. 术语与读法（先读这一节）

| 术语 | 含义 |
|---|---|
| **回合数** | 即 `SansLegs.HitAttempts` 的值。本作中它**只在玩家使用 FIGHT、Sans 闪避动画走完一圈时 +1**（`Event sheets\Battle.xml` → `SansAnimation` 组 `DodgeState==3`，第 1777 行附近）。因此"回合 N"= 第 N 次 FIGHT 闪避之后触发的那一幕攻击。 |
| **脚本** | `Files\<名字>.csv`，由 `Timeline.xml` 的时间线 VM 解释执行；一个脚本 = 一个攻击图案。 |
| **实体名** | Construct 2 的对象名，与 `.caproj` / 事件表一致，例如 `PlayerHeart`、`BoneV`、`GasterBlaster`、`CombatZone`。 |
| **置信度** | ★★★ = 项目自述或代码可直接证实；★★ = 由代码逻辑推断；★ = 与原版《Undertale》对比，缺少原版帧数据、需逐个核对。 |

> 重要提醒：本作把 `HitAttempts` 当作"回合数"，但**ATT/ITEM/MERCY 回合不会让它 +1**（见 B-01），所以下表是"玩家每回合都选择 FIGHT"时的标准序列。

---

## 1. 回合 ↔ 攻击脚本 ↔ 战斗框 总对照表

| 回合 (HitAttempts) | 触发点 | NextAttack | 攻击脚本 | 战斗框 (Left,Top,Right,Bottom) | 主要实体 |
|---|---|---|---|---|---|
| 0 | 资源加载完成后自动播放 | 0 | `sans_intro` | 239,226,404,391 → 逐段变化 | `SansBody` `SansHead` `GasterBlaster` `BoneStab` `SineBones` `SansSlam` |
| 1 | 第 1 次 FIGHT 闪避后 | 1 | `sans_bonegap1` | 133,251,508,391 | `BoneVRepeat` |
| 2 | 2 | 2 | `sans_bluebone` | 133,251,508,391 | `BoneV`(Color=1) `PlayerHeart.Mode` |
| 3 | 3 | 3 | `sans_bonegap2` | 133,251,508,391 | `BoneV` `RND` `TLVars` |
| 4 | 4 | 4 | `sans_platforms1` | 133,251,508,391 | `Platform1/2` `BoneVRepeat` |
| 5 | 5 | 5 | `sans_platforms2` | 133,251,508,391 | `Platform1/2` `BoneV` |
| 6 | 6 | 6 | `sans_platforms3` | 133,251,508,391 | `PlatformRepeat` `BoneV` |
| 7 | 7 | 7 | `sans_platforms4` | 113,231,548,391 | `Platform1`(Reverse) `BoneVRepeat` |
| 8 | 8 | 8 | `sans_platformblaster` | 133,251,508,391 | `PlatformRepeat` `GasterBlaster` |
| 9 | 9 | 9 | `sans_platforms4hard` | 113,231,548,391 | `Platform1`(Reverse) `BoneVRepeat` |
| 10 | 10 | 10 | `sans_bonegap1fast` | 133,251,508,391 | `BoneVRepeat` |
| 11 | 11 | 11 | `sans_boneslideh` | 133,251,508,391 | `BoneVRepeat` |
| 12 | 12 | 12 | `sans_bonegap2`（第二次） | 133,251,508,391 | `BoneV` `RND` |
| 13 | 13 | — | `sans_spare`（休息回合） | 133,251,508,391 | 音乐暂停、`SansSweat` |
| 14 | 14 | 0 | `sans_multi1` | 133,251,508,391 | `BoneV` `Platform` `GasterBlaster` |
| 15 | 15 | 1 | `sans_randomblaster1` | 121,186,526,391 | `GasterBlaster` |
| 16 | 16 | 2 | `sans_multi2` | 241,226,406,391 等 | `Platform` `GasterBlaster` `SineBones` |
| 17 | 17 | 3 | `sans_bonestab1` | 241,226,406,391 | `BoneStabH/V` `BoneStabWarn` `SansSlam` |
| 18 | 18 | 4 | `sans_bonestab2` | 241,226,406,391 | `BoneStab` |
| 19 | 19 | 5 | `sans_randomblaster2` | 121,186,526,391 | `GasterBlaster`(Size=1) |
| 20 | 20 | 6 | `sans_boneslidev` | 241,226,406,391 | `BoneHRepeat` |
| 21 | 21 | 7 | `sans_multi3` | 239,226,404,391 | `BoneV` `Platform` `GasterBlaster` `SineBones` |
| 22 | 22 | 8 | `sans_bonestab3` | 241,226,406,391 | `BoneStab` |
| ≥23 | >22 | — | `sans_final` → 胜利 | 动态变化 | 全部攻击实体 + `SansSlam` |

**不可达内容**：`NextAttack==13`（`sans_platformblasterfast`）与 `NextAttack==14`（`choose(...)` 随机收尾）永远触发不到（见 B-02）。

---

## 2. 判定类差距（H）

### H-01 心判定盒与实际碰撞不一致 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 全部回合（所有攻击） |
| 脚本 | 全局 |
| 实体 | `PlayerHeart`、`PlayerHitbox`、`Attack9Patch`、`AttackSprite`、`AttackTiled` |
| 差距 | 心本体是 16×16 贴图；`PlayerHitbox` 是另建的 **4×4** 精灵，每帧跟随心。判定需同时满足"`Pick overlapping point(PlayerHeart.X, PlayerHeart.Y)`"与"`PlayerHitbox` 与攻击物重叠"。两套判定标准不一致，README 也自述"Heart hitbox is probably not accurate"。 |
| 代码位置 | `Event sheets\Battle.xml` → `PlayerDamage` 组（`LastDamageTime < time-0.033` 之后的三段判定） |
| 建议 | 统一为单一口径：把 `PlayerHitbox` 尺寸/形状与心贴图对齐，或在 `Pick overlapping point` 处直接使用心的碰撞多边形；必要时把 4×4 调整为与心中心一致的正确偏移。 |
| 置信度 | ★★★ |

### H-02 蓝/橙判定基于 `Is moving`，会被重力/平台带动干扰 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 2（`sans_bluebone`）、所有含蓝骨的回合（14、21） |
| 脚本 | `sans_bluebone.csv`、`sans_multi1.csv`、`sans_multi3.csv` |
| 实体 | `Attack9Patch.Color`、`PlayerHeart`（Custom Movement `Is moving`） |
| 差距 | 判定规则：Color=0 白→无条件伤害；Color=1 蓝→`Is moving` 为真时伤害；Color=2 橙→`Is moving` 取反时伤害。但 `Is moving` 是"速度≠0"，在蓝色（重力）模式下即使玩家不按键，重力下落/平台带动也会让速度≠0，导致蓝骨"站着不动也受伤"或橙骨误判。 |
| 代码位置 | `Battle.xml` → `PlayerDamage` 组（Color==1 / Color==2 分支） |
| 建议 | 改用"玩家输入是否产生位移"或"水平输入轴是否非零"作为蓝/橙判定，排除重力与平台 `dx/dy`；或按原作把蓝/橙判定绑定到"灵魂移动键"。 |
| 置信度 | ★★★ |

### H-03 橙色攻击（Color=2）引擎支持但零使用 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 无（引擎级） |
| 脚本 | 全部 24 个脚本 |
| 实体 | `Attack9Patch.Color`、`BoneH`、`BoneV` |
| 差距 | 全量扫描 24 个 CSV：骨头颜色字段仅出现 `0`（白，14 次）、`1`（蓝，10 次）、空（默认白，41 次），**Color=2（橙）从未被任何图案使用**；实现里却有完整橙骨判定分支。 |
| 代码位置 | `Battle.xml` → `Bones` 组、`PlayerDamage` 组；CSV 颜色字段（第 8 列） |
| 建议 | 若目标是与原作一致，确认原作是否使用橙骨；若使用则补图案，若不使用则移除或标注为未启用，避免维护成本。 |
| 置信度 | ★★★ |

### H-04 无敌帧仅 1 帧（0.033 秒） ★★
| 项 | 内容 |
|---|---|
| 回合 | 全部回合 |
| 脚本 | 全局 |
| 实体 | `LastDamageTime`、`HP`、`KR` |
| 差距 | 受伤条件为 `LastDamageTime < time - 0.033`，即约 30 FPS 下 1 帧的无敌。与原作 Sans 战的受伤节奏、连续判定盒（尤其激光/骨墙）是否一致需核对。 |
| 代码位置 | `Battle.xml` → `PlayerDamage` 组 |
| 建议 | 用原版逐步数据确认 i-frame 时长；如仅需防同帧重复结算，可改为"记录本帧已受伤"的布尔标记，避免跨帧被连续扣血。 |
| 置信度 | ★★ |

### H-05 同一帧多个攻击物只结算一次 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 全部密集图案（4-9、14-23，尤其 23 `sans_final`） |
| 脚本 | `sans_final`、`sans_multi*`、`sans_platformblaster*` |
| 实体 | `Attack9Patch`、`AttackSprite`、`AttackTiled` |
| 差距 | 三段判定使用同一个 `LastDamageTime` 门控，同帧内先命中的一段会立刻把 `LastDamageTime` 设为当前时间，后续攻击物的 `DamagePlayer` 不再满足条件——多个攻击物重叠时只吃 1 次伤害。 |
| 代码位置 | `Battle.xml` → `PlayerDamage` 组（`LastDamageTime` 门控 + 三段 IF） |
| 建议 | 这是设计取舍，但需确认原作"同一帧多判定"的行为；如需多段可给每个攻击物加独立命中冷却，或改为"本帧最多 N 次"。 |
| 置信度 | ★★★ |

### H-06 平台水平碰撞判定被禁用 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 含平台的回合：4、5、6、7、8、9、14、16、21 |
| 脚本 | `sans_platforms*`、`sans_platformblaster*`、`sans_multi*` |
| 实体 | `HeartCheckSolid`（函数）、`Platform1`、`PlayerHeart` |
| 差距 | `HeartCheckSolid` 中 Angle=0 与 Angle=180 的两个"平台侧面实体"分支在 XML 里为 `disabled="1"`，即心的左/右侧不会与平台发生实体碰撞；只有上/下（90/270）方向有效。 |
| 代码位置 | `Event sheets\Battle.xml` → 被禁用事件（Angle 0 / Angle 180 的 `Set return value`），对应 `PlayerMovement` 组 `HeartCheckSolid` |
| 建议 | 明确设计意图：若需要侧面阻挡则启用并按当前移动方向修正相对速度判断；若刻意省略，应在文档与代码注释中写明。 |
| 置信度 | ★★★ |

---

## 3. 移动类差距（M）

### M-01 `sans_platforms4` / `sans_platforms4hard` 平台没有加速过程 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 7（`sans_platforms4`）、9（`sans_platforms4hard`） |
| 脚本 | `sans_platforms4.csv`、`sans_platforms4hard.csv` |
| 实体 | `Platform1`、`Platform2`、`PlayerHeart` |
| 差距 | README 明确承认：平台本应从 0 加速到全速，本作直接以满速开始，导致"不跳、靠走位躲骨头"时难度与原作不符。 |
| 代码位置 | `Battle.xml` → `Platforms` 组（`Platform()` 直接 `Set speed Speed`）；`Project readme.md` 已知问题第 2 条 |
| 建议 | 给 `Platform1` 增加 `Accel`/`CurrentSpeed` 实例变量，在 `Platform()` 初始化并以恒定加速度爬到 `Speed`；或按原作给每块平台单独初速曲线。 |
| 置信度 | ★★★ |

### M-02 左右重力下的平台吸附分支被禁用 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 含左右重力 + 平台的回合（4-9、14、16、21） |
| 脚本 | `sans_platforms*`、`sans_multi*` |
| 实体 | `PlayerHeart`、`Platform1` |
| 差距 | 蓝模式"重力朝左/右"分支中，`Is overlapping at offset(Platform1, X*0.2, Y*0.2) → 把心速度设为平台速度` 的事件为 `disabled="1"`，心不会随左右运动的平台一起被带走。 |
| 代码位置 | `Battle.xml` → `PlayerMovement` 组被禁用事件 |
| 建议 | 若原作存在"心随平台平移"，需启用并补齐边界收束；若不需要，删除死代码。 |
| 置信度 | ★★★ |

### M-03 蓝模式重力为分段常数，手感与原作可能不符 ★★
| 项 | 内容 |
|---|---|
| 回合 | 全部蓝模式回合（2、4-9、13、14、16、17、18、20、21、22、23） |
| 脚本 | 大部分脚本 |
| 实体 | `PlayerHeart`（`Gravity`、`DownSpeed`） |
| 差距 | 重力按沿重力方向速度分 4 档常数：`(15,240)→540`、`(−30,15]→180`、`(−120,−30]→450`、`≤−120→180`；这是"跳跃顶点弱、下落强"的近似，但对不同 `MaxFallSpeed`（60~750、甚至负值）会产生不同手感。 |
| 代码位置 | `Battle.xml` → `PlayerMovement` 组（`// Handle gravity` 之前的分档） |
| 建议 | 用原版逐帧速度表核对；或改为连续函数（如根据 `DownSpeed` 插值），减少对 `MaxFallSpeed` 变化的敏感度。 |
| 置信度 | ★★ |

### M-04 战斗框夹取使用硬编码 5 / 8 像素 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 全部回合（受 `CombatZoneResize` 影响） |
| 脚本 | 全部（每个脚本都会 resize） |
| 实体 | `CombatZone`、`PlayerHeart` |
| 差距 | `CombatZoneTick` 用 `BBox+5` 与 `+8` 把心强行夹回框内；战斗框在脚本中频繁改变尺寸（见总表），边界处可能产生瞬移/抖动，且 5 与 8 的取值无文档说明。 |
| 代码位置 | `Battle.xml` → `CombatZone` 组（`PlayerHeart Is overlapping CombatZone` 分支） |
| 建议 | 抽出可配置的 `BorderPadding`/`HeartRadius` 常量，并在 resize 完成回调（`EndResize`）后再夹取，避免动画过程中反复推挤。 |
| 置信度 | ★★★ |

### M-05 减速键（HeartSpeed 150→75）为自制功能 ★★
| 项 | 内容 |
|---|---|
| 回合 | 全部回合 |
| 脚本 | 全局 |
| 实体 | `VPad.Cancel`、`HeartSpeed`、`PlayerHeart` |
| 差距 | 按住取消键（键盘 X / Shift，手柄 B）时移速减半到 75。原作 Sans 战没有该功能，仅影响难度与手感。 |
| 代码位置 | `Battle.xml` → `PlayerMovement` 组（按 `VPad.Cancel` 设 `HeartSpeed`） |
| 建议 | 若追求复刻应移除或改为可选项（如"练习模式辅助"）。 |
| 置信度 | ★★ |

### M-06 `MaxFallSpeed` 允许负值，依赖 clamp 方向 ★★
| 项 | 内容 |
|---|---|
| 回合 | 23（`sans_final` 用 `HeartMaxFallSpeed -300`），以及 `sans_final` 的 0/60/240/330/450/480/750 各段 |
| 脚本 | `sans_final.csv` |
| 实体 | `MaxFallSpeed`、`PlayerHeart` |
| 差距 | `HeartMaxFallSpeed` 直接覆盖全局 `MaxFallSpeed`，`sans_final` 传入负值实现"向上甩飞"。clamp 逻辑按 `Is within angle` 分 4 支比较 `MaxFallSpeed`，负值时语义反转，容易与 `SansSlam` 的 `Slammed` 逻辑互相干扰。 |
| 代码位置 | `Battle.xml` → `PlayerMovement` 组 clamp 分支 + `sans_final.csv` 第 37/45/94/188/197/204/209 行 |
| 建议 | 明确 `MaxFallSpeed` 允许负值的语义并加注释，或改用独立的 `SlamSpeed`；补充负值情况下的单元测试/手动回归清单。 |
| 置信度 | ★★ |

---

## 4. 攻击实体与图案类差距（P）

### P-01 `SineBones` 为自制图案且作者不推荐使用 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 0（`sans_intro`）、16（`sans_multi2` Attack7）、21（`sans_multi3` Attack7） |
| 脚本 | `sans_intro.csv`、`sans_multi2.csv`、`sans_multi3.csv` |
| 实体 | `SineBones`（函数）、`BoneV` |
| 差距 | 文档原文："Created out of laziness, probably shouldn't use."（出于偷懒才做的，最好不要用）。它用 `floor(sin(loopindex/3*180/pi)*28)` 生成 28 像素摆幅的上下两排骨，是自创图案，原作没有等价物，且参数耦合（`Spacing` 正负决定方向）不易复用。 |
| 代码位置 | `Battle.xml` → `Bones` 组 `SineBones()`；`Documentation\Attacks.md` |
| 建议 | 用 `BoneVRepeat` + 逐列 `Y/Height` 计算重写为可复用图案，或直接移除并在文档标注废弃。 |
| 置信度 | ★★★ |

### P-02 大量 `RND` 随机化，破坏原作固定序列 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 3、12（`sans_bonegap2`）；14-22、≥23（`sans_multi*`、`randomblaster*`、`sans_final`） |
| 脚本 | 出现 `RND` 的脚本：`sans_bonegap2`、`sans_multi1/2/3`、`sans_randomblaster1/2`、`sans_final`、`sans_platformblaster*` 等 |
| 实体 | `TLVars`、`RND`、各攻击实体 |
| 差距 | 全量统计 `RND` 出现 31 次，用于随机方向、随机骨高/骨速、随机子攻击选择（`Attack0..Attack8`）。原作 Sans 战整体是固定编排（少量已知随机），本作的高随机度让每次战斗都不可复现，无法逐帧对照原作。 |
| 代码位置 | 各 CSV；`Timeline.xml` 的 `RND` 实现 |
| 建议 | 提供"原作序列模式"：用固定跳转表/固定种子 RNG 替换 `RND`；保留随机模式作为可选难度。 |
| 置信度 | ★★★ |

### P-03 `GasterBlast1/2/3` 未纳入任何家族，清理不彻底 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 0、8、14、15、16、19、21、23（所有激光回合） |
| 脚本 | 所有含 `GasterBlaster` 的脚本 |
| 实体 | `GasterBlaster`、`GasterBlast1/2/3`、`GasterBlastHit` |
| 差距 | 家族关系：`AttackSprite = {GasterBlaster, MenuBoneLeft, MenuBoneBottom}`、`AttackTiled = {GasterBlastHit}`。底座 `GasterBlast1/2/3`（光束本体）**不属于任何家族**。`EndAttack` 只销毁 `Attack9Patch`+`AttackSprite`，`BlackScreen` 只销毁 `AttackSprite`+`Attack9Patch`，都不会清理 `GasterBlast1/2/3` 与 `AttackTiled`。若攻击在中途被强制结束，光束可能残留。 |
| 代码位置 | `Bad Time Simulator (Sans Fight).caproj` → `<families>`；`Battle.xml` → `EndAttack()`、`BlackScreen()` |
| 建议 | 把 `GasterBlast1/2/3` 加入 `AttackTiled`（或新建 `AttackBeam` 家族），在 `EndAttack`/`BlackScreen` 一并销毁；同时补上 `AttackTiled` 的清理。 |
| 置信度 | ★★★ |

### P-04 `*Repeat` 命令丢失第 6/7 个参数（颜色 / 反弹） ★★★
| 项 | 内容 |
|---|---|
| 回合 | 1、3、7、8、9、10、11、12、14、16、19、21、23 |
| 脚本 | 所有用 `BoneHRepeat` / `BoneVRepeat` / `PlatformRepeat` 的脚本 |
| 实体 | `BoneHRepeat`、`BoneVRepeat`、`PlatformRepeat`、`BoneH`、`BoneV`、`Platform1` |
| 差距 | `BoneH()`/`BoneV()` 签名是 6 个参数（…Speed, Color），但 `BoneHRepeat()`/`BoneVRepeat()` 内部调用只传 5 个参数，**Color 永远为默认 0（白）**；`Platform()` 签名含第 6 参 `BooleanReverse`，但 `PlatformRepeat()` 只传 5 个参数，**永远无法反弹**。因此"重复生成的蓝骨/反弹平台"无法通过 Repeat 命令实现。 |
| 代码位置 | `Battle.xml` → `Bones` 组 `BoneHRepeat/BoneVRepeat`；`Platforms` 组 `PlatformRepeat` |
| 建议 | 在 Repeat 命令签名中加入 Color / BooleanReverse 参数并透传；至少为彩色骨提供 Repeat 变体。 |
| 置信度 | ★★★ |

### P-05 `GasterBlaster` Size=0 时不设置高度，可能继承上一发高度 ★★
| 项 | 内容 |
|---|---|
| 回合 | 0、8、14、15、16、19、21、23 |
| 脚本 | 所有激光脚本 |
| 实体 | `GasterBlaster` |
| 差距 | `Size==0` 只 `Set width = ImageWidth*2`，不显式设高度；`Size==1` 设 2×高、`Size==2` 设 3×高。连续生成不同 Size 的激光时，Size=0 会沿用对象池/上一实例的高度基准，导致光束粗细不一致。 |
| 代码位置 | `Battle.xml` → `GasterBlasters` 组（`Size` 分支） |
| 建议 | 为每个 Size 都显式设置宽高，或在创建时先重置为默认尺寸再应用 `Size`。 |
| 置信度 | ★★ |

### P-06 激光命中体只在 `STATE_LEAVE` 且 `opacity>80` 时生效 ★★
| 项 | 内容 |
|---|---|
| 回合 | 所有激光回合（0、8、14、15、16、19、21、23） |
| 脚本 | 含 `GasterBlaster` 的脚本 |
| 实体 | `GasterBlastHit`、`GasterBlast1.Opacity` |
| 差距 | `GasterBlastHit` 的 `Damage/Karma` 在进入 `STATE_FIRE` 后才置 1，但 `Timer>5/30+BlastTime` 之后会随透明度衰减，`Opacity<=80` 时 `Damage` 被置 0 且隐藏。若 `BlastTime`（脚本里常见 0.03333~0.5）过短，命中窗口可能不足一帧或与动画不同步，存在"看起来被激光打中却不掉血"。 |
| 代码位置 | `Battle.xml` → `GasterBlasters` 组（`STATE_FIRE`、`GasterBlast1` 的 opacity 分支） |
| 建议 | 把命中窗口与视觉开火窗口解耦（进入 FIRE 即开启，离场前若干帧才关闭），并对最短 `BlastTime` 做下限保护。 |
| 置信度 | ★★ |

### P-07 骨刺 UID 关联在并发时可能混用 ★★
| 项 | 内容 |
|---|---|
| 回合 | 17、18、22、≥23（`sans_bonestab1/2/3`、`sans_final`） |
| 脚本 | `sans_bonestab*.csv`、`sans_final.csv` |
| 实体 | `BoneStabWarn`、`BoneStabH`、`BoneStabV` |
| 差距 | 警告块 `BoneStabWarn` 倒计时结束后，按 Direction 分 V/H 两支 OR 事件生成实体，再用 `UID` 把 `Direction/Distance/StayTime` 回填给 `BoneStab`。`UID` 变量是单值，若同帧内存在多个警告块同时到期（`sans_final` 里多次 `0.03333` 连续调用），可能交叉引用错误的警告数据。 |
| 代码位置 | `Battle.xml` → `BoneStab` 组（`For Each BoneStabWarn` + `Set value UID` + `Pick by unique ID`） |
| 建议 | 改为在 `For Each BoneStabWarn` 循环内完成生成与回填（不依赖全局单值 UID），或把 `BoneStabWarn.UID` 存到实体自身实例变量。 |
| 置信度 | ★★ |

### P-08 速度与尺寸多为手调值，未按原作换算 ★★
| 项 | 内容 |
|---|---|
| 回合 | 全部回合 |
| 脚本 | 全部 24 个 CSV |
| 实体 | `Bone.Speed`、`Platform1.Speed`、`GasterBlaster`、`CombatZone` |
| 差距 | 文档规定"原作值 × 30（FPS）= 像素/秒"，但脚本里的数值（骨头 60~900、平台 60~360、激光出膛插值 `*dt*10` 等）多为作者手调，没有统一换算依据，无法保证与原作逐条一致。 |
| 代码位置 | 所有 CSV 的数值列；`Documentation\Attacks.md` 的 Speed 说明 |
| 建议 | 建立"原作帧值 → 本作 px/s"的换算表，逐脚本标注来源；对无法对应原作的招（如 `SineBones`）单独标注为自创。 |
| 置信度 | ★★ |

### P-09 战斗框尺寸逐招变化，原作是固定场地 ★★
| 项 | 内容 |
|---|---|
| 回合 | 全部回合（每个脚本首行都会 `CombatZoneResize*`） |
| 脚本 | 全部 CSV |
| 实体 | `CombatZone`、`CombatZoneBorder`、`CombatZoneClipper/Unclipper` |
| 差距 | 本作使用 5 种以上不同战斗框：133,251,508,391 / 241,226,406,391 / 113,231,548,391 / 121,186,526,391 / 239,226,404,391 等；且有逐帧动画式 resize（`CombatZoneSpeed`）。原作 Sans 战场地基本固定，动态变框与本作的"平台/追逐"设计耦合。 |
| 代码位置 | 各 CSV 首行；`Battle.xml` → `CombatZone` 组 |
| 建议 | 若追求复刻，固定主要战斗框尺寸，仅在必要招（如 `sans_final`）做一次性变化；把每个脚本的框尺寸集中到一张配置表便于核对。 |
| 置信度 | ★★ |

### P-10 直接 `BoneV` 调用缺 Color 参数的情况普遍存在 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 1、3、7、9、10、11、12、19、20、21、23 等 |
| 脚本 | `sans_bonegap1/2`、`sans_boneslide*`、`sans_platforms*`、`sans_multi*`、`sans_final` |
| 实体 | `BoneV`、`BoneH` |
| 差距 | 许多调用只写到 Speed（如 `0,BoneV,503,286,100,2,300`），Color 省略默认为 0=白。这在需要蓝骨/橙骨的图案里会造成"应是彩色却生成白骨"的错误；本作仅 `sans_bluebone` 等少数处显式补了 Color=1。 |
| 代码位置 | 各 CSV；`Battle.xml` → `BoneH()/BoneV()` |
| 建议 | 建立脚本规范：颜色字段必填；或在 VM 层对缺失参数给出显式警告（`PanicFunc`）。 |
| 置信度 | ★★★ |

---

## 5. 战斗流程与回合类差距（B）

### B-01 `HitAttempts` 只在 FIGHT 闪避后 +1，ACT/ITEM/MERCY 不推进回合 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 全局（影响 13、22 两个阶段门控） |
| 脚本 | 全局 |
| 实体 | `SansLegs.HitAttempts`、`SansLegs.NextAttack` |
| 差距 | 全代码中 `HitAttempts` 唯一的 +1 在 `DodgeState==3`（FIGHT 闪避收尾）。若玩家使用 ACT/CHECK、ITEM、MERCY，`StartAttack` 仍会推进 `NextAttack`，但 `HitAttempts` 不变 → 阶段判断（`<13`、`==13`、`>13&&<=22`、`>22`）与 `NextAttack` 脱节：可能出现提前/推迟进入"休息回合"、`NextAttack` 超出已定义分支而不出招，甚至卡在菜单。 |
| 代码位置 | `Battle.xml` → `SansAnimation` 组 DodgeState==3（+1）；`BattleMenu` 组 `MenuCheckSans`/`MenuUseItem`/`MenuSpare`（直接 `StartAttack`） |
| 建议 | 按原作规则统一回合计数：在每次菜单动作结束、进入 `StartAttack` 前 +1（或把"回合数"与"FIGHT 次数"拆成两个变量）。 |
| 置信度 | ★★★ |

### B-02 `NextAttack==13` / `==14` 分支不可达 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 13 |
| 脚本 | `sans_platformblasterfast.csv`（正片里不会出现） |
| 实体 | `SansLegs.NextAttack`、`sans_platformblasterfast`、`choose()` |
| 差距 | 第一阶段 `NextAttack` 链（0..14）整体位于 `HitAttempts < 13` 事件内；到 `HitAttempts==13` 时改走 `sans_spare` 分支并把 `NextAttack` 清零，因此 `NextAttack==13`（platformblasterfast）与 `NextAttack==14`（`choose(sans_bonegap1fast, sans_bonegap2, sans_boneslideh, sans_platformblasterfast)`）永远不会执行。 |
| 代码位置 | `Battle.xml` → `StartAttack()` 第一/第二阶段分支 |
| 建议 | 把这两个分支移到正确阶段（例如第一阶段延长到 `HitAttempts<=13`，或把 platformblasterfast 收入第二阶段的随机池）。 |
| 置信度 | ★★★ |

### B-03 Practice 模式近乎不可用 ★★★
| 项 | 内容 |
|---|---|
| 回合 | Practice 模式（不按回合推进） |
| 脚本 | 任意 |
| 实体 | `PracticeMode`、`PracticeAttack`、`SetPracticeAttack` |
| 差距 | 三重问题叠加：(1) `SetPracticeAttack` 仅在 `System.Is in preview` 时写入 `PracticeAttack`；(2) 触发它的预览初始化事件是 `disabled="1"`；(3) 主菜单 "Practice" 直接进入 `BattleScreen`，没有任何"选择要练习的招式"界面。结果 `PracticeAttack` 恒为 0，练习模式只会反复播放 `sans_intro`。 |
| 代码位置 | `Battle.xml` → `PracticeMode` 组；`Battle.xml` 被禁用事件（Is in preview）；`MainMenu.xml` → `MenuModePractice` |
| 建议 | 去掉 `Is in preview` 限制；启用/重写预览初始化；为 Practice 增加招式选择菜单（可复用 MODE_SINGLE 的选单）。 |
| 置信度 | ★★★ |

### B-04 `PracticeMode` 每 tick 覆盖 `NextAttack`，与主流程冲突 ★★★
| 项 | 内容 |
|---|---|
| 回合 | Practice 模式 |
| 脚本 | 任意 |
| 实体 | `SansLegs.NextAttack`、`PracticeAttack` |
| 差距 | `PracticeMode` 组有每 tick 的 `Set NextAttack = PracticeAttack`，而 `StartAttack()` 又会 `NextAttack += 1`。两者同时运行会互相覆盖，导致每次进入的攻击不确定。 |
| 代码位置 | `Battle.xml` → `PracticeMode` 组（顶层每 tick 事件） |
| 建议 | 只在 `StartAttack` 开始时设置一次 `NextAttack`，不要在每 tick 覆盖。 |
| 置信度 | ★★★ |

### B-05 缺少 Sans 对白（剧情缺失） ★★★
| 项 | 内容 |
|---|---|
| 回合 | 0（开场）、13（休息）、≥23（胜利前后） |
| 脚本 | `sans_intro.csv` 末尾、`sans_final.csv` 末尾 |
| 实体 | `SansText`、`SansFont`、`SpeechBubble` |
| 差距 | README 明确："Sans dialog is missing."。原作 Sans 战有大量标志性台词，本作仅在开场/胜利保留了极少文本（如 "ready?"、"here we go."、"huff... puff..."、"alright, i guess you win."），破坏了剧情复刻。 |
| 代码位置 | `Battle.xml` → `RPGText` 组、`EndAttack`；`Documentation\Sans.md` |
| 建议 | 建立台词表（按回合/阶段索引）并补全；注意 `SansText` 第二参数 `EndFunc` 的用法。 |
| 置信度 | ★★★ |

### B-06 KR 高值提示文案被禁用 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 全部回合收尾 |
| 脚本 | 全局 |
| 实体 | `CombatZone.InfoText` |
| 差距 | `EndAttack` 中 `KR>0` 的文案（"You felt your sins crawling on your back."）生效，但 `KR>10`（"weighing on your neck."）与 `KR>20`（"KARMA coursing through your veins."）两个事件为 `disabled="1"`，玩家永远看不到更高 Karma 的提示。 |
| 代码位置 | `Battle.xml` → `EndAttack` 中被禁用事件 |
| 建议 | 直接启用这两个事件；或按原作文案重写。 |
| 置信度 | ★★★ |

### B-07 FIGHT 恒为 MISS 的实现方式 ★★
| 项 | 内容 |
|---|---|
| 回合 | 所有菜单回合 |
| 脚本 | 全局（菜单，不走 CSV） |
| 实体 | `Target`、`TargetChoice`、`Strike`、`SansLegs.DodgeState` |
| 差距 | 原作是"Sans 闪避你的攻击"，本作用 `TargetChoice` 从一侧扫到边界即判 MISS 并 `StartAttack`，只有按确认才触发 `Strike` + `DodgeState`；两者都会进入同一套闪避状态机。表现上都是 MISS，但"准星扫过却算打空"的逻辑与原作不同，且 `TargetChoice` 的随机左右方向（`random(2)`）也与原作固定节奏不同。 |
| 代码位置 | `Battle.xml` → `BattleMenu` 组 `MenuFightEnemy`、`Target`/`TargetChoice` 事件 |
| 建议 | 若追求复刻，固定 FAIL 的触发时机与方向；或至少让"准星扫过"不直接判 MISS。 |
| 置信度 | ★★ |

### B-08 菜单骨命中强制 HP≥1（原作保护机制） ★★
| 项 | 内容 |
|---|---|
| 回合 | 14-22（`HitAttempts>13 且 <=22`） |
| 脚本 | 不适用（菜单阶段） |
| 实体 | `MenuBoneLeft`、`MenuBoneBottom`、`PlayerDamage` |
| 差距 | 当命中物是 `MenuBoneLeft`/`MenuBoneBottom` 时，若 `HP<=0` 会被强制设为 1，保证玩家不会因挡菜单的骨头死亡。原作没有这条对玩家的"保底"。 |
| 代码位置 | `Battle.xml` → `PlayerDamage` 组（`Pick by unique ID` + `Set HP=1`） |
| 建议 | 明确这是有意为之（防卡死/防剧情断裂）还是 bug；若保留应在文档标注，若复刻则按原作处理。 |
| 置信度 | ★★ |

### B-09 只有 Sans 一个敌人，敌人列表写死 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 全部 |
| 脚本 | 全局 |
| 实体 | `MenuEnemyList`、`SansLegs` |
| 差距 | 源码注释直接写 "Be lazy, just Sans"、"Lazy again. Just Sans."，菜单的 FIGHT/ACT 目标列表硬编码为 Sans，没有可扩展的敌人数据结构。 |
| 代码位置 | `Battle.xml` → `BattleMenu` 组 `MenuEnemyList` |
| 建议 | 若只做 Sans 战可接受，但建议把目标抽成数组以复用；至少在文档写明单敌人限制。 |
| 置信度 | ★★★ |

### B-10 `Debug` 命令会卡死游戏且对外公开 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 任意（脚本中调用 `Debug` 即可） |
| 脚本 | 潜在 |
| 实体 | `Timeline` → `Debug` |
| 差距 | `Debug` 函数执行 `System.Set time scale 0`，会让游戏完全静止；它却出现在 `Timeline.xml` 的公开指令集里，且 `Documentation\Programming.md` 未提示危险性。 |
| 代码位置 | `Timeline.xml` → `On function Debug` |
| 建议 | 移除或改为仅预览模式可用的调试开关；至少在文档中标注"会冻结游戏"。 |
| 置信度 | ★★★ |

### B-11 胜利无结局演出 ★★
| 项 | 内容 |
|---|---|
| 回合 | ≥23 |
| 脚本 | `sans_final.csv` → `Win1`/`Win2` |
| 实体 | `Win1`、`Win2`、`SansText` |
| 差距 | `Win1` 只说 "alright, i guess you win."，`Win2` 直接 `Go to layout MainMenu`。原作有完整的胜利演出与后续剧情，本作完全省略。 |
| 代码位置 | `Battle.xml` → `Win1`/`Win2` |
| 建议 | 若目标是复刻，补一段胜利演出（至少保留 Sans 离场/台词节奏）。 |
| 置信度 | ★★ |

### B-12 `BlackScreen` 的副作用与清理范围未文档化 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 0、14、16、21、23（闪白切换） |
| 脚本 | `sans_intro`、`sans_multi1/2/3`、`sans_final` |
| 实体 | `BlackScreen`、`AttackSprite`、`Attack9Patch`、`AttackTiled`、`GasterBlast1/2/3` |
| 差距 | `BlackScreen(1)` 在显示黑屏的同时会 `Destroy AttackSprite/Attack9Patch` 并暂停音乐，且不处理 `AttackTiled` 与 `GasterBlast1/2/3`；`Documentation\Generalities.md` 只说"removes projectiles from the combat zone"，未说明会销毁哪些家族、是否暂停音乐。 |
| 代码位置 | `Battle.xml` → `BlackScreen()`；`Documentation\Generalities.md` |
| 建议 | 统一销毁所有攻击家族；文档补上音乐暂停/恢复与清理范围的说明。 |
| 置信度 | ★★★ |

---

## 6. 数值与参数类差距（V）

### V-01 伤害 / Karma 数值需逐条与原作核对 ★★
| 项 | 内容 |
|---|---|
| 回合 | 全部 |
| 脚本 | 全局 |
| 实体 | `Attack9Patch.Damage/Karma`、`AttackTiled.Damage/Karma`、`AttackSprite.Damage/Karma` |
| 差距 | 本作：所有骨头 `Damage=1, Karma=6`；`GasterBlastHit` 在开火时 `Damage=1, Karma=10`；菜单骨 `Damage=1`。原作 Sans 战所有攻击基础伤害为 1，但 Karma 的取值/上限/衰减与原作的对应关系需要用原版数据核对（本作把激光 Karma 设为 10，与骨头 6 不同）。 |
| 代码位置 | `Battle.xml` → `Bones` 组（设 `Damage=1, Karma=6`）、`GasterBlasters` 组（`Karma=10`） |
| 建议 | 建立"攻击实体 → 原作伤害/Karma"对照表，逐条核对并注明来源。 |
| 置信度 | ★★ |

### V-02 Karma 上限与衰减分档 ★★
| 项 | 内容 |
|---|---|
| 回合 | 全部 |
| 脚本 | 全局 |
| 实体 | `KR`、`KR_T`、`HP` |
| 差距 | 本作：`KR` 上限 40；强制 `KR <= HP-1`；衰减间隔分档 `>40:0.033s / >30:0.066s / >20:0.166s / >10:0.5s / 其余:1s`，每步同时扣 1 `KR` 和 1 `HP`。上限 40 接近原作，但衰减曲线是自定义的，且 `KR<=HP-1` 的保底为本作添加。 |
| 代码位置 | `Battle.xml` → `PlayerDamage` 组（KR 处理） |
| 建议 | 用原版 KR 衰减数据核对；对 `KR<=HP-1` 的保底单独标注为设计取舍。 |
| 置信度 | ★★ |

### V-03 心速 / 跳跃 / 重力 / 最大下落速度参数 ★★
| 项 | 内容 |
|---|---|
| 回合 | 全部 |
| 脚本 | 全局 |
| 实体 | `HeartSpeed`(150，减速 75)、`HEART_JUMP_STRENGTH`(180)、`HEART_JUMPHOLD_CUTOFF`(30)、`MaxFallSpeed`(默认 750)、`Gravity`(540/180/450/180) |
| 差距 | 均为作者手调常量，文档未给出来源；与原作逐帧手感是否一致无法从工程内部证明。 |
| 代码位置 | `Battle.xml` → `PlayerMovement` 组头部常量与 gravity 分档 |
| 建议 | 与原版逐帧数据对齐，或把常量集中到一张"手感参数表"并记录调参依据。 |
| 置信度 | ★★ |

### V-04 激光 `BaseSize` / `SineSize` 为反编译近似 ★★
| 项 | 内容 |
|---|---|
| 回合 | 所有激光回合 |
| 脚本 | 含 `GasterBlaster` 的脚本 |
| 实体 | `GasterBlast1.BaseSize/SineSize/Timer/BlastTime` |
| 差距 | 源码注释："Original calculation meant to lerp BaseSize to 35*scale over 4 frames at 30fps"、"No idea what is going on here, so decompiled code ftw."。光束宽度/脉动是反编译近似，`floor(35 * Height/ImageHeight / 4) * dt * 30` 的取整方式会让不同帧率下粗细不同。 |
| 代码位置 | `Battle.xml` → `GasterBlasters` 组 `GasterBlast1 Is visible` 事件 |
| 建议 | 用连续插值替代取整步进，避免帧率相关；补注释说明 35/4 的来历。 |
| 置信度 | ★★ |

### V-05 Slam 撞击阈值与抖屏强度 ★★
| 项 | 内容 |
|---|---|
| 回合 | ≥23（`sans_final` 大量 `SansSlam`），其他偶发 |
| 脚本 | `sans_final.csv`、`sans_bonestab*.csv`、`sans_intro.csv` |
| 实体 | `PlayerHeart.Slammed/SlamDamage`、`SansShake` |
| 差距 | 撞击受伤阈值 `abs(dx/dy) > 330`；抖屏强度 `floor(abs(dx/dy)/30/3)`；`SansSlamDamage` 控制是否额外扣 1 HP。这些阈值/公式为自定义，原作撞击是一次性固定伤害与固定演出。 |
| 代码位置 | `Battle.xml` → `PlayerMovement` 组（`On horizontal/vertical step`）；`SansShake` 组 |
| 建议 | 按原作撞击处理核对；把阈值抽成常量。 |
| 置信度 | ★★ |

### V-06 无敌帧 0.033s（与 H-04 同源） ★★
见 H-04。此处仅作为数值项登记。

---

## 7. 文档与工程类差距（D）

### D-01 `CombatZoneResizeAuto` 名称与实现不符 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 全部 |
| 脚本 | `sans_intro`、`sans_multi*`、`sans_final` 等使用即时变框的脚本 |
| 实体 | `CombatZoneResizeInstant` |
| 差距 | `Documentation\Combat.md` 写的是 `CombatZoneResizeAuto`，而事件表与 CSV 使用的真实命令名是 `CombatZoneResizeInstant`。按文档写脚本会直接报 "Label/命令不存在"（触发 `PanicFunc`）。 |
| 代码位置 | `Documentation\Combat.md`；`Battle.xml` → `On function CombatZoneResizeInstant` |
| 建议 | 把文档改为 `CombatZoneResizeInstant`，或为兼容加一个 `CombatZoneResizeAuto` 别名。 |
| 置信度 | ★★★ |

### D-02 `Jumps.md` 中 `JMPG` / `JMPNG` 说明错误 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 不适用 |
| 脚本 | 使用 `JMPG`/`JMPNG` 的脚本（如 `sans_randomblaster1/2`） |
| 实体 | `Timeline` 的 `JMPG`、`JMPNG` |
| 差距 | 文档把 `JMPG` 与 `JMPNG` 都描述成 "first value is less than the second value"（复制粘贴错误）。实际实现：`JMPG` 用 Comparison=4（大于），`JMPNG` 用 Comparison=3（小于等于）。 |
| 代码位置 | `Documentation\Jumps.md`；`Timeline.xml` → `On function JMPG/JMPNG` |
| 建议 | 修正为"greater than"与"not greater（≤）"。 |
| 置信度 | ★★★ |

### D-03 `SansText` 等命令文档参数不全 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 0、13、≥23 |
| 脚本 | `sans_intro.csv`、`sans_final.csv` |
| 实体 | `SansText`、`SansFont.EndFunc` |
| 差距 | `SansText` 实际有第二个参数 `EndFunc`（文本播放完毕/关闭后要调用的函数，默认 `EndSansText` 恢复时间线），文档只写了 `Text`；`BoneStab` 未说明 Direction 取值与坐标系；`GasterBlaster` 未说明 `EndAngle` 单位（度）与 Size 取值含义。 |
| 代码位置 | `Documentation\Sans.md`、`Attacks.md`；`Battle.xml` → `RPGText`/`SansText` |
| 建议 | 补全参数表（名称、类型、取值范围、默认值、副作用）。 |
| 置信度 | ★★★ |

### D-04 示例 `Examples\Loops.csv` 有一行缺逗号 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 不适用 |
| 脚本 | `Documentation\Examples\Loops.csv` |
| 实体 | `SUB` |
| 差距 | 第 6 行 `0,SUB,LoopVar,$LoopVar,1` 末尾没有逗号，与其他行格式不一致，按逗号分列会少一列，示例本身可能无法按预期运行。 |
| 代码位置 | `Documentation\Examples\Loops.csv` |
| 建议 | 补齐末尾逗号或统一列数。 |
| 置信度 | ★★★ |

### D-05 维护性注释与"偷懒"实现遗留 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 0、16、21、所有菜单回合 |
| 脚本 | `sans_intro`（SineBones）、`sans_multi2/3`、菜单 |
| 实体 | `SineBones`、`GasterBlast1`、`MenuEnemyList` |
| 差距 | 代码中留有 "Created out of laziness, probably shouldn't use."（SineBones）、"No idea what is going on here, so decompiled code ftw."（GasterBlast1）、"Be lazy, just Sans."（敌人列表）等注释，说明这些模块未经整理，维护/扩展风险高。 |
| 代码位置 | `Battle.xml` 对应函数；`Documentation\Attacks.md` |
| 建议 | 逐条重写或加注释说明算法来源，避免后续修改者踩坑。 |
| 置信度 | ★★★ |

### D-06 README 已声明的 3 个已知问题 ★★★
| 项 | 内容 |
|---|---|
| 回合 | H-01（全部）、M-01（7、9）、B-05（0、13、≥23） |
| 脚本 | 见各项 |
| 实体 | `PlayerHitbox`、`Platform1`、`SansText` |
| 差距 | README 已知问题：(1) 心判定盒不准；(2) platforms4/hard 平台未加速；(3) 缺少 Sans 对白。分别对应 H-01、M-01、B-05。 |
| 代码位置 | `readme.md` |
| 建议 | 修复后同步更新 README 的 Known Issues。 |
| 置信度 | ★★★ |

### D-07 物品系统 8 格但只注册 4 种 ★★★
| 项 | 内容 |
|---|---|
| 回合 | 菜单 ITEM 回合 |
| 脚本 | 不适用 |
| 实体 | `PlayerItems`、`ItemDB` |
| 差距 | `PlayerItems` 压入 8 个槽位：`0,1,2,3,3,3,3,3`；`ItemDB` 只注册 4 种（Butterscotch Pie / Instant Noodles / Face Steak / Legendary Hero）。后 5 格都是 Legendary Hero 的重复填充，与"8 格背包"的预期不符。 |
| 代码位置 | `Battle.xml` → 布局开始事件（PlayerItems 初始化）；`Items.xml` → `RegisterItem` |
| 建议 | 决定是"4 格"还是"8 格"设计；补齐物品表或缩减槽位。 |
| 置信度 | ★★★ |

### D-08 触摸多点触控 ID 处理较脆弱 ★★
| 项 | 内容 |
|---|---|
| 回合 | 全部（移动端） |
| 脚本 | 不适用 |
| 实体 | `TouchDPad`、`TouchButton`、`TouchA/B`、`Touch.TouchID` |
| 差距 | 触摸按下时用 `Touch.TouchID` 绑定，松开时按 `TouchID` 匹配销毁；虚拟 DPad 的位置与 `TOUCH_ZONE` 判定在多点同时按下/滑动时可能串号，`TouchA`/`TouchB` 与 DPad 的 ID 复用缺少加锁。 |
| 代码位置 | `InputManagement.xml` → `Touch` 组 |
| 建议 | 为每个触摸控件维护独立的活动触摸表，处理 `touchend` 失配与多指同时按下的情况。 |
| 置信度 | ★★ |

### D-09 `Debug` 命令未在文档中提示风险 ★★★
与 B-10 同源，登记在文档类：`Documentation\Programming.md` 未列出 `Debug` 的危害。

### D-10 `BlackScreen` 等命令的副作用未文档化 ★★★
与 B-12 同源，登记在文档类：`Generalities.md` 未写明 `BlackScreen` 会销毁攻击物并暂停音乐、`EndAttack` 会重置变量等。

---

## 8. 修改优先级与路线图

### P0（影响可玩性 / 正确性，建议先修）
1. **B-01** 回合计数：把 `HitAttempts` 的推进与菜单动作统一，避免阶段错位/卡死。
2. **B-02** 修复不可达分支，让 `sans_platformblasterfast` 等回到正片流程。
3. **B-03 / B-04** 修好 Practice 模式（去掉 preview 限制、启用初始化、避免每 tick 覆盖 `NextAttack`）。
4. **H-01** 统一心判定盒。
5. **P-03 / B-12** 统一攻击家族的清理（尤其 `GasterBlast1/2/3`、`AttackTiled`）。
6. **P-04 / P-10** 修 `*Repeat` 参数丢失与彩色骨缺参。

### P1（与原作一致性）
7. **M-01** 平台加速；**M-02 / H-06** 恢复被禁用的平台碰撞/吸附分支。
8. **P-02** 提供原作固定序列模式，减少 `RND`。
9. **P-01** 重写或废弃 `SineBones`。
10. **B-05 / B-11** 补台词与胜利演出。
11. **B-06** 启用 KR 高值提示。
12. **V-01~V-06** 用原版数据逐条核对数值。

### P2（工程与文档）
13. **D-01 ~ D-10** 文档修正、示例修正、物品系统整理、触摸输入加固。
14. **P-05 / P-06 / P-07** 稳健性修补。

---

## 9. 需用原版数据核对的开放项（本工程无法自证）

| 编号 | 待核对内容 |
|---|---|
| H-04 / V-06 | 原作 Sans 战受伤 i-frame 时长 |
| V-01 | 每种攻击的原作伤害与 Karma 数值 |
| V-02 | 原作 KR 上限与衰减曲线 |
| V-03 | 心速、跳跃初速/截断、重力、最大下落速度的逐帧原值 |
| V-04 | Gaster Blaster 的尺寸/脉动/开火时长逐帧原值 |
| V-05 | 撞击伤害阈值与抖屏表现 |
| P-02 | 原作 Sans 战的随机点与固定序列 |
| P-09 | 原作战斗框尺寸与是否变化 |
| H-03 | 原作是否使用橙色攻击 |
| B-07 | 原作 FIGHT/闪避的触发与判定方式 |
| B-08 | 原作挡菜单骨是否会造成致命伤害 |

> 说明：以上标 ★ / ★★ 的条目在缺少原版拆包帧数据时只能给出"疑似差距"，建议以原版 ROM 的帧/数值表为唯一依据逐条确认后再改。

---

## 附录 A：实体与家族速查

| 家族 | 成员 | 实例变量 |
|---|---|---|
| `Attack9Patch` | `BoneH` `BoneV` `BoneStabH` `BoneStabV` `BoneStabWarn` `Platform1` `Platform2` | `Damage` `Karma` `Color` |
| `AttackSprite` | `GasterBlaster` `MenuBoneLeft` `MenuBoneBottom` | `Damage` `Karma` |
| `AttackTiled` | `GasterBlastHit` | `Damage` `Karma` |
| `Bone` | `BoneH` `BoneV` | `Direction` `Speed` |
| `BoneStab` | `BoneStabH` `BoneStabV` | `Direction` `Distance` `DestX` `DestY` `StayTime` `Reverse` |
| 无家族 | `GasterBlast1` `GasterBlast2` `GasterBlast3` | `BlastTime` `Timer` `BaseSize` `SineSize`（仅在 GasterBlast1） |

| 关键对象 | 关键实例变量 |
|---|---|
| `PlayerHeart` | `Mode`（0 红 / 1 蓝）、`Slammed`、`SlamDamage`；Custom Movement 行为 |
| `SansLegs` | `NextAttack`、`HitAttempts`、`DodgeState`、`DodgeTimer`、`JustDodged`、`XSpeed` |
| `CombatZone` | `TargetLeft/Top/Right/Bottom`、`InfoText` |
| `GasterBlaster` | `Ang`、`EndX`、`EndY`、`EndAng`、`State`、`Timer`、`LeaveSpeed` |
| 全局变量 | `SimulatorMode` `EndlessStage` `PracticeTarget` `SingleAttack` `HP` `MaxHP` `KR` `KR_T` |

## 附录 B：装备/判定数值速查

| 项 | 值 | 位置 |
|---|---|---|
| 心贴图 / 判定盒 | 16×16 / `PlayerHitbox` 4×4 | `Animations\PlayerHeart`、`Animations\PlayerHitbox` |
| 红模式移速 | 150（按住取消键 75） | `Battle.xml` → `PlayerMovement` |
| 蓝模式跳跃初速 / 松手截断 | 180 / 30 | 同上 |
| 最大下落速度默认 | 750 | 同上 |
| 重力分档 | (15,240)→540；(−30,15]→180；(−120,−30]→450；≤−120→180 | 同上 |
| 受伤无敌 | 0.033 s | `PlayerDamage` |
| 骨头伤害 / Karma | 1 / 6 | `Bones` 组 |
| 激光伤害 / Karma | 1 / 10 | `GasterBlasters` 组 |
| KR 上限 / 保底 | 40 / `KR ≤ HP−1` | `PlayerDamage` |
| 撞击伤害阈值 | 速度 >330 | `PlayerMovement` |
| 战斗框基准 | 133,251,508,391（多数）/ 241,226,406,391（骨刺、final）/ 113,231,548,391（平台 4）/ 121,186,526,391（随机激光） | 各 CSV 首行 |

## 附录 C：证据来源

1. `D:\c2-sans-fight-src\Bad Time Simulator (Sans Fight).caproj`（对象、家族、实例变量、行为）
2. `D:\c2-sans-fight-src\Event sheets\Battle.xml`（战斗主体，628 KB）
3. `D:\c2-sans-fight-src\Event sheets\Timeline.xml`（时间线 VM）
4. `D:\c2-sans-fight-src\Event sheets\AttackLoader.xml`（CSV 加载）
5. `D:\c2-sans-fight-src\Event sheets\InputManagement.xml`（键盘/手柄/触摸）
6. `D:\c2-sans-fight-src\Files\*.csv`（24 个攻击脚本）
7. `D:\c2-sans-fight-src\Documentation\*.md`（指令文档）
8. `D:\c2-sans-fight-src\readme.md`（已知问题）
9. `D:\stars\_analysis\*.xml.txt`（上述事件表的可读化转储）

---

*本文档基于工程内可见证据编写；凡标 ★ 的条目为"疑似与原作有差距"，需以原版拆包数据最终确认。*
