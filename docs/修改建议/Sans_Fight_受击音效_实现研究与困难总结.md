# 受击音效：原版实现 / 沙箱能力 / 现状差距 / 困难与方案

- **原版来源**：`D:\c2-sans-fight-src`（Construct 2 版 Bad Time Simulator）
  事件表 `Event sheets/Battle.xml`、`Menus.xml`、`RPGText.xml`、`System.xml`；音频资产 `Files/*.ogg`
- **沙箱来源**：`D:\miliastra-beyond-simulator`（模拟器运行时 + 官方文档蒸馏），
  以及 `D:\stars\another\BadTime-Miliastra-Handoff-2026-10-08\docs\部署与设置.md`（§6 音效与 BGM）、
  `D:\stars\workspace\sans-fight\docs\music-fit.md`（现役 BGM 音效方案）
- **工作区**：`D:\stars\workspace\sans-fight`（`lua/core.lua`、`lua/main.lua`、`lua/music.lua`、`lua/config.lua`）
- **日期**：2026-10-13
- **方法**：逐条读原版事件表（含 `<param name="Audio file">` 全量扫描 + 调用点回查）＋ 读模拟器 Lua 运行时
  的音频实现（参数个数与句柄生命周期是**从代码读出来的**，不是猜的）＋ 核对本工程现有音频通道

---

## 0. 一句话结论

**技术上完全可行、成本很低**：复用现役音效通道即可，**不需要服务端节点图、不需要新挂载点**，只是原脚本多一个模块行为。

**但有三条硬约束**：

1. **音色不由我们决定** —— 只能用千星音效库里已有的资产，`PlayAudio2D` 收的是「已配置音效资产 ID」；
2. **离线绝对听不到、也没法自动验证** —— 模拟器的 `PlayAudio2D` 只登记句柄不出声（见 §4-D3），
   而且它的句柄**永不自动结束**，会让「限流」这类逻辑在离线得到完全错误的结论（§4-D4，这是最大的坑）；
3. **原作那 3 个受击音效文件不能拿来用** —— 本工程 GDD 已明文约定「不使用 Undertale 的任何图像 / 音频 / 字体 / 文本」。

所以正确做法是：**把触发时机做对**（这部分可以离线断言），**音色交给平台资产**（这部分只能真机试听）。

---

## 1. 原版是怎么做的

### 1.1 原版音频资产全表（`Files/`，18 个 ogg）

| 资产 | 用途 |
|---|---|
| `mus_zz_megalovania.ogg` | 战斗 BGM（1.87 MB） |
| **`PlayerDamaged.ogg`** | **受击（本文件主角）** |
| `Slam.ogg` | 甩击撞墙 |
| `BoneStab.ogg` | 骨刺伸出 |
| `Warning.ogg` | 骨刺预警（BoneStabWarn 阶段） |
| `GasterBlaster.ogg` / `GasterBlast.ogg` / `GasterBlast2.ogg` | 龙骨炮：出现 / 开火 / 开火变体 |
| `HeartSplit.ogg` / `HeartShatter.ogg` | 灵魂裂开 / 碎裂（GAME OVER） |
| `PlayerFight.ogg` / `PlayerHeal.ogg` | 菜单「战斗」确认 / 使用回复道具 |
| `MenuCursor.ogg` / `MenuSelect.ogg` | 菜单移动 / 确认（在 `Menus.xml`） |
| `SansSpeak.ogg` | 台词气泡逐字音（在 `RPGText.xml:225`） |
| `BattleText.ogg` | 战斗文本音（在 `System.xml:645`） |
| `Ding.ogg` / `Flash.ogg` | 在工程资产表里，但**事件表里找不到 `<param name="Audio file">` 播放点**（可能由模板/其它机制触发）—— 本次不涉及，留作未决项 |

### 1.2 受击音效在原版里有 **3 个**触发点（不是一个）

