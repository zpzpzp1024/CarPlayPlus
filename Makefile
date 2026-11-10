# CarPlayPlus — a modern re-implementation of the Airaw CarPlay tweak.
# Reverse-engineered behavior targets iOS 14+ CarPlay private UI.

export ARCHS = arm64 arm64e
export TARGET = iphone:clang:14.5:14.0
export INSTALL_TARGET_PROCESSES = SpringBoard CarPlay

include $(THEOS)/makefiles/common.mk

SUBPROJECTS += Tweak Preferences IconsGenerator

include $(THEOS_MAKE_PATH)/aggregate.mk

# After building, generate placeholder assets:
#   python3 tools/gen_assets.py