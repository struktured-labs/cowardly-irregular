# Deployment platforms — measured status

Written 2026-07-30 by the deploy lane. Engine: **Godot 4.4.1**.

Every status below was **measured on this box**, not inferred from docs. Where a
platform is blocked, the blocker is the literal error string the toolchain
produced, so it can be rechecked rather than re-argued. Where something is
untested, it says so.

> The rule this document exists to prevent: an export that "succeeds" is not a
> build that runs. Godot exits 0 on an export that produced a binary which dies
> on startup. Every platform below therefore has a **boot gate** column, and a
> platform without one is not shippable no matter how clean its export log is.

---

## Summary

| Platform | Export | Boot gate | Publishable today | Blocker |
|---|---|---|---|---|
| **Linux** x86_64 | ✅ verified | ✅ native headless | ✅ yes | none — channel not yet created |
| **Web** (wasm) | ✅ shipping | ⚠️ none | ✅ live | no automated boot gate |
| **Windows** x86_64 | ✅ verified | ✅ **wine** | ✅ yes | none — channel not yet created |
| **macOS** universal | ✅ verified | ❌ impossible here | ⚠️ unsigned only | Gatekeeper; no Mac to test on |
| **Android** arm64 | ❌ blocked | ❌ no emulator | ❌ no | Android SDK absent |
| **iOS** | ❌ impossible | ❌ | ❌ no | requires macOS + Xcode |

---

## Linux — DONE

`tools/deploy_linux.sh` (verified end-to-end, gates 0–4).

- Binary: `build/linux/cowardly-irregular.x86_64`, **295 MiB**
- Boot gate: runs the exported binary `--headless --quit`, asserts `[GAME] Started`
- Templates: all arches present (x86_64/x86_32/arm64/arm32) — only x86_64 has a preset
- **itch channel `linux` does not exist yet.** Creating it is a publish, and publishing
  needs struktured's explicit per-deploy approval. `tools/deploy_linux.sh --publish <ver>`

**arm64 Linux** is one preset away (template installed) but has no boot gate on this
box — an x86_64 machine cannot run an arm64 binary without emulation. Do not ship it
untested; an unbootable arm64 build is worse than no arm64 build.

## Windows — BUILT AND BOOTED, not yet wired to a publish script

- Preset added: `[preset.2] "Windows Desktop"`, x86_64, embedded pck
- Binary: `build/windows/cowardly-irregular.exe`, **322 MiB**, verified `PE32+ ... x86-64`
- **Boot gate: wine 10.0.** `wine cowardly-irregular.exe --headless --quit` reaches
  `[GAME] Started` with **0 script errors**. This is the same assertion the Linux gate
  makes, so Windows is not a blind ship.
- `application/modify_resources=false` — **rcedit is absent**, and with it `true` the
  export emits `Could not start rcedit executable` and silently produces **no icon and
  no version metadata**. Turning the flag off makes the omission honest rather than
  warned-about-and-ignored.

**To get icon + version metadata:** install rcedit and set `export/windows/rcedit` in
editor settings; it is a Windows exe, so on Linux Godot invokes it through wine (already
present). Then flip `modify_resources` back to `true`. Cosmetic, not blocking.

**Code signing:** unsigned. Windows SmartScreen will warn on download. An OV/EV
code-signing certificate costs real money per year and is not worth it for an alpha;
`osslsigncode` is the Linux-side tool if that changes.

**Remaining work:** `tools/deploy_windows.sh`, mirroring the Linux gates with wine as
the boot gate. See "Script consolidation" below — do not fork the gates.

## Web — SHIPPING, with one real gap

Live at `struktured/cowardly-irregular:web`, currently `v3.33.203-alpha`.

- **No boot gate.** Linux and Windows both prove the artifact starts; web ships on
  export success alone. A browser build cannot be run headless the way a desktop
  binary can, but it is not unfixable — a headless-Chrome harness loading the export
  and waiting for a canvas frame or a JS console marker would close it.
