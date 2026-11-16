# Private PDF text worker

Run only on a Render **free** web-service plan, one instance, no disk or paid resources. Start `python app.py` after `pip install -r requirements.txt`. `PAPERLAB_CRON_TOKEN` authenticates extraction; `PAPERLAB_PDF_HOSTS` is a comma-separated list of registered official source hosts. No Gemini key, Supabase service key or portfolio data is stored here. `/health` exposes no secrets. Extraction is bounded to 20 MB and 600 pages, and rejects redirects and non-public addresses. Empty/scanned pages remain a gap; no automatic OCR claim is made.
