# Daily Buffett reading notes

PaperLab verifies one publicly accessible Berkshire Hathaway shareholder-letter passage each day at 06:00 UTC (07:00 Brussels winter / 08:00 summer). Eight editor-reviewed themes from letters of 1977, 1986, 1987, 1992 and 1996 form the initial library. The first complete letter and the relevant later passages were reviewed during setup. Only the selected passage is claimed by the daily routine.

The daily function retrieves the official HTTPS HTML without following redirects, limits download size and runtime, checks the expected text anchors, and stores a timestamp, content hash and the existing paraphrased lesson, research question and missing evidence. An inaccessible or changed source yields an explicit failure with no confirmed lesson. After eight successful themes, repeats are explicitly labelled. This is **not a new full book or fresh autonomous AI analysis each day**. There is no paid model or licensed book corpus attached.

Reading notes are separate from empirical training samples and frozen trading/model policies. They cannot change model weights, purchase rules, execution freshness gates or risk stops. Fundamental investing over years must be evaluated separately from the current intraday strategy. A quote or lesson is not a validated profitable signal.

Only the authenticated owner with MFA and a valid application session can view notes and pause/resume. The scheduled function requires the independent cron secret. Public and authenticated database roles cannot call the private RPCs or read the tables. URLs come from the fixed reviewed library, never a browser request. Remote text is data, never executable instructions.

At most 120 notes are retained for 120 days, and no full letters/books are stored. The routine reserves 300,000 estimated bytes per attempt, maximum three per UTC day and 20 MB/month; database/own-storage/shared-egress admission limits are 100 MB / 2 MB / 1.2 GB. A failed or terminated attempt retains its charge. These conservative app estimates are not a provider invoice and exclude unrelated Render traffic. Own cron logs older than seven days are removed in bounded batches.

The reading list distinguishes *The Essays of Warren Buffett* (compiled by Lawrence A. Cunningham) from *The Intelligent Investor* (Benjamin Graham) and *Security Analysis* (Graham and David Dodd). These books are not marked as fully read. A lawful full text is required for further chapter-level analysis. No purchase is made.

Sources: https://www.berkshirehathaway.com/letters/letters.html and the official year-specific HTML pages in `reading-plan.js`.

Install only this independent extension with `python scripts/reading_study.py configure PROJECT_REF`; it refuses an incompatible existing reading policy, deploys only `paper-reading` and `paper-api`, and schedules one daily job. It never initializes or resets an existing trading account. Validate with `npm test --prefix managed` and `python managed/tests/test_reading_database.py` (isolated local PostgreSQL fixture).
