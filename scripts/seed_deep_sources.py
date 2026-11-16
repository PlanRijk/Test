"""Import full extracted public texts from a local, hash-indexed source archive.
No credentials or source bodies are printed or written to Git. Safe to resume.
"""
import json,re,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
from scripts.deploy_managed import literal

def role(kind,url):
 s=url.lower()
 if kind in('10-K','20-F')or re.search(r'annual.report|annual_report|jaarverslag',s):return'annual'
 if kind in('10-Q','6-K')or re.search(r'q[1-4]|quarter|earningsrelease|earnings-release|interim|financial.report|nine.months',s):return'interim'
 if kind=='8-K'or re.search(r'ceo|news.details|press.release',s):return'material'
 return'other'
def documents(directory):
 for index in sorted(Path(directory).glob('*/sources.json')):
  meta=json.loads(index.read_text())
  for d in meta.get('documents',[]):
   url=d.get('url','');kind=d.get('kind','');r=role(kind,url);scope=d.get('read_scope','')
   if r=='other'or re.search(r'\.(?:xlsx?|zip)(?:[?#]|$)',url,re.I):continue
   path=index.parent/(d.get('sha256','')+'.txt')
   if not path.exists():continue
   text=path.read_text();complete=True
   if 'PDF'in scope:
    pages=re.search(r'(\d+) of (\d+) pages',scope)
    complete=bool(pages and pages[1]==pages[2])
   if not 300<=len(text)<=2000000:continue
   # Historic extraction saved the entire plain text; the old label referred to review, not truncation.
   yield {'symbol':meta['symbol'],'url':url,'sha256':d['sha256'],'text':text,'kind':kind,'role':r,'known_at':d.get('retrieved_at')or meta['checked_at'],'filed_at':d.get('filed_at'),'scope':scope+'; full saved text imported, not an audited interpretation','complete_extraction':complete}
def seed(ref,directory):
 if ref!='kdyzlbknygeqinqduuic':raise RuntimeError('Existing Paperlab project required')
 owner=api.sql(ref,'select owner_id from paperlab.settings where singleton',True)[0]['owner_id'];n=0
 for d in documents(directory):
  api.sql(ref,'select public.paper_deep_seed('+literal(owner)+'::uuid,'+literal(json.dumps([d],ensure_ascii=False))+'::jsonb)');n+=1
  if n%20==0:print(json.dumps({'documents_imported_or_already_cached':n}),flush=True)
 print(json.dumps({'documents_imported_or_already_cached':n,'plaintext_not_logged':True}))
if __name__=='__main__':seed(sys.argv[1],sys.argv[2])
