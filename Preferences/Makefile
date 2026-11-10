include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CarPlayPlus

CarPlayPlus_FILES = \
    CarPlayPlusRootListController.m \
    Controllers/Controllers.m \
    Cells/Cells.m
CarPlayPlus_CFLAGS = -fobjc-arc -w -I$(THEOS_PROJECT_DIR)/Preferences
CarPlayPlus_FRAMEWORKS = UIKit MessageUI
CarPlayPlus_PRIVATE_FRAMEWORKS = Preferences
CarPlayPlus_INSTALL_PATH = /Library/PreferenceBundles

# On Linux (Theos CI) force clang to use ld64.lld for Mach-O linking and
# feed it the options clang's Darwin driver omits without an Apple toolchain.
ifneq ($(shell test -x /usr/bin/ld64.lld && echo yes),)
CarPlayPlus_LDFLAGS += -fuse-ld=/usr/bin/ld64.lld \
    -Wl,-arch,arm64 -Wl,-platform_version,ios,14.0,14.5
endif

include $(THEOS_MAKE_PATH)/bundle.mk