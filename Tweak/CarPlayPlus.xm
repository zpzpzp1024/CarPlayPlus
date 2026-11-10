//
//  CarPlayPlus.xm
//  CarPlayPlus — modern re-implementation of the "Airaw" CarPlay tweak.
//
//  Behavioral reconstruction is based on public/observed artifacts and is
//  written from scratch. Hooks target CarPlay private UI on iOS 14+; every
//  private-class touch point is resolved at runtime so the tweak degrades
//  gracefully when a class is missing on a given iOS version.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <WebKit/WebKit.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import <sys/utsname.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <sys/sockaddr.h>
#import <net/if.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <notify.h>
#if __has_include(<IOKit/IOKitLib.h>)
#import <IOKit/IOKitLib.h>
#else
// Some stripped iOS SDKs ship IOKit.framework (linkable .tbd) without headers.
// Declare the few symbols used for battery info instead.
#include <CoreFoundation/CoreFoundation.h>
typedef unsigned int io_object_t;
typedef io_object_t io_registry_entry_t;
typedef io_object_t io_service_t;
extern "C" {
CFMutableDictionaryRef IOServiceMatching(const char *name);
io_service_t IOServiceGetMatchingService(mach_port_t mainPort, CFDictionaryRef matching);
kern_return_t IORegistryEntryCreateCFProperties(io_registry_entry_t entry, CFMutableDictionaryRef *properties, CFAllocatorRef allocator, uint32_t options);
kern_return_t IOObjectRelease(io_object_t object);
}
#define kIOMasterPortDefault 0
#endif
#import <SystemConfiguration/CaptiveNetwork.h>

#import <substrate.h>

#import "CPPreferences.h"
#import "PrivateHeaders.h"
#import "CarPlayPlusAnimatedImage.h"

// ---------------------------------------------------------------------------
#pragma mark - Preferences
// ---------------------------------------------------------------------------

// preference keys (mirror the reconstructed upstream feature set)
static NSString *const kEnabled          = @"kEnabled";
static NSString *const kDimming          = @"kDimming";
static NSString *const kOrienation       = @"kOrienation";      // 0 left / 1 right
static NSString *const kStatusBar        = @"kStatusBar";
static NSString *const kShowDate         = @"kShowDate";
static NSString *const kDateFormat       = @"kDateFormat";
static NSString *const kLocation         = @"kLocation";
static NSString *const kPosDate          = @"kPosDate";
static NSString *const kFontSize         = @"kFontSize";
static NSString *const kWeather_icon     = @"kWeather_icon";
static NSString *const kWeather_temperature = @"kWeather_temperature";
static NSString *const kPosWeather       = @"kPosWeather";
static NSString *const kdevice_icon      = @"kdevice_icon";
static NSString *const kBattery          = @"kBattery";
static NSString *const kEnaTimeColor     = @"kEnaTimeColor";
static NSString *const kTimeColor        = @"kTimeColor";
static NSString *const kCarrierColor     = @"kCarrierColor";
static NSString *const kEnaWifiColor     = @"kEnaWifiColor";
static NSString *const kWifiColor        = @"kWifiColor";
static NSString *const kEnaLteColor      = @"kEnaLteColor";
static NSString *const kLTEOnColor       = @"kLTEOnColor";
static NSString *const kLTEOffColor      = @"kLTEOffColor";
static NSString *const kTop_inset        = @"kTop_inset";
static NSString *const kBottom_inset     = @"kBottom_inset";
static NSString *const kLeft_inset       = @"kLeft_inset";
static NSString *const kRight_inset      = @"kRight_inset";
static NSString *const kHideLabel        = @"kHideLabel";
static NSString *const kHideLabelback    = @"kHideLabelback";
static NSString *const kDots             = @"kDots";
static NSString *const kRows             = @"kRows";
static NSString *const kColumns          = @"kColumns";
static NSString *const kIconSize         = @"kIconSize";
static NSString *const klblColor         = @"klblColor";
static NSString *const kAPI_Music        = @"kAPI_Music";
static NSString *const kAPI_Battey       = @"kAPI_Battey";
static NSString *const kAPI_System       = @"kAPI_System";
static NSString *const kAPI_Weather      = @"kAPI_Weather";
static NSString *const kAPI_CarPlay      = @"kAPI_CarPlay";
static NSString *const kAPI_Statusbar    = @"kAPI_Statusbar";
static NSString *const kFullApps         = @"kFullApps";
static NSString *const kFullBtn_x        = @"kFullBtn_x";
static NSString *const kFullBtn_y        = @"kFullBtn_y";
static NSString *const kFull_size        = @"kFull_size";
static NSString *const kWallEnabled      = @"kWallEnabled";
static NSString *const kWallpaper        = @"kWallpaper";
static NSString *const kWallpaperMotion  = @"kWallpaperMotion";
static NSString *const kWallpaperPrefix  = @"kWallpaper";       // kWallpaper0..4
static NSString *const kInterval         = @"kInterval";
static NSString *const kRemoveSplash     = @"kRemoveSplash";
static NSString *const kActiveWidgets    = @"kActiveWidgets";
static NSString *const kPageType         = @"kPageType";

static const int kMaxWallpapers = 5;

static BOOL gEnabled(void) {
    return CPPrefsBoolForKey(kEnabled, YES);
}

static NSInteger intPref(NSString *key, NSInteger def) {
    return CPPrefsIntegerForKey(key, def);
}

static CGFloat cgPref(NSString *key, CGFloat def) {
    return CPPrefsCGFloatForKey(key, def);
}

