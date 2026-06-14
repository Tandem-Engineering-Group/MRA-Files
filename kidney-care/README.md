# Independent Kidney Care — Pitch Website

Static site for presenting the independent dialysis center opportunity to nephrologists in metro Detroit.  
No build step, no server — open `index.html` in a browser or host anywhere.

## File structure

```
kidney-care/
├── index.html              one-page pitch site
├── deck.html               slide viewer (?deck=1 or ?deck=2)
├── map.html                embedded interactive Michigan map
├── css/site.css
├── js/site.js
└── assets/
    ├── deck1/slide-01.png … slide-09.png
    ├── deck2/slide-01.png … slide-08.png
    ├── Deck1_Independent_JV.pptx
    ├── Deck2_Chain_JV.pptx
    ├── Deck1.pdf
    ├── Deck2.pdf
    └── source/             original uploaded PPTX files
```

## Editing content

- **Contact info** — open `index.html`, search for `[ Your Name ]`, `[ your@email.com ]`, `[ (000) 000-0000 ]` and replace.
- **Stat cards** — edit the four `<div class="stat-card">` blocks in `index.html`.
- **Deck thumbnails / slides** — re-render using `render_slides.py` (requires `python3 -m pip install python-pptx pillow`), or replace the PNG files in `assets/deck1/` and `assets/deck2/` directly.

## Hosting

### GitHub Pages
1. Push this repo to GitHub.
2. Settings → Pages → Deploy from branch `main` / root (or `/kidney-care` subfolder using a `gh-pages` branch).
3. Live at `https://username.github.io/repo-name/kidney-care/`.

### Netlify (easiest)
1. Drag the `kidney-care/` folder onto [app.netlify.com](https://app.netlify.com).
2. Instant URL — add a custom domain in Site Settings if needed.

Either gives a single link you can text or email to a physician.

## Re-generating slides

If you update the PPTX files:

```bash
cd kidney-care
pip3 install python-pptx pillow
python3 render_slides.py
```

This produces PNG images in `assets/deck1/` and `assets/deck2/`.  
Then regenerate the PDFs:

```bash
convert assets/deck1/slide-*.png assets/Deck1.pdf
convert assets/deck2/slide-*.png assets/Deck2.pdf
```

(Requires ImageMagick. On Mac: `brew install imagemagick`.)
