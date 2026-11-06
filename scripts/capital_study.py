"""Configure a separate virtual EUR10,000 account; never reset an existing account."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql
from scripts.deploy_managed import jsql

def fingerprint():
    paths=['managed/functions/_shared/capital-study.js','managed/sql/011_capital_study.sql','managed/functions/paper-tick/index.js','managed/functions/_shared/engine.js','managed/functions/_shared/learning-runtime.js']
    manifest=[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()} for p in paths]
    value=hashlib.sha256(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()).hexdigest();target=ROOT/'managed/functions/_shared/capital-implementation.js'
    content="export const CAPITAL_IMPLEMENTATION_SHA = '"+value+"';\n"
    if not target.exists() or target.read_text()!=content:target.write_text(content)
    return value

def configure(ref):
    value=fingerprint()
    columns=sql(ref,"select 1 from information_schema.columns where table_schema='paperlab' and table_name='capital_runtime' and column_name='execution_profile'",True)
    if columns and sql(ref,"select execution_profile from paperlab.capital_runtime where execution_profile is not null",True):
        raise RuntimeError('Multiday phase active; use the versioned horizon installer, never reapply the legacy capital schema.')
    exists=sql(ref,"select to_regclass('paperlab.capital_runtime') is not null as present",True)[0]['present']
    if exists:
        rows=sql(ref,"select policy->>'implementation_sha256' as implementation from paperlab.capital_runtime where profile is not null",True)
        if rows and rows[0]['implementation']!=value:raise RuntimeError('Existing capital implementation frozen; do not replace a running trial.')
    market=sql(ref,'select state from paperlab.portfolio where singleton',True)[0]['state']
    code="import fs from 'node:fs';import {CAPITAL_POLICY,initialCapital} from './managed/functions/_shared/capital-study.js';import {learningFingerprint} from './managed/functions/_shared/learning-runtime.js';const s=JSON.parse(fs.readFileSync(0,'utf8'));console.log(JSON.stringify({policy:{...CAPITAL_POLICY,reference_fingerprint:await learningFingerprint(s)},state:initialCapital(s)}));"
    r=subprocess.run(['node','--input-type=module','-e',code],input=json.dumps(market),text=True,capture_output=True,cwd=ROOT,check=True);out=json.loads(r.stdout);out['policy']['implementation_sha256']=value
    sql(ref,(ROOT/'managed/sql/011_capital_study.sql').read_text())
    rows=sql(ref,'select public.paper_capital_configure('+jsql(out['policy'])+','+jsql(out['state'])+') as profile')
    return {'profile':rows[0]['profile'],'initial_virtual_eur':10000,'order_eur':500,'new_cron_jobs':0,'extra_market_downloads':0,'original_account_reset':False}

if __name__=='__main__':
    if sys.argv[1:]==['fingerprint']:print(fingerprint())
    elif len(sys.argv)==3 and sys.argv[1]=='configure':print(json.dumps(configure(sys.argv[2])))
    else:raise SystemExit('Use: capital_study.py fingerprint | configure PROJECT_REF')
