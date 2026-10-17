cmake_minimum_required(VERSION 3.16)
# usage: build/build-updater.sh configures this once per arch and merges the apps.
project(MakeUpdater LANGUAGES OBJC)

find_package(MavericksShipyard REQUIRED)
# spec: INGREDIENTS.md "How the updater is built" -- clang22, like everything else this repo compiles
set(MAVERICKS_REQUIRE_APPLECLANG OFF)
include(Mavericks)
include(MavericksSparkle)

mavericks_resolve_version(MK_VERSION)

mavericks_add_updater_app(
  PRODUCT make
  PRODUCT_NAME "Mavericks GNU Make"
  ALLOW_GENERIC
  VERSION "${MK_VERSION}"
  LOG_PREFIX "MavMakeUpdater"
  CONFIRM_TITLE "Mavericks GNU Make updated"
  CONFIRM_BODY "GNU Make in /usr/local/mavergreen/make was updated."
  RELAUNCH_MARKER "/tmp/.mavericks-make-updater-relaunched"
)
