// Prepare an operator-reviewed, private dossier from complete downloaded sources.
import fs from'node:fs';import crypto from'node:crypto';
import{parseCompanyFacts}from'../managed/functions/_shared/company-analysis.js';
import{parseCompanyCloses}from'../managed/functions/_shared/company-data.js';
import{COMPANY_CATALOGUE}from'../managed/functions/_shared/company-catalogue.js';
const[symbol,factsPath,submissionsPath,chartPath,outputPath]=process.argv.slice(2),item=COMPANY_CATALOGUE.find(c=>c.symbol===symbol);
if(!item||!outputPath)throw Error('Use: company_evidence.mjs SYMBOL facts.json submissions.json chart.json PRIVATE_OUTPUT.json');
const raw=[factsPath,submissionsPath,chartPath].map(p=>fs.readFileSync(p)),time=Date.now(),d=parseCompanyFacts(JSON.parse(raw[0]),JSON.parse(raw[1]),item,{time,source_bytes:raw.reduce((s,b)=>s+b.length,0)});d.sector=item.sector;
Object.assign(d,parseCompanyCloses(JSON.parse(raw[2]),item,time));d.source_hashes=Object.fromEntries(['SEC companyfacts','SEC submissions','Yahoo daily closes'].map((name,i)=>[name,crypto.createHash('sha256').update(raw[i]).digest('hex')]));fs.writeFileSync(outputPath,JSON.stringify(d),{mode:0o600});console.log(symbol+': validated private financial dossier prepared; qualitative review remains separate.');
