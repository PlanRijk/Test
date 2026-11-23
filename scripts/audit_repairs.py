import sys,json,importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT))
from scripts import managed_api as api
api.ROOT=ROOT;R='kdyzlbknygeqinqduuic'
q=api.sql
migration=(ROOT/'managed/sql/043_audit_repairs.sql').read_text()
# Transactional rehearsal compiles every definition and runs data checks, then rolls everything back.
q(R,migration.rsplit('commit;',1)[0]+'rollback;')
print('Migration transactional rehearsal passed.',flush=True)
q(R,migration)
print('Audit migration applied.',flush=True)
for slug in ['paper-project-followup','paper-api','paper-deep-research']:
 api.deploy_function(R,slug);print('Deployed '+slug,flush=True)
spec=importlib.util.spec_from_file_location('swingrepair',ROOT/'scripts/daily_weekly_swing.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);policy=m.protocol();old=q(R,'select policy from paperlab.swing_runtime',True)[0]['policy']
assert {k:v for k,v in old.items()if k!='implementation_sha256'}=={k:v for k,v in policy.items()if k!='implementation_sha256'}
job=q(R,"select jobid,active from cron.job where jobname='paperlab-tick'",True)[0]
q(R,'select cron.alter_job('+str(job['jobid'])+',active:=false)')
try:
 api.deploy_function(R,'paper-tick-swing')
 sql="""begin;create table if not exists paperlab.implementation_repairs(at timestamptz default now(),old_profile text,new_profile text,old_policy jsonb,new_policy jsonb,reason text);alter table paperlab.implementation_repairs enable row level security;revoke all on paperlab.implementation_repairs from public,anon,authenticated,service_role;
 do $repair$declare p jsonb:='POLICY'::jsonb;fp text;b jsonb;n bigint;begin
 select state into b from paperlab.capital_runtime where singleton for update;select count(*)into n from paperlab.capital_trades;fp:=encode(sha256(convert_to(p::text,'UTF8')),'hex');
 insert into paperlab.implementation_repairs(old_profile,new_profile,old_policy,new_policy,reason)select profile,fp,policy,p,'Audit A01: missing fx import; financial thresholds unchanged'from paperlab.swing_runtime where policy is distinct from p;
 update paperlab.swing_runtime set policy=p,profile=fp where singleton;
 update paperlab.capital_runtime set token=null,lease_until=null,revision=revision+1,summary=summary||jsonb_build_object('swing_profile',fp)where singleton;
 if b is distinct from(select state from paperlab.capital_runtime)or n<>(select count(*)from paperlab.capital_trades)then raise exception'Financial state changed';end if;
 end$repair$;commit;""".replace('POLICY',json.dumps(policy).replace("'","''"))
 q(R,sql);print('Swing code repair installed; full financial state and ledger preserved.',flush=True)
finally:q(R,'select cron.alter_job('+str(job['jobid'])+',active:='+str(job['active']).lower()+')')
cron=q(R,"select jobid from cron.job where jobname='paperlab-operations'",True)
if not cron:q(R,"select cron.schedule('paperlab-operations','20 * * * *','select public.paper_operations_check();')")
print(json.dumps(q(R,'select public.paper_operations_check()as health')[0]),flush=True)

# Weekly SQL preparation and one bounded encrypted part per active minute.
prepare="set statement_timeout='120s';select public.paper_project_backup_prepare();"
worker="select net.http_post(url:='https://"+R+".supabase.co/functions/v1/paper-project-followup',headers:=jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body:='{\"backup\":true}'::jsonb,timeout_milliseconds:=120000)where exists(select 1 from paperlab.project_followup where singleton and enabled and backup_info is not null and backup_until>now());"
for name,schedule,command in [('paperlab-backup-prepare','50 6 * * 0',prepare),('paperlab-backup-upload','* * * * *',worker)]:
 ids=api.sql(R,"select jobid from cron.job where jobname='"+name+"'",True)
 esc=command.replace("'","''")
 if ids:api.sql(R,"select cron.alter_job("+str(ids[0]['jobid'])+",schedule:='"+schedule+"',command:='"+esc+"',active:=true)")
 else:api.sql(R,"select cron.schedule('"+name+"','"+schedule+"','"+esc+"')")
 print(name,schedule)
