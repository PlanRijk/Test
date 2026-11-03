"""Explicit zero-paid-resource deployment stages. Never prints credential values.

Database stages require the user's scoped Management API token. A private
SQLite backup is made before import. Site creation is static_site only.
"""
import argparse
import base64
import hashlib
import html
import json
import os
from pathlib import Path
import secrets
import sqlite3
import sys
from datetime import datetime, timezone
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from scripts.managed_api import ROOT,request,project,sql,keys,project_request,deploy_function,private_json


def literal(value):
    return "'"+str(value).replace("'","''")+"'"


def jsql(value):
    return literal(json.dumps(value,ensure_ascii=False,separators=(',',':')))+'::jsonb'


def source_export():
    # Only the one-time legacy import requires the old SQLite backup helpers.
    # All managed-service operations work from the published managed checkout.
    from scripts.portfolio_backup import snapshot,connect
    from runtime import runtime_lock
    data=ROOT/'.data/week-2026-11-02'
    folder=ROOT/'.data/managed/source-backups'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    folder.mkdir(parents=True,mode=0o700)
    # Exclusive non-blocking lock rejects an active source collector atomically.
    with runtime_lock(data):
        info=snapshot(data/'paperlab.sqlite3',folder/'portfolio.sqlite3')
    db=connect(folder/'portfolio.sqlite3')
    state=json.loads(db.execute('select data from state where id=1').fetchone()[0])
    state['running']=False;state.pop('oracle_handoff',None)
    state['managed_transport']={'version':'supabase-v1','migrated_at':datetime.now(timezone.utc).isoformat(),'raw_quote_retention_days':2}
    records={}
    for table in ['trades','events','equity','observations']:
        records[table]=[]
        for row in db.execute('select * from '+table+' order by id'):
            row=dict(row)
            for key in ['snapshot','data','payload','fx']:
                if key in row and isinstance(row[key],str):row[key]=json.loads(row[key])
            records[table].append(row)
    db.close()
    return state,records,info


def import_sql(state,records):
    # All values are JSON-encoded then SQL-quoted. Never interpolate raw strings.
    columns={
      'trades':'id bigint,time timestamptz,symbol text,side text,qty double precision,price double precision,fee double precision,pnl double precision,reason text,snapshot jsonb',
      'events':'id bigint,time timestamptz,kind text,symbol text,reason text,data jsonb',
      'equity':'id bigint,time timestamptz,value double precision,benchmark double precision',
      'observations':'id bigint,received timestamptz,symbol text,source text,quote_time timestamptz,payload jsonb,fx jsonb'}
    statements=['begin;','do $import$ begin if not exists(select 1 from paperlab.portfolio where singleton) then']
    for table,definition in columns.items():
        statements.append(f'insert into paperlab.{table} select * from jsonb_to_recordset({jsql(records[table])}) as x({definition});')
        statements.append(f"perform setval(pg_get_serial_sequence('paperlab.{table}','id'),greatest(coalesce((select max(id) from paperlab.{table}),0),1),(select count(*)>0 from paperlab.{table}));")
    statements+=['insert into paperlab.portfolio(singleton,state) values(true,'+jsql(state)+');','end if;end $import$;','commit;']
    return '\n'.join(statements)


def database(ref):
    # Test actual SQL permission before applying any schema changes.
    existing=sql(ref,"select obj_description(oid,'pg_namespace') as marker from pg_namespace where nspname='paperlab'",True)
    if existing and existing[0].get('marker')!='PaperLab managed-v1':
        raise RuntimeError('An unrelated paperlab schema already exists. No schema changed.')
    state,records,manifest=source_export()
    sql(ref,(ROOT/'managed/sql/001_paperlab.sql').read_text())
    sql(ref,import_sql(state,records))
    result=sql(ref,"select (state->>'cash')::float8 as cash_eur,(select count(*) from paperlab.trades) as trades,revision from paperlab.portfolio where singleton",True)
    if not result or abs(result[0]['cash_eur']-manifest['cash_eur'])>1e-6 or result[0]['trades']!=manifest['trades']:
        raise RuntimeError('Existing target differs from the preserved source; no overwrite or reset performed.')
    private_json('migration.json',{'manifest':manifest,'target':result[0]})
    print(json.dumps({'stage':'database','status':'import_verified','cash_eur':result[0]['cash_eur'],'trades':result[0]['trades']}))


