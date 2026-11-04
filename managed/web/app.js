import {CONFIG} from './config.js';
import {COMPANIES,BY_SYMBOL} from './catalogue.js';
import {freeBudgetAlert} from './usage.js';
import {learningMarkup} from './learning.js';
import {opportunityMarkup,opportunityDetailMarkup} from './opportunities.js';
import {reliabilityMarkup} from './reliability.js';
import {taxMarkup} from './tax.js';
import {dailyMarkup} from './daily-study.js';
import {historyMarkup} from './history-learning.js';
const $=q=>document.querySelector(q),money=new Intl.NumberFormat('nl-BE',{style:'currency',currency:'EUR'}),num=new Intl.NumberFormat('nl-BE',{maximumFractionDigits:4});
const euros=n=>money.format(Number(n)||0),when=t=>t?new Intl.DateTimeFormat('nl-BE',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Brussels'}).format(new Date(t)):'—';
const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
let session=null,data=null,factor=null,challenge=null,enrolling=false,receipt=null,lastActivity=Date.now(),polling=false;
function authError(message){$('#authError').textContent=message;$('#authError').hidden=!message;}
function toast(message){$('#toast').textContent=message;$('#toast').hidden=false;setTimeout(()=>$('#toast').hidden=true,5000);}
function form(id,title,text){for(const x of ['loginForm','passwordForm','factorForm','recoveryForm','recoveryCodes'])$('#'+x).hidden=x!==id;$('#authTitle').textContent=title;$('#authText').textContent=text;authError('');}
function setSession(s){session={access_token:s.access_token,refresh_token:s.refresh_token,expires_at:Date.now()+(s.expires_in||3600)*1000};}
async function auth(path,method='GET',body=null,anonymous=false){
 const r=await fetch(CONFIG.url+'/auth/v1'+path,{method,headers:{apikey:CONFIG.key,'Content-Type':'application/json',...(session&&!anonymous?{Authorization:'Bearer '+session.access_token}:{})},body:body?JSON.stringify(body):undefined});
 const result=await r.json().catch(()=>({}));if(!r.ok)throw Error(result.msg||result.message||result.error_description||'Aanmelden niet voltooid. Controleer je gegevens.');return result;
}
async function refresh(){if(session&&session.expires_at<Date.now()+60000)setSession(await auth('/token?grant_type=refresh_token','POST',{refresh_token:session.refresh_token},true));}
async function api(query='',body=null){
 if(!session)throw Error('Meld opnieuw aan.');await refresh();
 const r=await fetch(CONFIG.url+'/functions/v1/paper-api'+query,{method:body?'POST':'GET',headers:{apikey:CONFIG.key,Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});
 const result=await r.json().catch(()=>({}));if(!r.ok){if(r.status===401)await logout(false);throw Error(result.error||'De opdracht is niet voltooid.');}return result;
}
async function setupFactor(){
 const user=await auth('/user');factor=(user.factors||[]).find(f=>f.factor_type==='totp'&&f.status==='verified');
 enrolling=!factor;$('#enrollment').hidden=!enrolling;$('#useRecovery').hidden=enrolling;
 if(enrolling){
  for(const f of user.factors||[])if(f.factor_type==='totp'&&f.status!=='verified')await auth('/factors/'+f.id,'DELETE');
  factor=await auth('/factors','POST',{factor_type:'totp',friendly_name:'PaperLab'});
  $('#qr').src='data:image/svg+xml;charset=utf-8,'+encodeURIComponent(factor.totp.qr_code);$('#manualSecret').textContent=factor.totp.secret;
 }
 challenge=await auth('/factors/'+factor.id+'/challenge','POST',{});
 form('factorForm',enrolling?'Beveilig je account':'Tweede verificatie',enrolling?'Koppel je authenticator en vul de zescijferige code in.':'Vul de code uit je authenticator-app in.');$('#code').value='';$('#code').focus();
}
async function recoveryCodes(){
 const codes=Array.from({length:10},()=>[...crypto.getRandomValues(new Uint8Array(12))].map(x=>x.toString(16).padStart(2,'0')).join(''));
 const hashes=await Promise.all(codes.map(async c=>[...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(c)))].map(x=>x.toString(16).padStart(2,'0')).join('')));
 await api('',{action:'recovery-codes',hashes});$('#codes').replaceChildren(...codes.map(c=>{const x=document.createElement('code');x.textContent=c;return x;}));
 $('#savedCodes').checked=false;$('#finishSetup').disabled=true;$('#app').hidden=true;$('#auth').hidden=false;
 form('recoveryCodes','Bewaar je herstelcodes','Je vorige herstelcodes vervallen zodra je nieuwe codes maakt.');
}
async function enter(){
 data=await api();if(data.not_initialized)throw Error('De portefeuille wordt nog geïnstalleerd.');
 $('#auth').hidden=true;$('#app').hidden=false;lastActivity=Date.now();render();
}
async function logout(remote=true){
 if(remote&&session){try{await api('',{action:'logout'});}catch{}try{await auth('/logout','POST',{});}catch{}}
 session=null;data=null;factor=null;$('#app').hidden=true;$('#auth').hidden=false;$('#password').value='';$('#manualSecret').textContent='';$('#qr').removeAttribute('src');$('#codes').replaceChildren();form('loginForm','Welkom terug','Meld aan met je wachtwoord en authenticator.');
}
async function busy(button,work){const text=button.textContent;button.disabled=true;try{await work();}catch(e){if($('#app').hidden)authError(e.message);else toast(e.message);}finally{button.disabled=false;button.textContent=text;}}
$('#loginForm').onsubmit=e=>{e.preventDefault();busy(e.submitter,async()=>{setSession(await auth('/token?grant_type=password','POST',{email:$('#email').value.trim(),password:$('#password').value},true));$('#password').value='';await setupFactor();});};
$('#passwordForm').onsubmit=e=>{e.preventDefault();busy(e.submitter,async()=>{const p=$('#newPassword').value;if(p.length<14||p!==$('#repeatPassword').value)throw Error('Gebruik minstens 14 tekens en twee gelijke wachtwoorden.');await auth('/user','PUT',{password:p});$('#newPassword').value='';$('#repeatPassword').value='';await setupFactor();});};
$('#factorForm').onsubmit=e=>{e.preventDefault();busy(e.submitter,async()=>{setSession(await auth('/factors/'+factor.id+'/verify','POST',{challenge_id:challenge.id,code:$('#code').value.trim()}));$('#code').value='';$('#manualSecret').textContent='';$('#qr').removeAttribute('src');if(enrolling)await recoveryCodes();else await enter();});};
$('#useRecovery').onclick=()=>form('recoveryForm','Authenticator herstellen','Gebruik een ongebruikte herstelcode. Daarna koppel je een nieuwe authenticator.');
$('#recoveryForm').onsubmit=e=>{e.preventDefault();busy(e.submitter,async()=>{await api('',{action:'recover',code:$('#recoveryCode').value.trim().toLowerCase()});$('#recoveryCode').value='';await setupFactor();});};
$('#savedCodes').onchange=e=>$('#finishSetup').disabled=!e.target.checked;
$('#finishSetup').onclick=e=>busy(e.currentTarget,async()=>{$('#codes').replaceChildren();await enter();});
$('#logout').onclick=()=>logout();$('#newRecovery').onclick=e=>busy(e.currentTarget,recoveryCodes);
for(const type of ['pointerdown','keydown','touchstart'])document.addEventListener(type,()=>lastActivity=Date.now(),{passive:true});
const titles={overview:'Portefeuilleoverzicht',catalogue:'Aandelencatalogus',trades:'Transactiegeschiedenis',research:'Onderzoek & handelsregels',learning:'Leren & aankoopanalyse',opportunities:'Breder kansenonderzoek'};
async function loadTaxReport(){try{$('#taxReport').innerHTML=taxMarkup(await api('?tax-report=1'));}catch(e){$('#taxReport').textContent=e.message;}}
async function loadOpportunities(){
 try{const [result,reliability,daily]=await Promise.all([api('?opportunities=1'),api('?reliability=1'),api('?daily-study=1')]);$('#opportunitiesBody').innerHTML=dailyMarkup(daily)+reliabilityMarkup(reliability)+opportunityMarkup(result);
  $('#dailyStudyExport').onclick=e=>busy(e.currentTarget,async()=>{const rows=await api('?daily-export=1'),quote=v=>'"'+String(v??'').replaceAll('"','""')+'"';download(new Blob(['\uFEFF'+[['id','symbol','decision_day','week','profile','sealed','record_json'],...rows.map(r=>[r.id,r.symbol,r.decision_day,r.week,r.profile,r.sealed,JSON.stringify(r)])].map(r=>r.map(quote).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'}),'paperlab-dagonderzoek.csv');});
  $('#studyArchiveExport').onclick=e=>busy(e.currentTarget,async()=>{const rows=await api('?archive-export=1'),quote=v=>'"'+String(v??'').replaceAll('"','""')+'"';download(new Blob(['\uFEFF'+[['id','day','symbol','cohort','sealed','codec_version','profile','compact_record_json'],...rows.map(r=>[r.id,r.day,r.symbol,r.cohort,r.sealed,r.codec_version,r.profile,JSON.stringify(r)])].map(r=>r.map(quote).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'}),'paperlab-compact-archief.csv');});
  $('#studyToggle').onclick=e=>busy(e.currentTarget,async()=>{await api('',{action:'opportunities',command:e.currentTarget.dataset.command});await loadOpportunities();});
  document.querySelectorAll('[data-opportunity]').forEach(b=>b.onclick=()=>busy(b,async()=>{const r=await api('?opportunity='+encodeURIComponent(b.dataset.opportunity));$('#opportunityDetailBody').innerHTML=opportunityDetailMarkup(r);$('#opportunityDetail').showModal();}));
  $('#studyExport').onclick=e=>busy(e.currentTarget,async()=>{const rows=await api('?opportunity-export=1'),headers=['id','day','symbol','cohort','decision_at','statement','main_reasons_json','entry_json','outcomes_json','features_json','fingerprint','record_json'];
   const quote=v=>'"'+String(v??'').replaceAll('"','""')+'"';const lines=[headers,...rows.map(r=>[r.id,r.day,r.symbol,r.cohort,r.decision_at,r.statement,JSON.stringify(r.main_reasons),JSON.stringify(r.entry||null),JSON.stringify(r.outcomes),JSON.stringify(r.context?.features),r.fingerprint,JSON.stringify(r)])];download(new Blob(['\uFEFF'+lines.map(r=>r.map(quote).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'}),'paperlab-hypothetische-observaties.csv');});
 }catch(e){$('#opportunitiesBody').textContent=e.message;}
}
$('#closeOpportunity').onclick=()=>$('#opportunityDetail').close();
async function loadLearning(){
 try{const [result,purchases,shadows,history]=await Promise.all([api('?learning=1'),api('?purchase-analysis=1'),api('?learning-trades=1'),api('?history-learning=1')]);
  const rows=shadows.map(x=>({...x,shadow:true}));renderLearning(result,[...purchases,...rows],history);}catch(e){$('#learningBody').textContent=e.message;}
}
function renderLearning(result,purchases,history){
 $('#learningBody').innerHTML=historyMarkup(history)+learningMarkup(result,purchases);
 $('#historyExport').onclick=e=>busy(e.currentTarget,async()=>{const rows=await api('?history-export=1'),quote=v=>'"'+String(v??'').replaceAll('"','""')+'"';download(new Blob(['\uFEFF'+[['id','model_id','symbol','decision_at','probability','selected','status','origin','record_json'],...rows.map(r=>[r.id,r.model_id,r.symbol,r.decision_at,r.probability,r.selected,r.status,r.origin,JSON.stringify(r)])].map(r=>r.map(quote).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'}),'paperlab-historisch-model-voorwaarts.csv');});
 document.querySelectorAll('[data-purchase]').forEach(b=>b.onclick=()=>openReceipt(Number(b.dataset.purchase),b.dataset.shadow==='true'));
 $('#learningExport').onclick=e=>busy(e.currentTarget,async()=>{
  const rows=await api('?learning-export=1'),headers=['id','schema','fingerprint','symbol','venue','decision_time','entry_time','available_at','net_eur','features_json'];
  const quote=x=>'"'+String(x??'').replaceAll('"','""')+'"';download(new Blob(['\uFEFF'+[headers,...rows.map(r=>[r.id,r.schema,r.fingerprint,r.symbol,r.venue,r.decision_time,r.entry_time,r.available_at,r.net_eur,JSON.stringify(r.features)])].map(r=>r.map(quote).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'}),'paperlab-leerdata.csv');
 });
 document.querySelectorAll('[data-learning]').forEach(b=>b.onclick=()=>busy(b,async()=>{
  await api('',{action:'learning',command:b.dataset.learning,model:b.dataset.model||null});await loadLearning();
 }));
}
document.querySelectorAll('[data-page]').forEach(button=>button.onclick=()=>{document.querySelectorAll('.page').forEach(p=>p.hidden=p.id!==button.dataset.page+'Page');document.querySelectorAll('[data-page]').forEach(b=>b.classList.toggle('active',b===button));$('#pageTitle').textContent=titles[button.dataset.page];if(button.dataset.page==='learning')loadLearning();if(button.dataset.page==='opportunities')loadOpportunities();if(button.dataset.page==='research')loadTaxReport();});
function plot(points){
 if(!points.length)return '<p class="muted">Nog geen koersmetingen.</p>';
 const values=points.map(p=>Number(p.value)),lo=Math.min(...values)*.999,hi=Math.max(...values)*1.001,range=hi-lo||1;
 const path=values.map((v,i)=>`${i?'L':'M'}${(i*780/Math.max(1,values.length-1)).toFixed(2)},${(195-(v-lo)/range*165).toFixed(2)}`).join(' ');
 return `<svg viewBox="0 0 800 220" role="img" aria-label="Verloop van de virtuele portefeuille"><path d="M0 50H800 M0 120H800 M0 195H800" stroke="#263448" fill="none"/><path d="${path}" stroke="#65dcb1" stroke-width="2.5" fill="none"/><text x="5" y="18" fill="#94a3b8" font-size="12">${esc(euros(Math.max(...values)))}</text></svg>`;
}
function sign(node,value){node.classList.toggle('negative',value<0);node.classList.toggle('positive',value>0);}
function render(){
 if(!data?.state)return;const s=data.state,eq=data.equity;
 $('#equity').textContent=euros(eq);$('#cash').textContent=euros(s.cash);$('#realized').textContent=euros(s.realized);sign($('#realized'),s.realized);
 $('#return').textContent=`${euros(eq-500)} (${((eq/500-1)*100).toFixed(2)}%) sinds de start`;sign($('#return'),eq-500);
 $('#fees').textContent=euros(s.fees)+' gesimuleerde commissie';$('#positionsCount').textContent=Object.keys(s.positions).length+' / 4';
 $('#cycleCount').textContent=s.tick+' metingen · '+data.trade_count+' handelsacties';$('#chart').innerHTML=plot(data.curve||[]);$('#firstTime').textContent=when(data.curve?.[0]?.time);$('#lastTime').textContent=when(s.last_update);
 const end=s.operation_mode!=='continuous'&&Date.parse(s.run_until)<=Date.now(),halt=s.risk.daily_halted||s.risk.global_halted;
 $('#agentStatus').textContent=end?'Proef afgelopen':!s.running?'Gepauzeerd':halt?'Actief · risicostop':data.collector_status==='error'?'Actief · controle nodig':'Actief';
 $('#lastMeasurement').textContent='Laatste opgeslagen meting: '+when(s.last_update)+' (Brussel)';$('#coverage').textContent=(s.data_info?.fresh_symbols??0)+' verse koersen in de laatste batch. Oude koersen worden niet uitgevoerd.';
 $('#toggle').textContent=s.running?'Experiment pauzeren':'Experiment hervatten';$('#toggle').disabled=end;$('#step').disabled=end;
 $('#deadline').textContent=s.operation_mode==='continuous'?'Doorlopende paperproef zonder vaste einddatum. Geplande koers-, bron- en leercontroles lopen zonder geopende website, binnen risico- en verbruiksgrenzen.':'Deze proef eindigt '+when(s.run_until)+' Belgische tijd. Geplande controles lopen zonder geopende website.';
 $('#globalError').textContent=s.error||'';$('#globalError').hidden=!s.error;
 const positions=Object.entries(s.positions);$('#positions').innerHTML=positions.length?positions.map(([k,p])=>{const c=BY_SYMBOL[k]?.currency||'USD',rate=s.price_fx?.[k]||(c==='EUR'?1:s.usd_per_eur),value=p.qty*s.prices[k]/rate;return `<div class="position"><div><strong>${esc(k)}</strong><p>${esc(BY_SYMBOL[k]?.name||k)}</p><small>${esc(num.format(p.qty))} aandelen · stop ${esc(euros(p.stop))} · doel ${esc(euros(p.target))}</small></div><div><strong>${esc(euros(value))}</strong><p class="${value-p.cost<0?'negative':'positive'}">${esc(euros(value-p.cost))}</p><small>Voor toekomstige verkoopkosten</small></div></div>`;}).join(''):'<p class="muted">Geen open posities. Wachten op een geldig signaal is ook een beslissing.</p>';
 $('#events').innerHTML=(data.events||[]).slice(0,8).map(x=>`<div class="event"><p>${esc(x.reason)}</p><small>${esc(when(x.time))}${x.symbol?' · '+esc(x.symbol):''}</small></div>`).join('')||'<p class="muted">Nog geen nieuwe besluiten.</p>';
 const r=s.risk.config,t=s.belgian_tax.config;$('#riskSummary').textContent=`${euros(r.daily_loss_eur)} dagverliestrigger · ${euros(r.max_drawdown_eur)} daling vanaf piek · ${euros(r.min_cash_eur)} kasreserve. Maximaal ${r.max_buys_per_day} aankopen per dag.`;
 $('#taxSummary').textContent=`Proefaannames: ${(t.transaction_tax_rate*100).toFixed(2)}% TOB per zijde en ${(t.capital_gains_reserve_rate*100).toFixed(0)}% reserve op positieve bruto EUR-meerwaarde. Gewone winstneming vereist minstens ${euros(t.minimum_net_profit_eur)} netto. Geen bevestigde persoonlijke belastingberekening.`;
 $('#tradeRows').innerHTML=(data.trades||[]).map(t=>`<tr><td>${esc(when(t.time))}</td><td><strong>${esc(t.symbol)}</strong><small>${esc(BY_SYMBOL[t.symbol]?.name||'')}</small></td><td><span class="${t.side==='koop'?'buy':'sell'}">${t.side==='koop'?'Aankoop':'Verkoop'}</span></td><td>${esc(num.format(t.price))} ${esc(t.currency||'USD')}</td><td class="${t.pnl<0?'negative':t.pnl>0?'positive':''}">${t.side==='verkoop'?esc(euros(t.pnl)):'—'}</td><td><button class="secondary" data-receipt="${t.id}">Bewijs</button></td></tr>`).join('')||'<tr><td colspan="6" class="muted">Nog geen transacties.</td></tr>';
 document.querySelectorAll('[data-receipt]').forEach(b=>b.onclick=()=>openReceipt(Number(b.dataset.receipt)));
 const research=data.research;
 if(research){
  const d=research.diagnostics,sources=research.sources||[];
  let html=`<p>Laatste controle: ${esc(when(research.checked_at))}. ${esc(research.ok_sources??0)} bronnen beschikbaar. ${esc(research.note||'')}</p>`;
  if(d){
   html+=`<p><strong>Deze beheerde fase:</strong> ${esc(d.managed_actions)} handelsacties, ${esc(d.managed_closes)} gesloten posities; ${esc(euros(d.managed_realized_eur))} gerealiseerd netto. Kosten en reserves: ${esc(euros(d.managed_costs_and_reserves_eur))}.</p><p class="muted">${esc(d.sample_note)}</p>`;
   if(d.coverage?.recorded_days)html+=`<p>Koersdekking sinds start van de kwaliteitsmeting: ${esc(num.format(d.coverage.fresh_percent??0))}% over ${esc(d.coverage.recorded_days)} dagen; ${esc(d.coverage.failed_rounds)} mislukte rondes.</p><ul>${Object.entries(d.coverage.venues||{}).map(([k,v])=>`<li>${esc(k)}: ${esc(num.format(v.fresh_percent??0))}% verse bronmetingen</li>`).join('')}</ul>`;
   html+='<h3>Kosten eerst terugverdienen</h3><p class="muted">Hypothetische EUR100-orders met de huidige proefkosten; geen bevestigd brokertarief.</p><ul>'+d.cost_scenarios.map(x=>`<li>${esc(x.symbol)}: ongeveer ${esc(num.format(x.required_move_percent))}% koersstijging nodig voor ${esc(euros(x.minimum_net_profit_eur))} netto; circa ${esc(euros(x.flat_round_trip_loss_eur))} verlies bij onveranderde markt.</li>`).join('')+'</ul>';
   html+='<h3>Volgende onderzoeksvragen</h3><ul>'+(d.proposals||[]).map(x=>`<li>${esc(x)}</li>`).join('')+'</ul>';
  }
  const indicators=sources.filter(x=>x.indicator);
  const knowledge=sources.filter(x=>x.takeaway||x.article);
  if(knowledge.length)html+='<h3>Marktkennis uit primaire bronnen</h3><p class="muted">Vastgelegde kennisnotities en korte bronfragmenten. Een inhoudswijziging is een signaal voor herbeoordeling; zij traint het handelsmodel niet automatisch.</p>'+knowledge.map(x=>`<article><h4>${esc(x.article?.title||x.id)}</h4><p>${esc(x.takeaway||'')}</p><p>${esc(x.implication||'')}</p>${x.article?`<blockquote>${esc(x.article.excerpt)}</blockquote>`:''}<small>${esc(x.url)} · ${esc(when(x.checked_at))}${x.cached?' · uit weekcache':''}${x.content_changed?' · broninhoud gewijzigd':''} · ${esc(x.status)}</small></article>`).join('');
  if(indicators.length)html+='<h3>Vertraagde macrocontext</h3><ul>'+indicators.map(x=>`<li>${esc(x.indicator.label)}: ${esc(num.format(x.indicator.value))} ${esc(x.indicator.unit)} · ${esc(x.indicator.date)}${x.indicator.stale?' · verouderd':''}</li>`).join('')+'</ul><p class="muted">Geen crashkans of zelfstandig handelssignaal. De observatiedatum bewijst niet wanneer het cijfer voor het eerst beschikbaar was.</p>';
  const headlines=sources.flatMap(x=>(x.headlines||[]).map(h=>({...h,source:x.id})));
  if(headlines.length)html+='<h3>Officiële nieuwstitels</h3><ul>'+headlines.map(h=>`<li>${esc(h.title)}<small>${esc(h.source)} · ${esc(h.published)}</small></li>`).join('')+'</ul>';
  $('#researchStatus').innerHTML=html;
 }else $('#researchStatus').textContent='De bronnenroutine heeft op deze installatie nog geen rapport opgeslagen. Onderzoek past de handelsregels niet automatisch aan.';
 const usage=data.free_usage,budget=usage?.automatic_budget;
 const warning=freeBudgetAlert(usage);$('#usageWarning').textContent=warning;$('#usageWarning').hidden=!warning;
 $('#freeUsage').textContent=usage?`Database: ${num.format(usage.database_bytes/1e6)} MB. Automatische pauze vanaf ${num.format((budget?.max_database_bytes||300000000)/1e6)} MB. ${budget?.tick_attempts||0} koersrondes deze maand; maandbudget ${budget?.max_tick_attempts||10000}. Geraamd automatisch dataverkeer: ${num.format((budget?.estimated_worker_egress_bytes||0)/1e9)} / ${num.format((budget?.max_worker_egress_bytes||3000000000)/1e9)} GB.`:'Verbruiksbeveiliging wordt voorbereid.';
 renderCatalogue();
}
function renderCatalogue(){
 const s=data?.state,term=$('#search').value.trim().toLowerCase(),region=$('#region').value,sector=$('#sector').value;
 const rows=COMPANIES.filter(x=>(!term||(x.name+' '+x.symbol).toLowerCase().includes(term))&&(!sector||x.sector===sector)&&(!region||(region==='brussels'?x.exchange==='XBRU':region==='us'?['XNAS','XNYS'].includes(x.exchange):!['XNAS','XNYS','XBRU'].includes(x.exchange))));
 $('#catalogueRows').innerHTML=rows.map(x=>{const q=s?.last_observation?.[x.symbol],p=s?.prices?.[x.symbol],age=q?(Date.now()-Date.parse(q.time))/1000:Infinity;return `<tr><td><strong>${esc(x.name)}</strong><small>${esc(x.symbol)}</small></td><td>${esc(x.sector)}<small>${esc(x.exchange)} · ${esc(x.currency)}</small></td><td>${q&&p?esc(num.format(p))+' '+esc(x.currency):'—'}<small>${!q?'Nog geen verse meting':age<=120?'Recente bronkoers':'Oude waarneming · geen actuele uitvoering'}</small></td><td>${q?esc(when(q.time)):'—'}</td></tr>`;}).join('');
}
for(const sector of [...new Set(COMPANIES.map(x=>x.sector))].sort()){const o=document.createElement('option');o.value=o.textContent=sector;$('#sector').append(o);}
for(const id of ['search','sector','region'])$('#'+id).addEventListener('input',renderCatalogue);
$('#toggle').onclick=e=>busy(e.currentTarget,async()=>{data=await api('',{action:data.state.running?'pause':'start'});render();});
$('#step').onclick=e=>busy(e.currentTarget,async()=>{toast('Koersen ophalen en controleren…');data=await api('',{action:'step'});render();});
async function openReceipt(id,shadow=false){try{receipt=await api((shadow?'?shadow-receipt=':'?receipt=')+id);const s=receipt.snapshot,t=s.tax_detail||{};
 const rows=[['Portefeuille',({reference:'Schaduwreferentie',low_turnover:'Schaduw · minder transacties',learned:'Schaduw · model'})[receipt.account]||'Hoofdproef'],['Aandeel',receipt.symbol],['Actie',receipt.side],['Besluit',when(s.decision_time)],['Uitvoering',when(receipt.time)],['Aantal',num.format(receipt.qty)],['Lokale uitvoeringsprijs',num.format(receipt.price)+' '+(s.currency||'USD')],['Valuta-eenheden per EUR',num.format(s.fx)],['Commissie',euros(receipt.fee)],['TOB',euros(t.transaction_tax_eur)],['Meerwaardereserve',euros(t.capital_gains_reserve_eur)],['Internationale reserve',euros((t.foreign_tax_reserve_eur||0)+(t.adr_reserve_eur||0))],['Resultaat',euros(receipt.pnl)],['Profiel',s.strategy_version||'momentum-v1']];
 $('#receiptBody').innerHTML=rows.map(([k,v])=>`<div class="receipt-row"><span>${esc(k)}</span><strong>${esc(v)}</strong></div>`).join('')+`<p>${esc(receipt.reason)}</p><p class="small muted">Indicatieve paperuitvoering met proefkosten. Geen brokerbevestiging.</p>`;$('#receipt').showModal();
 const r=s.purchase_rationale;
 if(r){
  $('#receiptBody').innerHTML+=`<h3>Oorspronkelijke aankoopmotivatie</h3><p>${esc(r.decision?.statement||'')}</p><p>${esc(r.execution?.statement||'')}</p>`;
  if(r.decision?.note)$('#receiptBody').innerHTML+=`<p class="muted">${esc(r.decision.note)}</p>`;
  if(r.decision?.model)$('#receiptBody').innerHTML+=`<p>Model ${esc(r.decision.model.id)}: ${esc((r.decision.model.probability_net_positive*100).toFixed(1))}% geschatte kans; drempel ${esc((r.decision.model.threshold*100).toFixed(0))}%. Geen winstgarantie.</p>`;
  if(r.decision?.observations)$('#receiptBody').innerHTML+='<h3>Koersmetingen bekend bij het besluit</h3><ul>'+r.decision.observations.map(x=>`<li>${esc(when(x.time))}: ${esc(num.format(x.price))} ${esc(r.decision.currency)}</li>`).join('')+'</ul>';
  if(r.cost_estimate)$('#receiptBody').innerHTML+=`<p>Verwacht verlies bij onveranderde markt: ${esc(euros(r.cost_estimate.flat_round_trip_loss_eur))}. Beoogd bruto koersdoel: ${esc(euros(r.cost_estimate.gross_target_price_eur))}. Gewone verkoop vereist ${esc(euros(r.cost_estimate.minimum_net_profit_eur))} netto na de proefkosten.</p>`;
  if(r.risk_at_decision)$('#receiptBody').innerHTML+=`<p>Bij besluit: ${esc(euros(r.risk_at_decision.cash_eur))} kas, ${esc(r.risk_at_decision.open_positions)} open posities, ${esc(r.risk_at_decision.buys_today)} aankopen die dag. Sectorcontrole ${r.risk_at_decision.sector_available?'geslaagd':'geblokkeerd'}.</p>`;
  $('#receiptBody').innerHTML+='<ul>'+(r.limitations||[]).map(x=>`<li>${esc(x)}</li>`).join('')+'</ul>';
 }
 }catch(e){toast(e.message);}}
$('#closeReceipt').onclick=()=>$('#receipt').close();
function download(blob,name){const a=document.createElement('a'),url=URL.createObjectURL(blob);a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),2000);}
$('#png').onclick=()=>{
 if(!receipt)return;const c=document.createElement('canvas');c.width=900;const x=c.getContext('2d'),lines=[];let y=65;
 const add=(text,color='#e7edf7',font='18px sans-serif')=>{x.font=font;const words=String(text||'').split(/\s+/);let line='';for(const word of words){const next=line?line+' '+word:word;if(x.measureText(next).width>810&&line){lines.push({text:line,color,font,y});y+=27;line=word;}else line=next;}if(line){lines.push({text:line,color,font,y});y+=29;}};
 add('PaperLab · Transactiebewijs','#65dcb1','bold 32px sans-serif');y+=25;
 for(const row of $('#receiptBody').querySelectorAll('.receipt-row')){add(row.querySelector('span').textContent,'#94a3b8');add(row.querySelector('strong').textContent);y+=10;}
 const r=receipt.snapshot.purchase_rationale;add('Motivatie','#65dcb1','bold 22px sans-serif');add(r?.decision?.statement||receipt.reason);if(r?.execution?.statement)add(r.execution.statement);
 if(r?.decision?.model)add('Model '+r.decision.model.id+' · geschatte kans '+(r.decision.model.probability_net_positive*100).toFixed(1)+'% · geen winstgarantie');
 if(r?.cost_estimate)add('Verwacht verlies bij onveranderde markt: '+euros(r.cost_estimate.flat_round_trip_loss_eur)+'. Minimale nettowinst gewone verkoop: '+euros(r.cost_estimate.minimum_net_profit_eur)+'.');
 for(const o of r?.decision?.observations||[])add(when(o.time)+' · '+num.format(o.price)+' '+r.decision.currency,'#94a3b8','15px sans-serif');
 y+=15;add('Virtuele transactie · Europe/Brussels · Geen brokerbevestiging','#94a3b8','14px sans-serif');c.height=y+25;x.fillStyle='#131c29';x.fillRect(0,0,c.width,c.height);
 for(const line of lines){x.font=line.font;x.fillStyle=line.color;x.fillText(line.text,45,line.y);}c.toBlob(blob=>blob&&download(blob,'paperlab-transactie-'+receipt.id+'.png'),'image/png');
};
$('#export').onclick=e=>busy(e.currentTarget,async()=>{const rows=await api('?export=1'),headers=['id','time_utc','symbol','side','quantity','price_local','currency','fee_eur','pnl_eur','fx_units_per_eur','transaction_tax_eur','capital_gains_reserve_eur','foreign_tax_reserve_eur','adr_reserve_eur','strategy_version','reason','purchase_rationale_json'];const quote=v=>'"'+String(v??'').replaceAll('"','""')+'"';const lines=[headers,...rows.map(t=>[t.id,t.time,t.symbol,t.side,t.qty,t.price,t.currency||'USD',t.fee,t.pnl,t.fx,t.tax_detail?.transaction_tax_eur||0,t.tax_detail?.capital_gains_reserve_eur||0,t.tax_detail?.foreign_tax_reserve_eur||0,t.tax_detail?.adr_reserve_eur||0,t.strategy_version||'momentum-v1',t.reason,t.purchase_rationale?JSON.stringify(t.purchase_rationale):''])];download(new Blob(['\uFEFF'+lines.map(r=>r.map(quote).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'}),'paperlab-transacties.csv');});
setInterval(async()=>{if(!session||$('#app').hidden||polling)return;if(Date.now()-lastActivity>1800000){await logout();return;}polling=true;try{const next=await api('?revision='+data.revision);if(next.unchanged){data.collector_status=next.collector_status;renderCatalogue();}else{data=next;render();}}catch(e){$('#globalError').textContent=e.message;$('#globalError').hidden=false;}finally{polling=false;}},60000);
async function boot(){
 if(!CONFIG.url||!CONFIG.key){authError('De beveiligde installatie wordt voorbereid.');$('#loginForm').hidden=true;return;}
 const fragment=new URLSearchParams(location.hash.slice(1));if(fragment.has('access_token')){
  $('#app').hidden=true;$('#auth').hidden=false;
  setSession({access_token:fragment.get('access_token'),refresh_token:fragment.get('refresh_token'),expires_in:Number(fragment.get('expires_in')||3600)});
  history.replaceState(null,'',location.pathname);form('passwordForm','Activeer je privéaccount','Kies een uniek wachtwoord van minstens veertien tekens. Daarna koppel je je authenticator.');
 }else if(fragment.has('error')){history.replaceState(null,'',location.pathname);authError('De activatielink is ongeldig of verlopen. Vraag een nieuwe privélink.');}
}
window.addEventListener('hashchange',()=>boot().catch(()=>authError('De activatielink kon niet worden geopend.')));
boot().catch(()=>authError('De aanmelding kon niet worden voorbereid.'));

setInterval(()=>{if(session&&!$('#app').hidden&&!$('#learningPage').hidden)loadLearning();},300000);
setInterval(()=>{if(session&&!$('#app').hidden&&!$('#opportunitiesPage').hidden)loadOpportunities();},300000);