| # | 位置 | 条件 | 播放 |
|---|---|---|---|
| ① | `Battle.xml` **L7778–7796**，函数 `DamagePlayer` | 任意普通命中（骨头 / 龙骨炮 / 蓝骨 / 橙骨 / 浮空板…） | **`PlayerDamaged`** |
| ② | `Battle.xml` **L3467–3475** | 甩击撞墙、**水平**：`abs(PlayerHeart.CustomMovement.dx) > 330` | `PlayerDamaged` **+** `Slam`（同帧两连放）+ `SansShake` |
| ③ | `Battle.xml` **L3578–3586** | 甩击撞墙、**垂直**：`abs(PlayerHeart.CustomMovement.dy) > 330` | 同上（`dy` 版） |

`DamagePlayer` 的原文（逐条转写）：

```
On function "DamagePlayer":
    LastDamageTime := time
    HP := HP - Function.Param(0)        -- 伤害值
    KR := KR + Function.Param(1)        -- 业障
    Play "PlayerDamaged" (Loop=0, Volume=0)
```

它在同一张表里被 **5 个地方**调用（L7902 / L7988 / L8038 / L8071 / L8104）—— 正好对应原版五种弹幕的命中分支。
**这就是「所有普通受击只有一个播放点」的原因**：伤害与音效绑在同一个函数里。

### 1.3 两个容易漏掉的原版事实

- **KR（业障）燃烧扣血是静默的。** 全表只有 3 处 `PlayerDamaged`（①②③），KR 每 tick 扣 1 滴血**不在其中**。
  所以实现时**不要**在 KR tick 上加音效，否则会变成「滴滴滴」连响，比原版吵得多。
- **撞墙是「两连放」**：`PlayerDamaged` 与 `Slam` 同一帧各播一次。因为我们用的是同一条音效通道，
  两个同时触发只会互相抢占（§4-D6），要么放弃 `Slam` 层，要么给「受击」和「撞墙」分别留冷却。

### 1.4 与我们代码的对应关系

| 原版 | 工作区（`lua/core.lua`） | 备注 |
|---|---|---|
| `DamagePlayer` 函数 | **`Game:hurt(kind, karma, src)` L2091–2109** | 单一漏斗；`self.hp = self.hp - 1` 在 L2093 |
| 甩击撞墙 + `SansShake` | slam 分支 **L2419–2435**（`v > 330` → `sansShake` + `slamDamage` 扣 1） | 与我们「撞墙」语义一一对应 |
| KR 燃烧（无音效） | `Game:updateKR` **L2112–2132** | 保持静默，**不加音效** |
| 受击视觉反馈 | `self.flash = 0.12`（L2103） | 目前受击只有红闪，**没有任何音频** |

**结论：要接的只有两个地方 —— `Game:hurt`（普通受击）和 slam 分支里的 `v > 330`（撞墙）。**

---

## 2. 千星（沙箱）能给我们什么

### 2.1 客户端 Lua 只有三个音频 API

| 接口 | 参数个数 | 说明 |
|---|---|---|
| `game.PlayAudio2D(audioId)` | **1** | 播放 2D 音频，返回句柄 `h` |
| `game.StopAudio(h)` | 1 | 停止指定句柄 |
| `game.IsAudioAlive(h)` | 1 | 查询句柄是否存活 |

参数个数是从**模拟器运行时代码**读出来的（`D:\miliastra-beyond-simulator\client\lua-runtime\src\runtime.js`：

`PlayAudio2D: 1, StopAudio: 1, IsAudioAlive: 1`，见 `GAME_ARG_COUNTS`，L44）。
模拟器实现（同文件 L512–526）：

```js
PlayAudio2D: (LL) => {
  const id = rt.nextAudioId++
  rt.audios.set(id, { audioId: lua.lua_tointeger(LL, 1), alive: true })   // ← 只登记，不出声
  lua.lua_pushinteger(LL, id)
  return 1
},
StopAudio: (LL) => { const a = rt.audios.get(...); if (a) a.alive = false; return 0 },
IsAudioAlive: (LL) => { lua.lua_pushboolean(LL, !!(a && a.alive)); return 1 },
```

