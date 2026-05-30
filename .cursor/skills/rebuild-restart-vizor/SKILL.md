---
name: rebuild-restart-vizor
description: Rebuild and restart the isolated Vizor macOS debug app. Use when the user asks to rebuild Vizor, restart Vizor, rerun the isolated build-vizor app, or refresh the local macOS debug app after code changes.
---

# Rebuild Restart Vizor

Use this skill to rebuild the isolated `build-vizor` macOS debug app and restart that app instance.

## Preconditions

- Use the existing `./build-vizor` script as the only build entry point.
- The isolated app identity is `com.keplr.vizor.build-vizor`.
- The built app is expected at `build/build-vizor/DerivedData/Build/Products/Debug/Vizor.app`.

## Workflow

1. Check for an existing terminal or process only if needed to avoid duplicating a long-running app command.
2. Rebuild the app:

   ```bash
   ./build-vizor
   ```

3. Restart only the isolated app:

   ```bash
   app_path="build/build-vizor/DerivedData/Build/Products/Debug/Vizor.app"
   bundle_id="com.keplr.vizor.build-vizor"

   osascript -e "tell application id \"${bundle_id}\" to quit" >/dev/null 2>&1 || true
   sleep 1
   open -n "${app_path}"
   ```

4. Report whether the build succeeded and whether the isolated app was opened.

## Safety

- Do not use `pkill Vizor` or broad process-name kills; that can terminate the regular Vizor app.
- If the isolated app does not quit promptly, report that it may still be running instead of killing unrelated processes.
- Do not modify code, commit, or push as part of this skill unless the user explicitly asks.
