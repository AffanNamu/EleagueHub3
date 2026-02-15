# Marketplace (Firebase + Cloudinary) — Full Implementation Guide (From 0)

This document explains, end-to-end, what was implemented in your Flutter app to add an **Affiliate Marketplace** feature with:

- Firestore-backed products collection (`marketplace_products`)
- Cloudinary-hosted images (NO Firebase Storage)
- Super-admin-only product uploads (UI + Firestore Rules enforcement)
- User marketplace browsing + product details + external “Buy Now” redirect
- Google Play policy safety: affiliate disclosure + no auto-redirects

Everything is implemented to avoid breaking existing app features (leagues, live, profile, etc.) and to match your existing architecture patterns (Glass UI, GoRouter, FirebaseAuth sign-in gating).

---

## 0) What You Started With (Baseline)

You already had:

- Firebase Authentication working
- Firestore rules already configured
- Existing profile screen, home tabs, leagues/live features
- A “Glass” UI system and `GlassScaffold`
- Cloudinary usage already in Profile for avatar upload (via raw HTTP), meaning Cloudinary was already an accepted dependency/pattern in your app

This Marketplace is added as an additional feature module without altering existing flows.

---

## 1) Firestore Data Model (Required Structure)

### Collection
`marketplace_products`

### Document ID
We generate `doc.id` and store it as `productId` inside the document.

### Fields stored (exact):
- `productId` (string)
- `name` (string)
- `price` (string)
- `description` (string)
- `imageUrl` (string)  ← Cloudinary `secure_url`
- `affiliateUrl` (string)
- `category` (string)
- `sellerName` (string)
- `createdAt` (timestamp)
- `createdBy` (string) ← super admin UID

---

## 2) Security: Firestore Rules (READ for users, CREATE only for super admin)

### What we did
We added a new rules block:

`match /marketplace_products/{productId}` with:

- `allow get, list: if signedIn();`
- `allow create:` only if:
  - signed in
  - `request.auth.uid` == your super admin UID (`a0JDUelQW3TEyoXTm4ESuGi7ndq1`)
  - `createdBy` equals the uploader uid
  - document contains all required keys
  - `createdAt` is a `timestamp`
  - `productId` matches the document id (`productId == productId` path variable)

- `allow update, delete: if false;`

### Important implication
Your rules check:
```js
(request.resource.data.createdAt is timestamp)
```

That means the client must send an actual timestamp value (NOT serverTimestamp).

So the Flutter repository writes:
```dart
'createdAt': Timestamp.fromDate(now),
```

This was corrected explicitly to satisfy rules.

---

## 3) Cloudinary Image Upload (NO Firebase Storage)

### Requirement
Use Cloudinary for product image uploads.

### What we implemented
We created a Cloudinary service:

- `lib/features/marketplace/data/cloudinary_upload_service.dart`

It uses `cloudinary_public` to upload images.

### How upload works
The Admin upload screen picks an image using `image_picker`, then uploads via:

```dart
CloudinaryFile.fromFile(path, folder: 'eleaguehub/marketplace_products')
```

Then we store:
- `secureUrl` returned by Cloudinary → saved into Firestore as `imageUrl`

### Configuration
The Cloudinary service reads:

- `CLOUDINARY_CLOUD_NAME`
- `CLOUDINARY_UNSIGNED_UPLOAD_PRESET`

from Dart defines:

- `--dart-define=CLOUDINARY_CLOUD_NAME=...`
- `--dart-define=CLOUDINARY_UNSIGNED_UPLOAD_PRESET=...`

These must be set in your build pipeline (local run configs / CI / Codemagic / GitHub Actions).

---

## 4) Marketplace Domain Model

### File created
`lib/features/marketplace/domain/marketplace_product_model.dart`

### Purpose
- Strong typed data structure
- Firestore snapshot parsing
- `Timestamp` → `DateTime` conversion
- Defensive parsing when fields are missing or incorrectly typed

---

## 5) Marketplace Repository (Firestore access layer)

### File created
`lib/features/marketplace/data/marketplace_repository.dart`

### What it provides
1) Watch products list:
```dart
watchProducts(category: ..., limit: ...)
```
- Uses `StreamBuilder` friendly stream
- Uses `orderBy('createdAt', descending: true)`
- Optional category filter:
  - `where('category', isEqualTo: cat)`
  - This may trigger a Firestore index requirement (Firestore will tell you in console with a direct link).

2) Watch single product by id:
```dart
watchProductById(productId)
```

3) Create product (super admin only):
```dart
createProduct(...)
```
- Writes all required fields
- Ensures `createdAt` is a client timestamp to satisfy your rules.

---

## 6) Admin Upload Screen (Super Admin Only)

### File created
`lib/features/marketplace/presentation/admin_marketplace_upload_screen.dart`

### Access control
- In UI: checks current UID from FirebaseAuth
- If UID != super admin UID → shows “Access Denied”
- Additionally, Firestore Rules also block unauthorized creates

### Screen includes
- Image picker (gallery) using `image_picker`
- Fields:
  - Product Name
  - Price
  - Description
  - Affiliate Link
  - Category dropdown
  - Seller Name
- Upload button:
  - Uploads image to Cloudinary
  - Saves product document to Firestore

### Validations
- All fields required
- Affiliate URL must start with `http://` or `https://`
- Image size limit enforced in memory (~8MB)

