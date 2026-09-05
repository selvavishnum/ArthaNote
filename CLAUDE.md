# கணக்கபிள்ளை (Kanakkupillai) — Claude Code Context

> ⚠️ **This repository is public. Do not put personal or account details in
> this file.** No owner email addresses, no Firebase Auth UIDs, no API keys,
> no real staff/customer names. This file is indexed by search engines and
> read by AI assistants, so anything written here is effectively published.
> The live values all exist in the code already — read them from there:
> the Firebase web config is in `index.html`, the admin allowlist is in
> `admin.html` (`ADMIN_EMAILS`), and the admin UID is in `firestore.rules`
> (`isAdmin()`). Referring to them by location keeps this doc useful without
> restating them.

## PROJECT OVERVIEW
SaaS PWA for Tamil Nadu small retailers — digital ledger app
- **Live URL:** https://arthanote.com/
- **GitHub Repo:** selvavishnum/ArthaNote (main branch)
- **Firebase project / web API key:** see the `firebaseConfig` block in
  `index.html`. (A Firebase *web* API key is a public client identifier by
  design, not a secret — Firestore security rules are the real boundary.)
- **Admin account:** the allowlist is `ADMIN_EMAILS` in `admin.html`; the
  matching UID is hardcoded in `isAdmin()` in `firestore.rules`. Both must
  refer to the same account.

## TECH STACK
- Frontend: Single HTML PWA (vanilla JS, no framework)
- Auth: Firebase Auth (Email/Password + Google OAuth popup)
- Database: Firestore (cache-first, localStorage backup)
- Hosting: Vercel (arthanote.com). GitHub Pages is no longer used.
- OCR: Gemini SDK (gemini-2.0-flash) → Claude fallback
- PWA: manifest.json + sw.js (v7, no-cache passthrough)

## REPO FILES
- `index.html` — main app (was app.html)
- `admin.html` — super admin panel
- `attend.html` — QR attendance (no login)
- `finance.html` — Finance & Chit Fund module
- `gemini-test.html` — Gemini API key tester
- `clear-cache.html` — cache clearing utility
- `manifest.json`, `sw.js`, `icon-192.png`, `icon-512.png`

## FIREBASE COLLECTIONS
- `staff` — user profiles (role: owner/manager/cashier)
- `config` — shop config, shops object, bizType, gstOn
- `transactions` — ledger entries (businessId, shop, date, type, amount, desc)
- `suppliers` — supplier list
- `supplier_bills` — supplier payments
- `fc_members` — finance module members
- `fc_payments` — monthly collection payments
- `fc_chits` — chit fund groups
- `attendance` — QR attendance records

## FIRESTORE RULES
**Source of truth: `firestore.rules` (repo root).** Deployed via `firebase deploy
--only firestore:rules` or pasted in Firebase Console → Firestore → Rules. GitHub
Pages does NOT deploy rules — after editing the file you must deploy separately.

Rules are **businessId-scoped** (NOT the old `if request.auth != null` free-for-all):
- Helpers: `isAdmin()` (admin UID hardcoded), `myBusinessId()` (reads own staff
  doc), `ownsBusiness(bid)` = `auth.uid == bid || myBusinessId() == bid`.
- Every business collection — `config`, `transactions`, `suppliers`,
  `sup_bills`/`supplier_bills`, `stock_items`, `stock_moves`, `fc_members`,
  `fc_payments`, `fc_chits`, `construction_projects`, `construction_entries`,
  `audit` — gates read/update/delete on `ownsBusiness(resource.data.businessId)`
  and create on `ownsBusiness(request.resource.data.businessId)`. One business
  CANNOT read or write another business's data.
- `staff`: **read is public** (`if true`) — required because `attend.html` (QR,
  no login) lists staff by businessId; write is locked so nobody can overwrite
  another user's `businessId`/`uid` (the fields that grant data access).
- `attendance`: **read+write public** (`if true`) — QR page has no login.
- `promo_codes`: read if authed; redeem-update limited to `usedCount`/`usedBy`;
  create/delete admin-only.
- `deletion_requests`/`deleted_accounts`/`billing_anomalies`: admin-gated reads.

⚠️ Known limitation (pending item): a Google-linked account gets a new auth UID
whose profile lives on the original staff doc via `altUids` — `myBusinessId()`
looks up `staff/{newUid}` which doesn't exist, so a linked user can be denied.
Tied to the "link accounts" pending item below.

## KEY ARCHITECTURE DECISIONS
1. **Cache-first**: localStorage → Firestore (never read on every login)
2. **Google login**: signInWithPopup ONLY (signInWithRedirect breaks Android Chrome sessionStorage)
3. **OCR**: Gemini SDK (importmap) → no CORS issues
4. **Owner-only**: Scan tab + OCR API Keys hidden for anyone who is not the
   owner account (see `OWNER_EMAIL` in `index.html`)
5. **SW v7**: No-cache passthrough (unregisters old SWs on load)

## APP FEATURES
### Main App (index.html)
- Multi-shop dashboard (all shops or single shop filter)
- Daily ledger entry (sales/expense/payment)
- OCR scan from handwritten ledger photo
- Supplier ledger
- MIS Reports (15 sections)
- Staff management + QR attendance
- Finance & Chit Fund module link
- Tamil/English toggle
- Offline queue → Firestore sync

