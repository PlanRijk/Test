"""Synthetic all-catalogue baseline interface; no live account."""
from pathlib import Path
import json,subprocess
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[2];WEB=ROOT/'managed/web'
code="""import{quarterlyBaseline}from'./managed/functions/_shared/quarterly-expectations.js';const now=Date.now(),rows=['2025-09-30','2025-12-31','2026-03-31','2026-06-30','2026-09-30'].map((end,i)=>({end,value:100+i*10,currency:'EUR'}));console.log(JSON.stringify(quarterlyBaseline({symbol:'TEST',known_at:new Date(now).toISOString(),quote_at:new Date(now).toISOString(),official_source_available:true,values:{quarterlyTotalRevenue:rows}})));"""
r=json.loads(subprocess.check_output(['node','--input-type=module','-e',code],cwd=ROOT));data={'counts':{'registered':100,'eligible':57,'with_baseline':50},'records':[{'symbol':'TEST','record':r}],'schedule':'Dagelijks begrensde bronverwerking','limitations':'Geen consensus of koopgoedkeuring.'}
html='<meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/style.css"><main class="panel" id="body"></main><script type="module">import{quarterlyMarkup}from"/quarterly-expectations.js";document.querySelector("main").innerHTML=quarterlyMarkup('+json.dumps(data)+');</script>'
with sync_playwright()as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox']);page=b.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 def route(r):
  path=r.request.url.split('paperlab.test',1)[1].split('?')[0];file=WEB/path.lstrip('/')
  if path=='/':r.fulfill(content_type='text/html',body=html)
  elif file.is_file():r.fulfill(content_type='text/css'if path.endswith('.css')else'text/javascript',body=file.read_text())
  else:r.fulfill(status=404,body='')
 page.route('**/*',route)
 for w in [1400,390]:
  page.set_viewport_size({'width':w,'height':1000});page.goto('https://paperlab.test/');page.get_by_role('heading',name='Doorlopende kwartaalramingen').wait_for();page.locator('summary').first.click();assert 'geen geverifieerde analistenconsensus'in page.inner_text('body');assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),w
 assert not errors,errors;b.close();print('Chromium quarterly passed: 390/1400px, open research detail, explicit numerical limitations and no overflow/errors.')
