# ADR 0012: Compiled asset catalog for the app icon and launch screen

**Status:** Accepted\
**Date:** 2026-10-03

## Context

ADR 0001 bundled the iPhone icon PNGs as loose files (`CFBundleIconFiles`) and left
`UILaunchScreen` empty, so device builds did not depend on CoreSimulator, which the asset catalog
compiler needed at the time.

The redesign's white and lime icon needs the iOS 18 dark and tinted appearances, and its launch
screen needs a graphite background with the mark. Loose icon files cannot carry appearances, and
`UILaunchScreen` can name a colour and an image only from a compiled asset catalog.

On 2026-10-03, `actool` (Xcode 27) compiled the catalog on the owner's Mac while CoreSimulator was
unavailable there (`simctl` failed to load its device set). CI's macOS runners compile it as part of
`flutter build ios`.

## Decision

- The Runner target compiles `Runner/Assets.xcassets` (`ASSETCATALOG_COMPILER_APPICON_NAME =
  AppIcon`). The loose icon files and `CFBundleIconFiles` are removed. `actool` adds
  `CFBundleIconName` to the built Info.plist.
- The launch screen stays storyboard-free. `UILaunchScreen` names the `LaunchBackground` colour and
  the `LaunchImage` image from the catalog.
- `tool/render_app_icon.sh` renders every icon and launch PNG from the mark painter.
  `scripts/verify-app-bundle.sh` refuses a build whose `Assets.car` lacks the icon appearances or
  the launch artwork.

## Consequences

- Device and CI builds need a working `actool`. If a future Xcode needs CoreSimulator for it again,
  the build stops at the catalog step, and `verify-app-bundle.sh` catches any build that ships
  without the icon or launch artwork.
- iOS caches launch screens, so a changed launch screen may need the app deleted and reinstalled.
