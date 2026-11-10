"""Exercise the layout with private snapshots and mocked API; never submits live actions.
Run after saving .data/managed/layout-api-fixtures.json through owner read RPCs.
PAPERLAB_BROWSER_URL may select published static assets; all private APIs remain mocked.
"""
import asyncio,json,os,sys,copy
from pathlib import Path
from urllib.parse import urlsplit,parse_qs
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'.deps'))
from playwright.async_api import async_playwright
async def main():
 fixtures=json.loads((ROOT/'.data/managed/layout-api-fixtures.json').read_text());web=ROOT/'managed/web';target=os.environ.get('PAPERLAB_BROWSER_URL','https://paperlab.test');host=urlsplit(target).hostname
 base=json.loads((ROOT/'managed/tests/python-fixtures.json').read_text())['state'];base['positions']={};base['running']=True;base['operation_mode']='continuous'
 async with async_playwright()as p:
  opts={'executable_path':'/usr/bin/chromium','headless':True,'args':['--no-sandbox','--disable-dev-shm-usage']}
  proxy=os.environ.get('HTTPS_PROXY')or os.environ.get('HTTP_PROXY')
  if proxy:
   u=urlsplit(proxy);opts['proxy']={'server':u.scheme+'://'+u.hostname+(':'+str(u.port)if u.port else'')}
  b=await p.chromium.launch(**opts)
  for width in[1440,390]:
   context=await b.new_context(viewport={'width':width,'height':1100});page=await context.new_page();errors=[];actions=[];page.on('pageerror',lambda e:errors.append(str(e)))
   async def route(r):
    u=urlsplit(r.request.url)
    if u.hostname==host:
     if host!='paperlab.test':await r.continue_();return
     file=web/(u.path.lstrip('/')or'index.html')
     if not file.is_file():await r.abort();return
     await r.fulfill(body=file.read_bytes(),content_type='text/html'if file.suffix=='.html'else'text/css'if file.suffix=='.css'else'application/json'if file.suffix=='.json'else'text/javascript');return
    if u.path!='/functions/v1/paper-api':await r.abort();return
    if r.request.method!='GET':actions.append(r.request.post_data);await r.abort();return
    query=parse_qs(u.query);name=next(iter(query),'')
    if name in fixtures:out=copy.deepcopy(fixtures[name])
    elif name=='capital-receipt':
     out=next(t for t in fixtures['capital-receipts']if str(t['id'])==query[name][0])
    elif name=='capital-export':out=fixtures['capital-receipts']
    elif name=='tax-report':out={}
    else:out={'revision':1,'state':base,'equity':500,'trade_count':0,'trades':[],'events':[],'curve':[],'collector_status':'fixture','free_usage':None}
    await r.fulfill(body=json.dumps(out),content_type='application/json')
   await context.route('**/*',route)
   await page.add_init_script("sessionStorage.setItem('paperlab.tab-session.v1',JSON.stringify({version:1,session:{access_token:'synthetic-aal2',refresh_token:'synthetic-refresh',expires_at:Date.now()+3600000},started_at:Date.now(),last_activity:Date.now(),page:'overview'}))")
   await page.goto(target+'/');await page.locator('#dashboardChart').wait_for(state='visible');assert('bedrijfspijlers'in await page.locator('#dashboardBody').inner_text())if fixtures['dashboard']['account']['summary'].get('company_policy')else('Alle 12 plaatsen'in await page.locator('#dashboardBody').inner_text())
   await page.screenshot(path=str(ROOT/f'.data/managed/dashboard-{width}.png'),full_page=True)
   for name in['trades','catalogue','research','opportunities','learning','settings']:
    await page.locator(f'[data-page="{name}"]').click();await page.locator('#'+name+'Page').wait_for(state='visible')
    if name=='trades':
     await page.locator('[data-dashboard-receipt]').first.wait_for(state='visible');assert await page.locator('#portfolioBody .clean-table tbody tr').count()==fixtures['dashboard']['account']['summary']['positions']
     await page.locator('[data-dashboard-receipt]').first.click();await page.locator('#receipt').wait_for(state='visible');assert'Oorspronkelijke aankoopmotivatie'in await page.locator('#receipt').inner_text();await page.locator('#closeReceipt').click()
     async with page.expect_download()as download:await page.locator('#dashboardExport').click()
     assert(await download.value).suggested_filename=='paperlab-10000-transacties.csv'
    if name=='research':
     await page.locator('#iexWatchlist').wait_for(state='visible');assert await page.locator('#iexWatchlist tbody tr').count()==6
     await page.get_by_text('Vandaag per bedrijf',exact=False).click();assert await page.locator('#iexCompanies tbody tr').count()==53
    if name=='opportunities':await page.locator('#dailyStudy').wait_for(state='visible');assert'Netto-uitkomsten'in await page.locator('#opportunitiesBody').inner_text()
    if name=='learning':
     await page.locator('#fundComparison summary').click();await page.locator('#fundComparison table').wait_for(state='visible');assert'Berkshire'in await page.locator('#strategyReview').inner_text();assert'undefined'not in await page.locator('#learningBody').inner_text()
     if'companies'in fixtures:
      await page.locator('#companyReview h2').wait_for(state='visible');await page.locator('#companyReview summary').filter(has_text='Dekking van alle').click();assert await page.locator('#companyCoverage tbody tr').count()==100;assert'Eerst het bedrijf'in await page.locator('#companyReview').inner_text()
    if name=='settings':await page.locator('#mainRoutineStatus').get_by_text('Hoofdkoersroutine:',exact=False).wait_for(state='visible')
    assert await page.locator('body').evaluate('(e)=>e.scrollWidth<=innerWidth'),(width,name)
    assert not errors,errors
   assert not actions,actions
   await page.locator('[data-page=learning]').click();await page.screenshot(path=str(ROOT/f'.data/managed/strategy-{width}.png'),full_page=True)
   print('Layout passed',width,': active account, reasons, open positions, receipts, CSV, six live quotes, 53 research rows, daily results, fund sources and all navigation; no live API writes.')
   await context.close()
  await b.close()
asyncio.run(main())