def functions(ref):
    # Sequential: simultaneous first-time creations were observed to lose list entries.
    for slug in ['paper-api','paper-tick','paper-research']:
        result=deploy_function(ref,slug);verified=request('supabase','/v1/projects/'+ref+'/functions/'+slug)
        if verified.get('status')!='ACTIVE':raise RuntimeError('Function not active: '+slug)
        private_json(slug+'-deployment.json',result)
        print(json.dumps({'function':slug,'status':'ACTIVE','version':verified['version']}),flush=True)


def public_config(ref):
    values=keys(ref);public=values.get('publishable') or values['anon']
    if public.startswith('sb_secret_'):raise RuntimeError('Refusing to publish a secret key.')
    if public.count('.')==2:
        payload=json.loads(base64.urlsafe_b64decode(public.split('.')[1]+'=='))
        if payload.get('role')!='anon':raise RuntimeError('Refusing to publish a privileged JWT.')
    (ROOT/'managed/web/config.js').write_text('export const CONFIG = '+json.dumps({'url':'https://'+ref+'.supabase.co','key':public})+';\n')


def site(ref,owner):
    if not owner or not owner.startswith('tea-'):raise ValueError('Render workspace ID required; no service created.')
    existing=request('render','/v1/services?limit=100')
    found=[r.get('service',r) for r in existing if r.get('service',r).get('name')=='paperlab-prive']
    if found:
        service=found[0]
        if service.get('type')!='static_site':raise RuntimeError('Existing name belongs to another service; no paid service modified.')
        private_json('site.json',service);print(json.dumps({'stage':'site','status':'exists','id':service['id']}));return
    host='https://'+ref+'.supabase.co'
    headers=[{'path':'/*','name':name,'value':value} for name,value in {
      'Content-Security-Policy':"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self' "+host+"; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
      'X-Frame-Options':'DENY','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer',
      'Cache-Control':'no-store','Permissions-Policy':'camera=(), microphone=(), geolocation=()'}.items()]
    body={'type':'static_site','name':'paperlab-prive','ownerId':owner,'repo':'https://github.com/PlanRijk/Test',
          'branch':'paperlab-managed','autoDeployTrigger':'off','serviceDetails':{'buildCommand':'node managed/check-public.mjs',
          'publishPath':'managed/web','headers':headers,'pullRequestPreviewsEnabled':'no'}}
    # No disk, database, compute plan, add-on or paid service can enter this request.
    if body['type']!='static_site' or 'plan' in body['serviceDetails']:raise RuntimeError('Non-free service forbidden.')
    result=request('render','/v1/services','POST',body)
    service=result.get('service',result)
    if service.get('type')!='static_site':raise RuntimeError('Unexpected created resource type.')
    private_json('site.json',service)
    print(json.dumps({'stage':'site','status':'static_site_created','id':service['id'],'url':service.get('serviceDetails',{}).get('url')}))


