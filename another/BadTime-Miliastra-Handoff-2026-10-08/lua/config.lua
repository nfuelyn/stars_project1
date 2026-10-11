-- 编辑完配置后运行 python tools/build.py，再导入生成的 main.lua。
local C = {}
C.difficulty = 'original'       -- easy / normal / hard / original
C.trainingItems = false         -- true 才添加旧版的 20 个传奇面包
C.updateCallback = 'level'      -- 官方：level；仅 OnUpdate 的外部宿主：ui
C.device = 'auto'               -- auto / keyboard / mobile
C.debug = false

-- 以下是原脚本的工程模板索引。新建工程后替换为你实际的“控件模板索引”。
-- 这些数字不是所有工程通用的 ID，也不是画布中的运行时控件 id。
C.templates = {
  rect = 1073741855, circle = 1073741857, ring = 1073741859,
  rot = 1073741856, rtri = 1073741858,
  text = 1073741860, cursor = 1073741861,
  baked = 1073741862, bakedC = 1073741862, bakedRoot = 1073741862,
}
C.legacyTemplateFallback = false
-- 0 = 沿用模板内的图片；正整数才按当前工程的真实图片资产 ID 替换。
-- 模拟器的 100001 等编号不是已确认的官方通用资产编号。
C.images = { rect = 0, circle = 0, ring = 0, rot = 0, rtri = 0 }

-- 填“已配置的音效 ID”；0 表示静音。不在脚本中导入外部 mp3。
C.audio = {
  bgm = 0, bgmLoop = true,
  -- bgm=0 时，可选用现有的单音旋律；默认关闭。
  useNoteMusic = false, notes = {}, pitchClasses = {}, fallbackNote = 0,
  effects = { menu = 0, confirm = 0, cancel = 0, hit = 0, heal = 0,
              jump = 0, blasterCharge = 0, blasterFire = 0,
              soulMode = 0, slam = 0, death = 0, victory = 0,
              boneWarn = 0, boneStab = 0,
              scriptSoundFlash = 0, scriptSoundDing = 0, scriptSoundGasterBlaster = 0 },
}
C.settlement = { signal = 'SansFightSettle', retryDelay = 1, maxAttempts = 3 }
return C
