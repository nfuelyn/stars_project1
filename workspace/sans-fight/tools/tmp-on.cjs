const fs = require('fs');
let c = fs.readFileSync('lua/core.lua','utf8').replace(/\r\n/g,'\n');
const a = '  local scriptOwnsRound = (self.world ~= nil and self.world.script ~= nil) and not self.final';
if (!c.includes(a)) { console.error('MISS'); process.exit(1); }
c = c.replace(a, '  local scriptOwnsRound = false   -- TEMP: 只为截图，打开内置生成器');
fs.writeFileSync('lua/core.lua', c);
console.log('TEMP: 已临时打开内置生成器');
