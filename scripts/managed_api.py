"""Management clients. Credentials stay in memory and are never logged."""
import json
import os
import secrets
import urllib.request
import urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ApiError(RuntimeError):
    def __init__(self, provider, status, message=''):
        super().__init__(f'{provider} HTTP {status}: {message[:500]}')
        self.status = status


def request(provider, path, method='GET', body=None, content_type='application/json', timeout=90):
    host, variable = {'supabase': ('api.supabase.com', 'SUPABASE_ACCESS_TOKEN'),
                      'render': ('api.render.com', 'RENDER_API_KEY')}[provider]
    key = os.environ[variable]
    data = json.dumps(body).encode() if body is not None and not isinstance(body, bytes) else body
    req = urllib.request.Request('https://' + host + path, data=data, method=method,
                                 headers={'Authorization': 'Bearer ' + key, 'Content-Type': content_type,
                                          'Accept': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            raw = response.read(16 * 1024 * 1024)
        return json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        # Errors may contain SQL or submitted secret values: never echo bodies.
        raise ApiError(provider, exc.code, 'Response details withheld to protect credentials.') from None


def project():
    rows = request('supabase', '/v1/projects')
    eligible = [r for r in rows if r.get('status') == 'ACTIVE_HEALTHY' and r.get('region', '').startswith('eu-')]
    if len(eligible) != 1:
        raise ValueError('Expected exactly one healthy EU project; select explicitly before modifying anything.')
    return eligible[0]


def sql(ref, query, read_only=False):
    endpoint = '/database/query/read-only' if read_only else '/database/query'
    return request('supabase', '/v1/projects/' + ref + endpoint, 'POST', {'query': query}, timeout=120)


def keys(ref):
    rows = request('supabase', '/v1/projects/' + ref + '/api-keys?reveal=true')
    result = {}
    for row in rows:
        if row.get('name') in ('anon', 'service_role'):
            result[row['name']] = row['api_key']
        if row.get('type') == 'publishable':
            result['publishable'] = row['api_key']
    return result


def project_request(ref, key, path, method='GET', body=None, bearer=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request('https://' + ref + '.supabase.co' + path, data=data, method=method,
                                 headers={'apikey': key, 'Authorization': 'Bearer ' + (bearer or key),
                                          'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=45) as response:
            raw = response.read(8 * 1024 * 1024)
        return json.loads(raw) if raw else None
    except urllib.error.HTTPError as exc:
        raise ApiError('project', exc.code, 'Response details withheld.') from None


def multipart(metadata, files):
    boundary = 'paperlab-' + secrets.token_hex(16)
    parts = []
    def field(name, data, filename=None, kind=None):
        header = '--' + boundary + '\r\nContent-Disposition: form-data; name="' + name + '"'
        if filename:
            header += '; filename="' + filename + '"'
        if kind:
            header += '\r\nContent-Type: ' + kind
        parts.append(header.encode() + b'\r\n\r\n' + data + b'\r\n')
    field('metadata', json.dumps(metadata).encode(), kind='application/json')
    for path, data in files:
        field('file', data, path, 'application/javascript')
    parts.append(('--' + boundary + '--\r\n').encode())
    return b''.join(parts), 'multipart/form-data; boundary=' + boundary


def deploy_function(ref, slug):
    folder = ROOT / 'managed/functions'
    paths = list((folder / '_shared').glob('*.js')) + [folder / slug / 'index.js']
    # Relative filenames preserve sibling _shared imports in the platform bundle.
    files = [(str(path.relative_to(folder)), path.read_bytes()) for path in paths]
    body, content_type = multipart({'name': slug, 'entrypoint_path': slug + '/index.js',
                                     'verify_jwt': False}, files)
    return request('supabase', '/v1/projects/' + ref + '/functions/deploy?slug=' + slug,
                   'POST', body, content_type, timeout=180)


def private_json(name, data):
    folder = ROOT / '.data/managed'
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    path = folder / name
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    path.chmod(0o600)
    return path
