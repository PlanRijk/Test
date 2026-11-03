"""Deployment safety checks: schema collisions, free-only hosting, no secrets."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from scripts import deploy_managed as deploy


class DeploymentTests(unittest.TestCase):
    def test_unrelated_schema_blocks_all_modifications(self):
        with patch.object(deploy,'sql',return_value=[{'marker':'another application'}]) as sql,patch.object(deploy,'source_export') as export:
            with self.assertRaisesRegex(RuntimeError,'unrelated'):deploy.database('test')
            self.assertEqual(sql.call_count,1);self.assertTrue(sql.call_args.args[2]);export.assert_not_called()

    def test_only_free_static_site_is_created(self):
        def api(provider,path,method='GET',body=None):
            if method=='GET':return []
            self.assertEqual(provider,'render');self.assertEqual(path,'/v1/services')
            self.assertEqual(body['type'],'static_site');self.assertNotIn('plan',body['serviceDetails'])
            self.assertNotIn('disk',body);self.assertEqual(body['serviceDetails']['publishPath'],'managed/web')
            self.assertEqual(body['autoDeployTrigger'],'off')
            return {'service':{'type':'static_site','id':'srv-test','serviceDetails':{'url':'https://test.onrender.com'}}}
        with patch.object(deploy,'request',side_effect=api),patch.object(deploy,'private_json'):
            deploy.site('test','tea-example')

    def test_existing_paid_service_is_not_modified(self):
        service=[{'service':{'name':'paperlab-prive','type':'web_service','id':'srv-test'}}]
        with patch.object(deploy,'request',return_value=service) as req:
            with self.assertRaisesRegex(RuntimeError,'paid service'):deploy.site('test','tea-example')
            self.assertEqual(req.call_count,1)

    def test_missing_workspace_never_creates_a_resource(self):
        with patch.object(deploy,'request') as req:
            with self.assertRaises(ValueError):deploy.site('test',None)
            req.assert_not_called()

    def test_private_credentials_rejected_before_browser_config_write(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'managed/web').mkdir(parents=True)
            with patch.object(deploy,'ROOT',root),patch.object(deploy,'keys',return_value={'publishable':'sb_secret_testvalue'}):
                with self.assertRaises(RuntimeError):deploy.public_config('test')
            self.assertFalse((root/'managed/web/config.js').exists())


if __name__=='__main__':unittest.main()
