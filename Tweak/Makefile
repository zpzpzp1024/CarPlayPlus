include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CarPlayPlus

CarPlayPlus_FILES = CarPlayPlus.xm CarPlayPlusAnimatedImage.m
CarPlayPlus_CFLAGS = -fobjc-arc -w -I$(THEOS_PROJECT_DIR)/PrefsVendor
CarPlayPlus_LIBRARIES = substrate
CarPlayPlus_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore WebKit IOKit CoreTelephony CoreServices
CarPlayPlus_PRIVATE_FRAMEWORKS = BackBoardServices MediaRemote
CarPlayPlus_LDFLAGS = -lMobileGestalt -F/Library/Frameworks -framework Cephei

include $(THEOS_MAKE_PATH)/tweak.mk