static BOOL boolPref(NSString *key, BOOL def) {
    return CPPrefsBoolForKey(key, def);
}

static UIColor *CPColorFromPref(NSString *key, NSString *fallbackHex) {
    NSString *hex = CPPrefsStringForKey(key, fallbackHex);
    if (!hex.length) return nil;
    hex = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned val = 0;
    NSScanner *sc = [NSScanner scannerWithString:hex];
    if (![sc scanHexInt:&val]) return nil;
    switch (hex.length) {
        case 3:
            return [UIColor colorWithRed:((val>>8)&0xF)/15.0 green:((val>>4)&0xF)/15.0
                                     blue:(val&0xF)/15.0 alpha:1];
        case 6:
            return [UIColor colorWithRed:((val>>16)&0xFF)/255.0 green:((val>>8)&0xFF)/255.0
                                     blue:(val&0xFF)/255.0 alpha:1];
        case 8:
            return [UIColor colorWithRed:((val>>16)&0xFF)/255.0 green:((val>>8)&0xFF)/255.0
                                     blue:(val&0xFF)/255.0 alpha:((val>>24)&0xFF)/255.0];
        default:
            return nil;
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Device/battery/network helpers
// ---------------------------------------------------------------------------

static NSString *CPDeviceModelName(void) {
    // hw.machine → marketing name table (subset of the well-known mapping)
    static NSDictionary *names = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @"iPhone7,1": @"iPhone 6 Plus",  @"iPhone7,2": @"iPhone 6",
            @"iPhone8,1": @"iPhone 6S",      @"iPhone8,2": @"iPhone 6S Plus",
            @"iPhone8,4": @"iPhone SE",      @"iPhone9,1": @"iPhone 7",
            @"iPhone9,3": @"iPhone 7",       @"iPhone9,2": @"iPhone 7 Plus",
            @"iPhone9,4": @"iPhone 7 Plus",  @"iPhone10,1": @"iPhone 8",
            @"iPhone10,4": @"iPhone 8",      @"iPhone10,2": @"iPhone 8 Plus",
            @"iPhone10,5": @"iPhone 8 Plus", @"iPhone10,3": @"iPhone X",
            @"iPhone10,6": @"iPhone X",      @"iPhone11,8": @"iPhone XR",
            @"iPhone11,2": @"iPhone XS",     @"iPhone11,4": @"iPhone XS Max",
            @"iPhone11,6": @"iPhone XS Max", @"iPhone12,1": @"iPhone 11",
            @"iPhone12,3": @"iPhone 11 Pro", @"iPhone12,5": @"iPhone 11 Pro Max",
            @"iPhone12,8": @"iPhone SE (2nd)", @"iPhone13,1": @"iPhone 12 mini",
            @"iPhone13,2": @"iPhone 12",     @"iPhone13,3": @"iPhone 12 Pro",
            @"iPhone13,4": @"iPhone 12 Pro Max", @"iPhone14,2": @"iPhone 13 Pro",
            @"iPhone14,3": @"iPhone 13 Pro Max", @"iPhone14,4": @"iPhone 13 mini",
            @"iPhone14,6": @"iPhone SE (3rd)", @"iPhone14,7": @"iPhone 14",
            @"iPhone14,8": @"iPhone 14 Plus", @"iPhone15,2": @"iPhone 14 Pro",
            @"iPhone15,3": @"iPhone 14 Pro Max",
        };
    });
    struct utsname sys;
    uname(&sys);
    NSString *m = [NSString stringWithCString:sys.machine encoding:NSUTF8StringEncoding];
    return names[m] ?: m;
}

static NSDictionary *CPBatteryInfo(void) {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    CFMutableDictionaryRef props = NULL;
    io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("IOPMPowerSource"));
    if (service) {
        IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0);
        IOObjectRelease(service);
    }
    NSDictionary *dict = (__bridge_transfer NSDictionary *)props;
#define CP_NUM(key, out) do { id v = dict[[NSString stringWithUTF8String:key]]; if (v) info[out] = v; } while (0)
    CP_NUM("InstantAmperage", @"currentCapacity");
    CP_NUM("CycleCount", @"cycles");
    CP_NUM("AppleRawMaxCapacity", @"maxCapacity");
    CP_NUM("AppleRawCurrentCapacity", @"currentCapacity");
    CP_NUM("DesignCapacity", @"designCapacity");
    CP_NUM("Temperature", @"temperature");
    CP_NUM("Voltage", @"voltage");
#undef CP_NUM
    return info;
}

static int CPBatteryPercent(void) {
    static Class bcClass = Nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ bcClass = NSClassFromString(@"BCBatteryDeviceController"); });
    if (bcClass && [bcClass respondsToSelector:@selector(sharedInstance)]) {
        id ctrl = [bcClass sharedInstance];
        Class devCls = NSClassFromString(@"BCBatteryDevice");
        if ([ctrl respondsToSelector:@selector(connectedDevices)]) {
            for (id dev in [ctrl connectedDevices]) {
                if (!devCls || ![dev isKindOfClass:devCls]) continue;
                NSString *identifier = [dev valueForKey:@"identifier"] ?: @"";
                if ([identifier hasPrefix:@"AppleInternalBattery"]) {
                    NSNumber *cap = [dev valueForKey:@"batteryCapacityAsPercentage"];
                    if (cap) return cap.intValue;
                }
            }
        }
    }
    [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
    return (int)([UIDevice currentDevice].batteryLevel * 100.0 + 0.5);
}

