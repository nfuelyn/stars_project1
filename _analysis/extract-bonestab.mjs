import fs from 'node:fs';
const path = 'D:/stars/workspace/sans-fight/sans-fight.save.json';
const save = JSON.parse(fs.readFileSync(path,'utf8'));
// 找出承载内联源码的位置
const hits = [];
function walk(o, p){
  if (typeof o === 'string'){
    if (o.includes('sans_bonestab1')) hits.push({path:p, len:o.length, sample:o.slice(0,60)});
  } else if (o && typeof o === 'object'){
    for (const k of Object.keys(o)) walk(o[k], p+'.'+k);
  }
}
walk(save, '$');
console.log('含 sans_bonestab1 的字符串字段：');
for (const h of hits) console.log('  ' + h.path + '  len=' + h.len + '  ' + JSON.stringify(h.sample));
// 取第一个，抽取三段 csv
if (hits.length){
  let src = null;
  (function find(o,p){ if(src) return; if(typeof o==='string'){ if(o.includes('sans_bonestab1')) src=o; } else if(o&&typeof o==='object'){ for(const k of Object.keys(o)) find(o[k],p+'.'+k);} })(save,'$');
  for (const name of ['sans_bonestab1','sans_bonestab2','sans_bonestab3']){
    const re = new RegExp('name = "'+name+'", csv = \\[==\\[([\\s\\S]*?)\\]==\\]');
    const m = src.match(re);
    console.log('\\n===== '+name+' =====');
    console.log(m ? m[1].trim() : '(未找到)');
  }
}
