include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CarPlayPlus

CarPlayPlus_FILES = \
    CarPlayPlusRootListController.m \
    Controllers/Controllers.m \
    Cells/Cells.m
CarPlayPlus_CFLAGS = -fobjc-arc -w -I$(THEOS_PROJECT_DIR)/PrefsVendor
CarPlayPlus_FRAMEWORKS = UIKit MessageUI
CarPlayPlus_PRIVATE_FRAMEWORKS = Preferences
CarPlayPlus_LDFLAGS = -F/Library/Frameworks -framework Cephei -framework CepheiPrefs
CarPlayPlus_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk