# CarPlayPlus — a modern re-implementation of the Airaw CarPlay tweak.
# Reverse-engineered behavior targets iOS 14+ CarPlay private UI.
#
# Build (macOS/Linux with Theos):
#   make clean package FINALPACKAGE=1
#
# CI: see .github/workflows/build.yml (GitHub Actions + Theos + iOS 14.5 SDK).
# Sanity checks: python3 tools/validate_project.py

export ARCHS = arm64 arm64e
export TARGET = iphone:clang:14.5:14.0
export INSTALL_TARGET_PROCESSES = SpringBoard CarPlay
# Rootless jailbreaks (Dopamine / palera1n rootless) report iphoneos-arm64
# and install everything under /var/jb; Theos maps all layout/install paths
# and stamps the deb architecture automatically when this scheme is on.
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += Tweak Preferences IconsGenerator

include $(THEOS_MAKE_PATH)/aggregate.mk