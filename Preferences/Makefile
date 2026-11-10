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

include $(THEOS_MAKE_PATH)/bundle.mk