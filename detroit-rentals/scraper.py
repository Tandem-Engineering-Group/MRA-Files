#!/usr/bin/env python3
"""
Scrape Detroit rental listings (4-6 BR, 2+ bath, $1,250-$1,750) using headless Chromium.
Tries multiple platforms and collects real listing data.
"""
import json, time, re, sys
from playwright.sync_api import sync_playwright

CHROME = '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'

URLS = [
    # (platform, url, parser_key)
    ("Zumper",
     "https://www.zumper.com/houses-for-rent/detroit-mi?beds=4-6&baths=2&price_min=1250&price_max=1750",
     "zumper"),
    ("HotPads",
     "https://hotpads.com/detroit-mi/4-plus-bedroom-houses-for-rent?bathrooms=2%2C3%2C4&price_max=1750&price_min=1250",
     "hotpads"),
    ("Apartments.com",
     "https://www.apartments.com/houses/detroit-mi/4-bedrooms/min-1250-max-1750/2-bathrooms/",
     "apts"),
    ("Redfin",
     "https://www.redfin.com/city/5665/MI/Detroit/4-bedroom-2-bath-house-for-rent",
     "redfin"),
    ("Rent.com",
     "https://www.rent.com/michigan/detroit-houses/max-price-1750?bedrooms=4%2C5%2C6&bathrooms=2%2C3",
     "rent"),
]

def make_browser(p):
    return p.chromium.launch(
        headless=True,
        executable_path=CHROME,
        args=['--ignore-certificate-errors','--no-sandbox',
              '--disable-dev-shm-usage','--disable-blink-features=AutomationControlled']
    )

def make_context(browser):
    return browser.new_context(
        ignore_https_errors=True,
        user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                   '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        viewport={'width':1440,'height':900},
        extra_http_headers={
            'Accept-Language': 'en-US,en;q=0.9',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        }
    )

def wait_and_scroll(page, seconds=4):
    """Wait for page load then scroll to trigger lazy content."""
    page.wait_for_timeout(seconds * 1000)
    for _ in range(3):
        page.mouse.wheel(0, 1200)
        page.wait_for_timeout(1000)

def scrape_zumper(page):
    listings = []
    try:
        cards = page.query_selector_all('[data-tid="listing-card"], article[class*="listing"], [class*="listingCard"]')
        print(f"  Zumper: found {len(cards)} card elements")
        for c in cards[:30]:
            try:
                txt = c.inner_text()
                href = None
                a = c.query_selector('a[href]')
                if a: href = a.get_attribute('href')
                listings.append({'raw': txt[:400], 'href': href, 'source': 'Zumper'})
            except: pass
    except Exception as e:
        print(f"  Zumper error: {e}")
    return listings

def scrape_hotpads(page):
    listings = []
    try:
        cards = page.query_selector_all('[class*="listing-card"], [class*="listingCard"], [data-tag*="listing"]')
        print(f"  HotPads: found {len(cards)} card elements")
        for c in cards[:30]:
            try:
                txt = c.inner_text()
                href = None
                a = c.query_selector('a[href]')
                if a: href = a.get_attribute('href')
                listings.append({'raw': txt[:400], 'href': href, 'source': 'HotPads'})
            except: pass
    except Exception as e:
        print(f"  HotPads error: {e}")
    return listings

def scrape_apts(page):
    listings = []
    try:
        cards = page.query_selector_all('article.placard, [class*="placard"], .property-card')
        print(f"  Apartments.com: found {len(cards)} card elements")
        for c in cards[:30]:
            try:
                txt = c.inner_text()
                href = None
                a = c.query_selector('a[href]')
                if a: href = a.get_attribute('href')
                listings.append({'raw': txt[:400], 'href': href, 'source': 'Apartments.com'})
            except: pass
    except Exception as e:
        print(f"  Apts error: {e}")
    return listings

def scrape_redfin(page):
    listings = []
    try:
        cards = page.query_selector_all('[class*="homecard"], .HomeCard, [data-rf-test-name*="property"]')
        print(f"  Redfin: found {len(cards)} card elements")
        for c in cards[:30]:
            try:
                txt = c.inner_text()
                href = None
                a = c.query_selector('a[href]')
                if a: href = a.get_attribute('href')
                listings.append({'raw': txt[:400], 'href': href, 'source': 'Redfin'})
            except: pass
    except Exception as e:
        print(f"  Redfin error: {e}")
    return listings

