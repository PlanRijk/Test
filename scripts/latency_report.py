"""Aggregate a bounded live study without publishing raw quotes or credentials."""
import json,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def percentile(xs,p):
 return sorted(xs)[math.ceil(len(xs)*p)-1] if xs else None
def summary(xs):
 return {'median':percentile(xs,.5),'p95':percentile(xs,.95),'max':max(xs) if xs else None}
def generate():
 attempts=[json.loads(line) for line in(ROOT/'.data/managed/alpaca-opening-2026-11-09.jsonl').read_text().splitlines()]
 valid=[r for r in attempts if r.get('status')=='measured']
 if not valid:raise RuntimeError('No valid live samples; cannot publish results')
 quote_ages=[q['quote_age_seconds'] for r in valid for q in r['rows'] if q['valid_quote_sides'] and q['quote_age_seconds'] is not None and q['quote_age_seconds']>=0]
 trade_ages=[q['trade_age_seconds'] for r in valid for q in r['rows'] if q['trade_price'] and q['trade_age_seconds'] is not None and q['trade_age_seconds']>=0]
 outliers=[]
 for symbol in [q['symbol'] for q in valid[0]['rows']]:
  rows=[next(q for q in r['rows'] if q['symbol']==symbol) for r in valid]
  stale=sum(not q['quote_within_60s'] for q in rows)
  if stale:outliers.append({'symbol':symbol,'over_60_or_invalid_rounds':stale,'rounds':len(rows),'max_quote_age_seconds':max(q['quote_age_seconds'] for q in rows if q['quote_age_seconds'] is not None)})
 study={'date':'2026-11-09','timezone':'Europe/Brussels','feed':'IEX','scope':'53 Amerikaanse catalogusnoteringen; quotes en laatste transacties, geen nieuws of volledig orderboek',
 'attempts':len(attempts),'valid_rounds':len(valid),'initial_failed_rounds':len(attempts)-len(valid),'failure_explanation':'Eerste twee aanvragen kregen HTTP 400; Berkshire-symbool vertalen van Yahoo BRK-B naar Alpaca BRK.B verhielp dit. Mislukte aanvragen tellen niet als leeftijdsmetingen.',
 'started_at':attempts[0]['requested_at'],'first_valid_at':valid[0]['requested_at'],'finished_at':valid[-1]['checked_at'],'expected_symbols':53,
 'quote_observations':len(valid)*53,'quotes_within_60s':sum(r['quotes_within_60s'] for r in valid),'min_fresh_per_round':min(r['quotes_within_60s'] for r in valid),'max_fresh_per_round':max(r['quotes_within_60s'] for r in valid),
 'quote_age_seconds':summary(quote_ages),'trade_age_seconds':summary(trade_ages),
 'provider_request_ms':summary([p['elapsed_ms'] for r in valid for p in r['provider']]),'client_roundtrip_ms':summary([r['client_roundtrip_ms'] for r in valid]),
 'provider_payload_bytes':sum(p.get('payload_bytes',0) for r in attempts for p in r['provider']),
 'outliers':outliers,'rounds':[{k:r[k] for k in ['checked_at','quotes_within_60s','quotes_within_120s','trades_within_60s','quote_age_seconds','collection_ms','client_roundtrip_ms']} for r in valid],
 'orders_submitted':0,'trading_feed_changed':False,'continuous_monitoring':False}
 (ROOT/'managed/web/latency-study.js').write_text('export const US_LATENCY_STUDY = '+json.dumps(study,ensure_ascii=False,separators=(',',':'))+';\n')
 print(json.dumps({k:v for k,v in study.items() if k not in ['rounds']},ensure_ascii=False,indent=2))
 return study
if __name__=='__main__':generate()
