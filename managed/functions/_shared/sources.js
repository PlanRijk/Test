export const SOURCES = [
  {
    "id": "jst",
    "url": "https://www.macrohistory.net/database/",
    "kind": "html"
  },
  {
    "id": "fed1929",
    "url": "https://www.federalreservehistory.org/essays/stock-market-crash-of-1929",
    "kind": "html"
  },
  {
    "id": "fed1987",
    "url": "https://www.federalreservehistory.org/essays/stock-market-crash-of-1987",
    "kind": "html"
  },
  {
    "id": "fed2008",
    "url": "https://www.federalreservehistory.org/essays/great-recession-and-its-aftermath",
    "kind": "html"
  },
  {
    "id": "sec2010",
    "url": "https://www.sec.gov/news/studies/2010/marketevents-report.pdf",
    "kind": "pdf"
  },
  {
    "id": "secstops",
    "url": "https://www.investor.gov/introduction-investing/investing-basics/how-stock-markets-work/types-orders",
    "kind": "article",
    "takeaway": "Marktorders geven geen vaste uitvoeringsprijs; limietorders kunnen onuitgevoerd blijven. Een stopprijs is geen gegarandeerde verkoopprijs.",
    "implication": "De paperprijs en verliesdrempel blijven schattingen; een echte brokerkoppeling moet ordertype, spread, gaps en gedeeltelijke uitvoering afzonderlijk toetsen."
  },
  {
    "id": "bis2024",
    "url": "https://www.bis.org/publications/qr-202409",
    "kind": "html"
  },
  {
    "id": "bis2020",
    "url": "https://www.bis.org/publications/bulletin-2-leverage-and-margin-spirals-fixed-income-markets-during-covid-19-crisis",
    "kind": "html"
  },
  {
    "id": "japan",
    "url": "https://indexes.nikkei.co.jp/en/nkave/archives/data?list=annually",
    "kind": "html"
  },
  {
    "id": "nasdaqhalts",
    "url": "https://www.nasdaqtrader.com/Trader.aspx?id=CircuitBreaker",
    "kind": "html"
  },
  {
    "id": "ecbindex",
    "url": "https://www.ecb.europa.eu/press/financial-stability-publications/fsr/html/index.en.html",
    "kind": "html"
  },
  {
    "id": "yalecorrect",
    "url": "https://economics.yale.edu/people/robert-shiller",
    "kind": "html"
  },
  {
    "id": "fedfeed",
    "url": "https://www.federalreserve.gov/feeds/press_all.xml",
    "kind": "rss"
  },
  {
    "id": "ecbfeed",
    "url": "https://www.ecb.europa.eu/rss/press.html",
    "kind": "rss"
  },
  {
    "id": "vix",
    "url": "https://fred.stlouisfed.org/graph/fredgraph.csv?id=VIXCLS&cosd=2000-01-01",
    "kind": "fred_csv"
  },
  {
    "id": "creditspread",
    "url": "https://fred.stlouisfed.org/graph/fredgraph.csv?id=BAMLH0A0HYM2&cosd=2000-01-01",
    "kind": "fred_csv"
  },
  {
    "id": "yieldcurve",
    "url": "https://fred.stlouisfed.org/graph/fredgraph.csv?id=T10Y3M&cosd=2000-01-01",
    "kind": "fred_csv"
  },
  {
    "id": "conditions",
    "url": "https://fred.stlouisfed.org/graph/fredgraph.csv?id=NFCI&cosd=2000-01-01",
    "kind": "fred_csv"
  },
  {
    "id": "fedasia1997",
    "url": "https://www.federalreservehistory.org/essays/asian-financial-crisis",
    "kind": "html"
  },
  {
    "id": "odean",
    "kind": "pdf",
    "url": "https://faculty.haas.berkeley.edu/odean/Papers%20current%20versions/Individual_Investor_Performance_Final.pdf"
  },
  {
    "id": "pbo",
    "kind": "pdf",
    "url": "https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf"
  },
  {
    "id": "dsr",
    "kind": "pdf",
    "url": "https://www.davidhbailey.com/dhbpapers/deflated-sharpe.pdf"
  },
  {
    "id": "tsm",
    "kind": "html",
    "url": "https://www.aqr.com/Insights/Research/Journal-Article/Time-Series-Momentum"
  },
  {
    "id": "multipletesting",
    "kind": "html",
    "url": "https://www.nber.org/papers/w20592"
  },
  {
    "id": "ecbtransmission",
    "url": "https://www.ecb.europa.eu/mopo/intro/transmission/html/index.en.html",
    "kind": "article",
    "takeaway": "Rente werkt via verwachtingen, activaprijzen, wisselkoersen en krediet. De vertraging is lang, variabel en onzeker.",
    "implication": "Een rentebesluit is geen betrouwbaar vijfminuten-koopadvies. Bewaar datums en toets mogelijke effecten afzonderlijk met toen beschikbare gegevens."
  },
  {
    "id": "finraorders",
    "url": "https://www.finra.org/investors/investing/investment-products/stocks/order-types",
    "kind": "article",
    "takeaway": "Ordertype bepaalt de afweging tussen prijszekerheid en uitvoeringskans; stops kunnen bij snelle beweging een andere uitvoeringsprijs krijgen.",
    "implication": "Nettoresultaat moet uitvoeringsfrictie omvatten. Bescherming is een trigger, geen gegarandeerd maximaal verlies."
  },
  {
    "id": "nbbstability",
    "url": "https://www.nbb.be/en/financial-supervision/financial-stability",
    "kind": "article",
    "takeaway": "Onderlinge verbindingen en vergelijkbare posities kunnen financiële schokken verspreiden. Alleen afzonderlijke instellingen beoordelen is onvoldoende.",
    "implication": "Sectorverdeling alleen bewijst geen spreiding van systeemrisico. Onderzoek gezamenlijke blootstelling en stressperiodes voordat risicoregels veranderen."
  },
  {
    "id": "frenchdata",
    "url": "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/data_library.html",
    "kind": "html",
    "takeaway": "De onderzoeksbibliotheek onderscheidt markt-, omvang-, waarde-, winstgevendheids- en investeringsfactoren. De overgang van CRSP FIZ naar CIZ wijzigt onder meer de verwerking van dividenden.",
    "implication": "Leg datasetversie, dividendmethode en regio vast. Deze historische factorreeksen zijn geen actuele uitvoeringskoersen en nog niet opgenomen als handelskenmerken."
  }
];
