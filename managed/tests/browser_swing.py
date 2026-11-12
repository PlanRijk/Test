"""Synthetic strategy dashboard, desktop/mobile; no account access."""
from pathlib import Path
from playwright.sync_api import sync_playwright
import json
ROOT=Path(__file__).resolve().parents[2];WEB=ROOT/'managed/web'
s={'positions':7,'buys_today':0,'cash_eur':6200,'equity_eur':9750,'liquidation_eur':9716,'swing_policy':'quality-swing-paper-v1','swing_profile':'synthetic','new_entries_allowed':True,'company_policy':'company-entry-v1','company_ready':[],'positions_detail':[],'swing_checks':[{'symbol':'AAPL','eligible':False,'reason':'Niet alle vijf bedrijfspijlers goedgekeurd.'}],'entry_audit':{'held_stop_risk_eur':151},'risk_config':{'max_positions':12,'max_buys_per_day':2}}
d={'available':True,'main_running':True,'account':{'enabled':True,'allow_entries':True,'summary':s},'trades':[],'curve':[]}
html='<meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/style.css"><main id="body" class="app"><section id="slot"></section></main><script type="module">import{dashboardMarkup}from"/dashboard.js";document.getElementById("slot").innerHTML=dashboardMarkup('+json.dumps(d)+');</script>'
with sync_playwright()as p:
 b=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox']);page=b.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 def serve(route):
  path=route.request.url.split('paperlab.test',1)[1].split('?')[0];file=WEB/path.lstrip('/')
  if path=='/':route.fulfill(status=200,content_type='text/html',body=html)
  elif file.is_file():route.fulfill(status=200,content_type='text/css'if path.endswith('.css')else'text/javascript',body=file.read_text())
  else:route.fulfill(status=404,body='')
 page.route('**/*',serve)
 for width in [1400,390]:
  page.set_viewport_size({'width':width,'height':1000});page.goto('https://paperlab.test/');page.get_by_role('heading',name='Actief: dag-/weekstrategie in de paperproef').wait_for();body=page.inner_text('body');assert 'tweemaal het oorspronkelijke'in body;assert 'IBKR is niet gekoppeld'in body;assert 'bestaande gezamenlijke stoprisico'in body;assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),width
 assert not errors,errors
 b.close();print('Chromium swing dashboard passed: daily/week rules, explicit blockers and simulation scope, no errors/overflow at 390 and 1400px.')