def scrape_rent(page):
    listings = []
    try:
        cards = page.query_selector_all('[class*="listing"], [class*="property-card"], article')
        print(f"  Rent.com: found {len(cards)} card elements")
        for c in cards[:30]:
            try:
                txt = c.inner_text()
                href = None
                a = c.query_selector('a[href]')
                if a: href = a.get_attribute('href')
                listings.append({'raw': txt[:400], 'href': href, 'source': 'Rent.com'})
            except: pass
    except Exception as e:
        print(f"  Rent error: {e}")
    return listings

SCRAPERS = {
    'zumper': scrape_zumper,
    'hotpads': scrape_hotpads,
    'apts': scrape_apts,
    'redfin': scrape_redfin,
    'rent': scrape_rent,
}

def parse_listing(raw_text, href, source):
    """Parse raw text into structured listing data."""
    txt = raw_text.replace('\n', ' ').strip()

    # Price: $1,250 – $1,750
    price = None
    pm = re.search(r'\$([0-9,]+)(?:/mo|/month)?', txt)
    if pm:
        try:
            price = int(pm.group(1).replace(',',''))
        except: pass

    # Beds
    beds = None
    bm = re.search(r'(\d+)\s*(?:bed|bd|br|bedroom)', txt, re.I)
    if bm: beds = int(bm.group(1))

    # Baths
    baths = None
    bam = re.search(r'(\d+(?:\.\d)?)\s*(?:bath|ba)', txt, re.I)
    if bam:
        try: baths = float(bam.group(1))
        except: pass

    # Address - look for street patterns
    addr = None
    am = re.search(r'\d+\s+[A-Z][a-zA-Z\s]+(?:St|Ave|Rd|Dr|Blvd|Ln|Ct|Way|Pl|Hwy|Pkwy)[\.,\s]', txt)
    if am: addr = am.group(0).strip().rstrip('.,')

    return {
        'source': source,
        'address': addr,
        'price': price,
        'beds': beds,
        'baths': baths,
        'url': href,
        'raw': txt[:300]
    }

def scrape_all():
    all_raw = []

    with sync_playwright() as p:
        browser = make_browser(p)

        for platform, url, key in URLS:
            print(f"\n[{platform}] {url[:80]}")
            try:
                ctx = make_context(browser)
                page = ctx.new_page()
                page.goto(url, timeout=30000, wait_until='domcontentloaded')
                wait_and_scroll(page, seconds=5)

                # Save page content for debugging
                content = page.content()
                title = page.title()
                print(f"  Title: {title} | HTML len: {len(content)}")

                # Save HTML snapshot
                with open(f'/tmp/scrape_{key}.html', 'w') as f:
                    f.write(content)

                # Run scraper
                scraper = SCRAPERS[key]
                raw_listings = scraper(page)
                print(f"  Raw listings: {len(raw_listings)}")

                for r in raw_listings:
                    parsed = parse_listing(r['raw'], r['href'], platform)
                    all_raw.append(parsed)

                ctx.close()
            except Exception as e:
                print(f"  ERROR: {e}")

        browser.close()

    # Filter to criteria
    filtered = []
    seen_addrs = set()
    for l in all_raw:
        if l['price'] and (l['price'] < 1250 or l['price'] > 1750): continue
        if l['beds'] and (l['beds'] < 4 or l['beds'] > 6): continue
        if l['baths'] and l['baths'] < 2: continue
        if l['address'] and l['address'] in seen_addrs: continue
        if l['address']: seen_addrs.add(l['address'])
        filtered.append(l)

    print(f"\n\n=== RESULTS ===")
    print(f"Total raw: {len(all_raw)}, filtered to criteria: {len(filtered)}")
    for l in filtered:
        print(f"  {l['source']:15} | ${l['price'] or '?':>6} | {l['beds'] or '?'}bd {l['baths'] or '?'}ba | {l['address'] or 'no addr'}")

    with open('/tmp/listings_raw.json', 'w') as f:
        json.dump({'all': all_raw, 'filtered': filtered}, f, indent=2)

    return filtered

if __name__ == '__main__':
    results = scrape_all()
    print(f"\nSaved to /tmp/listings_raw.json")