static NSString *CPNetworkType(void) {
    CTTelephonyNetworkInfo *net = [[CTTelephonyNetworkInfo alloc] init];
    NSString *tech = net.currentRadioAccessTechnology;
    if ([tech isEqualToString:CTRadioAccessTechnologyLTE]) return @"LTE";
    if ([tech isEqualToString:CTRadioAccessTechnologyNR]) return @"5G";
    if ([tech isEqualToString:CTRadioAccessTechnologyNRNSA]) return @"5G";
    if ([tech isEqualToString:CTRadioAccessTechnologyHSDPA] ||
        [tech isEqualToString:CTRadioAccessTechnologyHSUPA] ||
        [tech isEqualToString:CTRadioAccessTechnologyWCDMA]) return @"3G";
    if ([tech isEqualToString:CTRadioAccessTechnologyEdge]) return @"E";
    if ([tech isEqualToString:CTRadioAccessTechnologyGPRS]) return @"G";
    if ([tech isEqualToString:CTRadioAccessTechnologyCDMA1x]) return @"1x";
    return tech ?: @"";
}

static NSString *CPCarrierName(void) {
    CTTelephonyNetworkInfo *net = [[CTTelephonyNetworkInfo alloc] init];
    CTCarrier *carrier = net.subscriberCellularProvider;
    return carrier.carrierName ?: @"";
}

static NSString *CPWiFiSSID(void) {
    NSDictionary *ifs = (__bridge_transfer NSDictionary *)CNCopyCurrentNetworkInfo(CFSTR("en0"));
    return ifs[(NSString *)kCNNetworkInfoKeySSID] ?: @"";
}

static NSString *CPIPAddress(void) {
    struct ifaddrs *addrs = NULL;
    if (getifaddrs(&addrs) != 0) return @"";
    NSString *ip = nil;
    for (struct ifaddrs *a = addrs; a; a = a->ifa_next) {
        if (a->ifa_addr && a->ifa_addr->sa_family == AF_INET &&
            !(a->ifa_flags & IFF_LOOPBACK) && a->ifa_name && strcmp(a->ifa_name, "en0") == 0) {
            char buf[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &((struct sockaddr_in *)a->ifa_addr)->sin_addr, buf, sizeof(buf));
            ip = [NSString stringWithCString:buf encoding:NSUTF8StringEncoding];
            break;
        }
    }
    freeifaddrs(addrs);
    return ip ?: @"";
}

static NSString *CPRamUsage(BOOL used) {
    mach_port_t host = mach_host_self();
    vm_size_t pageSize = 0;
    mach_vm_size_t totalMem = (mach_vm_size_t)[NSProcessInfo processInfo].physicalMemory;
    host_page_size(host, &pageSize);
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_statistics64_data_t vm;
    mach_vm_size_t freeMem = 0;
    if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS) {
        freeMem = (mach_vm_size_t)vm.free_count * pageSize;
    }
    if (used) return [NSString stringWithFormat:@"%lluMB", (unsigned long long)((totalMem - freeMem) / 1024 / 1024)];
    return [NSString stringWithFormat:@"%lluMB", (unsigned long long)(totalMem / 1024 / 1024)];
}

// ---------------------------------------------------------------------------
#pragma mark - Notifications
// ---------------------------------------------------------------------------

static NSString *const kIconLayoutChanged = @"xyz.carplayplus.iconLayouChanged";
static NSString *const kChangedImg        = @"xyz.carplayplus.changedImg";
static NSString *const kFullscreenToggle  = @"xyz.carplayplus.fullscreen";

// ---------------------------------------------------------------------------
#pragma mark - Icon Layout
// ---------------------------------------------------------------------------

%group CarPlayPlusLayout

%hook CARIconListView

- (void)layoutSubviews {
    %orig;
    if (!gEnabled()) return;

    NSInteger rows = intPref(kRows, 3);
    NSInteger cols = intPref(kColumns, 5);
    NSInteger iconSize = intPref(kIconSize, 40);

    id conf = nil;
    if ([self respondsToSelector:@selector(iconListViewLayoutConfiguration)])
        conf = [self iconListViewLayoutConfiguration];
    else if ([self respondsToSelector:@selector(layoutConfiguration)])
        conf = [self layoutConfiguration];
    if (conf) {
        if ([conf respondsToSelector:@selector(setNumberOfPortraitRows:)])
            [conf setNumberOfPortraitRows:rows];
        if ([conf respondsToSelector:@selector(setNumberOfPortraitColumns:)])
            [conf setNumberOfPortraitColumns:cols];
        if ([conf respondsToSelector:@selector(setIconSize:)])
            [conf setIconSize:(CGFloat)iconSize];
    }

    CGFloat top = cgPref(kTop_inset, 30);
    CGFloat bottom = cgPref(kBottom_inset, -30);
    CGFloat left = cgPref(kLeft_inset, 20);
    CGFloat right = cgPref(kRight_inset, 20);
    if ([UIView userInterfaceLayoutDirectionForSemanticContentAttribute:self.semanticContentAttribute]
            == NSLayoutDirectionRightToLeft) {
        CGFloat t = left; left = right; right = t;
    }
    UIEdgeInsets insets = UIEdgeInsetsMake(top, left, bottom, right);
    if ([self isKindOfClass:NSClassFromString(@"UIScrollView")])
        ((UIScrollView *)self).contentInset = insets;
    else
        [self setValue:[NSValue valueWithUIEdgeInsets:insets] forKey:@"contentInset"];

    if ([self respondsToSelector:@selector(iconViews)])
        for (UIView *iv in self.iconViews)
            if ([iv respondsToSelector:@selector(setIconSize:)])
                [iv setIconSize:(CGFloat)iconSize];
}

