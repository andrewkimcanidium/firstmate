#!/usr/bin/env node
// Protocol fixture: JSON config stands in for Codex-owned TOML parsing.
const fs = require('node:fs'), path = require('node:path'), rl = require('node:readline');
const store = path.join(process.env.CODEX_HOME, 'config.toml');
// A remote job's env -i resolves the real account store; persist elsewhere.
const file = process.env.FM_TEST_CODEX_STORE || store;
if (process.env.FM_TEST_CODEX_CONFIG_STALL) { // a server that never finishes shutting down
  fs.writeFileSync(process.env.FM_TEST_CODEX_CONFIG_STALL, String(process.pid));
  process.on('SIGTERM', () => {}); setInterval(() => {}, 1000);
}
rl.createInterface({input: process.stdin}).on('line', line => {
  const r = JSON.parse(line);
  if (r.id === undefined) return;
  try {
    const content = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '{}';
    const config = JSON.parse(content);
    let result = {};
    if (r.method === 'config/read') {
      result = {layers: [{name: {type:'user', file:store, profile:null}, version:content, config}]};
      if (process.env.FM_TEST_CODEX_CONFIG_CONFLICT === '1')
        fs.writeFileSync(file, JSON.stringify({...config, concurrent_setting: true}));
    }
    if (r.method === 'config/value/write') {
      if (r.params.expectedVersion !== content) throw Error('version conflict');
      const key = JSON.parse(r.params.keyPath.slice(9, -12));
      config.projects ||= {}; config.projects[key] ||= {};
      config.projects[key].trust_level = r.params.value;
      fs.writeFileSync(file, JSON.stringify(config));
      result = {status:'ok', filePath:store};
    }
    console.log(JSON.stringify({id:r.id, result}));
  } catch(error) { console.log(JSON.stringify({id:r.id, error:{message:error.message}})); }
});
