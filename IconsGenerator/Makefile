include $(THEOS)/makefiles/common.mk

# CarPlayPlusIconsGenerator — creates invisible (fully transparent) CarPlay
# dashboard icons by duplicating bridged application bundles with a hidden
# identifier. Behavior reconstructed from the upstream `IconsGenerator` tool.
TOOL_NAME = CarPlayPlusIconsGenerator

CarPlayPlusIconsGenerator_FILES = main.m
CarPlayPlusIconsGenerator_CFLAGS = -fobjc-arc -w
CarPlayPlusIconsGenerator_FRAMEWORKS = Foundation CoreFoundation MobileCoreServices
CarPlayPlusIconsGenerator_INSTALL_PATH = /usr/bin

# On Linux (Theos CI) force clang to use ld64.lld for Mach-O linking and
# feed it the options clang's Darwin driver omits without an Apple toolchain.
ifneq ($(shell test -x /usr/bin/ld64.lld && echo yes),)
CarPlayPlusIconsGenerator_LDFLAGS += -fuse-ld=/usr/bin/ld64.lld \
    -Wl,-arch,arm64 -Wl,-platform_version,ios,14.0,14.5
endif

include $(THEOS_MAKE_PATH)/tool.mk

# The generator must run as root even when spawned from the mobile
# Preferences app; the setuid bit is applied in layout/DEBIAN/postinst
# (which covers both rootful and /var/jb rootless install paths).