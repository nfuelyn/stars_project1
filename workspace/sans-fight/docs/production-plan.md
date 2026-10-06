# sans-fight · 制作计划

- 项目：`D:\stars\workspace\sans-fight\`（会话工作区已绑定 `D:\stars`）
- 当前步骤：**5 Lua 编码实现 已开工（UI 侧待建，脚本侧 API 已解锁）**
- 更新：2026-09-27

## 七步进度

| 步骤 | 状态 | 退出证据 |
|---|---|---|
| PREFLIGHT | ✅ | 环境核查完成；模拟器工具可用，工作区绑定 `D:\stars` |
| 1 策划案 | ✅ | `docs/gdd.md`：C1–C13 契约、20 回合结构（随机模板 + 螺旋档）、三档难度、四个菜单子面板 |
| 2 TDD 用例 | ✅（draft） | `tests/` 8 个 `qxqy-autotest` 用例；只做静态/schema 检查 |
| 3 HTML 效果展示 | ✅ **v2 已按用户反馈重做** | L1 自测 **58 PASS / 0 FAIL**；待用户再确认手感 |
| 4 美术参考与素材 | ⏳ 待步骤 3 再确认 | 目标 `docs/art-bible.md` |
| 5 Lua 编码实现 | 🚧 进行中 | API 已解锁（见下）；探针脚本已进模拟器存档；真实游戏脚本与控件树待建 |
| 6 测试 | —— | —— |
| 7 真机试玩与修复 | —— | —— |

## 已解除的阻塞：官方 2D/Lua API

用**单问题探针**在模拟器里实测拿到接口，写在 `docs/api-2d-lua.md`（含 ✅ 实测 / ❓ 待验 标记）。三个关键结论：

1. **逐帧回调是全局函数 `OnLevelUpdate(dt)`**（实测每帧 0.0333s）——游戏主循环挂这里。
2. **生命周期是全局函数** `OnInit` / `OnEnable` / `OnStart`；`script` 是 userdata，乱写字段会中断脚本。
3. 控件是 userdata，已实测 `SetAnchoredPosition` / `SetSizeDelta` / `SetVisible` / `SetActive` / `SetImage` /
   `SetAnchorMin` / `SetPivot` / `SetSiblingIndex` / `AddKeyEventListener` 存在，`Id` 是 number 字段；
   类型专属方法（`SetFillAmount` / `PlayAnimation` / `AddCursorEventListener` / `SetText`）待在对应控件上验证。

## 剩余阻塞

| 阻塞 | 影响 | 解除方式 |
|---|---|---|
| 类型专属控件方法未验证 | 进度条填充、动效播放、光标事件、文本设置要用探针逐个确认 | 步骤 5 内继续「一次一条问题」探针 |
| HTML v2 手感未确认 | 步骤 4 之后的美术与最终数值可能还要改 | 用户试玩 `prototype/index.html`（v2） |
| GIA 导出 | 导出按钮在模拟器顶栏，由用户点击 | 我建好工程后请用户导出「资产包 GIA（整合包）」；**GIA 不保存脚本挂载关系**，我会单列挂载步骤 |

## 本轮产出与已验证事实

- **复刻路线转向「1:1 不做简化」（用户指定）**：`docs/attack-manifest.md`
  - 新建 **`prototype/attack-engine.js`**：BTS 兼容攻击脚本引擎（弹幕/平台/灵魂/框体/流程/表现/运算/跳转 全套命令），**内部坐标系统一用原版 640×480**，渲染时整幅 ×1.5 → 原始数值逐字照用、零换算误差
  - 新建 **`prototype/attack-loader.js`**（直接读 CSV，支持 `#` 注释与 `:标签` 行）
  - **已移植 11 个攻击脚本**（`prototype/attacks/*.csv`）：intro、bonestab1/2/3、bluebone、bonegap1、bonegap1fast、bonegap2、boneslideh、boneslidev、spare
  - 新建 **`prototype/attack-selftest.js`** → **22 PASS / 0 FAIL**（无未知命令、都能 EndAttack）
  - 修掉 3 个真 bug：① `JMPREL` 被当绝对跳转 ② 跳转测试参数误含"目标行号" ③ `exec` 里 `var c = line.cmd` 是字符串 → `c.cmd` 恒 undefined、pc 归零
  - 关键细节：**标签行必须占一行**（原版 `JMPABS/JMPZ` 用 1-based 物理行号）；延时 = 「执行该行前要等的时间」（首行延时也生效）
  - 待移植 13 个：platforms1/2/3/4/4hard、platformblaster(+fast)、randomblaster1/2、multi1/2/3、final