%end

%hook CARIconListPageControl

- (void)setHidden:(BOOL)hidden {
    if (gEnabled() && boolPref(kDots, YES)) hidden = YES;
    %orig;
}

%end

// apply label options to icon views (called from layout below)
static void ApplyLabelStyleToIconView(UIView *iconView) {
    if (boolPref(kHideLabel, YES)) {
        for (UIView *sub in iconView.subviews)
            sub.hidden = YES;
    }
    if ([iconView respondsToSelector:@selector(label)])
        iconView.label.hidden = boolPref(kHideLabel, YES);
    if ([iconView respondsToSelector:@selector(labelLegibilityView)])
        iconView.labelLegibilityView.hidden = boolPref(kHideLabelback, YES);
    UIColor *lblColor = [UIColor whiteColor];
    NSString *hex = CPPrefsStringForKey(klblColor, @"FFFFFF");
    unsigned val = 0;
    NSScanner *sc = [NSScanner scannerWithString:hex];
    if ([sc scanHexInt:&val]) lblColor = [UIColor colorWithRed:((val>>16)&0xFF)/255.0
                                                         green:((val>>8)&0xFF)/255.0
                                                          blue:(val&0xFF)/255.0 alpha:1];
    if ([iconView respondsToSelector:@selector(label)])
        iconView.label.textColor = lblColor;
}

%hook CARIconView

- (void)layoutSubviews {
    %orig;
    if (gEnabled()) ApplyLabelStyleToIconView(self);
}

%end

static void ApplyLayoutToAll(void) {
    NSArray *windows = [UIApplication sharedApplication].windows;
    for (UIWindow *win in windows) {
        for (UIView *v in win.subviews)
            if ([v isKindOfClass:NSClassFromString(@"CARIconListView")])
                [v setNeedsLayout];
    }
}

%end // CarPlayPlusLayout

// ---------------------------------------------------------------------------
#pragma mark - Wallpaper (static / GIF / slideshow / motion)
// ---------------------------------------------------------------------------

%group CarPlayPlusWallpaper

@interface CarPlayPlusWallpaper : NSObject
@property (nonatomic, strong) UIImageView *wallpaperImageView;
@property (nonatomic, strong) CarPlayPlusAnimatedImage *gifPlayer;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, strong) NSTimer *slideshowTimer;
+ (instancetype)shared;
- (void)applyToWindow:(UIWindow *)window;
- (void)invalidate;
- (void)scheduleSlideshowIfNeeded;
@end

@implementation CarPlayPlusWallpaper

+ (instancetype)shared {
    static CarPlayPlusWallpaper *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [CarPlayPlusWallpaper new]; });
    return inst;
}

- (NSString *)selectedPath {
    NSString *path = CPPrefsStringForKey(kWallpaper, nil);
    if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) return path;
    for (NSInteger i = 0; i < kMaxWallpapers; i++) {
        NSString *p = CPPrefsStringForKey([NSString stringWithFormat:@"%@%ld", kWallpaperPrefix, (long)i], nil);
        if (p && [[NSFileManager defaultManager] fileExistsAtPath:p]) return p;
    }
    return nil;
}

- (BOOL)isGIF:(NSString *)path {
    NSData *head = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (head.length < 6) return NO;
    return memcmp(head.bytes, "GIF87a", 6) == 0 || memcmp(head.bytes, "GIF89a", 6) == 0;
}

