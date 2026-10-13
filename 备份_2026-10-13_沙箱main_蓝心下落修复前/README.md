# 备份：2026-10-13 沙箱 main（蓝心下落修复前）

- 来源：C:\Users\19637\AppData\LocalLow\miHoYo\原神\BeyondLocal\248255821\Beyond_Local_Save_Level\1073741827\external_lua_file\main.lua
- 含义：**千星试玩实际加载的那一份**（= 存档 assets.scripts[0].source 内联自足包，含 main+core+attacks+textdata+config）
- 备份时间：2026-10-13
- BUILD 标记：2026-10-11-bone-knob
- 字符数：772723（UTF-8 字节 860699）
- 与当时存档逐字节一致（sha256 515c21e357198c6a03a10cb286fea3f07f379b67a1a7ce9dedeb356ccb2d7954）

## 为什么留两份
- main.lua  —— 沙箱原样（千星真正读的文件）
- sans-fight.save.json —— 同一时刻的工作库存档，用来反查/回滚构建状态
  （重建回滚：把这个 save.json 覆盖回 workspace/sans-fight/，再跑 node tools/sync-sandbox.mjs）

## 本次要改的内容
依据 D:\stars\Sans_Fight_原版蓝心运动逻辑与现状对比.md §4.1：
补上原版 DownSpeed >= 240 -> Gravity = 0 的死区，让蓝心自由落体终端从
MaxFallSpeed(750) 回到原版的 ≈243 px/s。