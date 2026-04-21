# /deploy — Export and push to itch.io

**IMPORTANT: Always ask the user for confirmation before pushing to itch.io.**

## Steps

1. **Export web build:**
   ```
   godot --headless --export-release "Web" builds/web/index.html
   ```

2. **Get version tag** from the latest git tag, or ask user for one.

3. **Confirm with user** before pushing. Show them the tag and what's changed since last deploy.

4. **Push to itch.io:**
   ```
   ./butler-bin/butler push builds/web/ struktured/cowardly-irregular:web --userversion <tag>
   ```
   Note: `:web` is the active channel (served by itch.io). `:html5` is legacy/unused — do not push there.

5. Report success with the itch.io URL: https://struktured.itch.io/cowardly-irregular

## Input

Optional version tag as argument (e.g., `/deploy v0.21.0`). If omitted, derive from latest git tag or ask.
