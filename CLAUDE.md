# கணக்கபிள்ளை (Kanakkupillai) — Claude Code Context

## PROJECT OVERVIEW
SaaS PWA for Tamil Nadu small retailers — digital ledger app
- **Live URL:** https://selvavishnum.github.io/Kannakupilai/
- **GitHub Repo:** selvavishnum/Kannakupilai (main branch)
- **Firebase Project:** selva-ledger (projectId: selva-ledger)
- **Firebase API Key:** AIzaSyB5q3fFfl5aUXp8d9yb0K_qkI20vdTL2Xg
- **Admin email:** selvavishnu.m@gmail.com
- **Admin UID:** WpCQtDGJkpOXJfWntS6vu3B5HXO2

## TECH STACK
- Frontend: Single HTML PWA (vanilla JS, no framework)
- Auth: Firebase Auth (Email/Password + Google OAuth popup)
- Database: Firestore (cache-first, localStorage backup)
- Hosting: GitHub Pages
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
```
rules_version = '2';
service cloud.firestore { match /databases/{database}/documents {
  match /{document=**} { allow read, write: if request.auth != null; }
  match /attendance/{docId} { allow read, write: if true; }
  match /staff/{docId} { allow read: if true; allow write: if request.auth != null; }
}}
```

## KEY ARCHITECTURE DECISIONS
1. **Cache-first**: localStorage → Firestore (never read on every login)
2. **Google login**: signInWithPopup ONLY (signInWithRedirect breaks Android Chrome sessionStorage)
3. **OCR**: Gemini SDK (importmap) → no CORS issues
4. **Owner-only**: Scan tab + OCR API Keys hidden for non selvavishnu.m@gmail.com
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

## SELVA'S SHOPS (hardcoded fallback)
```javascript
SHOPS = {
  s1:{name:'Tulsi Thuckaly',icon:'🥬',type:'vegetables'},
  s2:{name:'Tea Shop',icon:'☕',type:'tea'},
  s3:{name:'Tulsi Bridal',icon:'💍',type:'jewellery'},
  s4:{name:'Tulsi Monday market',icon:'🥬',type:'vegetables'}
}
```

## OWNER PERMISSIONS
```javascript
const OWNER_EMAIL='selvavishnu.m@gmail.com';
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
Perinbham, Sherina, Suseela, Shubhala, Suriya, Dishan, Aswathy, Manikandan, Mohan, Gaddson, Vishnu

## PRICING MODEL
- Free: 1 shop, basic features
- Pro: ₹199/month — unlimited shops, OCR scan, MIS reports

## DEVELOPMENT NOTES
- App is vanilla JS — no React/Vue/Angular
- All in one HTML file (4600+ lines)
- Bilingual: Tamil + English toggle
- Mobile-first design
- Green theme: #065f46 (primary), #059669 (secondary)
