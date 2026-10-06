import { readFileSync } from 'node:fs';
const env = Object.fromEntries(readFileSync('D:/stars/glm-mcp/.env','utf8').split(/\r?\n/).map(l=>/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/.exec(l)).filter(Boolean).map(m=>[m[1],m[2].trim()]));
const key = env.GLM_API_KEY;
if (!key) { console.log('NO KEY'); process.exit(1); }
const models = ['glm-4.6v-flash','glm-4.5v','glm-4.6','glm-4.5','glm-4.5-flash','glm-4.5-air','glm-4-flash','glm-4-plus','glm-4v-flash','glm-4.1v-thinking-flash','glm-z1-flash'];
for (const model of models) {
  try {
    const res = await fetch('https://open.bigmodel.cn/api/paas/v4/chat/completions', {
      method:'POST', headers:{'content-type':'application/json', authorization:`Bearer ${key}`},
      body: JSON.stringify({ model, messages:[{role:'user',content:'hi'}], max_tokens: 8, stream:false }),
      signal: AbortSignal.timeout(30000),
    });
    const txt = await res.text();
    let note = txt.slice(0,140);
    try { const j = JSON.parse(txt); if (j.choices) note = `OK -> ${JSON.stringify(j.choices[0]?.message?.content).slice(0,80)}`; else if (j.error) note = `${j.error.code}: ${j.error.message}`; } catch {}
    console.log(`${model.padEnd(26)} HTTP ${res.status}  ${note}`);
  } catch (e) { console.log(`${model.padEnd(26)} ERR   ${e.message}`); }
}
