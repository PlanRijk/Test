"""Reproducible extraction from already captured official companyfacts, no network.

Only an unambiguous annual us-gaap:Revenues context in the recorded 10-K is
used. No value is chosen to match an aggregator; conflicting figures remain.
"""
import copy,datetime,hashlib,json,sys
from pathlib import Path
def prepare(input_path,source_root,output_path):
 out=[];today=datetime.datetime.now(datetime.timezone.utc).isoformat();day=datetime.date.fromisoformat
 for c in json.loads(Path(input_path).read_text())['coverage']:
  if not c.get('verified_financials'):continue
  n=copy.deepcopy(c['verified_financials']);path=Path(source_root)/c['symbol']/'facts.json'
  if not path.exists():continue
  blob=path.read_bytes();facts=json.loads(blob)
  if str(facts.get('cik','')).zfill(10)!=n['cik']:raise RuntimeError('CIK mismatch')
  rows=facts.get('facts',{}).get('us-gaap',{}).get('Revenues',{}).get('units',{}).get('USD',[]);f=n['financial'];acc=n['annual_report']['accession'];start=f['annual_start'];end=f['annual_end']
  current={v['val']for v in rows if v.get('accn')==acc and v.get('start')==start and v.get('end')==end}
  if len(current)!=1 or next(iter(current))==f['revenue']:continue
  annual=[v for v in rows if v.get('accn')==acc and v.get('start')and 330<(day(v['end'])-day(v['start'])).days<400 and 330<(day(end)-day(v['end'])).days<400]
  previous={v['val']for v in annual}
  if len(previous)!=1:continue
  current=next(iter(current));previous=next(iter(previous));recent=[v for v in rows if v.get('accn')==n['latest_report']['accession']and v.get('start')and 60<=(day(v['end'])-day(v['start'])).days<=380];recent.sort(key=lambda v:(v['end'],v['start']),reverse=True);latest=recent[0]if recent else None;comp=None
  if latest:
   span=(day(latest['end'])-day(latest['start'])).days;comp=next((v for v in recent if 330<(day(latest['end'])-day(v['end'])).days<400 and abs(span-(day(v['end'])-day(v['start'])).days)<12),None)
  old={k:f.get(k)for k in['revenue','previous_revenue','revenue_growth','latest_revenue_growth']};f.update(revenue=current,previous_revenue=previous,revenue_growth=current/previous-1 if previous>0 else None,latest_revenue_growth=latest['val']/comp['val']-1 if latest and comp and comp['val']>0 else None,revenue_definition='us-gaap:Revenues');n['known_at']=today
  n['source_extraction']={'method':'consolidated_revenue_v1','concept':'us-gaap:Revenues','accession':acc,'start':start,'end':end,'source_url':'https://data.sec.gov/api/xbrl/companyfacts/CIK'+n['cik']+'.json','sha256':hashlib.sha256(blob).hexdigest(),'interpreted_at':today,'scope':'Only consolidated revenue contexts re-evaluated; other metrics and original source-check date retained; no qualitative approval.'}
  out.append({'symbol':c['symbol'],'old':old,'native':n})
 Path(output_path).write_text(json.dumps(out));Path(output_path).chmod(0o600)
 print(json.dumps([{'symbol':x['symbol'],'before':x['old']['revenue'],'after':x['native']['financial']['revenue']}for x in out]))
if __name__=='__main__':prepare(*sys.argv[1:])
