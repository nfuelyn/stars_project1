-- config.lua —— 与「当前千星工程」绑定的环境配置（模板索引 / 图片资产 / 更新回调 / 设备分流）。
--
-- 改动本文件后必须重建存档才会进到脚本里：  node tools/build-save.mjs
--
-- 注意：模板索引**不是跨工程通用的**。新建/换一个工程、或重新排布客户端控件之后，
-- 都要对着编辑器里的实际索引重填一遍。默认值写在 lua/main.lua 的 G / G_REAL / IMAGE_ID，
-- 这里留 nil 就沿用默认值（默认已经把「用户确认的模板索引」和「交接包实测索引」两套都列进候选）。
local C = {}

-- 更新回调：官方推荐 'level' —— 只走 OnLevelUpdate，和「关卡暂停」一致。
-- 只有当外部宿主**只**调用 OnUpdate（不调 OnLevelUpdate）时才改成 'ui'，否则战斗完全不推进。
-- 注意：两个回调都推进是错的，会让每帧跑两遍（速度翻倍、双倍伤害）。
C.updateCallback = 'level'

-- 设备分流：'auto' 读 game.GetDevice()；'keyboard' / 'touch' 可强制某一分支（真机调试用）。
C.device = 'auto'

-- 键位诊断（默认关）：true 时把 Enum.KeyEventType 里所有事件都挂上「按到就打印」的监听。
-- 真机上不确定某个物理键对应哪个事件名时打开它：按一下键，日志里会打 main: [keyDiag] <事件名>。
-- 查完记得改回 false（只用于诊断，会额外挂一百多个监听）。
C.keyDiag = false

-- 文字渲染方式：
--   'art'     = 用 lua/textart.lua 的矩形字形自绘（**默认**；原生文本框在真机渲染不出字形，
--               写入/尺寸/对齐都验证过是对的，所以绕开它）
--   'control' = 强行用原生文本框（只有想在模拟器里对照时才切）
C.textMode = 'art'

-- 文本渲染「隔离探针」（默认关）：true 时**不画战斗内容**，只画
--   ① 白色参照矩形  ② 画布里手放的文本框 TextProbe（脚本一个字都不写）  ③ 脚本实例化+写入的 4 个文本框。
-- 用来回答"这台机器到底能不能渲染原生文本框"，排除战斗/池清理/黑底/闪层的干扰。查完记得改回 false。
C.textProbe = false

-- 模板试错顺序：'sim' = 先试模拟器模板（离线自测/模拟器试玩页命中；真机对这些索引返回 nil，
-- 会自动接着试真机索引）；'real' = 先试真机模板。
C.templatesFirst = 'sim'
-- 是否允许回退到模拟器 GUID。模拟器/离线自测需要 true；纯真机工程可以改 false。
C.legacyTemplateFallback = true

-- 覆盖单个图元的模板索引（留 nil = 用 lua/main.lua 里的候选列表）。
-- 例子：C.templates = { rect = 1073741865, circle = 1073741871, ring = 1073741875,
--                      rot = 1073741877, rtri = 1073741879, text = 1073741867,
--                      cursor = 1073741860, baked = 1073741862, bakedC = 1073741862,
--                      bakedRoot = 1073741862 }
C.templates = nil

-- 图片资产 ID：留 nil / 0 = **沿用模板自带的图片**（真机推荐）。
-- 只有确认了当前工程里真实存在的图片资产 ID，才在这里填正整数；模拟器的 100001..100006
-- 是**内置图元编号**，真机没有对应资产，填进去会把图元刷成空白。
-- 例子：C.images = { rect = 100001, circle = 100002, ring = 100006, rot = 100001, rtri = 100003 }
C.images = nil

return C

