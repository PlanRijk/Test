"""Restricted in-memory credential transport; synthetic values only."""
import io,json,sys,unittest,urllib.error
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT))
from scripts.access_recovery import token_client,NoCredentialRedirect
from scripts.managed_api import ApiError
class Response(io.BytesIO):
 def __enter__(self):return self
 def __exit__(self,*args):self.close()
class ClientTest(unittest.TestCase):
 def test_fixed_host_and_memory_header(self):
  seen=[];token='sbp_'+'a'*40
  class Opener:
   def open(self,r,timeout):seen.append(r);return Response(b'[{"ok":true}]')
  with patch('scripts.access_recovery.urllib.request.build_opener',return_value=Opener()):
   call=token_client(token);self.assertEqual(call('/v1/projects/x/database/query','POST',{'query':'select 1'}),[{'ok':True}])
   for invalid in['https://outside.invalid','//outside.invalid','/other/path','/v1/x\r\nInjected: x']:
    with self.assertRaises(RuntimeError):call(invalid)
  self.assertEqual(len(seen),1);self.assertEqual(seen[0].full_url,'https://api.supabase.com/v1/projects/x/database/query');self.assertEqual(seen[0].get_header('Authorization'),'Bearer '+token);self.assertNotIn(token,seen[0].data.decode())
 def test_provider_response_cannot_echo_credential(self):
  token='sbp_'+'a'*40
  class Opener:
   def open(self,r,timeout):raise urllib.error.HTTPError(r.full_url,401,'Unauthorized',{},io.BytesIO(token.encode()))
  with patch('scripts.access_recovery.urllib.request.build_opener',return_value=Opener()):
   with self.assertRaises(ApiError)as e:token_client(token)('/v1/projects')
  self.assertNotIn(token,str(e.exception));self.assertEqual(e.exception.status,401)
 def test_credentials_never_follow_redirect(self):
  self.assertIsNone(NoCredentialRedirect().redirect_request(None,None,302,'',{},'https://outside.invalid'))
unittest.main()
