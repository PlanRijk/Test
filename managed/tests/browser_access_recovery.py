"""Real browser encryption with a synthetic token; no credential or API writes."""
import asyncio,json,os,sys
from pathlib import Path
from urllib.parse import urlsplit
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT));sys.path.insert(0,str(ROOT/'.deps'))
from playwright.async_api import async_playwright
from scripts.access_recovery import decode
async def main():
 target=os.environ.get('PAPERLAB_BROWSER_URL','https://paperlab.test');host=urlsplit(target).hostname;dummy='sbp_'+'a'*40
 async with async_playwright()as p:
  options={'executable_path':'/usr/bin/chromium','headless':True,'args':['--no-sandbox','--disable-dev-shm-usage']};proxy=os.environ.get('HTTPS_PROXY')or os.environ.get('HTTP_PROXY')
  if proxy:
   u=urlsplit(proxy);options['proxy']={'server':u.scheme+'://'+u.hostname+(':'+str(u.port)if u.port else'')}
  b=await p.chromium.launch(**options)
  for width in[1440,390]:
   context=await b.new_context(viewport={'width':width,'height':1000});page=await context.new_page();errors=[];requests=[];page.on('pageerror',lambda e:errors.append(type(e).__name__))
   async def route(r):
    u=urlsplit(r.request.url);requests.append({'url':r.request.url,'method':r.request.method,'body':r.request.post_data})
    assert u.hostname==host,'Unexpected external request';assert r.request.method=='GET','Recovery submitted a network write';assert dummy not in r.request.url and dummy not in(r.request.post_data or''),'Token transmitted'
    if host!='paperlab.test':await r.continue_();return
    file=ROOT/'managed/web'/u.path.lstrip('/');assert file.is_file()
    await r.fulfill(body=file.read_bytes(),content_type='text/html'if file.suffix=='.html'else'text/css'if file.suffix=='.css'else'application/json'if file.suffix=='.json'else'text/javascript')
   await context.route('**/*',route);await page.goto(target+'/access-recovery.html');await page.locator('#accessRecoveryEncrypt').wait_for(state='visible')
   await page.wait_for_function("()=>!document.getElementById('accessRecoveryEncrypt').disabled")
   await page.locator('#accessRecoveryToken').fill(dummy);count=len(requests);await page.locator('#accessRecoveryEncrypt').click();await page.locator('#accessRecoveryResult').wait_for(state='visible');envelope=await page.locator('#accessRecoveryOutput').input_value()
   assert decode(envelope)['t']==dummy;assert not await page.locator('#accessRecoveryToken').input_value();assert dummy not in await page.locator('body').inner_text();assert len(requests)==count
   assert await page.evaluate('localStorage.length+sessionStorage.length')==0;assert await context.cookies()==[];assert not errors;assert await page.locator('body').evaluate('(e)=>e.scrollWidth<=innerWidth')
   for bad in[envelope[:-1]+('A'if envelope[-1]!='A'else'B')]:
    try:decode(bad);raise AssertionError('Tampered envelope accepted')
    except RuntimeError:pass
   try:decode(envelope,now=__import__('time').time_ns()//1000000+1800001);raise AssertionError('Expired envelope accepted')
   except RuntimeError:pass
   await page.screenshot(path=str(ROOT/f'.data/managed/access-recovery-{width}.png'),full_page=True)
   print('Recovery browser passed',width,': matching private-key decryption, tamper/expiry rejection, cleared input, no storage, no outbound token or network writes.');await context.close()
  await b.close()
asyncio.run(main())