### 2.2 `audioId` 到底是什么

> **已配置的音效资产 ID** —— 不是音效播放器实例序号、不是文件路径、不是脚本模板索引。

`0` = 静音（不报错、静默降级）。**没有「按文件名播」的通道**，也没有音量 / 音高参数。

### 2.3 拿到 ID 的两条路（官方两条文档）

| 路径 | 入口 | 适用 |
|---|---|---|
| 客户端 Lua 直接播 | `game.PlayAudio2D(audioId)` | **我们的路线**（不需要节点图、不需要挂载点） |
| 音效播放器（组件） | 实体/元件 → 组件页签 → **音效播放器** → 详细编辑 → 添加音效 | 可调音量 / 播放速度 / 循环 / 3D；适合场景 BGM，不适合逐次命中的短音效 |

- 官方音频 API：<https://act.mihoyo.com/ys/ugc/tutorial/detail/mhtakr07vej4>
- 官方音效播放器：<https://act.mihoyo.com/ys/ugc/tutorial/detail/mhwiv89yra02>
  （⚠ 这两页实测是 SPA 空壳，`Invoke-WebRequest` 拿到的是 6918 字节的壳、抓不到正文 —— 见 §4-D10）

### 2.4 沙箱侧已知约束（都来自本地知识库转述的官方口径）

- **没有音量 / 音高 / 声像接口**，官方明确「不要写不存在的 `SetAudioPitch`」；
  音量与混音只能用**资产本身**或**播放器组件**解决。
- **Lua 无法停止它没有创建的音频实例** → 不要同时挂一个自动循环的场景 BGM 播放器又用 Lua 播同一首，会叠音且停不掉。
- `bgmLoop=true` 是「播完再播」而不是采样级无缝。

---

## 3. 工作区现状：路已经铺好了 90%

| 项 | 现状 | 结论 |
|---|---|---|
| 音效通道 | `lua/music.lua` 已有：`hasSink()` 探测 + `pcall` 包裹 + `PlayAudio2D` / `StopAudio` | ✅ 直接复用 |
| 静音安全 | `id == 0` 直接 `return`（L141），不报错不卡住 | ✅ 与 `C.audio=0` 约定一致 |
| 绑定表 | `M.SFX`（精确音名）/ `M.SFX_PC`（12 音级）/ `M.FALLBACK`，**目前全为 0** | ⚠ 全静音 → 日志里就是那句 `音效绑定 0 项` |
| 短音效 API | `fire()` 是 **local**，只服务 BGM 的「单声部」；`M` 没有对外 `sfx()` | ❌ 需要新增 |
| 句柄管理 | `M.voice` 单声部：每次 `fire` 先 `stopVoice()` | ⚠ 单声部模型，受击音效会被 BGM 抢掉 |
| 配置项 | `lua/config.lua` **没有 `C.audio` 段**（但 `another\千星沙箱接口总结.md` §8、`部署与设置.md` §6 都写着「填 `C.audio`」） | ❌ 文档与代码不一致，需要补 |
| 生命周期 | `main.lua:3020` 调 `music.stop(); music.stopEffects()`，而 **`music.lua` 里没有 `stopEffects`** | ❌ 潜在 bug（被 `pcall` 吞掉，目前表现为「停音效」只停了 BGM） |
| 架构约束 | `千星沙箱接口总结.md`：「核心层 `lua/core.lua` **不直接依赖平台接口**，因此可以离线测试」 | ⚠ 音效**不能**在 core 里直接调 `PlayAudio2D` |
| 离线可测性 | `docs/music-fit.md` §：「模拟器的 `PlayAudio2D` 只登记句柄、**不出声**……音色、音量、是否串音只能在真机听」 | ⚠ 见 §6 |

---

## 4. 困难（逐条，附证据）

### D1 音色不由我们决定
`audioId` 必须指向**当前工程已配置的音效资产**。平台音效库给什么音色，我们只能用那个 ——
做不出「原作那一声 `PlayerDamaged`」的听感，只能找**最接近的金属/打击类短音**。

