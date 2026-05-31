# ArthaNote — Claude Code Context

## PROJECT OVERVIEW
SaaS PWA + Flutter Android app for Tamil Nadu small retailers — digital shop ledger
- **Live URL:** https://arthanote.com (Vercel, CNAME → arthanote.com)
- **GitHub Repo:** selvavishnum/arthanote (main branch)
- **Firebase Project:** selva-ledger (projectId: selva-ledger)
- **Firebase API Key:** AIzaSyB5q3fFfl5aUXp8d9yb0K_qkI20vdTL2Xg
- **Admin email:** selvavishnu.m@gmail.com
- **Admin UID:** WpCQtDGJkpOXJfWntS6vu3B5HXO2

## TECH STACK

### Web PWA
- Frontend: Vanilla JS single-file HTML (no framework)
- Auth: Firebase Auth (Email/Password + Google OAuth popup)
- Database: Firestore (cache-first, localStorage backup)
- Hosting: Vercel (vercel.json rewrites, security headers)
- OCR: Gemini SDK (gemini-2.0-flash) → Claude fallback
- PWA: manifest.json + sw.js (v7, no-cache passthrough)

### Flutter Android App
- Framework: Flutter 3.22.0 / Dart ≥3.3.0
- State: Provider (`AppProvider` ChangeNotifier)
- Auth: Firebase Auth + Google Sign-In
- DB: Firestore (offline persistence, unlimited cache) + file cache
- Min SDK: Android (see build.gradle)
- Build: GitHub Actions → GitHub Releases

## REPO STRUCTURE
```
.
├── index.html          # Main PWA app (8 000+ lines, vanilla JS)
├── admin.html          # Super admin panel (1 500 lines)
├── attend.html         # QR attendance scanner (no login, 530 lines)
├── finance.html        # (referenced in QR URL; not in repo — redirect)
├── gemini-test.html    # Gemini API key tester
├── clear-cache.html    # Cache clearing utility
├── icon-gen.html       # Icon generator utility
├── icon-preview.html   # Icon preview utility
├── feature-graphic-gen.html  # Play Store feature graphic generator
├── privacy.html        # Privacy policy
├── manifest.json       # PWA manifest (name: ArthaNote, theme: #065f46)
├── sw.js               # Service Worker v7 — no-cache passthrough
├── firebase.json       # Firebase CLI config (rules + indexes)
├── firestore.rules     # Firestore security rules
├── vercel.json         # Vercel deployment (rewrites + security headers)
├── .vercelignore       # Files excluded from Vercel deploy
├── CNAME               # arthanote.com
├── .well-known/assetlinks.json  # Android app link verification
├── .github/workflows/
│   ├── build-flutter-apk.yml   # Auto-build on push to main (flutter_app/**)
│   └── build-admin-apk.yml     # Manual trigger — admin APK
└── flutter_app/
    ├── pubspec.yaml            # Version: 1.2.8+28
    ├── lib/
    │   ├── main.dart           # App entry point, Firebase init, error logging
    │   ├── main_admin.dart     # Admin app entry point (separate APK target)
    │   ├── theme.dart          # Colors, gradients, shadows
    │   ├── l10n.dart           # Tamil/English translations
    │   ├── firebase_options.dart
    │   ├── providers/
    │   │   └── app_provider.dart  # Central state (shops, txns, profile, lang)
    │   ├── models/
    │   │   ├── txn.dart
    │   │   ├── shop.dart
    │   │   ├── supplier.dart
    │   │   ├── supplier_bill.dart
    │   │   ├── fc_member.dart
    │   │   ├── fc_payment.dart
    │   │   ├── fc_chit.dart
    │   │   └── payment_reminder.dart
    │   ├── services/
    │   │   ├── auth_service.dart    # Firebase Auth + Google Sign-In
    │   │   ├── db_service.dart      # Firestore + file cache (~23h sync cycle)
    │   │   ├── fc_service.dart      # Finance & Chit Fund Firestore ops
    │   │   ├── lock_service.dart    # PIN hash + biometric (local_auth)
    │   │   ├── pattern_service.dart # Pattern lock
    │   │   ├── reminder_service.dart # Payment reminders + local notifications
    │   │   └── admin_service.dart   # Admin panel data
    │   └── screens/
    │       ├── splash_screen.dart
    │       ├── login_screen.dart
    │       ├── onboarding_screen.dart
    │       ├── home_screen.dart        # Bottom nav host
    │       ├── lock_screen.dart        # PIN/biometric gate
    │       ├── dashboard_tab.dart
    │       ├── entry_tab.dart
    │       ├── entry_screen.dart
    │       ├── ledger_tab.dart
    │       ├── suppliers_tab.dart
    │       ├── scan_tab.dart           # OCR (admin-only)
    │       ├── reports_tab.dart
    │       ├── finance_tab.dart        # Finance & Chit Fund
    │       ├── shop_detail_screen.dart
    │       ├── settings_screen.dart    # QR attendance, PIN/biometric, lang
    │       ├── reminders_screen.dart
    │       ├── reminder_detect_sheet.dart
    │       └── admin/
    │           ├── admin_app.dart
    │           ├── admin_home_screen.dart
    │           ├── admin_login_screen.dart
    │           ├── admin_dashboard_tab.dart
    │           ├── admin_activity_tab.dart
    │           ├── admin_shops_tab.dart
    │           └── admin_users_tab.dart
    └── android/
        ├── app/
        │   ├── build.gradle
        │   ├── arthanote-release.keystore  # Committed release keystore
        │   ├── google-services.json
        │   └── src/main/kotlin/com/arthanote/app/MainActivity.kt
        └── ...
```