def activate(ref,origin,email):
    if not origin.startswith('https://') or not origin.endswith('.onrender.com') or '/' in origin[8:]:raise ValueError('Exact HTTPS Render origin required.')
    sql(ref,'select singleton from paperlab.portfolio where singleton',True)
    request('supabase','/v1/projects/'+ref+'/config/auth','PATCH',{'site_url':origin,'uri_allow_list':origin,
      'disable_signup':True,'external_anonymous_users_enabled':False,'external_email_enabled':True,
      'mfa_totp_enroll_enabled':True,'mfa_totp_verify_enabled':True,'password_min_length':14,'jwt_exp':900})
    values=keys(ref);admin=values['service_role']
    users=project_request(ref,admin,'/auth/v1/admin/users?page=1&per_page=100').get('users',[])
    matches=[u for u in users if u.get('email','').lower()==email.lower()]
    if len(matches)>1:raise RuntimeError('Ambiguous owner account.')
    account=matches[0] if matches else None
    if not account or not any(f.get('status')=='verified' for f in account.get('factors',[])):
        link=project_request(ref,admin,'/auth/v1/admin/generate_link','POST',{'type':'recovery' if account else 'invite','email':email,'redirect_to':origin})
        owner=link.get('id') or link.get('user',{}).get('id')
        action_link=link.get('action_link') or link.get('properties',{}).get('action_link')
        if not owner or not action_link:raise RuntimeError('Private activation was not generated.')
        folder=ROOT/'.data/managed';folder.mkdir(exist_ok=True,mode=0o700)
        activation=folder/'PRIVE-ACTIVATIE.html'
        activation.write_text('<!doctype html><meta charset="utf-8"><meta name="referrer" content="no-referrer"><title>PaperLab privéactivatie</title><h1>Activeer je privéaccount</h1><p>Deze persoonlijke link is tijdelijk. Deel hem niet.</p><a rel="noreferrer" href="'+html.escape(action_link,quote=True)+'">Kies je wachtwoord en koppel je authenticator</a>')
        activation.chmod(0o600)
    else:owner=account['id']
    sql(ref,"do $$begin if exists(select 1 from paperlab.settings where owner_id is not null and owner_id<>"+literal(owner)+"::uuid) then raise exception 'Owner mismatch';end if;end$$; update paperlab.settings set owner_id="+literal(owner)+"::uuid,origin="+literal(origin)+" where singleton;")
    sql(ref,'create extension if not exists pg_cron; create extension if not exists pg_net with schema extensions;')
    # The read-only API uses a restricted DB role without Vault decryption rights.
    # Read through the admin endpoint; never log the returned secret.
    rows=sql(ref,"select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token'")
    cron=rows[0]['decrypted_secret'] if rows else secrets.token_hex(32)
    if not rows:sql(ref,'select vault.create_secret('+literal(cron)+",'paperlab_cron_token');")
    request('supabase','/v1/projects/'+ref+'/secrets','POST',[{'name':'PAPERLAB_CRON_TOKEN','value':cron}])
    base='https://'+ref+'.supabase.co/functions/v1/'
    for job,schedule,slug in [('paperlab-tick','*/5 * * * *','paper-tick'),('paperlab-research','30 22 * * 1-5','paper-research')]:
        command="select net.http_post(url := "+literal(base+slug)+", headers := jsonb_build_object('Content-Type','application/json','X-PaperLab-Cron',(select decrypted_secret from vault.decrypted_secrets where name='paperlab_cron_token')),body := '{}'::jsonb,timeout_milliseconds := 80000) where exists(select 1 from paperlab.portfolio where singleton and (state->>'run_until')::timestamptz>now()"+(" and (state->>'running')::boolean" if slug=='paper-tick' else '')+");"
        sql(ref,'select cron.schedule('+literal(job)+','+literal(schedule)+','+literal(command)+');')
    private_json('activation-status.json',{'owner_id':owner,'origin':origin,'activation_file':str(ROOT/'.data/managed/PRIVE-ACTIVATIE.html'),'jobs_installed':True,'email_sent':False})
    print(json.dumps({'stage':'activate','status':'owner_invitation_and_jobs_prepared','origin':origin,'email_sent':False,'running':'unchanged'}))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage',choices=['inspect','database','functions','config','site','activate'])
    parser.add_argument('--owner');parser.add_argument('--origin');parser.add_argument('--email')
    args=parser.parse_args();selected=project();ref=selected['id']
    if args.stage=='inspect':print(json.dumps({k:selected.get(k) for k in ['id','name','region','status']}))
    elif args.stage=='database':database(ref)
    elif args.stage=='functions':functions(ref)
    elif args.stage=='config':public_config(ref);print('Public browser configuration prepared.')
    elif args.stage=='site':site(ref,args.owner)
    elif args.stage=='activate':
        if not args.email:raise ValueError('Owner email required; no account inferred automatically.')
        activate(ref,args.origin,args.email)

if __name__=='__main__':main()
