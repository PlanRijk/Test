"""Isolated browser page using collected public research; never logs into production."""
import json,sys
from pathlib import Path
from playwright.sync_api import sync_playwright
root=Path(__file__).resolve().parents[1]/'web';record=json.loads(Path(sys.argv[1]).read_text())[0]
html='<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/style.css"><main class="auth-wrap"><section class="panel" id="body"></section></main><script type="module">import{researchDetail}from"/company-research.js";document.getElementById("body").innerHTML=researchDetail('+json.dumps({'record':record,'followup':{'runtime':{'last_refresh':'2026-11-12T06:55:00Z','diagnostics':{'due':100}},'queue':[{'symbol':record['symbol'],'reasons':['qualitative_review_missing'],'due_at':'2026-11-12T06:55:00Z'}],'history':[{'hash':'0'*64,'at':'2026-11-12T06:55:00Z','sources':4,'findings':8}],'publications':{'checked':20,'confirmed':16,'schedule':'Twintig bedrijven per werkdag.'}}})+');</script>'
with sync_playwright()as p:
 b=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox']);page=b.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 def serve(route):
  path=route.request.url.split('paperlab.test',1)[1].split('?')[0]
  if path=='/':route.fulfill(status=200,content_type='text/html',body=html)
  elif(root/path.lstrip('/')).is_file():route.fulfill(status=200,content_type='text/css'if path.endswith('.css')else'text/javascript',body=(root/path.lstrip('/')).read_text())
  else:route.fulfill(status=404,body='')
 page.route('**/*',serve)
 for width in[1400,390]:
  page.set_viewport_size({'width':width,'height':1000});page.goto('https://paperlab.test/');page.get_by_role('heading',name='Uitgebreid financieel onderzoek',exact=True).wait_for();page.locator('details').first.click();assert'Financiering'in page.inner_text('body');assert'geen koopgoedkeuring'in page.inner_text('body');assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),width
 assert not errors,errors
 b.close();print('Chromium passed: 390/1400px layout, expanded sources, rendering and no page errors; no live login.')
