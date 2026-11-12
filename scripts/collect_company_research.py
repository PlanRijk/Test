"""Bounded operator research. Reads official sources; never issues trade approvals.

Run in a work session, not a background AI service. Output contains public sources
and explicit failures, not API credentials. Uses only the existing issuer registry.
"""
import concurrent.futures,datetime,hashlib,io,json,re,threading,time,urllib.error,urllib.parse,urllib.request
from html.parser import HTMLParser
from pathlib import Path

MAX_BYTES=24_000_000
MAX_RUN_BYTES=400_000_000
RUN_BYTES=0
BLOCKED=set()
LOCK=threading.Lock()
class Text(HTMLParser):
 def __init__(self):super().__init__();self.parts=[];self.links=[];self.skip=0;self.href=None;self.label=[]
 def handle_starttag(self,tag,attrs):
  if tag in ('script','style','noscript'):self.skip+=1
  if tag in ('p','div','tr','h1','h2','h3','h4','li'):self.parts.append('\n')
  if tag=='a':self.href=dict(attrs).get('href');self.label=[]
 def handle_endtag(self,tag):
  if tag in ('script','style','noscript'):self.skip=max(0,self.skip-1)
  if tag=='a' and self.href:self.links.append((self.href,' '.join(self.label)));self.href=None
  if tag in ('p','div','tr','h1','h2','h3','h4','li'):self.parts.append('\n')
 def handle_data(self,data):
  if not self.skip:
   self.parts.append(data+' ')
   if self.href:self.label.append(data)
 def text(self):return '\n'.join(re.sub(r'\s+',' ',s).strip() for s in ''.join(self.parts).splitlines() if s.strip())
def fetch(url):
 global RUN_BYTES
 host=urllib.parse.urlsplit(url).hostname
 if host in BLOCKED:raise RuntimeError('rate_limit_backoff')
 req=urllib.request.Request(url,headers={'User-Agent':'PaperLab research contact via issuer website; bounded educational paper study','Accept':'application/json,text/html,application/pdf'})
 try:
  with urllib.request.urlopen(req,timeout=18) as r:
   chunks=[];size=0
   while True:
    block=r.read(min(262144,MAX_BYTES-size+1))
    if not block:break
    size+=len(block)
    with LOCK:
     RUN_BYTES+=len(block)
     if RUN_BYTES>MAX_RUN_BYTES:raise RuntimeError('research_run_400MB_limit')
    if size>MAX_BYTES:raise RuntimeError('document_exceeds_24MB_limit')
    chunks.append(block)
   raw=b''.join(chunks)
   return raw,r.geturl(),r.headers.get_content_type()
 except urllib.error.HTTPError as e:
  if e.code==429:
   with LOCK:BLOCKED.add(host)
  raise RuntimeError('HTTP_'+str(e.code)) from None
def excerpts(text):
 patterns={
 'competition':r'competiti|concurrent|pricing power|market share|switching|patent|backlog|order book',
 'financing':r'liquidity|liquiditeit|maturit|refinanc|covenant|indebted|dividend|repurchase|capital expenditure|cash flow',
 'outlook':r'outlook|guidance|vooruitzicht|demand|vraag|restructur|impairment|tariff|geopolit|cyber|litigation|regulator|China|export'}
 out={}
 for topic,pattern in patterns.items():
  lines=[s for s in text.splitlines() if 100<len(s)<15000 and re.search(pattern,s,re.I) and not re.search(r'cookie|accept all|privacy policy',s,re.I)]
  # Actual source passages, not automatic qualitative approval. Context is limited.
  out[topic]=list(dict.fromkeys(s[:1800] for s in lines))[:4]
 return out
