# PureFacebook — tracker-free build

A build of [3elegant/PureFacebook](https://github.com/3elegant/PureFacebook) with the
**Firebase / Google tracking layer removed**.

This repository contains **no upstream source code**. It holds one patch and a CI
workflow. On every new upstream tag, CI clones that tag, applies the patch, builds,
signs, verifies, and publishes the APK.

---

## Read this before you install

This removes **Google's** tracking. It does **not** remove **Meta's**.

```
┌──────────────────────────────────────────────────────────────────┐
│  REMOVED by this build            STILL PRESENT                   │
│  ────────────────────             ─────────────                   │
│  Firebase Analytics               Meta/Facebook account tracking  │
│  Firebase Installations           WebView cookies + fingerprint   │
│  Advertising ID (AD_ID)           Login alerts / device model     │
│  Google cloud backup              Sponsored content telemetry     │
└──────────────────────────────────────────────────────────────────┘
```

The app is a WebView pointed at `m.facebook.com`. Meta sees exactly what it would see
in a browser: your IP, your session cookie, your device model, what you tap. No patch
can change that — the only way to avoid Meta's tracking is to not use Facebook.

So: **fewer third parties, not zero tracking.** That is the honest claim.

---

## What the patch changes

| File | Change |
|---|---|
| `build.gradle.kts` (root) | drops the `com.google.gms.google-services` plugin |
| `app/build.gradle.kts` | drops that plugin, Firebase BOM + Analytics deps; new `applicationId`; version comes from CI |
| `gradle/libs.versions.toml` | drops Firebase + google-services version entries |
| `MainActivity.kt` | drops the 3 Firebase imports, the analytics field, the init, and the `select_content` event |
| `AndroidManifest.xml` | `allowBackup="false"`; `AD_ID` permission explicitly removed with `tools:node="remove"` |
| `strings.xml` | app label is `PureFacebook` |
| `settings.gradle.kts` | root project name |

App id is `io.github.ihsanlabs.purefacebook`, so it installs **alongside** the original
app instead of replacing it.

### Why `allowBackup="false"` matters

```
allowBackup = true                    allowBackup = false
──────────────────                    ────────────────────
WebView cookie jar                    cookie jar stays
   │                                    on this device
   ▼
Android Auto Backup
   │
   ▼
Google Drive  ← Facebook session cookie leaves the phone
```

That was the single worst leak in the original build, and it is now closed.

---

## Install

1. Grab the newest `.apk` from [Releases](../../releases/latest).
2. Allow install from unknown sources for your browser/file manager.
3. Install. It will not overwrite the original app — different package id.

Verify the download if you want:

```bash
sha256sum -c SHA256SUMS
```

The APK is signed with a key that lives only in this repo's Actions secrets.

---

## How the automation works

```
cron 06:00 UTC  ──┐
                  ├──► latest upstream tag ──► already released? ──► stop
manual dispatch ──┘                                  │
                                                     no
                                                     ▼
                                   clone upstream at tag
                                                     │
                                   git apply --3way patches/*.patch
                                                     │
                                    fails? ──► JOB FAILS, no publish
                                                     │
                                   build → zipalign → apksigner
                                                     │
                                   verify-no-tracking.sh
                                                     │
                                    finds firebase/AD_ID? ──► JOB FAILS
                                                     │
                                                     ▼
                                   GitHub Release + SHA256SUMS
                                                     │
                                   bump update.json  [skip ci]
```

Two hard gates: **patch must apply** and **APK must be clean**. Either one failing
means nothing is published. A silent regression is the failure mode we care about most.

### Versioning

```
versionCode = upstream versionCode × 100 + build_rev
versionName = "<upstream version>-privacy"
```

Upstream `1.3` / code `4` becomes `1.3-privacy` / code `400`. Need to rebuild the same
tag after fixing the patch? Run the workflow with `build_rev=1` → code `401`, which
Android treats as an upgrade.

---

## Maintaining it when upstream changes

If a new tag breaks the patch, CI fails with `Patch failed to apply`. Fix it locally:

```bash
git clone https://github.com/3elegant/PureFacebook.git up
cd up && git checkout <new-tag>

git apply --3way ../patches/0001-remove-firebase-and-rebrand.patch
# resolve conflicts, keep the intent: no firebase, allowBackup=false, AD_ID removed

git diff > ../patches/0001-remove-firebase-and-rebrand.patch
```

Then re-run the workflow with `force` checked.

---

## Signing secrets

Four repository secrets are required. Missing keystore = the job fails on purpose
rather than shipping an unsigned APK.

| Secret | Value |
|---|---|
| `KEYSTORE_BASE64` | `base64 -w0 release.p12` |
| `KEYSTORE_PASSWORD` | keystore password |
| `KEY_ALIAS` | key alias, e.g. `purefacebook` |
| `KEY_PASSWORD` | key password |

Generate one with `./scripts/generate-keystore.sh` — needs only `openssl`.

> **Back up `release.p12` and its password.** If you lose them you cannot ship an
> update to existing installs; users would have to uninstall and reinstall.

---

## License and redistribution

The upstream repository has **no LICENSE file**. Its README describes the project as
for *personal and educational use*, which is **not** a grant to redistribute binaries.

This repository is a set of patches, not a copy of upstream code. The **APK releases
are still a redistribution** of a derivative work. Keep them private, or get the
upstream author's written permission before publishing them publicly.

Nothing here is legal advice.

---

## No warranty

Provided as-is. Not affiliated with Meta or with the upstream author. Use at your own
risk; a modified client can trip Facebook's automated abuse checks on your account.