## FIREBASE COLLECTIONS
| Collection | Purpose |
|---|---|
| `staff` | User profiles (`role`: owner/manager/cashier, `businessId`, `email`) |
| `config` | Shop config per business (`shops` object, `bizType`, `gstOn`) |
| `transactions` | Ledger entries (`businessId`, `shop`, `date`, `type`, `amount`, `desc`) |
| `suppliers` | Supplier list |
| `supplier_bills` | Supplier payment records |
| `fc_members` | Finance/chit fund members |
| `fc_payments` | Monthly collection payments |
| `fc_chits` | Chit fund groups |
| `attendance` | QR attendance records (public read/write) |

## FIRESTORE RULES (current — business-scoped)
```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    function isAdmin() {
      return request.auth != null && request.auth.uid == 'WpCQtDGJkpOXJfWntS6vu3B5HXO2';
    }

    function myBusinessId() {
      return get(/databases/$(database)/documents/staff/$(request.auth.uid)).data.businessId;
    }

    function ownsBusiness(bid) {
      return request.auth != null &&
        (request.auth.uid == bid || myBusinessId() == bid);
    }

    match /staff/{uid}       { allow read: if true; allow write: if request.auth != null; }
    match /attendance/{docId}{ allow read, write: if true; }
    match /config/{bid}      { allow read, write: if isAdmin() || ownsBusiness(bid); }

    // All business-scoped collections use resource.data.businessId for reads/updates/deletes
    // and request.resource.data.businessId for creates
    match /transactions/{d}   { ... }
    match /suppliers/{d}      { ... }
    match /supplier_bills/{d} { ... }
    match /fc_members/{d}     { ... }
    match /fc_payments/{d}    { ... }
    match /fc_chits/{d}       { ... }
  }
}
```
> **Important:** Rules are in `firestore.rules`. Deploy with `firebase deploy --only firestore:rules`. The old wildcard `allow read, write: if request.auth != null` is replaced with per-collection business-scoped rules.

## KEY ARCHITECTURE DECISIONS

### Web PWA
1. **Cache-first**: localStorage → Firestore (5-min rate limit prevents re-reading on every login)
2. **Google login**: `signInWithPopup` ONLY — `signInWithRedirect` clears Android Chrome sessionStorage
3. **OCR**: Gemini SDK via importmap (esm.run) to avoid CORS; falls back to Claude API
4. **Owner-only**: Scan tab + OCR API Keys visible only to `selvavishnu.m@gmail.com`
5. **SW v7**: No-cache passthrough — unregisters old SWs on activate, always fresh from network

### Flutter App
1. **Offline-first**: Firestore `persistenceEnabled: true` + `CACHE_SIZE_UNLIMITED` + file cache
2. **Sync cadence**: `db_service.dart` syncs from Firestore only when >23h since last sync
3. **Lock screen**: PIN hash (SHA-like) + biometric via `local_auth` — checked in `home_screen.dart` on resume
4. **Admin gate**: `ScanTab` visible only to admin UID; admin APK uses separate `main_admin.dart` entrypoint
5. **Finance tab**: Only shown when selected shop type is `finance` or `chit`
6. **Portrait lock**: App forces portrait orientation in `main.dart`

## APP FEATURES

### Web PWA (index.html)
- Landing page with pricing (Free / Pro ₹99/month via Razorpay)
- Multi-shop dashboard (all shops or single shop filter)
- Daily ledger entry (sales/expense/payment)
- OCR scan from handwritten ledger photo (admin-only)
- Supplier ledger
- MIS Reports (15+ sections)
- Staff management + QR attendance
- Finance & Chit Fund module link
- Tamil/English toggle
- Offline queue → Firestore sync
- Paywall modal (`openPaywall()` / `startProPayment()`)

### OCR System (Web)
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
- Finance/Chit → skip steps 2-3, go directly to finance module

