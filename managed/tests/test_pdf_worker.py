"""Run with PyMuPDF installed: python managed/tests/test_pdf_worker.py."""
import importlib.util,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('paperlab_pdf',Path(__file__).resolve().parents[1]/'pdf-worker/app.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class PDFTests(unittest.TestCase):
 def test_complete_page_extraction_and_ocr_gap(self):
  import pymupdf
  doc=pymupdf.open();doc.new_page().insert_text((72,72),'Year revenue 100 USD; operating cash 80 USD.');raw=doc.tobytes();x=m.extract_bytes(raw)
  self.assertEqual(x['pages_processed'],1);self.assertTrue(x['complete_extraction']);self.assertIn('cash 80 USD',x['text']);self.assertEqual(len(x['sha256']),64)
  doc.new_page();x=m.extract_bytes(doc.tobytes());self.assertEqual(x['pages_processed'],2);self.assertFalse(x['complete_extraction']);self.assertEqual(x['empty_pages'],[2]);self.assertTrue(x['ocr_required'])
 def test_private_and_unregistered_hosts_rejected(self):
  for url in ['http://issuer.example/r.pdf','https://attacker.example/r.pdf','https://issuer.example@attacker.example/r.pdf']:
   with self.assertRaises(ValueError):m.allowed(url,['issuer.example'])
  with patch.object(m.socket,'getaddrinfo',return_value=[(2,1,6,'',('127.0.0.1',443))]):
   with self.assertRaisesRegex(ValueError,'not_public'):m.allowed('https://issuer.example/r.pdf',['issuer.example'])
 def test_binary_is_not_accepted_as_pdf(self):
  with self.assertRaisesRegex(ValueError,'not_pdf'):m.extract_bytes(b'not a PDF')
if __name__=='__main__':unittest.main()
