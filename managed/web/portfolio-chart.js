const esc=x=>String(x??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=x=>new Intl.NumberFormat('nl-BE',{style:'currency',currency:'EUR',maximumFractionDigits:0}).format(x);
export function portfolioChart(points){
 const rows=(points||[]).filter(p=>typeof p.value==='number'&&Number.isFinite(p.value)&&p.value>=0);if(!rows.length)return'<div class="chart-empty"><strong>Nog geen waardereeks</strong><p>De grafiek verschijnt na een opgeslagen rekeningmeting.</p></div>';
 const v=rows.map(r=>r.value),lo=Math.min(...v),hi=Math.max(...v),pad=Math.max((hi-lo)*.18,hi*.0005,1),bottom=lo-pad,range=hi-lo+2*pad,x=i=>12+i*776/Math.max(1,v.length-1),y=n=>238-(n-bottom)/range*220;
 const path=v.map((n,i)=>`${i?'L':'M'}${x(i).toFixed(2)},${y(n).toFixed(2)}`).join(' '),end=x(v.length-1),last=y(v.at(-1)),area=path+` L${end.toFixed(2)},260 L12,260 Z`;
 return `<div class="portfolio-chart"><div class="chart-scale" aria-hidden="true"><span>${esc(money(hi+pad))}</span><span>${esc(money((hi+lo)/2))}</span><span>${esc(money(bottom))}</span></div><svg viewBox="0 0 800 270" preserveAspectRatio="none" role="img" aria-label="Geschatte portefeuillewaarde: eerste meting ${esc(money(v[0]))}, laatste ${esc(money(v.at(-1)))}"><path class="chart-grid" d="M0 18H800 M0 128H800 M0 238H800"/><path class="chart-area" d="${area}"/><path class="chart-line" d="${path}" vector-effect="non-scaling-stroke"/><circle class="chart-last" cx="${end.toFixed(2)}" cy="${last.toFixed(2)}" r="4"/></svg></div>`;
}
