"""Private public-report text extraction. No model key, broker access or persistence."""
import hashlib,hmac,io,ipaddress,json,os,socket,threading,urllib.request,urllib.error
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from urllib.parse import urlsplit
MAX_BYTES=20000000
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs):return None
def allowed(url,hosts):
 u=urlsplit(url)
 if u.scheme!='https'or u.username or u.password or u.port not in(None,443)or not u.hostname or not any(u.hostname==h or u.hostname.endswith('.'+h)for h in hosts):raise ValueError('source_host_not_registered')
 if not all(ipaddress.ip_address(x[4][0]).is_global for x in socket.getaddrinfo(u.hostname,443,type=socket.SOCK_STREAM)):raise ValueError('source_address_not_public')
 return u.geturl()
def extract_bytes(raw):
 import pymupdf
 if not raw.startswith(b'%PDF-'):raise ValueError('not_pdf')
 with pymupdf.open(stream=raw,filetype='pdf')as doc:
  if doc.is_encrypted:raise ValueError('encrypted_pdf')
  if len(doc)>600:raise ValueError('page_budget')
  parts=[];empty=[];size=0
  for index,page in enumerate(doc):
   text=page.get_text('text',sort=True);size+=len(text)
   if size>2000000:raise ValueError('text_budget')
   if not text.strip():empty.append(index+1)
   parts.append('[PAGINA '+str(index+1)+']\n'+text)
  text='\n'.join(parts)
  return {'version':'paperlab-pdf-text-v1','sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'text':text,'text_sha256':hashlib.sha256(text.encode()).hexdigest(),'pages_total':len(doc),'pages_processed':len(doc),'empty_pages':empty,'complete_extraction':not empty,'scope':'Text extracted from every PDF page; tables, images and reading order are not independently audited','ocr_required':bool(empty)}
lock=threading.BoundedSemaphore(1)
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def reply(self,value,code=200):
  raw=json.dumps(value,ensure_ascii=False).encode();self.send_response(code);self.send_header('Content-Type','application/json');self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw)
 def do_GET(self):
  self.reply({'status':'ready','private_extraction':True})if self.path=='/health'else self.reply({'error':'not_found'},404)
 def do_POST(self):
  secret=os.environ.get('PAPERLAB_CRON_TOKEN','');actual=self.headers.get('X-PaperLab-Cron','')
  if not secret or not hmac.compare_digest(secret,actual):self.reply({'error':'not_allowed'},401);return
  if self.path!='/extract':self.reply({'error':'not_found'},404);return
  if not lock.acquire(blocking=False):self.reply({'error':'busy','retry_after_seconds':60},429);return
  try:
   n=int(self.headers.get('Content-Length','0'))
   if not 0<n<=4000:raise ValueError('request_budget')
   body=json.loads(self.rfile.read(n));url=allowed(body['url'],[s.strip().lower()for s in os.environ.get('PAPERLAB_PDF_HOSTS','').split(',')if s.strip()]);opener=urllib.request.build_opener(NoRedirect())
   with opener.open(urllib.request.Request(url,headers={'User-Agent':'PaperLab public financial report reader'}),timeout=35)as response:
    raw=response.read(MAX_BYTES+1)
   if len(raw)>MAX_BYTES:raise ValueError('download_budget')
   self.reply(extract_bytes(raw))
  except urllib.error.HTTPError as error:self.reply({'error':'source_unavailable','source_http_status':error.code},502)
  except ValueError as error:self.reply({'error':str(error)if str(error)in['source_host_not_registered','source_address_not_public','not_pdf','encrypted_pdf','page_budget','text_budget','request_budget','download_budget']else'invalid_input'},422)
  except Exception:self.reply({'error':'extraction_unavailable'},503)
  finally:lock.release()
if __name__=='__main__':ThreadingHTTPServer(('0.0.0.0',int(os.environ.get('PORT','10000'))),Handler).serve_forever()