---

## 7) Marketplace User Screen (Browse + Affiliate Disclosure)

### File created
`lib/features/marketplace/presentation/marketplace_screen.dart`

### Requirements met
- Uses `StreamBuilder` (real-time)
- Uses `CachedNetworkImage` for Cloudinary URLs
- Loading states (spinner)
- Error states (glass error card)
- Empty states (“No products yet”)
- Category row (All/Gamepads/Jerseys/Boots/Accessories)
- Product cards show:
  - image
  - name
  - price
  - seller

### Google Play compliance
- Includes affiliate disclosure card:
  “This marketplace contains affiliate products. We may earn commission from purchases.”
- No auto redirect; user must click “BUY NOW” and confirm.

---

## 8) Product Details Screen (Buy Now → External Browser Only)

### File created
`lib/features/marketplace/presentation/product_details_screen.dart`

### Features
- Loads product by id (stream)
- Shows:
  - large image
  - name
  - price
  - seller
  - description
- “BUY NOW” button:
  - shows confirmation dialog:
    “You are being redirected to partner store”
  - uses `url_launcher` with:
    `LaunchMode.externalApplication` (external browser only)

---

## 9) Profile Integration (Super Admin sees Marketplace Upload)

### File modified
`lib/features/profile/presentation/profile_screen.dart`

### What changed
- Added import:
  `AdminMarketplaceUploadScreen`
- Added super admin UID constant
- Added “Marketplace Upload” card inside the Admin section:
  - visible ONLY when current UID matches super admin uid
  - opens the upload screen

This does not affect existing pricing admin logic or other profile features.

---

## 10) App Router Integration (GoRouter)

### File modified
`lib/core/routing/app_router.dart`

### What changed
- Added routes:
  - `/marketplace` → `MarketplaceScreen`
  - `/admin/marketplace-upload` → `AdminMarketplaceUploadScreen`

### Access control
- Router redirect blocks `/admin/marketplace-upload` unless UID == super admin UID
- Users can open `/marketplace` as signed-in users (your rules also require signed in for reads)

This avoids accidental exposure of the admin upload route.

---

## 11) Home Tab Integration (Already Present)

Your `HomeShell` already includes a Marketplace tab via:

- `MarketplaceListScreen()` → wrapper around `MarketplaceScreen`

So Marketplace was already visible in the main navigation tabs; the router route is an additional safe entry point.

---

## 12) Dependencies (pubspec.yaml)

### File modified
`pubspec.yaml`

### Added / ensured dependencies
- `cloudinary_public` (Cloudinary SDK)
- `cached_network_image` (image caching)
- `url_launcher` (external browser redirect)
- `image_picker` already existed and is used for admin upload

---

## 13) Known Constraints / Notes

### A) Firestore indexing
If you filter by `category` AND order by `createdAt`, Firestore might require an index.
If Firestore throws an index error, it will provide a console link to create it.

### B) Web support
`image_picker` behavior differs on web; the admin upload flow is primarily for mobile. If you need web admin upload, we can add a web-safe upload path (or use file_picker + multipart upload), but that’s not what we shipped here.

### C) Cloudinary unsigned uploads
Unsigned upload presets must be configured securely in Cloudinary dashboard:
- restrict allowed folder
- restrict allowed formats
- consider upload limits

(You also have a Cloudflare Worker in your repo that can issue Cloudinary signed parameters, but the marketplace upload flow currently uses unsigned preset as per your requirement.)

---

## 14) How To Run / Verify (Local)

### 1) Configure dart defines
Example:
```bash
flutter run \
  --dart-define=CLOUDINARY_CLOUD_NAME=YOUR_CLOUD_NAME \
  --dart-define=CLOUDINARY_UNSIGNED_UPLOAD_PRESET=YOUR_UNSIGNED_PRESET
```

### 2) Validate
```bash
flutter pub get
flutter analyze
flutter test
```

### 3) Test flows
- Sign in as normal user:
  - open Marketplace tab
  - open product details
  - click BUY NOW → confirm → opens external browser
- Sign in as super admin UID:
  - open Profile → Admin → Marketplace Upload
  - select image
  - fill fields
  - upload → verify Firestore doc created with `imageUrl` from Cloudinary

---

## 15) GitHub / CI (What to do next)

Once all local checks pass:

```bash
git status
git add -A
git commit -m "Add Marketplace (Firestore + Cloudinary) with admin upload"
git push
```

Then let GitHub Actions run your existing workflow (build/analyze/tests).

---

## 16) Files Added / Modified Summary

### Created
- `lib/features/marketplace/domain/marketplace_product_model.dart`
- `lib/features/marketplace/data/marketplace_repository.dart`
- `lib/features/marketplace/data/cloudinary_upload_service.dart`
- `lib/features/marketplace/presentation/admin_marketplace_upload_screen.dart`
- `lib/features/marketplace/presentation/marketplace_screen.dart`
- `lib/features/marketplace/presentation/product_details_screen.dart`

(Optionally present wrappers in your repo)
- `lib/features/marketplace/presentation/marketplace_list_screen.dart`
- `lib/features/marketplace/presentation/listing_detail_screen.dart` (bridges old listing id to product details)

### Modified
- `lib/features/profile/presentation/profile_screen.dart`
- `lib/core/routing/app_router.dart`
- `pubspec.yaml`
- `firestore.rules`

