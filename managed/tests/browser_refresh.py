"""Browser regression with synthetic Auth/API responses; no production reads or writes.
Uses Playwright from the environment or .deps and /usr/bin/chromium.
Run: python managed/tests/browser_refresh.py
"""
import asyncio,json,os,sys,copy
from pathlib import Path
from urllib.parse import urlsplit
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'.deps'))
from playwright.async_api import async_playwright
WEB=ROOT/'managed/web';KEY='paperlab.tab-session.v1'
async def main():
 async with async_playwright()as p:
  opts={'executable_path':'/usr/bin/chromium','headless':True,'args':['--no-sandbox','--disable-dev-shm-usage']}
  proxy=os.environ.get('HTTPS_PROXY')or os.environ.get('HTTP_PROXY')
  if proxy:
   u=urlsplit(proxy);opts['proxy']={'server':u.scheme+'://'+u.hostname+(':'+str(u.port)if u.port else'')}
  browser=await p.chromium.launch(**opts);context=await browser.new_context(viewport={'width':1400,'height':1000});page=await context.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  counts={'password':0,'factor':0,'refresh':0,'reads':0};actions=[];revoked=False
  fixture=json.loads((ROOT/'managed/tests/python-fixtures.json').read_text())['state'];fixture['positions']={};fixture['operation_mode']='continuous';fixture['running']=True
  async def route(r):
   nonlocal revoked
   u=urlsplit(r.request.url);path=u.path
   if u.hostname=='paperlab.test':
    name=path.lstrip('/')or'index.html';file=WEB/name
    if not file.is_file():await r.abort();return
    mime='text/html'if name.endswith('.html')else'text/javascript'if name.endswith('.js')else'text/css'if name.endswith('.css')else'application/json'
    await r.fulfill(body=file.read_bytes(),content_type=mime);return
   if '.supabase.co'not in u.hostname:await r.abort();return
   body=json.loads(r.request.post_data or'{}');out={};status=200
   if path=='/auth/v1/token' and'grant_type=password'in u.query:counts['password']+=1;out={'access_token':'synthetic-aal1','refresh_token':'synthetic-refresh1','expires_in':3600}
   elif path=='/auth/v1/token' and'grant_type=refresh_token'in u.query:counts['refresh']+=1;out={'access_token':'synthetic-aal2-rotated','refresh_token':'synthetic-refresh2','expires_in':3600}
   elif path=='/auth/v1/user':out={'id':'synthetic-owner','factors':[{'id':'synthetic-factor','factor_type':'totp','status':'verified'}]}
   elif path.endswith('/challenge'):out={'id':'synthetic-challenge'}
   elif path.endswith('/verify'):counts['factor']+=1;out={'access_token':'synthetic-aal2','refresh_token':'synthetic-refresh1','expires_in':3600}
   elif path.endswith('/logout'):out={}
   elif path=='/functions/v1/paper-api':
    token=r.request.headers.get('authorization','')
    if revoked:status=401;out={'error':'Sessie verlopen'}
    elif token not in ['Bearer synthetic-aal2','Bearer synthetic-aal2-rotated']:status=403;out={'error':'Tweefactor vereist'}
    elif r.request.method=='POST':actions.append(body.get('action'));out={'ok':True}
    else:
     counts['reads']+=1;s=copy.deepcopy(fixture);s['cash']=500+counts['reads'];out={'revision':counts['reads'],'state':s,'equity':s['cash'],'trade_count':0,'curve':[],'events':[],'trades':[],'collector_status':'fixture','free_usage':None}
   else:status=404;out={'error':'unexpected fixture route'}
   await r.fulfill(status=status,body=json.dumps(out),content_type='application/json')
  await context.route('**/*',route)
  await page.add_init_script("""(()=>{const mode=sessionStorage.getItem('__fixture_patch');if(!mode)return;sessionStorage.removeItem('__fixture_patch');let r=JSON.parse(sessionStorage.getItem('paperlab.tab-session.v1')||'null');if(mode==='expire'&&r)r.session.expires_at=Date.now()-1;if(mode==='idle'&&r){r.last_activity=Date.now()-31*60000;r.started_at=r.last_activity-1000;}if(mode==='aal1'||mode==='revoked')r={version:1,session:{access_token:mode==='aal1'?'synthetic-aal1':'synthetic-aal2',refresh_token:'synthetic-refresh1',expires_at:Date.now()+3600000},started_at:Date.now(),last_activity:Date.now(),page:'overview'};sessionStorage.setItem('paperlab.tab-session.v1',JSON.stringify(r));})()""")
  async def login():
   await page.locator('#email').fill('test@example.invalid');await page.locator('#password').fill('synthetic-test-password');await page.locator('#loginForm button').click();await page.locator('#factorForm').wait_for(state='visible');assert await page.evaluate(f'sessionStorage.getItem({json.dumps(KEY)})')is None;await page.locator('#code').fill('123456');await page.locator('#factorForm button[type=submit],#factorForm button.primary').first.click();await page.locator('#app').wait_for(state='visible')
  await page.goto('https://paperlab.test/');await login();saved=await page.evaluate(f'sessionStorage.getItem({json.dumps(KEY)})');assert'synthetic-test-password'not in saved
  before=counts['reads'];await page.locator('#refreshData').click();await page.wait_for_function("document.querySelector('#toast').textContent==='Laatste gegevens opgehaald.'");assert counts['reads']==before+1;assert not actions
  await page.locator('[data-page=catalogue]').click();await page.reload();await page.locator('#app').wait_for(state='visible');await page.locator('#cataloguePage').wait_for(state='visible');assert counts['password']==1 and counts['factor']==1
  await page.evaluate("sessionStorage.setItem('__fixture_patch','expire')")
  await page.reload();await page.locator('#app').wait_for(state='visible');assert counts['refresh']==1;assert'synthetic-aal2-rotated'in await page.evaluate(f'sessionStorage.getItem({json.dumps(KEY)})')
  other=await context.new_page();await other.goto('https://paperlab.test/');await other.locator('#loginForm').wait_for(state='visible');assert await other.locator('#app').is_hidden();await other.close()
  for width in [1400,390]:
   await page.set_viewport_size({'width':width,'height':1000});assert await page.locator('body').evaluate('(e)=>e.scrollWidth<=window.innerWidth'),width;await page.screenshot(path=str(ROOT/f'.data/managed/refresh-{width}.png'),full_page=True)
  await page.evaluate("sessionStorage.setItem('__fixture_patch','idle')")
  reads=counts['reads'];await page.reload();await page.locator('#loginForm').wait_for(state='visible');assert await page.locator('#app').is_hidden();assert counts['reads']==reads;assert await page.evaluate(f'sessionStorage.getItem({json.dumps(KEY)})')is None
  await page.evaluate("sessionStorage.setItem('__fixture_patch','aal1')")
  await page.reload();await page.locator('#loginForm').wait_for(state='visible');assert await page.locator('#app').is_hidden();assert await page.evaluate(f'sessionStorage.getItem({json.dumps(KEY)})')is None
  revoked=True;await page.evaluate("sessionStorage.setItem('__fixture_patch','revoked')");await page.reload();await page.locator('#loginForm').wait_for(state='visible');assert await page.locator('#app').is_hidden();assert await page.evaluate(f'sessionStorage.getItem({json.dumps(KEY)})')is None;revoked=False
  await login();await page.locator('#logoutHeader').click();await page.locator('#loginForm').wait_for(state='visible');assert actions==['logout'];assert await page.evaluate(f'sessionStorage.getItem({json.dumps(KEY)})')is None
  await page.reload();await page.locator('#loginForm').wait_for(state='visible');assert await page.locator('#app').is_hidden();assert not errors,errors
  print('Browser passed: MFA before persistence, refresh GET only, reload/page restore, token rotation, separate tabs, idle expiry, AAL1/revoked-session rejection, logout clearing, desktop/mobile layout; no real credentials or production writes.')
  await browser.close()
asyncio.run(main())
