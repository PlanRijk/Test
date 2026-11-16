"""Estimate document-reading work from archived texts. No API calls or completion claim."""
import json,math,sys
from pathlib import Path
def estimate(root,symbols,chunk_chars=7000):
 result=[]
 for symbol in symbols:
  folder=Path(root)/symbol;meta=json.loads((folder/'sources.json').read_text());docs=[]
  for source in meta['documents']:
   text=folder/(source['sha256']+'.txt')
   if source.get('kind')not in('10-K','10-Q')or not text.exists():continue
   count=len(text.read_text());parts=math.ceil(count/chunk_chars)
   docs.append({'form':source['kind'],'characters':count,'chunks':parts,'model_calls_with_one_review_per_chunk':2*parts})
  calls=sum(d['model_calls_with_one_review_per_chunk']for d in docs)
  result.append({'symbol':symbol,'documents':docs,'document_calls':calls,'minimum_days_at_daily_calls':{str(n):math.ceil(calls/n)for n in(4,20,100)},'excludes':'Valuation, competitor analysis, extra sources, retries, provider failures and synthesis. This full-document workflow is not yet running.'})
 return {'version':'deep-research-work-estimate-v1','chunk_characters':chunk_chars,'companies':result}
if __name__=='__main__':
 if len(sys.argv)<2:raise SystemExit('research_capacity.py ARCHIVE_DIRECTORY [SYMBOL ...]')
 print(json.dumps(estimate(sys.argv[1],sys.argv[2:]or['NVDA','WMT','AAPL','MSFT']),ensure_ascii=False,indent=2))
