"""Official accession/identity matching and definition provenance, without network."""
import contextlib,io,json,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.prepare_source_revenue_corrections import prepare
with tempfile.TemporaryDirectory()as tmp:
 p=Path(tmp);(p/'ABC').mkdir();facts=p/'ABC/facts.json';inp=p/'in.json';out=p/'out.json'
 n={'cik':'0000000123','symbol':'ABC','checked_at':'2026-11-01T00:00:00Z','financial':{'annual_start':'2025-01-01','annual_end':'2025-12-31','revenue':90},'annual_report':{'accession':'annual'},'latest_report':{'accession':'quarter'}}
 inp.write_text(json.dumps({'coverage':[{'symbol':'ABC','verified_financials':n}]}))
 rows=[{'accn':'annual','start':'2025-01-01','end':'2025-12-31','val':100},{'accn':'annual','start':'2024-01-01','end':'2024-12-31','val':80},{'accn':'other','start':'2025-01-01','end':'2025-12-31','val':999}]
 def save(cik=123):facts.write_text(json.dumps({'cik':cik,'facts':{'us-gaap':{'Revenues':{'units':{'USD':rows}}}}}))
 def run():
  with contextlib.redirect_stdout(io.StringIO()):prepare(inp,p,out)
 save();run();x=json.loads(out.read_text())[0];assert x['native']['financial']['revenue']==100;assert x['native']['financial']['revenue_growth']==.25;assert x['native']['checked_at']==n['checked_at'];assert x['native']['source_extraction']['accession']=='annual';assert len(x['native']['source_extraction']['sha256'])==64
 rows.append({**rows[0],'val':101});save();run();assert json.loads(out.read_text())==[]
 save(124)
 try:run();raise AssertionError('CIK mismatch accepted')
 except RuntimeError as e:assert str(e)=='CIK mismatch'
print('Revenue correction passed: exact accession, ambiguous contexts rejected, CIK check, provenance and original check date preserved.')
