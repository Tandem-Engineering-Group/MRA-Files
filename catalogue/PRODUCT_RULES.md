# Product Lookup System Rules — V2.1 (Quintin, locked in 2026-07-16)

Combined operating standard for product entry, naming, sorting, IDs, duplicate detection,
job tags, and order history. **This file is the standard for every catalogue import — apply
it before adding or editing catalogue data.**

## 1. Purpose
- Central product lookup database for shop/material purchases.
- **Product Catalog** stores one row per unique physical product item.
- **Order History** stores one row per purchase/order event tied to a product.
- Search by product name, structured attributes, vendor, SKU, job tags, internal ID.
- Shipping, tax, tariffs, and general fees are OMITTED from product lookup — no product IDs.

## 2. Required sheet structure

### 2.1 Product Catalog — one row per unique product item
| # | Column | Use |
|---|--------|-----|
| 1 | internal_id | Full item ID: `DDCCSSFFF-III` |
| 2 | product_family_id | Family-level ID: `DDCCSSFFF` |
| 3 | product_family | Clear noun phrase identifying the item type/form/function |
| 4 | department | Materials, Hardware, Electrical, AV Tech |
| 5 | category | Functional group: Aluminum, Fasteners, Insulation, … |
| 6 | subcategory | Specific type: T-Slot, Screws, Plywood, Acrylic, … |
| 7 | size_1 | Primary size/dimension/thread/profile value |
| 8 | size_2 | Secondary dimension when applicable |
| 9 | thickness | Thickness/gauge/depth where relevant |
| 10 | length | Linear length where relevant |
| 11 | material | Material or material grade |
| 12 | color | Color only (Black, White, Milk White) |
| 13 | canonical_name | Generated from structured columns only |
| 14 | job_tags | Comma-separated job IDs, e.g. `J1526, J1560` |

### 2.2 Order History — one row per purchase/order event
| # | Column | Use |
|---|--------|-----|
| 1 | history_id | Unique row ID |
| 2 | internal_id | Links to Product Catalog item |
| 3 | vendor | Supplier for this purchase |
| 4 | sku | Vendor/manufacturer SKU if available |
| 5 | unit_cost | Cost per unit for this event |
| 6 | unit | each, sheet, pack, roll, … |
| 7 | order_date | Date ordered/purchased |
| 8 | job_tags | Job IDs for this purchase/use |
| 9 | quantity | Optional |
| 10 | extended_cost | Optional |
| 11 | notes | Optional |

## 3. Canonical naming rules
- `canonical_name` is **generated, not invented**: noun-first — product_family then
  category-defined attributes in priority order, **from structured columns only**.
- Never include vendor, SKU, price, job number, order date, tax, shipping, fees.
- Leave unknown fields blank — do not guess dimensions, materials, colors, features.
- No duplicate attributes in the name.
- Formula: `canonical_name = refined_product_family + structured attributes in category rule order, skipping blanks`.

## 4. Product family clarity & refinement
- product_family must be a clear noun phrase (form/function/system type). Generic values are
  not acceptable when a clearer phrase can be derived from category/subcategory/description.
- Refine BEFORE generating canonical_name; if it can't be confidently refined → flag for manual review.

| Generic family | Keyword trigger | Refined product_family |
|---|---|---|
| Adhesive | floor, flooring, vinyl, DriTac, SikBond | Floor Adhesive |
| Profile | t-slot, t-slotted, open t-slot, 8020, profile | T-Slot Aluminum Profile |
| Sheet | acrylic, plexiglas, optix | Acrylic Sheet |
| Panel | ACM, aluminum composite | ACM Panel |
| Board | PVC foam, Komatex | PVC Foam Board |
| Cable | Cat6, ethernet | Cat6 Cable |
| Screw | button head | Button Head Screw |
| Screw | flat head | Flat Head Screw |

