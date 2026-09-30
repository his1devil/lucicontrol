// Runs the design file's own logic class and writes renderVals() for each page state as JSON.
//   node vals.js <out dir>
const fs = require('fs');
const path = require('path');
const out = process.argv[2];
const src = fs.readFileSync(path.join(__dirname, '..', 'LuciControl.dc.html'), 'utf8');
const open = '<script type="text/x-dc" data-dc-script>';
const i = src.indexOf(open);
const js = src.slice(i + open.length, src.indexOf('</script>', i));
class DCLogic {
  setState(u) { this.state = { ...this.state, ...(typeof u === 'function' ? u(this.state) : u) }; }
}
const Component = new Function('DCLogic', js + '\nreturn Component;')(DCLogic);
const pages = {
  home: {},
  devices: { page8: 'devices' },
  'pair-qr': { page8: 'pair', pairMode: 'qr', pairSt: 'wait' },
  'pair-code': { page8: 'pair', pairMode: 'code', pairSt: 'wait' },
  'pair-done': { page8: 'pair', pairSt: 'done' },
  settings: { page8: 'settings', uSt: 'latest' },
  'settings-update': { page8: 'settings', uSt: 'avail', uInst: false },
  'settings-downloading': { page8: 'settings', uSt: 'downloading', uPct: 45 },
  add: { page8: 'add', addAg: 'Codex' },
};
fs.mkdirSync(out, { recursive: true });
for (const [name, state] of Object.entries(pages)) {
  const c = new Component();
  c.state = { ...c.state, ...state };
  fs.writeFileSync(path.join(out, name + '.json'), JSON.stringify(c.renderVals(), (k, v) => (typeof v === 'function' ? undefined : v)));
}
console.log(Object.keys(pages).join(' '));
