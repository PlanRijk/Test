import json,os,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from scripts.qualitative_api import build_request,validate_draft,pilot_call,estimate
sources=[{'id':'official-1','url':'https://issuer.example/report','text':'Reported cash flow was positive; debt maturities require refinancing.'}]
request=build_request(sources);assert request['store']is False and request['text']['format']['strict']is True
draft={'claims':[{'topic':'Financing','finding':'Refinancing requires review','source_id':'official-1','quote':'debt maturities require refinancing'}],'uncertainties':['No complete maturity schedule'],'counterarguments':['Source may omit recent financing']}
assert validate_draft(draft,sources)['trade_approval']is False
try:validate_draft(draft|{'claims':[draft['claims'][0]|{'quote':'invented supporting evidence'}]},sources)
except ValueError:pass
else:raise AssertionError('Invented quotation accepted')
try:pilot_call(sources)
except RuntimeError:pass
else:raise AssertionError('Disabled paid execution accepted')
policy={'enabled':True,'monthly_limit_usd':1,'model':'test-model','max_source_characters':80000,'max_output_tokens':4000,'input_usd_per_million':2,'output_usd_per_million':10,'pricing_checked_at':'2026-11-12'}
os.environ['OPENAI_API_KEY']='synthetic-test-only';events=[]
def fake(url,body,headers):
 assert url=='https://api.openai.com/v1/responses';assert body['store']is False
 return{'id':'synthetic-response','model':'test-model','status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':json.dumps(draft)}]}],'usage':{'input_tokens':100,'output_tokens':100}}
r=pilot_call(sources,policy=policy,reserve=lambda amount:events.append(('reserve',amount))or'ticket',settle=lambda *a:events.append(('settle',a)),fetch=fake);assert r['requires_review']and len(events)==2
assert estimate()['two_pass_usd']==12.4
del os.environ['OPENAI_API_KEY']
print('Model adapter passed: strict schema, grounded quotations, default-off paid guard, reservation before mocked request, usage settlement, and no trade approval. No real API calls.')
