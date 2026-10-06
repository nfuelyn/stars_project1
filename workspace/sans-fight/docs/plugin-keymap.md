# PC 键控链路：引擎键名、宿主映射、以及插件侧缺的那一层

> 这一页回答一个问题：**在试玩页里按 WASD 为什么没反应，要在哪一层补。**
> 结论先给：游戏的 Lua 侧已经绑对了键名，**缺的是插件试玩页的「物理键 → 语义键」映射**。
> 全部结论都带源码出处（本机快照，非推断）。

## 1. 引擎真正派发的键名（可监听的 KeyEventType）

形如 `Keyboard<语义键名><Down|Up>`。

出处：`D:\my-dsh\profiles\web\node_modules\dsh-plugin-beyond-simulator\dsh-plugin\dist\worker.js`
（同一份运行时的打包产物；`client/lua-runtime/src/enums.js` 是它的可读源）

```js
// 键盘键码枚举（压缩名 hl）
hl=[...Array.from({length:43},(e,t)=>`CraftspersonKey${t+1}`),
    "MoveForwardKey","MoveBackwardKey","MoveLeftKey","MoveRightKey",
    "SwitchToWalkOrRunKey","SprintKey","JumpKey","DropKey","OpenShortcutWheelKey",
    "InteractKey","NormalAttackKey","CharacterSkill1Key","CharacterSkill2Key",
    "CharacterSkill3Key","CharacterSkill4Key","None"]
// 事件名 = 对每个键码拼 Down/Up（pl()）
for (const t of ["Down","Up"]) { ... e.push(`Keyboard${i}${t}`) ... }
```

于是**键盘侧确实存在**的键名是：

| 用途 | 键名 |
|---|---|
| 上下左右 | `KeyboardMoveForwardKeyDown/Up`、`KeyboardMoveBackwardKeyDown/Up`、`KeyboardMoveLeftKeyDown/Up`、`KeyboardMoveRightKeyDown/Up` |
| 其它（枚举里有，本项目没用） | `KeyboardInteractKey*`、`KeyboardNormalAttackKey*`、`KeyboardSprintKey*`、`KeyboardJumpKey*`、`KeyboardCraftspersonKey1..43*` … |

⚠ **键盘枚举里没有 `MenuConfirmKey` / `MenuBackKey`**（只有手柄枚举 `ml` 里有
`ControllerMenuConfirmKey*` / `ControllerMenuBackKey*`）。也就是说
`KeyboardMenuConfirmKeyDown` **不是引擎枚举里的名字** —— 它只存在于下面第 2 层的映射表里。

## 2. 物理键 → 语义键的映射在「试玩页」，不在引擎里

模拟器仓库 `D:\miliastra-beyond-simulator\studio\play\browser-session.js:7-16`：

```js
const SEMANTIC_KEY_CODES = new Map([
  ['KeyW', 'MoveForwardKey'], ['ArrowUp', 'MoveForwardKey'],
  ['KeyS', 'MoveBackwardKey'], ['ArrowDown', 'MoveBackwardKey'],
  ['KeyA', 'MoveLeftKey'], ['ArrowLeft', 'MoveLeftKey'],
  ['KeyD', 'MoveRightKey'], ['ArrowRight', 'MoveRightKey'],
  ['Enter', 'MenuConfirmKey'], ['NumpadEnter', 'MenuConfirmKey'],
  ['Space', 'MenuConfirmKey'], ['KeyZ', 'MenuConfirmKey'],
  ['Escape', 'MenuBackKey'], ['KeyX', 'MenuBackKey'],
  ['ShiftLeft', 'SprintKey'], ['ShiftRight', 'SprintKey'],
  ['KeyJ', 'NormalAttackKey'], ['KeyF', 'InteractKey'], ['KeyE', 'InteractKey'],
])
```

`keyEventName()` 再拼成 `Keyboard${semantic}${Down|Up}` 发给运行时。

