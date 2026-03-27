# Live Icon Swap Findings

Date: 2026-03-27

## Goal

Make FloatyDo switch its app icon immediately at runtime, matching Loop, without rebuilding or relaunching.

## What Loop Actually Does

Reference repo:

- `/Users/raffichilingaryan/Developer/Loop/Loop/Icon/Icon.swift`
- `/Users/raffichilingaryan/Developer/Loop/Loop/Icon/IconManager.swift`
- `/Users/raffichilingaryan/Developer/Loop/Loop.xcodeproj/project.pbxproj`

Loop's runtime flow is simple:

1. Ship every icon as a real `.appiconset` inside `Assets.xcassets/App Icons`.
2. Persist the selected icon's asset name, for example `AppIcon-Holo`.
3. Load that same asset name at runtime with `NSImage(named:)`.
4. In `!DEBUG`, call:

   ```swift
   NSWorkspace.shared.setIcon(image, forFile: Bundle.main.bundlePath, options: [])
   ```

5. Always update the running app icon:

   ```swift
   if Defaults[.currentIcon] == Icon.default.assetName {
       NSApp.applicationIconImage = nil
   } else {
       NSApp.applicationIconImage = image
   }
   ```

Project-level details that matter:

- `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`
- no app sandbox setting was found in Loop's project file

## What FloatyDo Was Doing Before

Before the refactor attempt, FloatyDo had a hybrid pipeline:

- `.icon` bundles under `FloatyDo/FloatyDo/Icons/`
- separate preview assets for the settings UI
- a relaunch/build script path
- runtime logic that depended on a different set of preview image names

That was not equivalent to Loop's model.

## What Was Tried

I refactored FloatyDo toward the Loop model:

- created real `.appiconset` assets under `FloatyDo/FloatyDo/Assets.xcassets/App Icons`
- enabled:

  - `ASSETCATALOG_COMPILER_APPICON_NAME = "AppIcon-Theme1"`
  - `ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES`

- changed runtime preview and icon lookup to use the real app icon asset names
- replaced the relaunch-style controller with a runtime controller that:

  - persists the chosen asset name
  - loads `NSImage(named:)`
  - calls `NSWorkspace.shared.setIcon(...)`
  - updates `NSApp.applicationIconImage`

## What Was Verified

The asset bundling side is now correct.

Verified against the installed app:

- `/Applications/FloatyDo.app/Contents/Info.plist`
- `/Applications/FloatyDo.app/Contents/Resources/Assets.car`

Observed:

- `CFBundleIconFile = AppIcon-Theme1`
- `CFBundleIconName = AppIcon-Theme1`
- `Assets.car` contains:

  - `AppIcon-Theme1`
  - `AppIcon-Theme2`
  - `AppIcon-Theme3`
  - `AppIcon-Theme4`
  - `AppIcon-Theme5`
  - `AppIcon-Theme6`
  - `AppIcon-Theme7`
  - `AppIcon-Theme8`

So the remaining failure is not "assets are missing."

## The Important Difference From Loop

FloatyDo's installed Release build is sandboxed.

Confirmed from the built app's entitlements:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

Relevant project setting:

- `FloatyDo/FloatyDo.xcodeproj/project.pbxproj`
- Release:

  - `ENABLE_APP_SANDBOX = YES`

Loop does not appear to ship this runtime icon path under the same sandbox constraint.

That matters because `NSWorkspace.shared.setIcon(image, forFile: Bundle.main.bundlePath, options: [])`
is trying to mutate the app bundle's icon on disk. A sandboxed app may not be allowed to do that reliably.

## Debug vs Release

This is not mainly a "local vs TestFlight" problem.

It is:

- partly a `DEBUG` vs `RELEASE` problem
- mainly a `sandboxed` vs `unsandboxed` problem

Notes:

- Loop only calls `NSWorkspace.setIcon(...)` in `!DEBUG`
- a local Xcode Debug run is only useful for checking `NSApp.applicationIconImage`
- the real test is an installed Release build
- if the installed sandboxed Release build cannot mutate its own icon, TestFlight will not magically fix that

## Conclusion

The asset-catalog refactor was the right cleanup, but it did not solve the core issue.

The current evidence suggests:

- FloatyDo can match Loop's asset pipeline
- FloatyDo cannot assume Loop's runtime mutation behavior will work under FloatyDo's current sandboxed Release configuration

## Recommendation

Do not keep pushing on this branch as if it is one bug away from working.

If we revisit this later, the right next step is one of:

1. Build a tiny sandboxed macOS sample app that does nothing except:

   - compile multiple `.appiconset` assets
   - call `NSWorkspace.shared.setIcon(...)`
   - update `NSApp.applicationIconImage`

   This would prove whether the sandbox itself is the blocker.

2. Verify whether there is an Apple-supported runtime app icon API for sandboxed macOS apps that does not rely on mutating the app bundle.

3. If neither of the above pans out, treat immediate icon swapping as not viable for FloatyDo's shipping configuration and keep the explicit apply/relaunch workflow.

## Current Recommendation For Shipping

Do not expect an App Store or TestFlight build to make this work automatically.

If anything, those builds are the ones most likely to preserve the sandbox restriction that is currently blocking parity with Loop.
