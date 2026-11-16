"""Real browser encryption; synthetic API key, no provider calls or secret writes."""
import asyncio,json,os,sys,time
from pathlib import Path
from urllib.parse import urlsplit
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from playwright.async_api import async_playwright
from scripts.gemini_recovery import decode
async def main():
 target=os.environ.get('PAPERLAB_BROWSER_URL','https://paperlab.test');host=urlsplit(target).hostname;dummy='AIza'+'a'*35
 async with async_playwright()as p:
  b=await p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox','--disable-dev-shm-usage'])
  for width in [1440,390]:
   ctx=await b.new_context(viewport={'width':width,'height':1000});page=await ctx.new_page();errors=[];requests=[];page.on('pageerror',lambda e:errors.append(str(e)))
   async def route(r):
    u=urlsplit(r.request.url);requests.append(r.request.url)
    assert u.hostname==host and r.request.method=='GET';assert dummy not in r.request.url and dummy not in(r.request.post_data or'')
    if host!='paperlab.test':await r.continue_();return
    f=ROOT/'managed/web'/u.path.lstrip('/');assert f.is_file()
    await r.fulfill(body=f.read_bytes(),content_type='text/html'if f.suffix=='.html'else'text/css'if f.suffix=='.css'else'application/json'if f.suffix=='.json'else'text/javascript')
   await ctx.route('**/*',route);await page.goto(target+'/gemini-connect.html');await page.wait_for_function("!document.getElementById('encrypt').disabled")
   await page.locator('#token').fill(dummy);count=len(requests);await page.locator('#encrypt').click();await page.locator('#result').wait_for(state='visible');envelope=await page.locator('#output').input_value()
   assert decode(envelope)['t']==dummy;assert not await page.locator('#token').input_value();assert dummy not in await page.locator('body').inner_text();assert len(requests)==count
   assert await page.evaluate('localStorage.length+sessionStorage.length')==0;assert await ctx.cookies()==[];assert not errors;assert await page.evaluate('document.documentElement.scrollWidth<=innerWidth')
   for bad,now in [(envelope[:-10]+'A'*10,None),(envelope,int(time.time()*1000)+1800001),(envelope.replace('PAPERLAB-GEMINI-CONNECT-1','PAPERLAB-RENDER-RECOVERY-1'),None)]:
    try:decode(bad,now=now);raise AssertionError('Invalid message accepted')
    except RuntimeError:pass
   await ctx.close();print('Gemini browser passed',width,': actual decrypt, tamper/expiry/purpose rejection, cleared input, no storage, no network submission.')
  await b.close()
asyncio.run(main())