- (void)applyToWindow:(UIWindow *)window {
    if (!gEnabled() || !boolPref(kWallEnabled, YES)) return;
    if (!window) return;
    NSString *path = [self selectedPath];
    if (!path) return;

    if (!self.wallpaperImageView) {
        self.wallpaperImageView = [[UIImageView alloc] initWithFrame:window.bounds];
        self.wallpaperImageView.clipsToBounds = YES;
        self.wallpaperImageView.contentMode = UIViewContentModeScaleAspectFill;
        self.wallpaperImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }

    [self.gifPlayer stop];
    if ([self isGIF:path]) {
        self.gifPlayer = [[CarPlayPlusAnimatedImage alloc] initWithPath:path frame:window.bounds];
        [self.gifPlayer start];
        [window insertSubview:self.gifPlayer.view atIndex:0];
        self.gifPlayer.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.wallpaperImageView.hidden = YES;
    } else {
        self.wallpaperImageView.image = [UIImage imageWithContentsOfFile:path];
        self.wallpaperImageView.hidden = NO;
        if (!self.wallpaperImageView.superview)
            [window insertSubview:self.wallpaperImageView atIndex:0];
    }

    CGFloat dim = cgPref(kDimming, 0) / 100.0;
    UIView *dimLayer = [window viewWithTag:98471];
    if (!dimLayer) {
        dimLayer = [[UIView alloc] initWithFrame:window.bounds];
        dimLayer.tag = 98471;
        dimLayer.userInteractionEnabled = NO;
        dimLayer.backgroundColor = [UIColor blackColor];
        dimLayer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    }
    dimLayer.alpha = dim;
    if (!dimLayer.superview) [window insertSubview:dimLayer aboveSubview:self.wallpaperImageView];

    BOOL motion = boolPref(kWallpaperMotion, NO);
    UIInterpolatingMotionEffect *x = [[UIInterpolatingMotionEffect alloc]
        initWithKeyPath:@"center.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
    UIInterpolatingMotionEffect *y = [[UIInterpolatingMotionEffect alloc]
        initWithKeyPath:@"center.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
    x.minimumRelativeValue = @-12; x.maximumRelativeValue = @12;
    y.minimumRelativeValue = @-12; y.maximumRelativeValue = @12;
    UIMotionEffectGroup *group = [UIMotionEffectGroup new];
    group.motionEffects = @[x, y];
    UIView *subject = self.gifPlayer.view ?: self.wallpaperImageView;
    if (motion) {
        if (!subject.motionEffects.count) [subject addMotionEffect:group];
    } else {
        for (UIMotionEffect *e in subject.motionEffects) [subject removeMotionEffect:e];
    }

    [self scheduleSlideshowIfNeeded];
}

- (void)scheduleSlideshowIfNeeded {
    if (self.slideshowTimer) return;
    NSInteger interval = MAX(2, intPref(kInterval, 5));
    self.slideshowTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self
                                                         selector:@selector(slideshowTick)
                                                         userInfo:nil repeats:YES];
}

- (void)slideshowTick {
    NSMutableArray *paths = [NSMutableArray array];
    for (NSInteger i = 0; i < kMaxWallpapers; i++) {
        NSString *p = CPPrefsStringForKey([NSString stringWithFormat:@"%@%ld", kWallpaperPrefix, (long)i], nil);
        if (p && [[NSFileManager defaultManager] fileExistsAtPath:p]) [paths addObject:p];
    }
    if (!paths.count) return;
    self.currentIndex = (self.currentIndex + 1) % paths.count;
    CPPrefsSetObject(kWallpaper, paths[self.currentIndex]);
    [[NSNotificationCenter defaultCenter] postNotificationName:kChangedImg object:self];
}

- (void)invalidate {
    [self.slideshowTimer invalidate];
    self.slideshowTimer = nil;
    [self.gifPlayer stop];
    [self.wallpaperImageView removeFromSuperview];
    [self.gifPlayer.view removeFromSuperview];
    self.gifPlayer = nil;
    self.wallpaperImageView = nil;
}

@end

%hook CPWRootViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!gEnabled()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[CarPlayPlusWallpaper shared] applyToWindow:self.view.window];
    });
}

%end

%hook CARSplashScreenViewController

- (void)viewDidLoad {
    %orig;
    if (gEnabled() && boolPref(kRemoveSplash, NO))
        self.view.hidden = YES;
}

%end

%end // CarPlayPlusWallpaper

// ---------------------------------------------------------------------------
#pragma mark - Status Bar
// ---------------------------------------------------------------------------

%group CarPlayPlusStatusBar

@interface CarPlayPlusStatusBar : NSObject
@property (nonatomic, strong) UIView *container;
@property (nonatomic, strong) UILabel *dateLabel;
@property (nonatomic, strong) UILabel *weatherLabel;
@property (nonatomic, strong) UIImageView *weatherIconView;
@property (nonatomic, strong) UIImageView *batteryIconView;
@property (nonatomic, assign) NSInteger side; // 0 left / 1 right
+ (instancetype)shared;
- (UIView *)buildForContainerView:(UIView *)container;
- (void)updateAll;
- (void)remove;
@end

@implementation CarPlayPlusStatusBar

+ (instancetype)shared {
    static CarPlayPlusStatusBar *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [CarPlayPlusStatusBar new]; });
    return inst;
}

- (UIFont *)statusFont {
    return [UIFont monospacedDigitSystemFontOfSize:(CGFloat)intPref(kFontSize, 8) weight:UIFontWeightMedium];
}

- (NSString *)formattedDate {
    NSString *fmt = CPPrefsStringForKey(kDateFormat, @"EE,MMM d");
    NSString *loc = CPPrefsStringForKey(kLocation, @"en_US_POSIX");
    fmt = [fmt stringByReplacingOccurrencesOfString:@"@" withString:@"\n"];
    NSDateFormatter *df = [NSDateFormatter new];
    df.locale = [NSLocale localeWithLocaleIdentifier:loc];
    df.dateFormat = fmt;
    return [df stringFromDate:[NSDate date]];
}

- (UIView *)buildForContainerView:(UIView *)container {
    if (self.container.superview) [self.container removeFromSuperview];
    CGRect b = container.bounds;
    if (CGRectIsEmpty(b)) b = CGRectMake(0, 0, 320, 30);
    self.container = [[UIView alloc] initWithFrame:b];
    self.container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.container.userInteractionEnabled = NO;

    UIEdgeInsets pad = UIEdgeInsetsMake(0, 10, 0, 10);

    if (boolPref(kShowDate, NO) && self.dateLabel) {
        self.dateLabel.font = [self statusFont];
        self.dateLabel.text = [self formattedDate];
        self.dateLabel.textAlignment = NSTextAlignmentRight;
        [self.dateLabel sizeToFit];
        CGRect f = self.dateLabel.frame;
        f.origin.x = (self.side == 1)
            ? CGRectGetMinX(self.container.bounds) + pad.left
            : CGRectGetMaxX(self.container.bounds) - f.size.width - pad.right;
        f.origin.y = cgPref(kPosDate, 30);
        self.dateLabel.frame = f;
        [self.container addSubview:self.dateLabel];
    }

    if (self.weatherIconView || self.weatherLabel) {
        CGFloat wx = pad.left;
        if (self.weatherIconView) {
            CGRect f = self.weatherIconView.frame;
            f.origin = CGPointMake(wx, cgPref(kPosWeather, 40));
            self.weatherIconView.frame = f;
            wx += f.size.width + 4;
        }
        if (self.weatherLabel) {
            self.weatherLabel.font = [self statusFont];
            [self.weatherLabel sizeToFit];
            CGRect f = self.weatherLabel.frame;
            f.origin = CGPointMake(wx, cgPref(kPosWeather, 40));
            self.weatherLabel.frame = f;
        }
        if (self.weatherIconView) [self.container addSubview:self.weatherIconView];
        if (self.weatherLabel) [self.container addSubview:self.weatherLabel];
    }

    if (self.batteryIconView) {
        [self.batteryIconView sizeToFit];
        CGRect f = self.batteryIconView.frame;
        f.origin = CGPointMake(pad.left, cgPref(kBattery, 180));
        self.batteryIconView.frame = f;
        [self.container addSubview:self.batteryIconView];
    }

    [container addSubview:self.container];
    return self.container;
}

