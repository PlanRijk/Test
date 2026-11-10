"""Regression: rounded float transport must not reject an exact stored source."""
import secrets,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from managed.tests.test_database import query as admin,command,environment
def main():
 name='paperlab_precision_'+secrets.token_hex(4);admin('create database '+name)
 def q(s,error=None):
  r=subprocess.run(command+['-d',name],input=s.encode(),capture_output=True,env=environment)
  if error:assert r.returncode and error in r.stderr.decode(),r.stderr.decode()
  elif r.returncode:raise RuntimeError(r.stderr.decode()[-2000:])
  return r.stdout.decode().strip().splitlines()[-1]if r.stdout.strip()else''
 try:
  for p in sorted((ROOT/'managed/sql').glob('*.sql')):q(p.read_text())
  # Synthetic float8 producer in the isolated DB. The production frozen claim and
  # commit are never changed; this exercises their JSON transport boundary.
  q("create table paperlab.precision_fixture(close float8);insert into paperlab.precision_fixture values(249.24000549316406)")
  q("create or replace function public.paper_history_claim_transport_v1()returns jsonb language sql security definer set search_path=pg_catalog,pg_temp as $$select jsonb_build_object('close',close)from paperlab.precision_fixture$$")
  assert q("set extra_float_digits=0;select(public.paper_history_claim_transport_v1()->>'close')::float8=(select close from paperlab.precision_fixture)")=='f'
  assert q("set extra_float_digits=0;select(public.paper_history_claim()->>'close')::float8=(select close from paperlab.precision_fixture)")=='t'
  assert q("set extra_float_digits=0;select public.paper_history_claim();select current_setting('extra_float_digits')")=='0'
  for role in['anon','authenticated']:q('set role '+role+';select public.paper_history_claim()','permission denied')
  q('set role service_role;select public.paper_history_claim_transport_v1()','permission denied');q('set role service_role;select public.paper_history_claim()')
  q((ROOT/'managed/sql/022_history_transport_precision.sql').read_text());assert q("set extra_float_digits=0;select(public.paper_history_claim()->>'close')::float8=(select close from paperlab.precision_fixture)")=='t'
  print('Historical precision DB passed: low-precision transport reproduces strict source mismatch, wrapper preserves float8 round-trip, caller settings restored, owner-service boundary retained and migration repeatable.')
 finally:admin('drop database '+name+' with(force)')
if __name__=='__main__':main()