- **原版贴图**：`Textures/*.png` 因 GitHub API 限流（403）暂未取到二进制；几何以 CSV 为准（更决定手感），贴图待限流恢复后用于形状校对
- **学习参考工程（用户指定 jcw87 的 Bad Time Simulator）**：`docs/bts-study.md`
  - 站点 [jcw87.github.io/c2-sans-fight](https://jcw87.github.io/c2-sans-fight/) / 仓库 [Jcw87/c2-sans-fight](https://github.com/Jcw87/c2-sans-fight)（Construct 2）
  - 读到的是**原始文件**：`Documentation/{Attacks,Jumps,Math,Combat,Generalities,Sans}.md` + `Files/sans_*.csv` + `Textures/*`
  - 关键收获：**速度换算 ×30**（原作是 30fps 的 px/帧）；**颜色 0 白 / 1 蓝 / 2 橙**；**`BoneStab` 自带 `WarnTime`**（我们"冒头预示"的官方对应物，还有贴图 `BoneStabWarn.png`）；**`SansSlamDamage` 可关砸击伤害**（"壁ドン不致死"的实现）；逐行解码了 `sans_intro`（回合 0）与 `sans_bluebone`（**蓝骨+白骨成对**）
  - **架构结论：Lua 侧攻击脚本改为表驱动**（`{t, cmd, args}` + 跳转），照抄它的 CSV 时序表模型
- **据研究新增实现**：**橙骨**（Color=2：静止受伤、移动安全）+ 蓝/橙交替 + 颜色图例；「原作」档速度 1.00 → 1.25
  - L1 自测 **68 PASS / 0 FAIL**（新增 orange-bone 段）
- **原作内容研究（上一轮）**：`docs/original-research.md`（23 回合、命中 1 伤害、无无敌帧、KR 掉到 1 HP 停、中场选仁慈即死）
  - 已实现：回合 0 不意打ち、中场、**「原作」难度档（无无敌帧 0.15s）**
- **可读性 v3**：`drawBone()` 实体骨头外观；地面骨头四段生命（**冒头 0.5s 非致命预示** → 伸出 → 保持 → 收回）+ `floorLock` 防致命窗口重叠；`drawBlaster()` **细实线**龙骨炮（头骨折线 + 5 条平行细实线光束 + 拉链线，无实心填充）
- **难度与节奏 v2**：四档难度；R2 平移墙 → **原地升降 + 缺口预警**，同时只允许一道
- **四个菜单各有独立 UI 面板**：攻击时机条 / 行动 4 项 / 道具 2 项 / 仁慈 2 项
- **上一轮研究的出处与结论**：
  - 可访问源：[神ゲー攻略「サンズ戦の攻略と倒し方」](https://kamigame.jp/undertale/page/206025294560134270.html)（回合级攻略，2025/04/22）、检索片段：[Undertale Wiki·Sans](https://undertale.fandom.com/wiki/Sans?diff=prev&oldid=39073)、[萌娘百科·Sans](https://moegirl.icu/zh-hant/Sans(undertale))、[pixiv百科事典·Sans](https://dic.pixiv.net/a/Sans)
  - **Undertale Wiki 与萌娘百科正文在本机被拦截（403 / fetch failed）**，因此主要依据日文攻略站 + 检索片段；未逐字核对的项目已在文档里标 `待核`
  - 关键结论：23 回合以上；命中 1 伤害；**无无敌帧**；KR 在菜单里也掉血且**掉到 1 HP 就停**；**第 12 次攻击后有中场**（可回血，**选仁慈=即死**）；最终回合三段（重力→横スク→骨→旋转光束）；壁ドン 0 伤害；撑过后 Sans 用"什么都没做的特殊攻击"拖到玩家放弃
- **按研究修正实现（fidelity v4）**：
  - 新增**回合 0 不意打ち**（骨波 + 一发光束，2.8s；光束放在离灵魂最远侧，保证"站着不动也活得了"）→ C17
  - 新增**中场**：第 3 回合后 Sans 停手，回合不推进、可反复补给；**此阶段选仁慈 = 立即死亡** → C16
  - 新增**「原作」难度档**：无敌帧压到 0.15s（原作 Sans 攻击 `ignore invincibility`）；普通/困难仍是 0.80/0.55s 以保手感 → C18
  - L1 自测 **66 PASS / 0 FAIL**；难度断言改为测「相邻两波生成间隔」（旧指标有幸存者偏差：越难越早死 → 波数反而更少）
- **四个菜单各有独立 UI 面板（v2）**：攻击时机条 / 行动 4 项（沉默不结束回合）/ 道具 2 项 / 仁慈 2 项

## 视觉 → 千星控件的映射（步骤 5 建资产时照此做）

| 原型画法 | 千星侧实现 |
|---|---|
| `drawBone` 骨干 + 骨球 | **图片控件**（图元 `100001–100006`）拉伸：骨干一个竖长条、每端两个小圆各一个图片控件，共 5 个/骨；或用客户端模板 `Tpl_Bone` 一次性实例化 |
| 骨头冒头预示的占位框 | 一个半透明 **图片控件**（细边框），冒头期 `SetVisible(true)`，伸出时隐藏 |
| `drawBlaster` 头骨折线 | 细长 **图片控件** 拼折线（每条线一个控件，高 2–3px），或用一个头骨模板 `Tpl_BlasterHead` |
| 光束 5 条细实线 + 拉链线 | **图片控件** 数组：5 条长条（高 1.5–3px）+ 9 条短条；全部走对象池，只改位置与可见性 |
| 蓝骨 / 白骨的青色区分 | `SetImage` 换 `imageId` 或改图片颜色（颜色格式 `#AARRGGBB`） |

> 注意：千星控件是**轴对齐矩形**，没有 canvas 的 `arc/bezier`；所以"圆骨球"要用圆形图元或方形图元近似，`drawBone` 的几何比例照搬即可。