- 200 MB is itch's **HTML5 embed cap**, per file, not a game-size limit. This is why
  audio is the pressure valve (`tools/make_web_audio.sh`), and why art is never cut:
  the artist reviews sprites on the web build.
- **Two dead channels are publicly visible:** `html5` and `html5-v2`, both stuck at
  `v2.2.4-alpha` while `web` is on v3.33.203. Anyone clicking those plays a build
  from many versions ago. Hiding them is a dashboard action, struktured's call.

## macOS — exportable, but honestly a demo-only path

- Preset added: `[preset.3] "macOS"`.
- **`macos.zip` contains only `.universal` binaries** (verified by listing the
  template archive) — there is no x86_64-only template, so "just build Intel to dodge
  the ETC2 requirement" does not exist as an option.
- Universal/arm64 therefore requires `textures/vram_compression/import_etc2_astc=true`,
  now set in `project.godot`. Exact error before the change:
  `Cannot export for universal or arm64 if ETC2 ASTC texture format is disabled.`
- **Export verified:** `build/macos/cowardly-irregular.zip`, **272 MiB**, containing
  `Cowardly Irregular.app/Contents/{Info.plist,MacOS/…}` with Mach-O fat magic
  `cafebabe`. It is a real universal bundle, not a stub.

**Cost of that flag: none. Measured, after I had written down a cost that was wrong.**

I first recorded "449 textures reimport, every worktree pays." Then checked, because
`.godot` had not grown:

```
compress/mode across all 745 texture .import files:   745 x  mode=0  (lossless)
astc artifacts in .godot/imported:                      0
.godot before flag: 224 MiB      after reimport: 224 MiB
```

**Every texture in the project is imported lossless, so VRAM compression — ETC2, ASTC,
S3TC alike — never applies to any of them.** The flag satisfies Godot's export-time
config check and changes nothing on disk. That is also the correct setting for pixel
art, which block compression would visibly wreck; nobody should "fix" mode=0.

The reason the wrong number was plausible: 449 png/jpg files exist, the flag genuinely
is project-wide, and a reimport genuinely would be expensive **if** the textures were
VRAM-compressed. Every step was right except checking whether the premise held.

Same flag also satisfies **Android**'s check, so it unblocks both — still for free.

**Why it is demo-only regardless of whether it builds:**

1. **Unsigned and un-notarized.** Modern macOS refuses to launch it normally —
   the user must right-click → Open, or clear the quarantine attribute. Fixing this
   needs an Apple Developer account (~$99/yr) plus notarization; `rcodesign` can do it
   from Linux, but the account is the gate, not the tool.
2. **No boot gate is possible here.** There is no Mac and no legal way to emulate one.
   Every other platform in this document is proven to start; macOS would ship on
   "the export succeeded", which this project has already been burned by.

**Recommendation:** build it, hand the zip to someone with a Mac, get a human "it
launched" before ever creating an itch channel for it.

## Android — blocked on the SDK, cleanly

- Preset added: `[preset.4] "Android"`, prebuilt template (`use_gradle_build=false`).
- **Debug keystore generated** at `~/.local/share/godot/keystores/debug.keystore`
  (standard non-secret debug key, password `android`). Editor settings previously
  pointed at `/home/struktured/snap/code/217/.local/share/godot/keystores/debug.keystore`,
  a **dead VS Code snap path** — repointed, along with `java_sdk_path` → JDK 17.
- JDK 17 and 21 are both installed. Java is not the blocker.

**The blocker, verbatim:**

```
Invalid Android SDK path in Editor Settings. Missing 'platform-tools' directory!
Unable to find Android SDK platform-tools' adb command.
Invalid Android SDK path in Editor Settings. Missing 'build-tools' directory!
Unable to find Android SDK build-tools' apksigner command.
```

`adb`, `apksigner`, `zipalign`, `gradle` are all absent. Godot signs the APK with
`apksigner` even for a template (non-gradle) export, so the SDK is required even
though we are not doing a custom build.

