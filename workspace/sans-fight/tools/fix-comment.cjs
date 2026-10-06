const fs = require('fs');
let c = fs.readFileSync('lua/core.lua','utf8').replace(/\r\n/g,'\n');
c = c.replace("local FLOOR_BONE_INSET = 24              -- 框内钳位半径 = 心形视觉半宽（±8）",
              "local FLOOR_BONE_INSET = 24       -- 贴地排骨单根内缩量（越大越细；道间缝 = 本值）");
fs.writeFileSync('lua/core.lua', c);