### Finance Module (Web + Flutter)
- Tabs: Overview, Members, Collection, Chit Fund
- Collections: `fc_members`, `fc_payments`, `fc_chits`
- Features: member CRUD, monthly payment tracking, defaulter alerts, chit prize recording, CSV export

### Admin Panel (admin.html)
- Reads from: `staff` + `config` (NOT `users` collection — it doesn't exist)
- Expandable rows for users and shops
- Customer detail modal with 7-day chart
- Cache: `adm_c_users`, `adm_c_txns`

### Flutter App Screens
| Screen | Purpose |
|---|---|
| `SplashScreen` | Firebase init + auth check |
| `LoginScreen` | Email/password + Google Sign-In |
| `OnboardingScreen` | 3-step business setup |
| `LockScreen` | PIN/biometric gate (on resume) |
| `HomeScreen` | Bottom nav host: Dashboard, (Scan), Entry, Ledger, Suppliers, Reports |
| `DashboardTab` | Daily summary cards, shop filter |
| `EntryTab` / `EntryScreen` | Add sale/expense/payment |
| `LedgerTab` | Searchable transaction list |
| `SuppliersTab` | Supplier balances + bill history |
| `ScanTab` | OCR entry (admin only) |
| `ReportsTab` | Charts + P&L |
| `FinanceTab` | Members / Collection / Chit Fund (finance-type shops only) |
| `SettingsScreen` | QR attendance, PIN/biometric, language, shop config |
| `RemindersScreen` | Payment reminders with local notifications |

### Attendance System (Flutter)
- 4-punch system: **Mark IN → Take Break (REST) → Back to Work → Mark OUT**
- Direct mark from `SettingsScreen` (no QR scan needed)
- QR attendance page (`attend.html`) — no login, writes to `attendance` collection
- Permanent QR URL: `https://selvavishnum.github.io/Kannakupilai/attend.html`

### Lock / Security (Flutter)
- PIN (hashed with simple roll-hash in `lock_service.dart`)
- Biometric via `local_auth`
- Pattern lock via `pattern_service.dart`
- Activated on app resume (`WidgetsBindingObserver` in `home_screen.dart`)

### Payment Reminders (Flutter)
- Local `flutter_local_notifications` with scheduled alerts
- Auto-detect similar reminders from ledger entries
- WhatsApp share integration via `share_plus`

## FLUTTER APP VERSION (CRITICAL)
- **Current version:** `1.2.8+28` (versionName+versionCode)
- **File:** `flutter_app/pubspec.yaml` → `version:` field
- **Rule:** Every PR that changes Flutter app code MUST bump the version.
  - Increment versionCode by 1 (the number after `+`)
  - Increment versionName patch digit (e.g. 1.2.8 → 1.2.9)
  - Example: `1.2.8+28` → `1.2.9+29`
- **Play Store rejects APK/AAB uploads with a previously used versionCode.**

## CI / GITHUB ACTIONS

### `build-flutter-apk.yml`
- **Trigger:** push to `main` touching `flutter_app/**` OR `workflow_dispatch`
- **Flutter:** 3.22.0 stable, Java 17 (temurin)
- **Keystore:** `flutter_app/android/app/arthanote-release.keystore` (committed, storepass in workflow)
- **Outputs:** arm64-v8a APK, armeabi-v7a APK, AAB — uploaded as artifacts + GitHub Release tag `apk-<run_number>`

### `build-admin-apk.yml`
- **Trigger:** `workflow_dispatch` only (manual)
- **Target:** `lib/main_admin.dart` with `--dart-define=APP_ID=com.arthanote.admin`
- **Output:** `arthanote-admin-release.apk` — artifact + GitHub Release tag `admin-<run_number>`

## VERCEL DEPLOYMENT
```json
// vercel.json rewrites:
/attend  → /attend.html
/finance → /finance.html
/admin   → /admin.html
/privacy → /privacy.html

// Security headers on all routes:
X-Content-Type-Options: nosniff
X-Frame-Options: SAMEORIGIN
X-XSS-Protection: 1; mode=block

// sw.js: Cache-Control: no-cache, no-store, must-revalidate
```

## DESIGN SYSTEM
| Token | Value | Usage |
|---|---|---|
| `kPrimary` / `--primary` | `#065F46` | Deep forest green — nav, headers |
| `kSecondary` | `#059669` | Emerald — buttons, highlights |
| `kAccent` | `#D97706` | Amber gold — CTAs, Pro badge |
| `kRed` | `#DC2626` | Errors, expenses |
| `kAmber` | `#F59E0B` | Warnings |
| `kBg` | `#F3F4F6` | Background |
- Mobile-first, portrait only (Flutter)
- Bilingual: Tamil (ta) / English (en) toggle — `l10n.dart` in Flutter, `slv_lang` localStorage in web

## localStorage KEYS (Web PWA)
| Key | Purpose |
|---|---|
| `kp_me_cache` | User profile cache |
| `kp_cfg_cache` | Shop config cache |
| `kp_txs_cache` | Transactions cache |
| `kp_sups_cache` | Suppliers cache |
| `kp_bills_cache` | Bills cache |
| `kp_cache_ts` | Cache timestamp (5-min rate limit) |
| `slv_gemini_key` | Gemini API key |
| `slv_key` | Claude API key |
| `slv_gemini_on` | Gemini toggle |
| `slv_claude_on` | Claude toggle |
| `slv_onboarded` | Onboarding complete flag |
| `slv_shops` | Shops backup |
| `slv_lang` | Tamil/English preference |
| `slv_gst` | GST on/off |
| `slv_gstrate` | GST rate |

## SharedPreferences KEYS (Flutter)
| Key | Purpose |
|---|---|
| `kp_pin_hash` | Hashed PIN for lock screen |
| `kp_biometric_enabled` | Biometric lock toggle |
| `kp_crash_log` | Last 20 crash log entries |
| `kp_sync_ts_<businessId>` | Last Firestore sync timestamp |

## OWNER / ADMIN
```javascript
// Web PWA
const OWNER_EMAIL = 'selvavishnu.m@gmail.com';
// Scan tab hidden for non-owners
// OCR API Keys section hidden for non-owners
// applyOwnerPermissions() called in _finishAppSetup
```
```dart
// Flutter
const adminUid = 'WpCQtDGJkpOXJfWntS6vu3B5HXO2';
// ScanTab only shown when isAdmin (home_screen.dart)
// Admin APK: lib/main_admin.dart → admin/* screens only
```

## PRICING MODEL
- **Free:** 1 shop, basic ledger
- **Pro:** ₹99/month — unlimited shops, OCR scan, MIS reports, advanced features
- Payment: Razorpay (`startProPayment()` in index.html)
- Paywall gated: reports history, multiple shops, scan tab

## SELVA'S SHOPS (hardcoded fallback — web)
```javascript
SHOPS = {
  s1: {name:'Tulsi Thuckaly',    icon:'🥬', type:'vegetables'},
  s2: {name:'Tea Shop',          icon:'☕', type:'tea'},
  s3: {name:'Tulsi Bridal',      icon:'💍', type:'jewellery'},
  s4: {name:'Tulsi Monday market',icon:'🥬', type:'vegetables'}
}
```

## STAFF
Perinbham, Sherina, Suseela, Shubhala, Suriya, Dishan, Aswathy, Manikandan, Mohan, Gaddson, Vishnu

## KNOWN BUGS FIXED
- [x] Google login redirect → sessionStorage cleared → use popup only
- [x] obStep function missing (syntax error crashed all buttons)
- [x] Duplicate `_finishAppSetup` function (5 missing braces)
- [x] Firebase quota 85k reads → cache-first, 5-min rate limit
- [x] Gemini model not found → gemini-2.0-flash
- [x] CORS on Gemini fetch → use SDK via importmap esm.run
- [x] Image too large → compress to 1024px before OCR
- [x] Service Worker caching old code → SW v7 no-cache passthrough
- [x] Admin bypasses paywall (fixed)
- [x] Website auto-refreshes shops from Firestore on load
- [x] Real-time sync: Timestamp vs String date comparison bug
- [x] Duplicate gold highlight in live sync
- [x] Payment P&L calculation
- [x] OCR type toggle

## PENDING ITEMS
| Priority | Item |
|---|---|
| 🔴 | Firebase Blaze upgrade (quota limit — UPI method) |
| 🔴 | Gemini free key from aistudio.google.com (new project) |
| 🟡 | Razorpay live key + Pro payment flow |
| 🟡 | Google login → UID mismatch vs email UID (need account linking) |
| 🟡 | Play Store submission (via PWABuilder or Flutter APK) |
| 🟢 | Email/password login works |
| 🟢 | Finance & Chit Fund module working |
| 🟢 | 12 shop types onboarding |
| 🟢 | Flutter APK CI pipeline working |
| 🟢 | Vercel deployment live at arthanote.com |

## DEVELOPMENT NOTES
- Web app: vanilla JS, no build step — edit HTML and commit
- `index.html` is 8 000+ lines — search carefully before editing; all JS is inline
- Flutter: run `flutter pub get` then `flutter run` from `flutter_app/`
- No tests exist for either platform — verify manually
- Firebase rules: edit `firestore.rules`, then `firebase deploy --only firestore:rules`
- Do NOT change `attend.html` QR URL (`https://selvavishnum.github.io/Kannakupilai/attend.html`) — permanent QR codes are already printed/distributed