- (void)updateAll {
    if (!gEnabled() || !boolPref(kStatusBar, YES)) return;
    if (self.dateLabel) self.dateLabel.text = [self formattedDate];
    if (self.weatherLabel) {
        // temperature/icon are filled by the weather updater below
        self.weatherLabel.text = self.weatherLabel.text ?: @"";
    }
    if (self.batteryIconView) {
        NSString *sym = @"battery.25";
        int pct = CPBatteryPercent();
        if (pct >= 75) sym = @"battery.100";
        else if (pct >= 50) sym = @"battery.75";
        else if (pct >= 25) sym = @"battery.50";
        self.batteryIconView.image = [UIImage systemImageNamed:sym];
    }
    // color overrides (time label; carrier/wifi/network colors stay on the
    // system-drawn elements of the stock status bar)
    if (boolPref(kEnaTimeColor, NO) && self.dateLabel) {
        UIColor *c = CPColorFromPref(kTimeColor, @"FFFFFF");
        if (c) self.dateLabel.textColor = c;
    }
}

- (void)remove {
    [self.container removeFromSuperview];
}

@end

%hook CARRootStatusBarViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!gEnabled() || !boolPref(kStatusBar, YES)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        CarPlayPlusStatusBar *sb = [CarPlayPlusStatusBar shared];
        [sb buildForContainerView:self.view];
        [sb updateAll];
    });
}

%end

%hook CARStatusBarViewController

- (void)viewDidLoad {
    %orig;
    if (!gEnabled()) return;
    [CarPlayPlusStatusBar shared].side = intPref(kOrienation, 0);
}

%end

%end // CarPlayPlusStatusBar

// ---------------------------------------------------------------------------
#pragma mark - Fullscreen apps
// ---------------------------------------------------------------------------

%group CarPlayPlusFullscreen

static BOOL (*orig_BKSDisplayServicesSetScreenBlanked)(int blanked);
static BOOL gFullscreenActive = NO;

static void hook_BKSDisplayServicesSetScreenBlanked(int blanked) {
    // A CarPlay "fullscreen" session keeps the CarPlay output alive; the phone
    // screen may still blank normally through the original implementation.
    orig_BKSDisplayServicesSetScreenBlanked(blanked);
}

%hook CARAppDockButton

- (void)layoutSubviews {
    %orig;
    if (!gEnabled()) return;
    static UIButton *fsBtn = nil;
    if (!fsBtn) {
        fsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [fsBtn setImage:[UIImage systemImageNamed:@"arrow.up.left.and.arrow.down.right"]
               forState:UIControlStateNormal];
        fsBtn.tintColor = [UIColor whiteColor];
        [fsBtn addTarget:self action:@selector(carPlayPlusToggleFullscreen) forControlEvents:UIControlEventTouchUpInside];
        fsBtn.tag = 98001;
    }
    CGFloat size = cgPref(kFull_size, 30);
    fsBtn.frame = CGRectMake(cgPref(kFullBtn_x, 14), cgPref(kFullBtn_y, 14), size, size);
    if (!fsBtn.superview) [self addSubview:fsBtn];
}

- (void)carPlayPlusToggleFullscreen {
    gFullscreenActive = !gFullscreenActive;
    [[NSNotificationCenter defaultCenter] postNotificationName:kFullscreenToggle object:self
                                                       userInfo:@{@"active": @(gFullscreenActive)}];
}

%end

%end // CarPlayPlusFullscreen

// ---------------------------------------------------------------------------
#pragma mark - Widgets (CARAirawWindow + WebKit bridge)
// ---------------------------------------------------------------------------

%group CarPlayPlusWidgets

@interface CARAirawWindow : UIWindow
@property (nonatomic, strong) NSMutableDictionary<NSString *, WKWebView *> *widgetViews;
- (void)createWidgets;
- (void)updateWidgets;
@end

@implementation CARAirawWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.windowLevel = UIWindowLevelStatusBar + 1.0;
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
        self.hidden = YES;
        self.widgetViews = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSArray *)activeWidgetBundles {
    id active = CPPrefsObjectForKey(kActiveWidgets);
    return [active isKindOfClass:[NSArray class]] ? active : @[];
}

- (NSString *)htmlPathForWidget:(NSDictionary *)info {
    NSString *name = info[@"Widget_name"];
    NSString *kind = info[@"Widget"];
    if ([kind isEqualToString:@"SBHTML"])
        return [NSString stringWithFormat:@"/var/mobile/Library/SBHTML/%@/Wallpaper.html", name];
    if ([kind isEqualToString:@"iWidgets"])
        return [NSString stringWithFormat:@"/var/mobile/Library/iWidgets/%@/Widget.html", name];
    if ([kind isEqualToString:@"Universal"])
        return [NSString stringWithFormat:@"/var/mobile/Library/Widgets/Universal/%@/index.html", name];
    NSString *bundle = [NSString stringWithFormat:@"/Library/CarPlayPlus/Widgets/Controls/%@.bundle", name];
    NSDictionary *pl = [NSDictionary dictionaryWithContentsOfFile:[bundle stringByAppendingPathComponent:@"Info.plist"]];
    NSString *main = pl[@"CFBundleExecutable"] ?: @"index.html";
    return [bundle stringByAppendingPathComponent:main];
}

