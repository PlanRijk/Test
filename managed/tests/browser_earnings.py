"""Pilot form/layout with synthetic data only; no production account."""
from pathlib import Path
import json,datetime
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[2];WEB=ROOT/'managed/web';company=json.loads((ROOT/'managed/knowledge/earnings-pilot.json').read_text())['companies'][2]
now=datetime.datetime.now(datetime.timezone.utc);future=(now+datetime.timedelta(days=10)).isoformat();cutoff=(now+datetime.timedelta(days=9)).isoformat()
d={'companies':[company],'cycles':[{'id':'synthetic-cycle','symbol':company['symbol'],'cycle_key':'test-quarter','release_at':future,'cutoff_at':cutoff}],'tasks':[],'schedule':'Wekelijks, rond cijfers beperkt dagelijks','limitations':'Geen automatische kwalitatieve beoordeling.'}
html='<meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="/style.css"><main class="panel" id="body"></main><script type="module">import{earningsMarkup,forecastFromForm}from"/earnings-pilot.js";document.querySelector("main").innerHTML=earningsMarkup('+json.dumps(d)+');document.addEventListener("submit",e=>{e.preventDefault();window.saved=forecastFromForm(e.target);});</script>'
with sync_playwright()as p:
 b=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox']);page=b.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 def route(r):
  path=r.request.url.split('paperlab.test',1)[1].split('?')[0];f=WEB/path.lstrip('/')
  if path=='/':r.fulfill(content_type='text/html',body=html)
  elif f.is_file():r.fulfill(content_type='text/css'if path.endswith('.css')else'text/javascript',body=f.read_text())
  else:r.fulfill(status=404,body='')
 page.route('**/*',route)
 for width in [1400,390]:
  page.set_viewport_size({'width':width,'height':1000});page.goto('https://paperlab.test/');page.get_by_role('heading',name='Kwartaalpilot: tien bedrijven').wait_for();page.locator('summary').first.click();page.get_by_text('Eigen kwartaalverwachting vastleggen',exact=True).click();assert page.evaluate('document.documentElement.scrollWidth<=innerWidth'),width
 for kind in ['revenue','eps']:
  for i,k in enumerate(['low','base','high']):page.locator('[name='+kind+'_'+k+']').fill(str(i+1))
 page.locator('[name=rationale]').fill('Onderbouwde synthetische testverwachting met financiële gegevens en verklaarde risico’s. '+('a'*30));page.locator('[name=counterarguments]').fill('Tegenargument: vraag en marges kunnen tegenvallen door gewijzigde omstandigheden.');page.get_by_role('button',name='Verwachting definitief vastleggen').click();assert page.evaluate('window.saved.forecast.revenue.base')==2;assert page.evaluate('window.saved.forecast.sources.length')==1;assert not errors,errors
 b.close();print('Chromium earnings passed: scenario form/source serialization, explicit manual scope and no overflow/errors at 390 and 1400px.')