**含义**：Enter / 小键盘回车 / 空格 / Z 在宿主层就被归并成同一个
`KeyboardMenuConfirmKeyDown`；Esc / X 归并成 `KeyboardMenuBackKeyDown`。
所以游戏侧只绑 `KeyboardMenuConfirmKeyDown` 一个确认键，就同时覆盖这四种按法。

## 3. 插件自带的试玩页：**表已经补好了**，但运行中的 `dsh web` 仍可能在发旧字节

### 3.1 插件试玩页到底加载哪个文件（已实测，不是推断）

链路（全部有源码/实测出处）：

1. DSH Web GUI 的客户端插件把试玩页当 iframe 打开：
   `dsh-plugin/dist/client.js` → `playUrl: e => "/qxqy-simulator/play#" + encodeURIComponent(e)`；
2. 插件宿主 `dsh-plugin/dist/index.js` 注册该路由，**页面 HTML 与渲染器都是读文件**：
   ```js
   function Mu(){ ... [new URL("./play.html",import.meta.url), new URL("../lib/play.html",import.meta.url)].find(存在) ... }
   //   → dist/play.html 不存在 → 回落到 dsh-plugin/lib/play.html
   function Nu(){ ... [new URL("../dist/play-renderer.js",import.meta.url), new URL("./play-renderer.js",import.meta.url)].find(存在) ... }
   //   → 两份都指向同一个文件：dsh-plugin/dist/play-renderer.js（读一次后缓存在模块级变量 br 里）
   ```
3. `dsh-plugin/lib/play.html` 内联的 `<script type="module">` 只有一行 import：
   `import { PixiPlayRenderer, createPlaySession } from '/qxqy-simulator/play-renderer.js'`
   —— 没有任何按键监听代码（唯一的 `keydown` 是「embedded 时 Esc 关闭页面」）。

**结论：插件试玩页加载的是**
`%DSH_HOME%\profiles\web\node_modules\dsh-plugin-beyond-simulator\dsh-plugin\dist\play-renderer.js`
（本机 `<DSH_HOME>` = `D:\my-dsh`），由 `/qxqy-simulator/play-renderer.js` 原样吐出。
`index.js` / `worker.js` 里的 `MoveForwardKey` 只是**枚举表**（`KeyboardKeyCode`），两处 `keydown` 命中数均为 0，
即它们不监听按键；**键监听只在浏览器侧的 play-renderer.js 里**。

### 3.2 实测：运行中的 dsh web 发的是**补表之前**的字节

```powershell
Invoke-WebRequest http://127.0.0.1:3080/qxqy-simulator/play-renderer.js -UseBasicParsing
# 2026-10-05 实测：HTTP 200, bytes=565449, SHA256 = B90BECBC…518C06
#   == dist/play-renderer.js.bak-pre-keymap 的哈希（补表前的旧产物）
#   != dist/play-renderer.js 的哈希（磁盘上已补表，MoveForwardKey 2 处）
#   Markers in SERVED bytes: MoveForwardKey: 0   CraftspersonKey: 1   keydown: 5
```

原因：`Nu()` 把文件内容读进模块级缓存 `br`，**每个进程只读一次**；该进程启动于 16:xx，
而补表发生在 19:32 → 缓存里还是旧字节（响应头 `cache-control: no-store`，所以浏览器端不是问题）。

> **修法：重启 `dsh web`（不是刷新页面就够了）。** 重启后再跑上面那条命令，
> 应看到 `MoveForwardKey: 2`、`served sha256 == dist/play-renderer.js` 的哈希。

### 3.3 磁盘上各份产物现在的状态

