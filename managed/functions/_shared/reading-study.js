import {READING_PLAN,READING_POLICY} from './reading-plan.js';
import {sha} from './learner.js';
export function readingText(html){return html.replace(/<!--[^]*?-->/g,' ').replace(/<(script|style|noscript)\b[^>]*>[^]*?<\/\1>/gi,' ').replace(/<[^>]*>/g,' ').replace(/&nbsp;|&#160;/g,' ').replace(/&amp;/g,'&').replace(/&quot;/g,'"').replace(/&#39;|&#8217;/g,"'").replace(/\s+/g,' ').trim();}
export async function readDaily(input,{fetcher=fetch,time=Date.now()}={}){
 const slot=input.cursor%READING_PLAN.length,card=READING_PLAN[slot];if(!card||input.policy?.version!==READING_POLICY.version)throw Error('Reading plan unavailable');
 const result={version:READING_POLICY.version,day:input.day,checked_at:new Date(time).toISOString(),card_id:card.id,year:card.year,title:card.title,author:card.author,url:card.url,source_type:card.source_type,
  cycle:Math.floor(input.cursor/READING_PLAN.length),analysis_origin:'editor_reviewed_at_setup',read_scope:'selected_passage_verification',status:'source_unavailable',source_bytes:0,
  automatic_model_training:false,trading_changes:false,note:'Dagelijkse verificatie met een vooraf beoordeelde leesnotitie. Geen volledig boek of nieuwe dagelijkse AI-analyse; na acht thema’s volgt herkenbare herhaling.'};
 try{
  const r=await fetcher(card.url,{headers:{'User-Agent':'PaperLab/1.0 (bounded primary-source reading)'},redirect:'manual',signal:AbortSignal.timeout(8000)});result.http=r.status;
  if(!r.ok){await r.body?.cancel();return result;}
  if(!(r.headers.get('Content-Type')||'').toLowerCase().includes('text/html')){await r.body?.cancel();result.status='source_invalid';return result;}
  if(Number(r.headers.get('Content-Length'))>READING_POLICY.max_download_bytes){await r.body?.cancel();result.status='source_invalid';return result;}
  const reader=r.body?.getReader();if(!reader)throw Error('No source body');const chunks=[];let n=0;
  try{while(true){const {done,value}=await reader.read();if(done)break;n+=value.byteLength;result.source_bytes=n;if(n>READING_POLICY.max_download_bytes)throw Error('Reading byte limit');chunks.push(value);}}
  finally{await reader.cancel().catch(()=>{});}
  const bytes=new Uint8Array(n);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength;}
  const text=readingText(new TextDecoder().decode(bytes)),lower=text.toLowerCase();
  if(text.length<5000||!lower.includes('berkshire hathaway')||!lower.includes('buffett')||card.anchors.some(a=>!lower.includes(a.toLowerCase()))){result.status='source_invalid';return result;}
  result.status='verified';result.content_sha256=await sha(new TextDecoder().decode(bytes));result.source_text_chars=text.length;result.anchors_checked=card.anchors;
  result.lesson=card.lesson;result.question=card.question;result.missing=card.missing;return result;
 }catch{result.status='source_unavailable';return result;}
}
