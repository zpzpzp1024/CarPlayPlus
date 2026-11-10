include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CarPlayPlus

CarPlayPlus_FILES = CarPlayPlus.xm CarPlayPlusAnimatedImage.m
CarPlayPlus_CFLAGS = -fobjc-arc -w
CarPlayPlus_LIBRARIES = substrate
CarPlayPlus_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore WebKit IOKit CoreTelephony CoreServices
# BackBoardServices & MediaRemote are private frameworks resolved via dlopen/

# On Linux (Theos CI) force clang to use ld64.lld for Mach-O linking and
# feed it the options clang's Darwin driver omits without an Apple toolchain.
ifneq ($(shell test -x /usr/bin/ld64.lld && echo yes),)
CarPlayPlus_LDFLAGS += -fuse-ld=/usr/bin/ld64.lld \
    -Wl,-arch,arm64 -Wl,-platform_version,ios,14.0,14.5
endif

include $(THEOS_MAKE_PATH)/tweak.mk