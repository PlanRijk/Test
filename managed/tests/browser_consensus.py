"""Synthetic public-provider consensus rendering; no production login."""
from pathlib import Path
import json
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[2];WEB=ROOT/'managed/web'
m={'status':'provider_reported','analysts':30,'average':120e9,'low':110e9,'high':130e9,'currency':'USD','basis':'unknown'}
e={'status':'provider_reported','analysts':28,'average':2.5,'low':2.2,'high':2.8,'currency':'USD','basis':'normalized'}
d={'counts':{'reported':1,'unavailable':0,'pending':0},'records':[{'symbol':'TEST','eligible':True,'record':{'status':'provider_reported','known_at':'2026-11-16T10:00Z','source_url':'https://finance.yahoo.com/quote/TEST/analysis/','quarters':[{'period':'2026-10','provider_period_label':'Current Qtr. (Oct 2026)','eps':e,'revenue':m}]},'baseline_revenue':{'status':'baseline','currency':'USD','base':132e9,'target_period_reference':'2026-10-31'}}],'pre_event_snapshots':1,'schedule':'Begrensde bronopvolging'}
html='<meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/style.css"><main id="body" class="panel"></main><script type="module">import{consensusMarkup}from"/analyst-consensus.js";document.querySelector("main").innerHTML=consensusMarkup('+json.dumps(d)+');</script>'
with sync_playwright()as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox']);page=b.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 def route(r):
  path=r.request.url.split('paperlab.test',1)[1].split('?')[0];f=WEB/path.lstrip('/')
  if path=='/':r.fulfill(content_type='text/html',body=html)
  elif f.is_file():r.fulfill(content_type='text/css'if path.endswith('.css')else'text/javascript',body=f.read_text())
  else:r.fulfill(status=404,body='')
 page.route('**/*',route)
 for width in [1400,390]:
  page.set_viewport_size({'width':width,'height':1000});page.goto('https://paperlab.test/');page.get_by_role('heading',name='Analistenconsensus naast onze rekenraming').wait_for();page.locator('summary').first.click();text=page.inner_text('body');assert 'normalized'in text;assert '30 analisten'in text;assert '10% hoger'in text;assert 'EPS-verschil wordt niet automatisch berekend'in text;assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),width
 assert not errors,errors;b.close();print('Chromium consensus passed: analyst counts, basis, currency/month-matched revenue comparison, explicit EPS suppression and 390/1400px layout.')
