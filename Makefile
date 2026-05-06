# CalendarUpcoming — menu-bar list of upcoming calendar events.
#
# Release pipeline delegated to the shared `release.mk` from
# PerpetualBeta/jorvik-release. Xcode project, embedded Sparkle,
# dual-ship (.zip + .pkg).

BUNDLE_NAME      := CalendarUpcoming
BUNDLE_TYPE      := app
PRODUCT_NAME     := CalendarUpcoming.app
BUNDLE_ID        := cc.jorviksoftware.CalendarUpcoming
BUILD_SYSTEM     := xcode

XCODE_PROJECT    := CalendarUpcoming.xcodeproj
XCODE_SCHEME     := CalendarUpcoming

PACKAGE_TYPE     := zip
ALSO_SHIP_PKG    := true
EMBEDDED_FRAMEWORKS := Sparkle
ENTITLEMENTS     := CalendarUpcoming/CalendarUpcoming.entitlements

include ../jorvik-release/release.mk
