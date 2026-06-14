#!/usr/bin/env python3
"""
Run this on your LOCAL machine (not in Claude Code remote).
  pip install playwright && playwright install chromium
  python3 scrape_local.py

Paste the printed JSON back into Claude Code when done.
"""
import json, time, re
from playwright.sync_api import sync_playwright

SEARCH_URLS = [
    ("Zillow",
     "https://www.zillow.com/detroit-mi/rent-houses-4-bedrooms/",
     ['[class*="property-card"]', '[class*="StyledPropertyCard"]', 'article']),
    ("HotPads",
     "https://hotpads.com/detroit-mi/4-plus-bedroom-houses-for-rent?bathrooms=2%2C3%2C4&price_max=1750&price_min=1250",
     ['[class*="listing-card"]', '[class*="ListingCard"]', 'article']),
    ("Apartments.com",
     "https://www.apartments.com/houses/detroit-mi/4-bedrooms/min-1250-max-1750/2-bathrooms/",
     ['article.placard', '[class*="placard"]', '.property-card']),
    ("Zumper",
     "https://www.zumper.com/houses-for-rent/detroit-mi?beds=4-6&baths=2&price_min=1250&price_max=1750",
     ['[data-tid="listing-card"]', 'article[class*="listing"]', '[class*="listingCard"]']),
    ("Redfin",
     "https://www.redfin.com/city/5665/MI/Detroit/4-bedroom-2-bath-house-for-rent",
     ['[class*="homecard"]', '.HomeCard', '[class*="home-card"]']),
    ("Rent.com",
     "https://www.rent.com/michigan/detroit-houses/max-price-1750?bedrooms=4%2C5%2C6&bathrooms=2%2C3",
     ['[class*="listing"]', 'article', '[class*="property"]']),
]

def scroll_page(page, times=5):
    for _ in range(times):
        page.keyboard.press('End')
        page.wait_for_timeout(1200)

def extract_cards(page, selectors):
    for sel in selectors:
        cards = page.query_selector_all(sel)
        if cards:
            return cards
    return []

def parse_text(txt, href, source):
    txt = txt.replace('\n', ' ').strip()
    price = None
    m = re.search(r'\$([0-9,]+)(?:/mo|/month|mo)?', txt)
    if m:
        try: price = int(m.group(1).replace(',', ''))
        except: pass

    beds = None
    m = re.search(r'(\d)\s*(?:bed|bd|br)', txt, re.I)
    if m: beds = int(m.group(1))

    baths = None
    m = re.search(r'(\d\.?\d?)\s*(?:bath|ba)\b', txt, re.I)
    if m:
        try: baths = float(m.group(1))
        except: pass

    addr = None
    m = re.search(r'\d+\s+[A-Z][a-zA-Z0-9 ]+(?:St|Ave|Rd|Dr|Blvd|Ln|Ct|Way|Pl|Hwy|Pkwy)\.?', txt)
    if m: addr = m.group(0).strip()

    return {'source': source, 'address': addr, 'price': price,
            'beds': beds, 'baths': baths, 'url': href, 'snippet': txt[:300]}

def main():
    listings = []
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)  # visible so sites trust it
        ctx = browser.new_context(
            user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                       '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            viewport={'width': 1440, 'height': 900}
        )

        for platform, url, selectors in SEARCH_URLS:
            print(f"\n→ {platform}: {url[:70]}")
            page = ctx.new_page()
            try:
                page.goto(url, timeout=30000)
                page.wait_for_timeout(3000)
                scroll_page(page)
                page.wait_for_timeout(2000)

                cards = extract_cards(page, selectors)
                print(f"  Found {len(cards)} cards")

                for c in cards[:40]:
                    try:
                        txt = c.inner_text()
                        a = c.query_selector('a[href]')
                        href = a.get_attribute('href') if a else None
                        if href and href.startswith('/'):
                            base = url.split('/')[0] + '//' + url.split('/')[2]
                            href = base + href
                        parsed = parse_text(txt, href, platform)
                        listings.append(parsed)
                    except:
                        pass
            except Exception as e:
                print(f"  Error: {e}")
            finally:
                page.close()

        browser.close()

    # Filter
    good = []
    for l in listings:
        p = l.get('price')
        bd = l.get('beds')
        ba = l.get('baths')
        if p and (p < 1250 or p > 1750): continue
        if bd and (bd < 4 or bd > 6): continue
        if ba and ba < 2: continue
        good.append(l)

    print(f"\n\n{'='*60}")
    print(f"TOTAL raw listings: {len(listings)}")
    print(f"MATCHING criteria:  {len(good)}")
    print('='*60)

    output = json.dumps(good, indent=2)
    print("\n--- PASTE THIS BACK TO CLAUDE CODE ---")
    print(output)
    print("--- END ---")

    with open('listings.json', 'w') as f:
        f.write(output)
    print(f"\nAlso saved to listings.json")

if __name__ == '__main__':
    main()