## 5. Category naming rule table
| Category type | canonical_name structure | Example |
|---|---|---|
| Panels / Sheets | family + size_1 + size_2 + thickness + color | Acrylic Sheet 48 in 96 in 1/4 in Milk White |
| Fasteners / Screws | family + size_1 + length + material + color? | Button Head Screw M6 x 1 mm 12 mm 18-8 Stainless Steel |
| Aluminum Profiles / Structural | family + size_1 + size_2 + thickness/length + material | T-Slot Aluminum Profile 1.00 in 0.50 in 10 ft Aluminum |
| Wood / Plywood | family + size_1 + size_2 + thickness | Plywood Sheet 4 ft 8 ft 23/32 in |
| Insulation | family + size_1 + size_2 + thickness + material/rating | Foam Board Insulation 4 ft 8 ft 1 in R-5 |
| Fabric / Felt | family + size_1 + thickness + color | Poly Felt 60 in 3.5 mm Black |
| Adhesives / Sealants | family + size_1 + color? | Floor Adhesive 4 gal |
| Custom / Samples / Kits | family + known attributes only | Stool Sample; Aluminum Framing Package |

## 6. Departments
- **Materials** — aluminum, panels, plastics, wood, insulation, fabric/felt, adhesives.
- **Hardware** — fasteners, hinges, latches, locks, handles, brackets, casters.
- **Electrical** — power, wire, cable, connectors, network, electrical components.
- **AV Tech** — audio/video, racks, mounts, displays, tech hardware; tech/display furniture & samples.

## 7. Product ID system
- Format `DDCCSSFFF-III`: DD=department, CC=category, SS=subcategory, FFF=family (sequential
  within dept/cat/subcat), III=item (sequential within family).
- `product_family_id = DDCCSSFFF`; `internal_id = product_family_id + "-" + item_code`.
- Department codes: 01 Materials · 02 Hardware · 03 Electrical · 04 AV Tech.
- **IDs are permanent once assigned** — never change an existing ID when a name is corrected.
- Fees/shipping/tax/tariffs/non-products never get IDs.
- Examples: `010101001-001` Materials>Plastics>Acrylic>Acrylic Sheet item 001 ·
  `010402001-003` Materials>Aluminum>T-Slot>T-Slot Aluminum Profile item 003 ·
  `020101001-001` Hardware>Fasteners>Screws>Button Head Screw item 001.

## 8. Required entry rules
- Every product: product_family, department, category, subcategory, canonical_name, job_tags (if known).
- Vendor/SKU/unit_cost/unit/order_date belong in **Order History**, never product identity.
- Panels/sheets: size_1 + size_2 + thickness when known. Fasteners: size_1/thread + length +
  material when known. Profiles/structural: profile dimensions + length when known.
- color = color/finish only (never mixed with material or size).
- Readable units: `48 in`, `96 in`, `1/4 in`, `12 mm`, `10 ft`, `4 gal`.
- Unknown → blank, never invented.

## 9. Duplicate detection & order-history logic
- Product identity = structured product fields ONLY (family, dept, cat, subcat, size_1, size_2,
  thickness, length, material, color, canonical_name).
- vendor, sku, unit_cost, unit, order_date, job_tags NEVER create a new product.
- Existing product found → reuse internal_id + add an Order History row; never overwrite prior
  purchase details; cost changes never create products.
- Physical attributes differ → new product item under the correct family.
- Uncertain match → flag for manual review before assigning an ID.

## 10. Job tags
- Job ID only (`J1526`), comma+space separated, no duplicates, no job names.
- Product used on a new job → append job ID to catalog job_tags AND record in Order History.

## 11. Non-products & edge cases
- Shipping/tax/tariffs/fees: omit entirely.
- Custom fabricated items: enter only if reusable/reference-worthy.
- Packages/kits: clear family (e.g. Aluminum Framing Package), known attributes only.
- Repeat purchases keep the same internal_id.

## 12. Entry workflow (summary)
1. Read receipt line (description, vendor, SKU, cost, date, unit, job).
2. Omit shipping/tax/fees. 3. Assign dept > category > subcategory.
4. Refine product_family. 5. Extract structured attributes. 6. Generate canonical_name.
7. Compare identity fields to the existing catalog. 8. Duplicate → reuse ID, update job_tags,
add history. 9. New → new ID + initial history. 10. Uncertain → flag for manual review.

> Version note: V2.1 replaces the previous standalone rules + duplicate-detection addendum and
> adds the Product Family Clarity and Refinement Rule.
