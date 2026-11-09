"""Frozen archive helpers. The owner retired the daily note routine on 2026-11-09."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))

def fingerprint():
 paths=['managed/functions/_shared/reading-plan.js','managed/functions/_shared/reading-study.js','managed/functions/paper-reading/index.js','managed/sql/012_reading_study.sql']
 manifest=[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()} for p in paths]
 value=hashlib.sha256(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()).hexdigest()
 (ROOT/'managed/functions/_shared/reading-implementation.js').write_text("export const READING_IMPLEMENTATION_SHA = '"+value+"';\n")
 return value

def policy():
 r=subprocess.run(['node','--input-type=module','-e',"import {READING_POLICY,READING_PLAN,READING_BOOKS} from './managed/functions/_shared/reading-plan.js';console.log(JSON.stringify({...READING_POLICY,library:READING_PLAN.map(({id,url,year,title})=>({id,url,year,title})),books:READING_BOOKS}));"],capture_output=True,text=True,cwd=ROOT,check=True)
 return {**json.loads(r.stdout),'implementation_sha256':fingerprint()}

def configure(ref):
 raise RuntimeError("Daily note routine retired by owner on 2026-11-09; use the book reading progress instead.")

if __name__=='__main__':
 if sys.argv[1:]==['fingerprint']:print(fingerprint())
 elif len(sys.argv)==3 and sys.argv[1]=='configure':configure(sys.argv[2])
 else:raise SystemExit('Use reading_study.py fingerprint | configure REF')