- (WKWebView *)webViewForWidget:(NSString *)identifier path:(NSString *)path {
    WKWebView *web = self.widgetViews[identifier];
    if (web) return web;
    WKWebViewConfiguration *conf = [WKWebViewConfiguration new];
    conf.userContentController = [WKUserContentController new];
    WKUserScript *hideScroll = [[WKUserScript alloc]
        initWithSource:@"var s=document.createElement('style');s.innerHTML='::-webkit-scrollbar{display:none}';document.head.appendChild(s);"
          injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
    [conf.userContentController addUserScript:hideScroll];
    web = [[WKWebView alloc] initWithFrame:self.bounds configuration:conf];
    web.navigationDelegate = (id<WKNavigationDelegate>)self;
    web.opaque = NO;
    web.backgroundColor = [UIColor clearColor];
    web.scrollView.scrollEnabled = NO;
    web.scrollView.bounces = NO;
    NSString *dir = [path stringByDeletingLastPathComponent];
    [web loadFileURL:[NSURL fileURLWithPath:path]
allowingReadAccessToURL:[NSURL fileURLWithPath:dir]];
    self.widgetViews[identifier] = web;
    return web;
}

- (void)createWidgets {
    for (UIView *v in self.subviews) [v removeFromSuperview];
    [self.widgetViews removeAllObjects];

    NSInteger pageType = intPref(kPageType, 0);      // 0 universal / 1 specify
    NSInteger pageIndex = intPref(@"pageIndex", 0);

    for (NSDictionary *w in [self activeWidgetBundles]) {
        NSString *name = w[@"Widget_name"];
        if (pageType == 1 && [w[@"pageIndex"] integerValue] != pageIndex) continue;
        NSString *path = [self htmlPathForWidget:w];
        if (!path || ![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;

        WKWebView *web = [self webViewForWidget:name path:path];
        CGFloat ww = [w[@"width"] floatValue] ?: 200;
        CGFloat wh = [w[@"height"] floatValue] ?: 120;
        CGFloat wx = [w[@"PosX"] floatValue] ?: 0;
        CGFloat wy = [w[@"PosY"] floatValue] ?: 0;
        CGFloat zoom = [w[@"zoom_lbl"] floatValue] ?: 1.0;
        web.transform = CGAffineTransformMakeScale(zoom, zoom);
        web.frame = CGRectMake(wx, wy, ww, wh);
        [self addSubview:web];
    }
}

- (void)updateWidgets {
    for (WKWebView *web in self.widgetViews.allValues)
        [self evaluateWidgetDataIntoWeb:web];
}

- (void)evaluateWidgetDataIntoWeb:(WKWebView *)web {
    NSMutableString *js = [NSMutableString string];

    if (boolPref(kAPI_Music, YES)) {
        extern void MRMediaRemoteGetNowPlayingInfo(dispatch_queue_t, void (^)(NSDictionary *));
        extern NSString *kMRMediaRemoteNowPlayingInfoTitle;
        extern NSString *kMRMediaRemoteNowPlayingInfoArtist;
        extern NSString *kMRMediaRemoteNowPlayingInfoAlbum;
        extern NSString *kMRMediaRemoteNowPlayingInfoDuration;
        extern NSString *kMRMediaRemoteNowPlayingInfoElapsedTime;
        __block NSDictionary *now = nil;
        MRMediaRemoteGetNowPlayingInfo(dispatch_get_main_queue(), ^(NSDictionary *info) { now = info; });
        if (now) {
            NSString *t = now[kMRMediaRemoteNowPlayingInfoTitle] ?: @"";
            NSString *a = now[kMRMediaRemoteNowPlayingInfoArtist] ?: @"";
            NSString *al = now[kMRMediaRemoteNowPlayingInfoAlbum] ?: @"";
            NSNumber *dur = now[kMRMediaRemoteNowPlayingInfoDuration] ?: @0;
            NSNumber *ela = now[kMRMediaRemoteNowPlayingInfoElapsedTime] ?: @0;
            t = [t stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
            a = [a stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
            al = [al stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
            [js appendFormat:@"var artist='%@',album='%@',title='%@',currentDuration=%@,currentElapsedTime=%@;mainUpdate('music');",
                            a, al, t, dur, ela];
        }
    }

    if (boolPref(kAPI_Battey, YES)) {
        int pct = CPBatteryPercent();
        NSDictionary *b = CPBatteryInfo();
        BOOL charging = [UIDevice currentDevice].batteryState == UIDeviceBatteryStateCharging;
        BOOL lowPower = [NSProcessInfo processInfo].lowPowerModeEnabled;
        NSInteger cycles = [b[@"cycles"] integerValue];
        CGFloat health = 1.0;
        double maxC = [b[@"maxCapacity"] doubleValue], designC = [b[@"designCapacity"] doubleValue];
        if (maxC > 0 && designC > 0) health = maxC / designC;
        NSInteger voltage = [b[@"voltage"] integerValue];
        CGFloat celsius = [b[@"temperature"] doubleValue] / 100.0;
        NSData *jdata = [NSJSONSerialization dataWithJSONObject:b options:0 error:nil];
        NSString *json = [[NSString alloc] initWithData:jdata encoding:NSUTF8StringEncoding] ?: @"{}";
        json = [json stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
        [js appendFormat:
            @"var batteryPercent=%d,batteryCharging=%d,batteryLowPowerMode=%d,batteryCycles=%ld,"
             "batteryHealth=%.2f,batteryVoltage=%ld,batteryCelsius=%.2f,bateryInfo=JSON.parse('%@');mainUpdate('battery');",
            pct, charging, lowPower, (long)cycles, health, (long)voltage, celsius, json];
    }

    if (boolPref(kAPI_System, YES)) {
        [js appendFormat:
            @"var deviceName='%@',deviceType='%@',systemVersion='%@',ipAddress='%@',ramFree='%@',ramUsed='%@',ramTotal='%@';mainUpdate('system');",
            [UIDevice currentDevice].name, CPDeviceModelName(), [UIDevice currentDevice].systemVersion,
            CPIPAddress(), CPRamUsage(NO), CPRamUsage(YES), CPRamUsage(NO)];
    }

    if (boolPref(kAPI_Statusbar, YES)) {
        [js appendFormat:
            @"var signalBars='%@',signalName='%@',wifiBars='%@',wifiName='%@',signalNetworkType='%@';mainUpdate('statusbar');",
            @"--", CPCarrierName(), @"--", CPWiFiSSID(), CPNetworkType()];
    }

    if (js.length)
        [web evaluateJavaScript:js completionHandler:nil];
}

@end

static CARAirawWindow *gWidgetWindow;

static void UpdateWidgetWindowState(BOOL connected) {
    if (connected) {
        if (!gWidgetWindow) {
            CGRect b = [UIScreen mainScreen].bounds;
            gWidgetWindow = [[CARAirawWindow alloc] initWithFrame:b];
        }
        [gWidgetWindow setHidden:NO];
        [gWidgetWindow createWidgets];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [gWidgetWindow updateWidgets];
        });
        [gWidgetWindow setFrame:[UIScreen mainScreen].bounds];
    } else {
        [gWidgetWindow setHidden:YES];
    }
}

%end // CarPlayPlusWidgets

// ---------------------------------------------------------------------------
#pragma mark - Wiring
// ---------------------------------------------------------------------------

static void OnCarPlayConnect(NSNotification *note) {
    NSDictionary *ui = note.userInfo;
    NSNumber *connected = ui[@"IsConnected"] ?: ui[@"CarPlayIsConnectedDidChange_IsConnected"];
    UpdateWidgetWindowState(connected ? connected.boolValue : YES);
}

static void OnIconLayoutChanged(NSNotification *note) {
    ApplyLayoutToAll();
}

static void OnPrefsChanged(NSNotification *note) {
    if (gWidgetWindow) [gWidgetWindow updateWidgets];
    if (boolPref(kWallEnabled, NO)) {
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if (w) [[CarPlayPlusWallpaper shared] applyToWindow:w];
    } else {
        [[CarPlayPlusWallpaper shared] invalidate];
    }
    ApplyLayoutToAll();
}

%ctor {
    CPPrefsRegisterDefaults(@{
        kEnabled: @YES,
        kDimming: @0,
        kRows: @3, kColumns: @5, kIconSize: @40,
        kTop_inset: @30, kBottom_inset: @(-30), kLeft_inset: @20, kRight_inset: @20,
        kHideLabel: @YES, kHideLabelback: @YES, kDots: @YES, klblColor: @"FFFFFF",
        kStatusBar: @YES, kOrienation: @0, kDateFormat: @"EE,MMM d", kLocation: @"en_US_POSIX",
        kFontSize: @8, kPosDate: @30, kPosWeather: @40, kBattery: @180,
        kWallEnabled: @NO, kWallpaperMotion: @NO, kInterval: @5,
        kAPI_Music: @YES, kAPI_Battey: @YES, kAPI_System: @YES, kAPI_Weather: @YES,
        kAPI_CarPlay: @YES, kAPI_Statusbar: @YES,
        kFull_size: @30, kFullBtn_x: @14, kFullBtn_y: @14,
        kRemoveSplash: @NO,
    }];

    // BKS screen-blank hook
    void *bks = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
    if (bks) {
        void *sym = dlsym(bks, "BKSDisplayServicesSetScreenBlanked");
        if (sym)
            MSHookFunction(sym, (void *)&hook_BKSDisplayServicesSetScreenBlanked,
                           (void **)&orig_BKSDisplayServicesSetScreenBlanked);
    }

    %init(CarPlayPlusLayout);
    %init(CarPlayPlusWallpaper);
    %init(CarPlayPlusStatusBar);
    %init(CarPlayPlusFullscreen);
    %init(CarPlayPlusWidgets);

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserverForName:@"CarPlayIsConnectedDidChange" object:nil queue:nil usingBlock:OnCarPlayConnect];
    [nc addObserverForName:kIconLayoutChanged object:nil queue:nil usingBlock:OnIconLayoutChanged];
    [nc addObserverForName:kChangedImg object:nil queue:nil usingBlock:^(NSNotification *note) {
        UIWindow *w = [UIApplication sharedApplication].keyWindow;
        if (w) [[CarPlayPlusWallpaper shared] applyToWindow:w];
    }];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    (CFNotificationCallback)OnPrefsChanged,
                                    CFSTR("xyz.carplayplus.prefsChanged"),
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}