include $(THEOS)/makefiles/common.mk

# CarPlayPlusIconsGenerator — creates invisible (fully transparent) CarPlay
# dashboard icons by duplicating bridged application bundles with a hidden
# identifier. Behavior reconstructed from the upstream `IconsGenerator` tool.
TOOL_NAME = CarPlayPlusIconsGenerator

CarPlayPlusIconsGenerator_FILES = main.m
CarPlayPlusIconsGenerator_CFLAGS = -fobjc-arc -w
CarPlayPlusIconsGenerator_FRAMEWORKS = Foundation CoreFoundation MobileCoreServices
CarPlayPlusIconsGenerator_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk

# The generator writes under /Library/CarPlayPlus and runs `/usr/bin/uicache`,
# so it must run as root even when spawned from the mobile Preferences app.
after-install::
	chmod 6755 $(THEOS_STAGING_DIR)/usr/bin/CarPlayPlusIconsGenerator