### D2 版权：原作音频不能拿来用
本工程 `docs/gdd.md` 已明文写死：

- L166 权利假设：「**不使用 Undertale 的任何图像、音频、字体、文本**」；
- L205 分级标注：`must-reproduce` = 移动手感 / 预警 / KR / 1HP 下限 / 回合节奏 / 菜单；
  `can-degrade` = 命中特效、Sans 表情；**`concept-only` = 音效**、最终结局演出；
- L162 可访问性：「所有危险状态都有**颜色之外的反馈**……**不依赖音频**」。

⇒ 受击音效在本项目里是**锦上添花**，不是验收项。做的时候要保证「没有音效也完全可玩」。

### D3 离线听不到声音
模拟器（以及试玩页那一层）的 `PlayAudio2D` **只往 Map 里塞一条记录，不做任何播放**。
官方支持表也写着「界面动效 …… 官方皮肤/**音效未播放**」。
⇒ 音色、音量、延迟、是否串音 **100% 只能在真机听**。

### D4 ★ 致命坑：模拟器的音频句柄**永不自动结束**
`alive` 字段**只有 `StopAudio` 会置 false**，代码里没有任何「播完了」的回收：

```
rt.audios.set(id, { audioId: ..., alive: true })   // PlayAudio2D
if (a) a.alive = false                             // 只有 StopAudio
// 全文件再无其它写 alive 的地方
```

所以 `IsAudioAlive(h)` 在离线**永远返回 true**。后果：

- 任何「上一次还在播就别播新的」限流（`if game.IsAudioAlive(last) then return end`），
  **离线会在第一次之后彻底哑掉**，而真机是正常按时间间隔触发的；
- 反过来，如果用 `not IsAudioAlive(last)` 判断「上一次播完了」再重播，离线**永远不重播**。
- 结论：**受击音效的限流禁止用 `IsAudioAlive`**，要用我们自己的 `os.clock`/帧计时（core 侧时间即可）。

### D5 句柄只增不减
模拟器 `rt.audios` 是个只 `set` 不 `delete` 的 Map，`nextAudioId` 单调递增。
一次战斗上百次受击 → 上百条僵尸记录。模拟器里无害，但它提醒我们：
**真机上不 `StopAudio` 的短音效实例会由引擎回收，但如果我们自己缓存句柄表不清，会长期占内存**。
⇒ 句柄表要**只留最近若干个**（环形覆盖），不要 `table.insert` 无限追加。

### D6 同帧多次命中 / 与 BGM 抢声部
- 一帧内可能同时命中多根骨头 / 多发龙骨炮 → 会在同一帧连调好几次 `PlayAudio2D`，
  听起来是「一声爆响」或「卡顿」。需要在 main 侧**同帧去重**（一帧最多一次受击音）。
- `music.lua` 的 `fire()` 是**单声部**（`M.voice`），受击音效若复用它，会把 BGM 那个音掐掉，
  而 BGM 每 0.192s 才推进一次 → 表现为「受击时 BGM 掉一个音」。所以要**独立的句柄槽**。

### D7 音量 / 音高接口未确认
官方页抓不到正文（见 D10），本地知识库只写了「没有确认的音高修改 API」「脚本未提供客户端音量接口」。
「用 1 个音色 + 不同音高拼出 3 种受击音」这条路**目前不能假定存在**，属于待探针项。

### D8 没有统一的 SFX 触发点（架构约束）
`core.lua` 是纯逻辑层，**不允许**直接调 `game.*`（否则离线测试全废）。
所以必须在 core 与 main 之间加一条**事件通道**（§5.1），不能图省事在 `Game:hurt` 里直接播。

### D9 `0` 是静音而不是报错
`audioId = 0` 静默降级 —— 好处是「没配资产也能跑」，坏处是
**「我明明接了音效却没声音」和「我根本没接」在日志上长得一模一样**
（我们现在的 BGM 就是全 0，日志只有一行 `音效绑定 0 项`）。
⇒ 要补一条显式的**绑定计数 / 首次触发日志**，否则真机上白查半天。

### D10 环境限制：官方文档抓不到正文
`https://act.mihoyo.com/ys/ugc/tutorial/detail/mhtakr07vej4` 与 `mhwiv89yra02` 实测都是
返回 **6918 字节的同一个 SPA 壳**，正文由前端异步渲染 → 无法用命令行取证。
⇒ 音频能力的**最终依据只能来自本地知识库转述 + 编辑器内实测**，本文件里的接口事实均标注了出处。

### D11 端到端还有一个「看不见的敌人」：千星脚本缓存
音效改完必须 `node tools/build-save.mjs && node tools/sync-sandbox.mjs`，
并且**完全退出试玩再重进**（脚本只在关卡加载时读一次）。
否则会得到「改了没效果」的假象 —— 这个坑本项目已经踩过多次（见 `main.lua` BUILD 注释）。

---

## 5. 推荐方案

### 5.1 架构：core 发「音效命令」，main 负责播放

沿用现成的 **render 命令**通道（`shake` 就是这么做的：core 每帧推 `{kind='shake',x,y}`，main 在 L1868 读）。
好处：

- core 保持零平台依赖 → 离线可断言；
- 音效与「那一帧发生了什么」天然对齐，不会跨帧漂移；
- 静音 / 未绑定资产时 main 侧直接跳过，战斗逻辑完全不受影响。

### 5.2 改动清单（5 处，均在 `D:\stars\workspace\sans-fight`）

1. **`lua/core.lua` — `Game:hurt()`（L2091–2109）末尾**：记一次受击事件
   ```lua
   self.sfxHit = (self.sfxHit or 0) + 1     -- 本帧受击次数（main 读走并清零）
   ```
2. **`lua/core.lua` — slam 分支 `v > 330`（L2419–2428）内**：再加一个撞墙事件
   ```lua
   self.sfxSlam = (self.sfxSlam or 0) + 1
   ```
3. **`lua/core.lua` — `renderWorld`/`M.render` 里**：把这两个计数转成命令（照抄 `shake` 的写法）
   ```lua
   if (g.sfxHit or 0) > 0 then push(cmds, { kind = 'sfx', name = 'damage' }); g.sfxHit = 0 end
   if (g.sfxSlam or 0) > 0 then push(cmds, { kind = 'sfx', name = 'slam' }); g.sfxSlam = 0 end
   ```
4. **`lua/main.lua` — 画帧前扫一遍 `cmds`**（L1860 那一段同款循环）：
   ```lua
   if cmd.kind == 'sfx' and music then music.sfx(cmd.name) end
   ```
   **注意**：`'slam'` 用「与受击不同的槽位」，并且撞墙那一帧不要重复播 'damage'（§1.3）。
5. **`lua/music.lua`**：新增对外短音效 API（**独立句柄槽**，不复用 `M.voice`）
   ```lua
   M.SFX_EVENT = { damage = 0, slam = 0, warning = 0, bonestab = 0, blaster = 0 }  -- 填千星音效资产 ID
   M.SFX_GAP   = { damage = 0.10, slam = 0.12, warning = 0.12, bonestab = 0.10, blaster = 0.06 }
   function M.sfx(name)                 -- 自己计时冷却，**不用** IsAudioAlive（见 D4）
     local id = M.SFX_EVENT[name]
     if not id or id == 0 or not hasSink() then return false end
     local now = M.sfxClock or 0
     if now < (M.sfxNext or {})[name] then return false end      -- 同音效最小间隔
     ...
   end
   ```
   并在 `M.update(dt)` 里累加 `M.sfxClock`，在 `M.stop()` 里停掉所有受击句柄。
6. **`lua/config.lua`**：补上文档里承诺、代码里缺失的 `C.audio`（受击音效 ID 集中在这里，不散落在 music.lua）
   ```lua
   C.audio = { damage = 0, slam = 0, warning = 0, bonestab = 0, blaster = 0 }  -- 0 = 静音
   ```

### 5.3 明确**不要**做的事

- ❌ 不要在 `Game:updateKR` 加音效（原版 KR 燃烧静默，§1.3）；
- ❌ 不要用 `IsAudioAlive` 做限流（离线语义错误，§D4）；
- ❌ 不要在 `core.lua` 里直接写 `game.PlayAudio2D`（破坏离线可测架构，§D8）；
- ❌ 不要复用 `M.voice` 单声部槽（会掐掉 BGM 的音，§D6）；
- ❌ 不要挂场景循环 BGM 播放器 + Lua 同播（叠音且停不掉，§2.4）；
- ❌ 不要引入任何原作音频资产（§D2）。

### 5.4 静音安全（沿用本工程既有约定）
所有音效 ID 默认 `0` → `id == 0` 直接返回，**不报错、不卡住、战斗逻辑不受影响**。
这样「先静音试玩通过，再接音效」这个交付顺序仍然成立（`部署与设置.md` 也是这么要求的）。

---

## 6. 真机验收步骤（**离线测不了，必须做**）

1. 打开千星游戏窗口 → 音效库**逐个试听**，挑出合适的短音（受击：金属/打击类；撞墙：低频闷响），**记录实际 ID**；
2. 填进 `lua/config.lua` 的 `C.audio`；
3. `node tools/build-save.mjs && node tools/sync-sandbox.mjs`
   （同步脚本会打印覆盖前后 sha 与 BUILD，确认 `变化 已更新`）；
4. **完全退出试玩再重进**（否则跑的是旧包，§D11）；
5. 看日志：应出现首次受击的 `sfx damage id=<N>` 绑定行（用来区分「没接」和「接了但没声音」，§D9）；
6. 听感清单（逐项勾）：
   - [ ] 受击一声，**不叠加**（连续挨打不会糊成一片）
   - [ ] 撞墙是「受击 + 闷响」，且不与受击音打架
   - [ ] 与 BGM **不互相掐断**（受击时 BGM 不掉音）
   - [ ] 从按下到出声**无明显延迟**（若延迟明显 → 说明该走「音效播放器组件」而不是 Lua 2D 播放）
   - [ ] KR 燃烧期间**安静**（只有受击那一刻响）

---

## 7. 附：来源速查

| 内容 | 位置 |
|---|---|
| 原版受击函数 `DamagePlayer` | `D:\c2-sans-fight-src\Event sheets\Battle.xml` L7778–7796 |
| 原版甩击撞墙（水平/垂直） | 同表 L3467–3475 / L3578–3586 |
| 原版全部音效播放点 | 同表 L113/127/356/1274/2085/2475/3467/3473/3578/3584/4998/5104/5471/5857/5867/7795/8394/8406；`Menus.xml` L256/306/354 |
| 原版音频资产 | `D:\c2-sans-fight-src\Files\*.ogg`（18 个） |
| 沙箱音频 API 与参数个数 | `D:\miliastra-beyond-simulator\client\lua-runtime\src\runtime.js` L44（GAME_ARG_COUNTS）、L512–526（实现） |
| 沙箱音频接口说明 | `D:\stars\another\千星沙箱接口总结.md` §8；`another\BadTime-Miliastra-Handoff-2026-10-08\docs\部署与设置.md` §6 |
| 现役音效通道 | `D:\stars\workspace\sans-fight\lua\music.lua`（`hasSink` L99 / `fire` L138 / `M.voice` L148） |
| 模拟器不出声的既有记录 | `D:\stars\workspace\sans-fight\docs\music-fit.md` §（"模拟器的 PlayAudio2D 只登记句柄，不出声"） |
| 版权与分级口径 | `D:\stars\workspace\sans-fight\docs\gdd.md` L162 / L166 / L205 |
| 我们的受击点 | `D:\stars\workspace\sans-fight\lua\core.lua` `Game:hurt` L2091、slam 分支 L2419、`updateKR` L2112 |