| 文件 | 映射表 | 说明 |
|---|---|---|
| `studio/play/browser-session.js`（可读源） | ✅ `SEMANTIC_KEY_CODES` | 第 2 层的唯一真源（`studio/test/browser-session.test.mjs` 6/6 覆盖） |
| `web/public/play-renderer.js`、`web/dist/public/play-renderer.js` | ✅ `KE=new Map([...])` | 由上面那份构建，两份字节完全相同 |
| `dsh-plugin/dist/play-renderer.js`（miliastra 仓库） | ✅ 函数 `Yu` 内联对象表 | 手工补的，与源等价 |
| `<DSH_HOME>\…\dsh-plugin\dist\play-renderer.js`（**实际被加载**） | ✅ 磁盘上已补 | 但**运行中的进程还在发旧字节** → 重启 `dsh web` |
| `dsh-plugin/dist/{index,worker,client}.js` | — | 只有枚举，没有监听（`keydown` = 0） |
| `lib/play.html`、`web/public/play.js` | — | 只有「Esc 关闭 iframe」，不产生引擎按键事件 |

### 3.4 重建产物（如果改了 `browser-session.js`）

```powershell
cd D:\miliastra-beyond-simulator
node scripts/build.mjs dsh-plugin        # 生成 dsh-plugin/dist（含 play-renderer.js）
# 再把 dsh-plugin/dist/play-renderer.js 覆盖到已安装插件目录，或用 dsh 重新安装该插件
```

不重启也能验证键控链路的办法：Agent 侧注入（`qxqy_studio_play {action:"key", args:{key:"KeyboardMoveForwardKeyDown"}}`
或 `runCase` 里的 `{ "kind": "key", "payload": { "typeName": "…" } }`）——
`worker.js` 的 `Control.injectKey(name)` 按**精确同名**查找监听器，不做白名单校验。
另外 `lua/main.lua` 现在会在**收到第一个键盘事件时**打一行
`main: 收到按键事件 <事件名>（若你按了 WASD 却从未出现这行，说明试玩页那层没转发按键）`
—— 一眼区分「页面没转发」还是「游戏没响应」。

## 4. 监听按键的前提（已核对源码，不需要额外配置）

`worker.js` 的 `Control.emitKey` / `Runtime.injectKey`：

```js
injectKey(t){ const i = n => { if(!n.alive || !n.activeInHierarchy) return false
                              if(n.keyListeners.has(t) && n.emitKey(t)) return true
                              for (const r of [...n.children]) if (i(r)) return true
                              return false }
              for (const n of [...this.roots]) i(n) }
```

- 只要控件 **alive 且 activeInHierarchy**，按精确名字注册的监听就会触发；
- **不需要** `SetControllerFocus` / `canControllerFocus`（那是手柄导航用的）；
- **不需要** `disableKeyEventPassthrough = false`（`injectKey` 根本不读这个字段）；
- `AddKeyEventListener` 在公共方法表里（所有控件都有），挂在根容器 `n1` 上和挂在 cursor 控件上等价；
- 光标（指针/触摸）事件才是另一条路：必须有祖先容器 `showCursor = true`（本项目存档里 `n1` 已开）。

## 5. 指针坐标口径（同一个坑的另一半）

试玩页把指针位置换算成**画布坐标**：

```js
function hv(i,t,e,r){ return { x:(i.clientX-t.left)*e/t.width,
                               y:(t.bottom-i.clientY)*r/t.height } }   // 注意 t.bottom - clientY
```

DOM 的 `clientY` 向下增大，`rect.bottom - clientY` 是**离画布底边的距离** —— 即
**画布原点在左下、Y 向上**（与引擎盒子 `Ne()` 的 `bottom = parentBottom + anchorMinY*parentH + anchoredPositionY - sizeY*pivotY` 一致）。
世界是 640×480、Y 向下，所以适配层换算必须是：

```lua
x_world = (x_canvas - OX) / S
y_world = 480 - (y_canvas - OY) / S     -- ← 必须翻一次，且只翻一次
```

`lua/main.lua` 的 `M.toWorld` 就是这条公式；写反的表现是**所有点按上下镜像**（点底部的按钮行 → 算到屏幕上方 → 「点了没反应」），
摇杆也会跟着反（往上拖、灵魂往下走）。
