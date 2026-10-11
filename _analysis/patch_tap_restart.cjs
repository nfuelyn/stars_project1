const fs=require('fs');
let t=fs.readFileSync('lua/_tap.lua','utf8');
const o="  eq('result-tap-consumed', consumedR, true)\n  for _ = 1, 4 do pcall(main.OnLevelUpdate, 1.0 / 30.0) end";
const n="  eq('result-tap-consumed', consumedR, true)\n  -- 【2026-10-11 用户口径】重开改为二次确认（PC 也要）：同一位置再点一次才真的重开\n  local okR2, consumedR2 = pcall(tap, 320, 320)\n  eq('result-tap2-ok', okR2, true)\n  eq('result-tap2-consumed', consumedR2, true)\n  for _ = 1, 4 do pcall(main.OnLevelUpdate, 1.0 / 30.0) end";
if(!t.includes(o)) throw new Error('_tap 锚点未找到');
t=t.replace(o,n); fs.writeFileSync('lua/_tap.lua',t.replace(/\s+$/,'')+'\n','utf8');
console.log('_tap 已改为两次点按');
