# Firebase push notifications setup

Glamea uses **Firebase Cloud Messaging (FCM)** for push notifications. FCM is
free at any scale (no per-message or per-user cost, no payment card required) —
ideal for a startup that wants to grow first. This doc covers the one-time
setup for the Flutter app and the Go backend. Skip to
[How this fits together](#how-this-fits-together) for a map of the moving parts.

> Prefer a different provider? OneSignal is a common drop-in alternative, but
> everything below is already wired for FCM and works without any backend code
> changes.

## 1. Create a Firebase project

1. Go to https://console.firebase.google.com and create a project
   (e.g. `glamea`). Firebase Console itself is free.
2. You can add the app from the project console. You need the project ID for
   the backend later.

## 2. Android

1. In the Firebase console → *Project settings* → *Your apps* → add an
   **Android** app with package name **`com.glamea.glamea`**.
2. Download **`google-services.json`** and place it at
   `android/app/google-services.json`.
3. Uncomment the Google Services plugin line in `android/app/build.gradle.kts`:
   ```kotlin
   plugins {
       // id("com.google.gms.google-services")   <-- remove the // comment
   }
   ```
   The plugin is already declared (apply false) in `android/settings.gradle.kts`,
   so no other Gradle change is needed.
4. Android 13+ requires a runtime permission. The app already requests it via
   `firebase_messaging`, and `AndroidManifest.xml` already declares
   `POST_NOTIFICATIONS`. Notifications land on the `general` channel created at
   startup by `GlameaApp.kt`.

## 3. iOS (requires a Mac with Xcode)

1. In the Firebase console, add an **iOS** app with bundle ID **`com.glamea.glamea`**.
2. Download **`GoogleService-Info.plist`** into
   `ios/Runner/` (via Xcode, add it to the Runner target — *don't* drag it into
   your source tree).
3. Enable **Push Notifications** and **Background Modes → Remote notifications**
   in the Runner Xcode target capabilities.
4. FCM notifications reach iOS devices through Apple Push Notification Service
   (APNs), which requires a (free for development) Apple Developer account.

## 4. Backend (Go)

1. In the Firebase console → *Project settings* → *Service accounts* →
   **Generate new private key**. Save the JSON, e.g.
   `secrets/glamea-firebase.json` (keep it out of git).
2. Set two env vars (or add to your `.env`):
   ```
   FCM_PROJECT_ID=your-firebase-project-id
   FCM_SERVICE_ACCOUNT_FILE=/absolute/path/to/glamea-firebase.json
   ```
3. When either value is blank, push delivery is disabled and the backend only
   writes in-app notifications — a safe dev default.

## 5. Verify

1. Build & run the app (`flutter run`). Open it once so it registers its device
   token (`device_tokens` table).
2. Start the backend with the FCM vars above.
3. From the Firebase console → *Cloud Messaging* → *Send test message*, target
   your device token and send a notification with payload
   `{"notification_type":"booking","booking_id":"<a booking id>"}`.
4. Tapping it should deep-link into the app (booking → chat → etc. via
   `deepLinkFromPushData`).

## How this fits together

- **Device registration** — `DeviceTokenController` registers the FCM token on
  every login/session restore, and re-registers automatically whenever FCM
  rotates it (`notification_service.dart` → `tokenChanges`).
- **Foreground delivery** — pushes received while the app is open surface a
  dismissible in-app banner (`ForegroundNotificationBanner`) and the in-app
  notification list stays in sync.
- **Background/killed delivery** — the system notification is shown by FCM
  itself on the `general` channel; tapping it routes the user through
  `getInitialMessage`/`onMessageOpenedApp`.
- **Re-engagement jobs** (backend, in `internal/jobs/jobs.go`) — four frequency-
  capped nudges bring users back without spamming:
  - `unread_nudges` — after `UNREAD_NUDGE_AFTER` (2h) of unread messages.
  - `pending_expiry_nudges` — pros are reminded to confirm a pending request
    `PENDING_EXPIRY_NUDGE_BEFORE` (6h) before it expires.
  - `inactive_nudges` — after `INACTIVE_NUDGE_AFTER` (7 days); the message picks
    the best reason (pending booking → unread → new favorites → discover).
  - `favorites_digest` — weekly digest, only when a liked/saved professional
    posted something new (`DIGEST_NEW_CONTENT_WINDOW`).
  Each nudge is capped in the `push_caps` table (per user + type cooldown), so a
  quiet user receives at most a couple of pushes per week.

### Tuning knobs (env vars)

| Variable | Default | Meaning |
| --- | --- | --- |
| `UNREAD_NUDGE_AFTER` | `2h` | How long a message stays unread before a nudge |
| `UNREAD_NUDGE_COOLDOWN` | `24h` | Min gap between unread nudges per user |
| `PENDING_EXPIRY_NUDGE_BEFORE` | `6h` | Nudge pros to confirm before a request expires |
| `PENDING_EXPIRY_NUDGE_COOLDOWN` | `12h` | Min gap between expiry nudges per user |
| `INACTIVE_NUDGE_AFTER` | `168h` | Send a re-engagement nudge after this much inactivity |
| `INACTIVE_NUDGE_COOLDOWN` | `168h` | Min gap between inactive nudges per user |
| `DIGEST_INTERVAL` | `168h` | How often the favorites digest may fire |
| `DIGEST_NEW_CONTENT_WINDOW` | `168h` | Digest only when new posts exist within this window |

The scheduler runs every `JOB_INTERVAL` (default `1m`).