def document(url,folder,kind):
 raw,final,mime=fetch(url);digest=hashlib.sha256(raw).hexdigest();links=[]
 if mime=='application/pdf' or raw[:4]==b'%PDF':
  from pypdf import PdfReader
  reader=PdfReader(io.BytesIO(raw));text='\n'.join(p.extract_text() or '' for p in list(reader.pages)[:300]);scope='PDF text, first '+str(min(300,len(reader.pages)))+' of '+str(len(reader.pages))+' pages; tables/layout not fully interpreted'
 else:
  html=raw.decode('utf-8','replace');parser=Text();parser.feed(html);text=parser.text();links=parser.links;scope='HTML text extraction; selected passages, not full audited review'
 folder.mkdir(parents=True,exist_ok=True);(folder/(digest+'.txt')).write_text(text)
 return {'url':final,'requested_url':url,'sha256':digest,'bytes':len(raw),'kind':kind,'retrieved_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'read_scope':scope,'characters':len(text),'excerpts':excerpts(text)},links
def collect(item,route,root):
 symbol=item['symbol'];folder=root/symbol.replace('/','_');docs=[];failures=[];filings=[]
 def add(url,kind):
  try:
   d,links=document(url,folder,kind);docs.append(d);return links
  except Exception as e:failures.append({'url':url,'status':str(e)[:100] if isinstance(e,RuntimeError) else type(e).__name__});return []
 cik=item.get('sec_cik')
 if not cik and 'data.sec.gov/submissions/CIK' in item['primary_url']:cik=item['primary_url'].split('CIK')[1].split('.')[0]
 if cik:
  url='https://data.sec.gov/submissions/CIK'+cik+'.json'
  try:
   raw,_,_=fetch(url);data=json.loads(raw);recent=data['filings']['recent'];seen=set()
   for i,form in enumerate(recent['form']):
    if form not in ('10-K','10-Q','20-F','6-K','8-K'):continue
    row={k:recent[k][i] for k in ['form','filingDate','accessionNumber','primaryDocument']};row['url']='https://www.sec.gov/Archives/edgar/data/'+str(int(cik))+'/'+row['accessionNumber'].replace('-','')+'/'+row['primaryDocument'];filings.append(row)
    if len(filings)>=12:break
   # Filing-index summaries are bounded separately from report selection.
   # Annual reports must not disappear behind many recent insider/event filings.
   selected=[];groups=set()
   for i,form in enumerate(recent['form']):
    if form not in ('10-K','10-Q','20-F','6-K','8-K'):continue
    group='annual' if form in ('10-K','20-F') else 'quarterly' if form=='10-Q' else 'event'
    if group in groups:continue
    groups.add(group);row={k:recent[k][i] for k in ['form','filingDate','accessionNumber','primaryDocument']};row['url']='https://www.sec.gov/Archives/edgar/data/'+str(int(cik))+'/'+row['accessionNumber'].replace('-','')+'/'+row['primaryDocument'];selected.append(row)
   for row in selected:
    group='annual' if row['form'] in ('10-K','20-F') else 'quarterly' if row['form']=='10-Q' else 'event'
    if group in seen:continue
    seen.add(group);add(row['url'],row['form'])
    if len(seen)>=3:break
  except Exception as e:failures.append({'url':url,'status':str(e)[:100] if isinstance(e,RuntimeError) else type(e).__name__})
 # Actual IR content and at most one promising linked results/report page.
 links=add(route['issuer_url'],'issuer_IR')
 candidates=[]
 for href,label in links:
  u=urllib.parse.urljoin(route['issuer_url'],href)
  if not u.startswith('https://') or any(s in u.lower() for s in ['privacy','cookie','login','mailto:']):continue
  score=sum(bool(re.search(p,label+' '+u,re.I)) for p in [r'2026',r'results|earnings|quarter|interim|half.year',r'annual.report|financial.report',r'2025'])
  if score>=2 and u.rstrip('/')!=route['issuer_url'].rstrip('/'):
   quarter=re.search(r'(?:q|quarter[ -]?)([1-4])',label+' '+u,re.I)
   candidates.append((score+(int(quarter[1])/10 if quarter else 0),u))
 if candidates:add(sorted(candidates,key=lambda x:-x[0])[0][1],'linked_financial_publication')
 record={'symbol':symbol,'name':item['name'],'checked_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'documents':docs,'filings':filings,'failures':failures,'trade_approval':False,'complete_qualitative_review':False}
 folder.mkdir(parents=True,exist_ok=True);(folder/'sources.json').write_text(json.dumps(record,ensure_ascii=False,indent=2));return record
def main():
 global MAX_BYTES,MAX_RUN_BYTES
 import argparse
 p=argparse.ArgumentParser();p.add_argument('catalogue');p.add_argument('routes');p.add_argument('output');p.add_argument('--max-document-mb',type=int,default=24,choices=range(1,81));p.add_argument('--max-run-mb',type=int,default=400,choices=range(1,801));a=p.parse_args();MAX_BYTES=a.max_document_mb*1000000;MAX_RUN_BYTES=a.max_run_mb*1000000;items=json.loads(Path(a.catalogue).read_text());routes={x['symbol']:x for x in json.loads(Path(a.routes).read_text())};root=Path(a.output);root.mkdir(parents=True,exist_ok=True)
 results=[]
 with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
  futures=[pool.submit(collect,c,routes[c['symbol']],root) for c in items]
  for f in concurrent.futures.as_completed(futures):
   r=f.result();results.append(r);print(r['symbol']+': '+str(len(r['documents']))+' documents, '+str(len(r['failures']))+' source gaps',flush=True)
 results.sort(key=lambda x:x['symbol']);(root/'all-sources.json').write_text(json.dumps(results,ensure_ascii=False));print('Finished '+str(len(results))+' companies',flush=True)
if __name__=='__main__':main()
