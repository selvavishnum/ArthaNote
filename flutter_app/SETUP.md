# ArthaNote Flutter App — Setup Guide

## One-time Firebase Setup (required before first build)

### Step 1: Add Android app in Firebase Console
1. Go to console.firebase.google.com → Project: selva-ledger
2. Click "Add app" → Android
3. Package name: `com.arthanote.app`
4. Download `google-services.json`
5. Place it at: `flutter_app/android/app/google-services.json`

### Step 2: Add GitHub Secret
1. GitHub → Settings → Secrets → Actions → New secret
2. Name: `GOOGLE_SERVICES_JSON`
3. Value: paste the entire contents of google-services.json

### Step 3: Enable Google Sign-In in Firebase
1. Firebase Console → Authentication → Sign-in method
2. Enable Google → save
3. Add SHA-1 fingerprint (from Play Console or debug keystore)

## Build APK Automatically
Push to `main` branch → GitHub Actions builds APK automatically.
Download from: GitHub → Releases → latest release.

## Local Development
```bash
cd flutter_app
flutter pub get
flutter run
```
