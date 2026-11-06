import assert from 'node:assert/strict';
import fs from 'node:fs';
import {geopoliticsMarkup} from '../web/geopolitics.js';
import {SOURCES} from '../functions/_shared/sources.js';
const dossier=JSON.parse(fs.readFileSync(new URL('../web/geopolitics-data.json',import.meta.url))),ids=new Set(dossier.sources.map(s=>s.id)),channels=new Set(dossier.channels.map(c=>c.id));
assert.equal(dossier.events.length,19);assert.equal(dossier.sources.length,25);assert.equal(ids.size,25);assert.equal(dossier.automatic_training,false);assert.equal(dossier.trading_changes,false);assert.equal(dossier.new_scheduled_jobs,0);
for(const e of dossier.events){assert.equal(e.known_at_utc,null);assert.equal(e.lookahead_safe,false);assert.equal(e.model_input,false);assert(e.limits);assert(e.source_ids.every(id=>ids.has(id)));assert(e.channels.every(id=>channels.has(id)));if(e.anchor_day){assert(e.anchor_day>=dossier.window_start&&e.anchor_day<=dossier.window_end);assert.equal(e.date_status,'retrospective_anchor_only');}}
for(const s of dossier.sources){assert.match(s.sha256,/^[a-f0-9]{64}$/);assert(s.read_scope);assert.equal(s.content_stored_in_production,false);assert(s.checked_at.startsWith('2026-11-06'));}
const html=geopoliticsMarkup(dossier);assert(html.includes('geen causale backtest'));assert(html.includes('eerste publicatietijden'));assert.equal((html.match(/data-geo-case=/g)||[]).length,19);
const bad=structuredClone(dossier);bad.sources[0].url='javascript:alert(1)';bad.events[0].title='<img onerror=x>';bad.sources[1].url='https://example.invalid/untrusted';bad.sources[2].url='https://www.imf.org@evil.invalid/';
const safe=geopoliticsMarkup(bad);assert(!safe.includes('javascript:'));assert(!safe.includes('<img'));assert(!safe.includes('href="https://example.invalid'));assert(!safe.includes('href="https://www.imf.org@'));
assert.throws(()=>geopoliticsMarkup({...dossier,version:'untrusted'}));
assert.equal(new Set(SOURCES.map(s=>s.id)).size,SOURCES.length);
for(const id of ['imfgeopolitics2025','gprmethodology','eusanctions','supplychainnyfed','wtoredsea2024','chipcontrols2022','imfgeopolitics2026'])assert(SOURCES.find(s=>s.id===id));
console.log('Geopolitics: traceable source/time boundaries, no look-ahead-safe claims or model changes, safe rendering and source catalogue passed.');