**To unblock — needs struktured, because it means accepting Google's SDK licence:**

```bash
# ~150 MB+ download; the licence prompt is why this is not automated
mkdir -p ~/Android/Sdk/cmdline-tools && cd ~/Android/Sdk/cmdline-tools
# fetch commandlinetools-linux-*.zip from developer.android.com, unzip as 'latest'
yes | latest/bin/sdkmanager --sdk_root=$HOME/Android/Sdk --licenses
latest/bin/sdkmanager --sdk_root=$HOME/Android/Sdk \
    "platform-tools" "build-tools;34.0.0" "platforms;android-34"
# then set export/android/android_sdk_path in editor settings
```

**Beyond the SDK, still open for Android:**
- **Release signing.** The debug keystore is fine for sideloading and for itch, but a
  Play Store upload needs a real release keystore whose loss is unrecoverable. That is
  a secret — it belongs in `setenv.sh` (gitignored), never in the repo.
- **Touch controls.** This is a keyboard/mouse RPG. There is no evidence it has a touch
  input path, and an APK that installs but cannot be played is not a deliverable. This
  is a gameplay question, not a packaging one, and it is the real reason Android is
  third rather than second.
- **No boot gate.** No emulator installed; `adb` would be needed even to smoke-test on
  a physical device.

## iOS — not possible from this machine

`ios.zip` template is installed, which is misleading. iOS requires Xcode and a macOS
host to compile and sign; `xcrun` and `codesign` are both absent and cannot be
installed on Linux. There is no partial version of this. Not a backlog item — a
hardware prerequisite.

---

## Other distribution channels (not engine targets)

These are ways to *ship* the Linux/Windows builds that already work, not new exports:

- **Steam** — needs `steamcmd` + a Steam partner account ($100 per app). Would consume
  the same Linux/Windows binaries. Real audience, real money, real review process.
- **Flatpak** — the sane Linux distribution format; the binary is already
  self-contained, so the manifest is small. Good fit given Linux is first-class here.
- **AppImage** — single-file, no install. Cheapest possible "send a friend a link"
  for Linux, and closest in spirit to how web is used today.
- **GitHub Releases** — already wired in `.github/workflows/build.yml`, Linux only,
  fires on `v*` tags. Adding Windows to that workflow is straightforward now that the
  preset exists and cross-export from Linux is proven.

---

## Script consolidation — do this before adding the third platform

`tools/deploy_linux.sh` is 267 lines and gates 0/0b/1/2/3/4 are almost entirely
platform-independent. Gate 0b alone has had **four** correctness fixes (overwrite
coverage, a duplicate `trap` that silently disarmed the drift report, one-sided
enumeration blind to file creation, and a partial-snapshot control). Every one of
those would have to be re-fixed in a copy.

**So: `tools/deploy_windows.sh` must not be a copy of `deploy_linux.sh`.** Extract the
gates into `tools/deploy_desktop.sh <platform>` and make both entry points thin
wrappers, so the next platform is a table entry rather than a fork.

Per-platform, the only things that actually differ:

| | Linux | Windows | macOS |
|---|---|---|---|
| preset | `Linux` | `Windows Desktop` | `macOS` |
| artifact | `.x86_64` | `.exe` | `.zip` |
| boot gate | native | `wine` | **none possible** |
| itch channel | `linux` | `windows` | `osx` |

---

## What needs struktured

1. **Create the `linux` and `windows` itch channels?** Both builds are verified. This
   is a publish, so it needs explicit approval.
2. **Android SDK licence acceptance** — a human accepting Google's terms.
3. **Web audio bitrate: 64 vs 48 kbps.** 64k fits today (~176 MiB projected) but goes
   over with the ~48 queued monster themes; 48k fits both (~142 / ~179 MiB).
4. **The two stale `html5` channels** showing v2.2.4-alpha to anyone who clicks them.
5. **Does the game have any touch input path?** Decides whether Android is a real
   target or a build that installs and cannot be played.
