"""Install the separate candidate comparison without resetting any existing trial."""
import hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from scripts.managed_api import sql
from scripts.deploy_managed import jsql

def fingerprint():
    paths=['managed/functions/_shared/candidate-study.js','managed/sql/010_candidate_comparison.sql','managed/functions/paper-learn/index.js']
    manifest=[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()} for p in paths]
    value=hashlib.sha256(json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    target=ROOT/'managed/functions/_shared/candidate-implementation.js'
    content="export const CANDIDATE_IMPLEMENTATION_SHA = '"+value+"';\n"
    if not target.exists() or target.read_text()!=content:target.write_text(content)
    return value

def configure(ref):
    value=fingerprint()
    code="import {CANDIDATE_POLICY} from './managed/functions/_shared/candidate-study.js';console.log(JSON.stringify(CANDIDATE_POLICY));"
    policy=json.loads(subprocess.check_output(['node','--input-type=module','-e',code],cwd=ROOT));policy['implementation_sha256']=value
    sql(ref,(ROOT/'managed/sql/010_candidate_comparison.sql').read_text())
    result=sql(ref,'select public.paper_candidates_configure('+jsql(policy)+') as profile')
    return {'profile':result[0]['profile'],'implementation':value,'new_cron_jobs':0,'extra_market_downloads':0,'automatic_trading_approval':False}

if __name__=='__main__':
    if sys.argv[1:]==['fingerprint']:print(fingerprint())
    elif len(sys.argv)==3 and sys.argv[1]=='configure':print(json.dumps(configure(sys.argv[2])))
    else:raise SystemExit('Use: candidate_study.py fingerprint | configure PROJECT_REF')