### OCR System
```javascript
const API_CONFIG = {
  get geminiKey(){ return localStorage.getItem('slv_gemini_key')||''; },
  get claudeKey(){ return localStorage.getItem('slv_key')||''; },
  get geminiOn(){ return localStorage.getItem('slv_gemini_on')!=='false'; },
  get claudeOn(){ return localStorage.getItem('slv_claude_on')!=='false'; },
}
// Flow: callGeminiOCR() → if QUOTA_EXCEEDED → callClaudeOCR()
// Image compressed to 1024px, 0.75 quality before sending
```

### Onboarding (3 steps)
1. Business type (12 types: vegetables/grocery/tea/bakery/textile/hardware/jewellery/medical/hotel/finance/chit/other)
2. Shop name
3. GST option
- Finance/Chit → skip steps 2-3, go directly to finance.html

### Finance Module (finance.html)
- Tabs: Overview, Members, Collection, Chit Fund, Reports
- Collections: fc_members, fc_payments, fc_chits
- Features: member CRUD, monthly payment tracking, defaulter alerts, chit prize recording, CSV export

### Admin Panel (admin.html)
- Reads from: staff + config (NOT users collection — it's empty)
- Expandable rows for users and shops
- Customer detail modal with 7-day chart
- Cache system: adm_c_users, adm_c_txns

## CRITICAL BUGS FIXED
- [x] Google login redirect → sessionStorage cleared → use popup only
- [x] obStep function missing (syntax error crashed all buttons)
- [x] Duplicate _finishAppSetup function (5 missing braces)
- [x] Firebase quota 85k reads → cache-first, rate limit 5min
- [x] Gemini model not found → gemini-2.0-flash
- [x] CORS on Gemini fetch → use SDK via importmap esm.run
- [x] Image too large → compress to 1024px before OCR
- [x] Service Worker caching old code → SW v7 no-cache

## FLUTTER APP VERSION (IMPORTANT)
- **Current version:** `1.0.5+5` (versionName+versionCode)
- **File:** `flutter_app/pubspec.yaml` → `version:` field
- **Rule:** Every PR that changes Flutter app code MUST bump the version.
  - Increment versionCode by 1 (the number after `+`)
  - Increment versionName patch digit (e.g. 1.0.5 → 1.0.6)
  - Example: `1.0.5+5` → `1.0.6+6`
- Play Store rejects APK/AAB uploads with a previously used versionCode.
- **⚠️ ALWAYS ASK PERMISSION before bumping the version.** Do NOT auto-bump.
  Show the proposed version change (e.g. `1.3.5+35 → 1.3.6+36`) and wait
  for explicit confirmation from the user before editing `pubspec.yaml`.

## PENDING ITEMS
| Priority | Item |
|---|---|
| 🔴 | Firebase Blaze upgrade (quota limit — UPI method) |
| 🔴 | Gemini free key from aistudio.google.com NEW project |
| 🟡 | Razorpay ₹199/month Pro payment |
| 🟡 | Google login → creates new UID vs email UID (need to link accounts) |
| 🟡 | Play Store via PWABuilder |
| 🟢 | Login email/password works |
| 🟢 | Finance module working |
| 🟢 | 12 shop types onboarding |

## OWNER SHOPS (hardcoded fallback)
The owner account has a hardcoded `SHOPS` fallback in `index.html` (4 shops,
keyed `s1`–`s4`, each `{name, icon, type}`) used when the Firestore `config`
doc has not loaded yet. Read the real values from `index.html`; they are not
duplicated here because they name a real business.

## OWNER PERMISSIONS
```javascript
// OWNER_EMAIL is defined in index.html — see that file for the value.
// Scan tab hidden for non-owners
// OCR API Keys section hidden for non-owners
// applyOwnerPermissions() called in _finishAppSetup
```

## localStorage KEYS
- `kp_me_cache` — user profile cache
- `kp_cfg_cache` — shop config cache  
- `kp_txs_cache` — transactions cache
- `kp_sups_cache` — suppliers cache
- `kp_bills_cache` — bills cache
- `kp_cache_ts` — cache timestamp
- `slv_gemini_key` — Gemini API key
- `slv_key` — Claude API key
- `slv_gemini_on` — Gemini toggle
- `slv_claude_on` — Claude toggle
- `slv_onboarded` — onboarding complete flag
- `slv_shops` — shops backup
- `slv_lang` — Tamil/English
- `slv_gst` — GST on/off
- `slv_gstrate` — GST rate

## STAFF
Staff are real employees, so their names are not listed here — this file is
public. They live in the Firestore `staff` collection (~11 records for the
owner business) and are managed in-app under Staff management.

## PRICING MODEL
- Free: 1 shop, basic features
- Pro: ₹199/month — unlimited shops, OCR scan, MIS reports

## DEVELOPMENT NOTES
- App is vanilla JS — no React/Vue/Angular
- All in one HTML file (4600+ lines)
- Bilingual: Tamil + English toggle
- Mobile-first design
- Green theme: #065f46 (primary), #059669 (secondary)
