const fs = require('fs');
let c = fs.readFileSync('lua/core.lua','utf8').replace(/\r\n/g,'\n');
c = c.replace('  local scriptOwnsRound = (self.world ~= nil and self.world.script ~= nil) and not self.final',
              '  local scriptOwnsRound = false   -- TEMP 截图用');
fs.writeFileSync('lua/core.lua', c);
