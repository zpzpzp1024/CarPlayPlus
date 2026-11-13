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
#import <sys/socket.h>
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
#import <objc/message.h>

#import "CPPreferences.h"
#import "PrivateHeaders.h"
#import "CarPlayPlusAnimatedImage.h"

// Rootless-aware path helper: rootless jailbreaks (Dopamine / palera1n)
// keep the system root read-only and expose jailbreak data under /var/jb.
static NSString *CPJBPath(NSString *path) {
    static NSString *jbRoot;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        jbRoot = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? @"/var/jb" : @"";
    });
    return [jbRoot stringByAppendingString:path];
}

// Stage 1 "any app on CarPlay": a SpringBoard-side hosted window may be active
// (see CarPlayPlusHostedWindow) and keeps the CarPlay output alive while the
// phone screen blanks. Referenced by the BKS screen-blank hook below.
static BOOL gCPHostedWindowActive = NO;

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

static BOOL (*orig_BKSDisplayServicesSetScreenBlanked)(int blanked);

static void hook_BKSDisplayServicesSetScreenBlanked(int blanked) {
    // A CarPlay "fullscreen" session keeps the CarPlay output alive; the phone
    // screen may still blank normally through the original implementation.
    if (blanked == 1 && gCPHostedWindowActive) {
        // Stage 1: an app is rendering on the CarPlay display. Let the phone
        // screen blank as intended, then immediately undo the blanking state
        // so the hosted app's animations/video keep rendering. This does not
        // relight the phone display.
        orig_BKSDisplayServicesSetScreenBlanked(1);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            orig_BKSDisplayServicesSetScreenBlanked(0);
        });
        return;
    }
    orig_BKSDisplayServicesSetScreenBlanked(blanked);
}

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
    NSString *bundle = [NSString stringWithFormat:@"%@/Widgets/Controls/%@.bundle", CPJBPath(@"/Library/CarPlayPlus"), name];
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
        // MediaRemote is a private framework; resolve the entry point at
        // runtime so the tweak can be linked against SDKs without its .tbd.
        typedef void (^CPMRRemoteCompletion)(NSDictionary *);
        typedef void (*CPMRRemoteGetNowPlayingInfoFn)(dispatch_queue_t, CPMRRemoteCompletion);
        static CPMRRemoteGetNowPlayingInfoFn MRMediaRemoteGetNowPlayingInfoPtr = NULL;
        static dispatch_once_t cpMROnce;
        dispatch_once(&cpMROnce, ^{
            void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
            if (mr) MRMediaRemoteGetNowPlayingInfoPtr = (CPMRRemoteGetNowPlayingInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
        });
        __block NSDictionary *now = nil;
        if (MRMediaRemoteGetNowPlayingInfoPtr)
            MRMediaRemoteGetNowPlayingInfoPtr(dispatch_get_main_queue(), ^(NSDictionary *info) { now = info; });
        if (now) {
            NSString *t = now[@"kMRMediaRemoteNowPlayingInfoTitle"] ?: @"";
            NSString *a = now[@"kMRMediaRemoteNowPlayingInfoArtist"] ?: @"";
            NSString *al = now[@"kMRMediaRemoteNowPlayingInfoAlbum"] ?: @"";
            NSNumber *dur = now[@"kMRMediaRemoteNowPlayingInfoDuration"] ?: @0;
            NSNumber *ela = now[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] ?: @0;
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

static void OnPrefsChanged(NSNotification *note);
static void CPApplyDashboardLayout(void);   // forward (split-screen group below)

// Re-apply preferences for the features that remain:
// split-screen dashboard customization (and its hosted-window handling).
static void OnPrefsChanged(NSNotification *note) {
    CPApplyDashboardLayout();
}

// ---------------------------------------------------------------------------
#pragma mark - WiFi auto-join on CarPlay connect (SpringBoard)
// ---------------------------------------------------------------------------
//
// When CarPlay connects (wired or wireless) and the user enabled this in
// Settings, SpringBoard opens Wi-Fi and asks the system to join the
// configured hotspot. Two backends are attempted:
//   1) WiFiManagerClient (private C API) — adds the network to the known
//      list and flags it `joinOnce` so the system joins right away.
//   2) NEHotspotConfigurationManager — public API used as a fallback.

static NSString *const kWifiAutoJoin = @"kWifiAutoJoin";
static NSString *const kWifiSSID     = @"kWifiSSID";
static NSString *const kWifiPassword = @"kWifiPassword";

typedef struct __WiFiManagerClient *WiFiManagerClientRef;
typedef struct __WiFiNetwork *WiFiNetworkRef;

typedef WiFiManagerClientRef (*CPWiFiClientCreateFn)(CFAllocatorRef, int);
typedef void (*CPWiFiClientSetPowerFn)(WiFiManagerClientRef, bool);
typedef WiFiNetworkRef (*CPWiFiClientGetNetworkFn)(WiFiManagerClientRef, CFStringRef);
typedef void (*CPWiFiClientAddNetworkFn)(WiFiManagerClientRef, WiFiNetworkRef);
typedef void (*CPWiFiClientSetNetworkPropertyFn)(WiFiManagerClientRef, WiFiNetworkRef, CFStringRef, CFTypeRef);
typedef CFMutableDictionaryRef (*CPWiFiNetworkCreateFn)(CFAllocatorRef, CFDictionaryRef);
typedef void (*CPWiFiNetworkSetPropertyFn)(WiFiNetworkRef, CFStringRef, CFTypeRef);

static WiFiManagerClientRef (*sWiFiClientCreate)(CFAllocatorRef, int);
static void (*sWiFiClientSetPower)(WiFiManagerClientRef, bool);
static WiFiNetworkRef (*sWiFiClientGetNetwork)(WiFiManagerClientRef, CFStringRef);
static void (*sWiFiClientAddNetwork)(WiFiManagerClientRef, WiFiNetworkRef);
static void (*sWiFiClientSetNetworkProperty)(WiFiManagerClientRef, WiFiNetworkRef, CFStringRef, CFTypeRef);
static CFMutableDictionaryRef (*sWiFiNetworkCreate)(CFAllocatorRef, CFDictionaryRef);
static void (*sWiFiNetworkSetProperty)(WiFiNetworkRef, CFStringRef, CFTypeRef);

static void CPWiFiLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[CarPlayPlus WiFi] %@", msg);
}

static BOOL CPWiFiLoadSymbols(void) {
    static BOOL loaded = NO;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *paths = @[
            @"/System/Library/PrivateFrameworks/WiFiManager.framework/WiFiManager",
            @"/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi",
        ];
        for (NSString *path in paths) {
            void *handle = dlopen(path.UTF8String, RTLD_NOW);
            if (!handle) continue;
            sWiFiClientCreate          = (CPWiFiClientCreateFn)dlsym(handle, "WiFiManagerClientCreate");
            sWiFiClientSetPower        = (CPWiFiClientSetPowerFn)dlsym(handle, "WiFiManagerClientSetPower");
            sWiFiClientGetNetwork      = (CPWiFiClientGetNetworkFn)dlsym(handle, "WiFiManagerClientGetNetwork");
            sWiFiClientAddNetwork      = (CPWiFiClientAddNetworkFn)dlsym(handle, "WiFiManagerClientAddNetwork");
            sWiFiClientSetNetworkProperty = (CPWiFiClientSetNetworkPropertyFn)dlsym(handle, "WiFiManagerClientSetNetworkProperty");
            sWiFiNetworkCreate         = (CPWiFiNetworkCreateFn)dlsym(handle, "WiFiNetworkCreate");
            sWiFiNetworkSetProperty    = (CPWiFiNetworkSetPropertyFn)dlsym(handle, "WiFiNetworkSetProperty");
            if (sWiFiClientCreate && sWiFiClientAddNetwork) {
                loaded = YES;
                break;
            }
        }
    });
    return loaded;
}

static void CPJoinWiFiNetwork(NSString *ssid, NSString *password) {
    if (!ssid.length) return;

    // 1) Make sure Wi-Fi is turned on (SpringBoard controls it).
    @try {
        id wifiMgr = [NSClassFromString(@"SBWiFiManager") performSelector:@selector(sharedInstance)];
        if (wifiMgr && [wifiMgr respondsToSelector:@selector(setWiFiEnabled:)]) {
            ((void (*)(id, SEL, BOOL))objc_msgSend)(wifiMgr, NSSelectorFromString(@"setWiFiEnabled:"), YES);
        }
    } @catch (NSException *e) {}

    // 2) Primary path: WiFiManagerClient private API (add + joinOnce).
    if (CPWiFiLoadSymbols()) {
        WiFiManagerClientRef client = sWiFiClientCreate(kCFAllocatorDefault, 0);
        if (!client) {
            CPWiFiLog(@"failed to create WiFiManagerClient");
            return;
        }
        if (sWiFiClientSetPower) sWiFiClientSetPower(client, true);

        CFStringRef ssidRef = (__bridge CFStringRef)ssid;
        WiFiNetworkRef net = sWiFiClientGetNetwork ? sWiFiClientGetNetwork(client, ssidRef) : NULL;
        BOOL added = NO;
        if (!net && ssid.length) {
            NSMutableDictionary *props = [NSMutableDictionary dictionary];
            props[@"SSID"] = ssid;
            if (password.length) props[@"Password"] = password;
            CFMutableDictionaryRef propsRef = sWiFiNetworkCreate
                ? sWiFiNetworkCreate(kCFAllocatorDefault, (__bridge CFDictionaryRef)props)
                : NULL;
            if (propsRef) {
                sWiFiClientAddNetwork(client, (WiFiNetworkRef)propsRef);
                added = YES;
                if (sWiFiClientGetNetwork) net = sWiFiClientGetNetwork(client, ssidRef);
                CFRelease(propsRef);
            }
        }
        if (net) {
            if (sWiFiClientSetNetworkProperty)
                sWiFiClientSetNetworkProperty(client, net, CFSTR("joinOnce"), kCFBooleanTrue);
            if (sWiFiNetworkSetProperty)
                sWiFiNetworkSetProperty(net, CFSTR("remember"), kCFBooleanTrue);
        }
        CPWiFiLog(@"join \"%@\" added=%d known=%s", ssid, added, net ? "yes" : "no");
        CFRelease(client);
        return;
    }

    // 3) Fallback: public NEHotspotConfiguration API.
    @try {
        dlopen("/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension", RTLD_NOW);
        Class cfgClass = NSClassFromString(@"NEHotspotConfiguration");
        Class mgrClass = NSClassFromString(@"NEHotspotConfigurationManager");
        if (cfgClass && mgrClass) {
            id cfg = [[cfgClass alloc] initWithSSID:ssid
                                         passphrase:password.length ? password : nil
                                             isWEP:NO];
            if (cfg) {
                id manager = [mgrClass sharedManager];
                [manager applyConfiguration:cfg completionHandler:^(NSError *error) {
                    CPWiFiLog(@"NEHotspot apply \"%@\" error=%@", ssid, error);
                }];
            }
        }
    } @catch (NSException *e) {
        CPWiFiLog(@"NEHotspot fallback failed: %@", e);
    }
}

// Called when CarPlay transitions to connected. Delays briefly so the
// network stack settles, then joins the configured hotspot.
static void CPWiFiHandleCarPlayConnected(BOOL isConnected) {
    if (!isConnected) return;
    if (!gEnabled() || !CPPrefsBoolForKey(kWifiAutoJoin, NO)) return;
    NSString *ssid = CPPrefsStringForKey(kWifiSSID, nil);
    if (!ssid.length) return;
    NSString *password = CPPrefsStringForKey(kWifiPassword, @"");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        CPJoinWiFiNetwork(ssid, password);
    });
}

// Called from SpringBoard when the phone connects / disconnects CarPlay.
static void OnCarPlayConnectForWiFi(NSNotification *note) {
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) return;
    NSDictionary *ui = note.userInfo;
    NSNumber *connected = ui[@"IsConnected"] ?: ui[@"CarPlayIsConnectedDidChange_IsConnected"];
    BOOL isConnected = connected ? connected.boolValue : YES;
    CPWiFiHandleCarPlayConnected(isConnected);
}

// Fallback detection: SpringBoard exposes the live CarPlay session through
// AVExternalDevice. Poll it so the auto-join triggers even when the
// notification above doesn't reach SpringBoard on a given iOS version.
static BOOL CPIsCarPlayCurrentlyConnected(void) {
    @try {
        Class cls = NSClassFromString(@"AVExternalDevice");
        if (cls && [cls respondsToSelector:@selector(currentCarPlayExternalDevice)]) {
            id device = [cls performSelector:@selector(currentCarPlayExternalDevice)];
            return device != nil;
        }
    } @catch (NSException *e) {}
    return NO;
}

static BOOL gCarPlayWasConnected = NO;

static void CPWiFiPollCarPlay(void) {
    @autoreleasepool {
        BOOL now = CPIsCarPlayCurrentlyConnected();
        if (now && !gCarPlayWasConnected)
            CPWiFiHandleCarPlayConnected(YES);
        gCarPlayWasConnected = now;
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Split-screen dashboard customization (runs in com.apple.CarPlayApp)
// ---------------------------------------------------------------------------
//
// The CarPlay dashboard ("split view") is a CarPlayApp-scene UI rooted in
// [UIApplication sharedApplication]._currentDashboard (a CARDashboard). Its
// root view controller (_CARDashboardHomeViewController) hosts the vertical
// dock bar and the grid/dashboard panes. The tweak lets the user pin any
// CarPlay-enabled app to each of the three panes (left / top-right /
// bottom-right). Pane layout itself is decided by CarPlay after the pinned
// apps are launched, so this first pass launches the app via icon-tap
// simulation - CarPlay then assigns it to the appropriate pane.
//
// Because pane container classes differ between iOS releases, we additionally
// provide "Export CarPlay diagnostics" (Settings) which dumps the runtime
// dashboard hierarchy to /var/mobile/Documents/carplayplus_dump.txt so the
// exact pane containers can be pinned precisely on the next iteration.

static NSString *const kDashboardCustom   = @"kDashboardCustom";
static NSString *const kDashLeft          = @"kDashLeft";
static NSString *const kDashRightTop      = @"kDashRightTop";
static NSString *const kDashRightBottom   = @"kDashRightBottom";
static NSString *const kDumpNotification  = @"xyz.carplayplus.dumpDashboard";
static NSString *const kAnyAppCarPlay     = @"kAnyAppCarPlay";

// ---------------------------------------------------------------------------
// Stage 1 — "any app on CarPlay" runtime helpers (shared by CPLaunchDashboardApp
// below and the CarPlayPlusAnyApp group further down).
// ---------------------------------------------------------------------------

static BOOL CPAnyAppEnabled(void) { return gEnabled() && boolPref(kAnyAppCarPlay, YES); }

static void CPAnyAppLog(NSString *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[CarPlayPlus AnyApp] %@", msg);
}

// An app stamped with a forged CarPlay declaration carries a "CarPlayEnable"
// tag (set via the ivars _tags / _carPlayDeclaration on CARApplicationInfo).
static BOOL CPIsForcedCarPlayApp(id appInfo) {
    @try {
        if (!appInfo) return NO;
        id tags = [appInfo valueForKey:@"tags"];
        return [tags isKindOfClass:[NSArray class]] && [tags containsObject:@"CarPlayEnable"];
    } @catch (NSException *e) { return NO; }
}

// Ask the shared library whether a bundle id has been force-enabled for CarPlay.
static BOOL CPAppIsForcedForCarPlay(NSString *bundleID) {
    @try {
        if (!bundleID.length) return NO;
        id library = [[UIApplication sharedApplication] valueForKey:@"sharedApplicationLibrary"];
        if (!library) return NO;
        SEL sInfo = NSSelectorFromString(@"applicationInfoForBundleIdentifier:");
        if (![library respondsToSelector:sInfo]) return NO;
        return CPIsForcedCarPlayApp([library performSelector:sInfo withObject:bundleID]);
    } @catch (NSException *e) { return NO; }
}

// Rate-limit repeated forced-app launch requests (dashboard re-appear would
// otherwise dismiss + re-host the app on every viewDidAppear).
static NSMutableDictionary<NSString *, NSNumber *> *gForcedLaunchTimes;
static BOOL CPRecentlyRequestedForcedApp(NSString *bundleID) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gForcedLaunchTimes = [NSMutableDictionary dictionary]; });
    NSTimeInterval last = [gForcedLaunchTimes[bundleID] doubleValue];
    if (last > 0 && ([NSDate date].timeIntervalSince1970 - last) < 15.0) return YES;
    gForcedLaunchTimes[bundleID] = @([NSDate date].timeIntervalSince1970);
    return NO;
}

// Forward a launch request to SpringBoard, which hosts the app's scene in a
// window attached to the CarPlay display.
static void CPLogLaunchRequest(NSString *bundleID) {
    if (!bundleID.length) return;
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:@"xyz.carplayplus.launchAppOnCarPlay"
                      object:nil userInfo:@{@"identifier": bundleID}];
}

static void (*orig_CPDashHomeViewDidAppear)(id self, SEL _cmd, BOOL animated);
static void hook_CPDashHomeViewDidAppear(id self, SEL _cmd, BOOL animated) {
    orig_CPDashHomeViewDidAppear(self, _cmd, animated);
    CPApplyDashboardLayout();
}

// Depth-first search for the CarPlay icon view of a given bundle identifier.
static CARIconView *CPFindDashboardIcon(UIView *root, NSString *bundleID) {
    if (!root || !bundleID.length) return nil;
    for (UIView *sub in root.subviews) {
        if ([sub isKindOfClass:NSClassFromString(@"CARIconView")]) {
            CARIconView *iv = (CARIconView *)sub;
            NSString *bid = nil;
            if ([iv respondsToSelector:@selector(icon)]) {
                id icon = [iv performSelector:@selector(icon)];
                if ([icon respondsToSelector:@selector(applicationBundleID)])
                    bid = [icon performSelector:@selector(applicationBundleID)];
            }
            if ([bid isEqualToString:bundleID]) return iv;
        }
        CARIconView *found = CPFindDashboardIcon(sub, bundleID);
        if (found) return found;
    }
    return nil;
}

// Launch / foreground the given app inside the CarPlay dashboard.
static void CPLaunchDashboardApp(id dashboard, NSString *bundleID) {
    if (!dashboard) return;

    // Stage 1: apps force-enabled for CarPlay have no native template host.
    // Forward them to SpringBoard's hosted window on the CarPlay display.
    if (CPAppIsForcedForCarPlay(bundleID)) {
        if (CPRecentlyRequestedForcedApp(bundleID)) return;
        CPLogLaunchRequest(bundleID);
        return;
    }

    // 1) Prefer simulating a tap on the app's dashboard icon - CarPlay then
    //    launches it and places it in the correct pane (native behavior).
    UIView *rootView = nil;
    if ([dashboard respondsToSelector:@selector(rootViewController)]) {
        UIViewController *rootVC = [dashboard performSelector:@selector(rootViewController)];
        rootView = rootVC.view;
    }
    CARIconView *icon = rootView ? CPFindDashboardIcon(rootView, bundleID) : nil;
    if (icon) {
        SEL tapSel = NSSelectorFromString(@"iconTapped:");
        if ([icon respondsToSelector:tapSel]) {
            [icon performSelector:tapSel withObject:nil];
            return;
        }
        // some iOS releases use the SB-style ::_iconTapped:
        SEL itapSel = NSSelectorFromString(@"_iconTapped:");
        if ([icon respondsToSelector:itapSel]) {
            [icon performSelector:itapSel withObject:nil];
            return;
        }
    }

    // 2) Fallback: craft a CARApplicationLaunchInfo for the app. If CarPlay
    //    accepts it, the app becomes the foreground dashboard scene.
    Class proxyClass = NSClassFromString(@"LSApplicationProxy");
    Class launchClass = NSClassFromString(@"CARApplicationLaunchInfo");
    if (proxyClass && launchClass) {
        id proxy = [proxyClass performSelector:@selector(applicationProxyForIdentifier:)
                                    withObject:bundleID];
        if (proxy)
            [launchClass performSelector:@selector(launchInfoForApplication:withActivationSettings:)
                              withObject:proxy withObject:nil];
    }
}

// Apply the user's dashboard configuration to the live dashboard UI.
static void CPApplyDashboardLayout(void) {
    if (!gEnabled() || !boolPref(kDashboardCustom, NO)) return;

    UIApplication *app = [UIApplication sharedApplication];
    id dashboard = nil;
    if ([app respondsToSelector:@selector(_currentDashboard)])
        dashboard = [app performSelector:@selector(_currentDashboard)];
    if (!dashboard) return;

    NSArray *keys = @[kDashLeft, kDashRightTop, kDashRightBottom];
    for (NSString *key in keys) {
        NSString *bid = CPPrefsStringForKey(key, @"");
        if (!bid.length) continue;
        // skip apps already foregrounded on the dashboard
        if ([dashboard respondsToSelector:@selector(identifierToForegroundAppScenesMap)]) {
            NSDictionary *scenes = [dashboard valueForKey:@"identifierToForegroundAppScenesMap"];
            if ([scenes.allKeys containsObject:bid]) continue;
        }
        CPLaunchDashboardApp(dashboard, bid);
    }
}

// Recursively serialize a view + controller hierarchy for diagnostics.
static void CPDumpControllerTree(id vc, NSMutableString *out, NSInteger depth);
static void CPDumpViewTree(UIView *view, NSMutableString *out, NSInteger depth) {
    if (!view) return;
    NSString *pad = [@"" stringByPaddingToLength:depth * 2 withString:@"  " startingAtIndex:0];
    [out appendFormat:@"%@<%@: %p> frame=%@ hidden=%d\n",
        pad, NSStringFromClass(view.class), view,
        NSStringFromCGRect(view.frame), view.hidden];
    if ([view isKindOfClass:NSClassFromString(@"CARIconView")]) {
        NSString *bid = nil;
        if ([view respondsToSelector:@selector(icon)]) {
            id icon = [view performSelector:@selector(icon)];
            if ([icon respondsToSelector:@selector(applicationBundleID)])
                bid = [icon performSelector:@selector(applicationBundleID)];
        }
        [out appendFormat:@"%@  ↳ CARIconView bundleID=%@\n", pad, bid ?: @"(none)"];
    }
    for (UIView *sub in view.subviews) CPDumpViewTree(sub, out, depth + 1);
}

static void CPDumpControllerTree(id vc, NSMutableString *out, NSInteger depth) {
    if (!vc) return;
    NSString *pad = [@"" stringByPaddingToLength:depth * 2 withString:@"  " startingAtIndex:0];
    [out appendFormat:@"%@<%@: %p> title=%@\n",
        pad, NSStringFromClass([vc class]), vc, [vc performSelector:@selector(title)]];
    if ([vc respondsToSelector:@selector(view)] && [vc valueForKey:@"view"])
        CPDumpViewTree([vc valueForKey:@"view"], out, depth + 1);
    if ([vc respondsToSelector:@selector(childViewControllers)]) {
        for (id child in [vc valueForKey:@"childViewControllers"])
            CPDumpControllerTree(child, out, depth);
    }
}

static void CPWriteDashboardDump(void) {
    @autoreleasepool {
        NSMutableString *out = [NSMutableString string];
        [out appendFormat:@"===== CarPlayPlus dashboard dump %@ =====\n", [NSDate date]];
        [out appendFormat:@"process: %@\n", [NSBundle mainBundle].bundleIdentifier];
        UIApplication *app = [UIApplication sharedApplication];
        id dashboard = nil;
        if ([app respondsToSelector:@selector(_currentDashboard)])
            dashboard = [app performSelector:@selector(_currentDashboard)];
        [out appendFormat:@"dashboard: %@\n", dashboard ? NSStringFromClass([dashboard class]) : @"(nil)"];
        if (dashboard) {
            if ([dashboard respondsToSelector:@selector(identifierToForegroundAppScenesMap)]) {
                NSDictionary *scenes = [dashboard valueForKey:@"identifierToForegroundAppScenesMap"];
                [out appendFormat:@"foregroundScenes: %@\n", scenes];
            }
            if ([dashboard respondsToSelector:@selector(rootViewController)]) {
                id rootVC = [dashboard performSelector:@selector(rootViewController)];
                CPDumpControllerTree(rootVC, out, 0);
            }
        }
        NSString *path = @"/var/mobile/Documents/carplayplus_dump.txt";
        [out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

static void CPDarwinDumpCallback(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object, CFDictionaryRef info) {
    CPWriteDashboardDump();
}

// Install dashboard hooks. Safe for any process: every symbol is resolved at
// runtime and registration is skipped entirely when a class is absent.
static void CPInstallDashboardHooks(void) {
    Class cls = NSClassFromString(@"_CARDashboardHomeViewController");
    if (!cls) return;
    MSHookMessageEx(cls, @selector(viewDidAppear:),
                    (IMP)&hook_CPDashHomeViewDidAppear, (IMP *)&orig_CPDashHomeViewDidAppear);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    (CFNotificationCallback)CPDarwinDumpCallback,
                                    (__bridge CFStringRef)kDumpNotification,
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}

// ---------------------------------------------------------------------------
#pragma mark - Stage 1: "any app on CarPlay" (forged CRCarPlayAppDeclaration)
// ---------------------------------------------------------------------------
//
// Ports the proven mechanism from EthanArbuckle/carplay-cast (MIT) so that ANY
// installed app shows up in the CarPlay dashboard grid and can be presented on
// the car display — even without a native CarPlay declaration.
//
//   CarPlayApp process:
//   • +[CARApplication _newApplicationLibrary] returns a library listing every
//     installed app; each is stamped with a forged CRCarPlayAppDeclaration
//     (supportsTemplates=0, supportsMaps=1, bundle id/path) + "CarPlayEnable"
//     tag. supportsTemplates MUST stay 0 or the Template host spins up & crashes.
//   • +[CARApplicationLaunchInfo launchInfoForApplication:...] forwards launches
//     of forged apps to SpringBoard instead of running them in the template
//     host, closes the current dashboard foreground scene and refreshes the dock.
//
//   SpringBoard process:
//   • CarPlayPlusHostedWindow presents the app's *main screen* scene view inside
//     a window attached to the CarPlay display (FBSDisplayConfiguration).
//   • SBSuspendedUnderLockManager / FBScene / SBSceneView hooks keep the hosted
//     app alive under lock/backgrounding and guard orientation crashes.

%group CarPlayPlusAnyApp

// runtime shims (mirror carplay-cast's common.h) ---------------------------
#define CPPInvokeT(obj, sel, t) ((t (*)(id, SEL))objc_msgSend)(obj, NSSelectorFromString(sel))
#define CPPInvoke(obj, sel)     CPPInvokeT(obj, sel, id)
#define CPPInvoke1(obj, sel, a) ((id (*)(id, SEL, id))objc_msgSend)(obj, NSSelectorFromString(sel), a)
#define CPPInvoke2(obj, sel, a, b) ((id (*)(id, SEL, id, id))objc_msgSend)(obj, NSSelectorFromString(sel), a, b)

// Build a forged CRCarPlayAppDeclaration for an arbitrary app. ----------------
static id CPCreateFakeCarPlayDeclaration(NSString *bundleID, NSURL *bundleURL) {
    Class declClass = NSClassFromString(@"CRCarPlayAppDeclaration");
    if (!declClass) return nil;
    id declaration = [[declClass alloc] init];
    if (!declaration) return nil;
    // supportsTemplates MUST remain 0: without this the Template host process
    // continuously spins up and crashes looking for a template that doesn't exist.
    SEL s1 = NSSelectorFromString(@"setSupportsTemplates:");
    if ([declaration respondsToSelector:s1]) [declaration performSelector:s1 withObject:@0];
    SEL s2 = NSSelectorFromString(@"setSupportsMaps:");
    if ([declaration respondsToSelector:s2]) [declaration performSelector:s2 withObject:@1];
    SEL s3 = NSSelectorFromString(@"setBundleIdentifier:");
    if ([declaration respondsToSelector:s3]) [declaration performSelector:s3 withObject:bundleID];
    SEL s4 = NSSelectorFromString(@"setBundlePath:");
    if ([declaration respondsToSelector:s4]) [declaration performSelector:s4 withObject:bundleURL];
    return declaration;
}

// Stamp every undeclared user app in the library with a forged declaration. ---
static void CPAddCarplayDeclarationsToAppLibrary(id appLibrary) {
    @try {
        if (!appLibrary) return;
        NSArray *installed = nil;
        SEL sInstalled = NSSelectorFromString(@"allInstalledApplications");
        if ([appLibrary respondsToSelector:sInstalled])
            installed = [appLibrary performSelector:sInstalled];
        if (![installed isKindOfClass:[NSArray class]]) return;
        for (id appInfo in installed) {
            id existing = nil;
            @try { existing = [appInfo valueForKey:@"_carPlayDeclaration"]; } @catch (NSException *e) {}
            if (existing != nil) continue;                  // native CarPlay app? leave it alone
            NSString *bundleID = nil;
            @try { bundleID = [appInfo valueForKey:@"bundleIdentifier"]; } @catch (NSException *e) {}
            if (!bundleID.length) continue;
            id bundleType = nil;
            @try { bundleType = [appInfo valueForKey:@"bundleType"]; } @catch (NSException *e) {}
            if (![bundleType isEqualToString:@"User"] && [bundleID containsString:@"com.apple."])
                continue;                                   // skip stock/system apps
            NSURL *bundleURL = nil;
            @try { bundleURL = [appInfo valueForKey:@"bundleURL"]; } @catch (NSException *e) {}
            id declaration = CPCreateFakeCarPlayDeclaration(bundleID, bundleURL);
            if (!declaration) continue;
            @try {
                [appInfo setValue:declaration forKey:@"_carPlayDeclaration"];
                NSArray *tags = [appInfo valueForKey:@"tags"];
                NSMutableArray *newTags = [NSMutableArray arrayWithObject:@"CarPlayEnable"];
                if ([tags isKindOfClass:[NSArray class]]) [newTags addObjectsFromArray:tags];
                [appInfo setValue:newTags forKey:@"_tags"];
            } @catch (NSException *e) {}
        }
    } @catch (NSException *e) {
        CPAnyAppLog(@"CPAddCarplayDeclarationsToAppLibrary error: %@", e);
    }
}

// ---------------------------------------------------------------------------
#pragma mark - SpringBoard hosted window
// ---------------------------------------------------------------------------
// Presents an arbitrary app on the CarPlay display: the app's main-screen scene
// (SBAppViewController) is placed into a window created on the CarPlay display.

@interface CarPlayPlusHostedWindow : NSObject
@property (nonatomic, strong) UIWindow *rootWindow;
@property (nonatomic, strong) UIView *appContainerView;
@property (nonatomic, strong) id appViewController;      // SBAppViewController
@property (nonatomic, copy) NSString *hostedBundleID;
@property (nonatomic, strong) NSMutableArray *lockAssertions;
+ (instancetype)shared;
- (void)presentAppWithBundleID:(NSString *)bundleID;
- (void)dismiss;
@end

static id CPGetCarplayCADisplay(void) {
    Class avClass = NSClassFromString(@"AVExternalDevice");
    SEL sCurrent = NSSelectorFromString(@"currentCarPlayExternalDevice");
    if (!avClass || ![avClass respondsToSelector:sCurrent]) return nil;
    id carplayDevice = CPPInvoke(avClass, @"currentCarPlayExternalDevice");
    if (!carplayDevice) return nil;
    NSArray *screenIDs = CPPInvoke(carplayDevice, @"screenIDs");
    if (![screenIDs isKindOfClass:[NSArray class]] || !screenIDs.count) return nil;
    NSString *carplayUniqueID = screenIDs[0];
    Class displayClass = NSClassFromString(@"CADisplay");
    SEL sDisplays = NSSelectorFromString(@"displays");
    if (!displayClass || ![displayClass respondsToSelector:sDisplays]) return nil;
    for (id display in CPPInvoke(displayClass, @"displays")) {
        id uniqueID = CPPInvoke(display, @"uniqueId");
        if ([uniqueID isKindOfClass:[NSString class]] && [uniqueID isEqualToString:carplayUniqueID])
            return display;
    }
    return nil;
}

@implementation CarPlayPlusHostedWindow

+ (instancetype)shared {
    static CarPlayPlusHostedWindow *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [CarPlayPlusHostedWindow new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.lockAssertions = [NSMutableArray array];
    }
    return self;
}

- (void)dismiss {
    @try {
        self.hostedBundleID = nil;
        self.appViewController = nil;                 // releases the scene handle
        [self.appContainerView removeFromSuperview];
        self.appContainerView = nil;
        [self.rootWindow setHidden:YES];
        self.rootWindow = nil;
        [self.lockAssertions removeAllObjects];
        gCPHostedWindowActive = NO;
    } @catch (NSException *e) {
        CPAnyAppLog(@"dismiss error: %@", e);
    }
}

- (void)presentAppWithBundleID:(NSString *)bundleID {
    @try {
        [self dismiss];

        // 1) Find the CarPlay display and create a window attached to it.
        id carplayDisplay = CPGetCarplayCADisplay();
        if (!carplayDisplay) {
            CPAnyAppLog(@"no CarPlay CADisplay available");
            return;
        }
        Class fbsConfigClass = NSClassFromString(@"FBSDisplayConfiguration");
        if (!fbsConfigClass) return;
        id displayConfig = ((id (*)(id, SEL, id, BOOL))objc_msgSend)(
            [fbsConfigClass alloc],
            NSSelectorFromString(@"initWithCADisplay:isMainDisplay:"),
            carplayDisplay, NO);
        if (!displayConfig) return;
        Class rootWindowClass = NSClassFromString(@"UIRootSceneWindow");
        if (!rootWindowClass) return;
        self.rootWindow = ((id (*)(id, SEL, id))objc_msgSend)(
            [rootWindowClass alloc],
            NSSelectorFromString(@"initWithDisplayConfiguration:"), displayConfig);
        if (!self.rootWindow) return;

        CGRect fullFrame = self.rootWindow.bounds;
        if (CGRectIsEmpty(fullFrame)) fullFrame = CGRectMake(0, 0, 800, 400);
        self.appContainerView = [[UIView alloc] initWithFrame:fullFrame];
        self.appContainerView.backgroundColor = [UIColor blackColor];
        self.appContainerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.appContainerView.layer.cornerRadius = 13.0;
        self.appContainerView.layer.masksToBounds = YES;
        [self.rootWindow addSubview:self.appContainerView];

        // 2) Resolve the app (SBApplication).
        Class appControllerClass = NSClassFromString(@"SBApplicationController");
        if (!appControllerClass ||
            ![appControllerClass respondsToSelector:@selector(sharedInstance)]) {
            [self dismiss]; return;
        }
        id application = CPPInvoke1(CPPInvoke(appControllerClass, @"sharedInstance"),
                                    @"applicationWithBundleIdentifier:", bundleID);
        if (!application) {
            CPAnyAppLog(@"no SBApplication for %@", bundleID);
            [self dismiss]; return;
        }

        // 3) Scene identity + handle on the main display scene manager.
        Class sceneManagerClass = NSClassFromString(@"SBSceneManagerCoordinator");
        SEL sMainManager = NSSelectorFromString(@"mainDisplaySceneManager");
        if (!sceneManagerClass || ![sceneManagerClass respondsToSelector:sMainManager]) {
            [self dismiss]; return;
        }
        id sceneManager = CPPInvoke(sceneManagerClass, @"mainDisplaySceneManager");
        if (!sceneManager) { [self dismiss]; return; }
        id mainScreenIdentity = nil;
        @try { mainScreenIdentity = [sceneManager valueForKey:@"displayIdentity"]; } @catch (NSException *e) {}
        id sceneIdentity = nil;
        SEL sSceneId = NSSelectorFromString(@"_sceneIdentityForApplication:createPrimaryIfRequired:");
        if ([sceneManager respondsToSelector:sSceneId])
            sceneIdentity = ((id (*)(id, SEL, id, BOOL))objc_msgSend)(
                sceneManager, sSceneId, application, YES);
        if (!sceneIdentity) {
            CPAnyAppLog(@"no scene identity for %@", bundleID);
            [self dismiss]; return;
        }

        Class requestClass = NSClassFromString(@"SBApplicationSceneHandleRequest");
        SEL sDefaultRequest = NSSelectorFromString(@"defaultRequestForApplication:sceneIdentity:displayIdentity:");
        if (!requestClass || ![requestClass respondsToSelector:sDefaultRequest]) { [self dismiss]; return; }
        id handleRequest = ((id (*)(id, SEL, id, id, id))objc_msgSend)(
            requestClass, sDefaultRequest, application, sceneIdentity, mainScreenIdentity);
        if (!handleRequest) { [self dismiss]; return; }
        id sceneHandle = nil;
        SEL sFetchHandle = NSSelectorFromString(@"fetchOrCreateApplicationSceneHandleForRequest:");
        if ([sceneManager respondsToSelector:sFetchHandle])
            sceneHandle = [sceneManager performSelector:sFetchHandle withObject:handleRequest];
        if (!sceneHandle) { [self dismiss]; return; }

        // 4) App view controller + launch transaction.
        Class entityClass = NSClassFromString(@"SBDeviceApplicationSceneEntity");
        Class appVCClass = NSClassFromString(@"SBAppViewController");
        if (!entityClass || !appVCClass) { [self dismiss]; return; }
        id entity = ((id (*)(id, SEL, id))objc_msgSend)(
            [entityClass alloc], NSSelectorFromString(@"initWithApplicationSceneHandle:"), sceneHandle);
        if (!entity) { [self dismiss]; return; }
        self.appViewController = ((id (*)(id, SEL, id, id))objc_msgSend)(
            [appVCClass alloc],
            NSSelectorFromString(@"initWithIdentifier:andApplicationSceneEntity:"),
            bundleID, entity);
        if (!self.appViewController) { [self dismiss]; return; }

        ((void (*)(id, SEL, BOOL))objc_msgSend)(self.appViewController, NSSelectorFromString(@"setIgnoresOcclusions:"), NO);
        @try { [self.appViewController setValue:@(2) forKey:@"_currentMode"]; } @catch (NSException *e) {}
        @try {
            id activationSettings = [self.appViewController valueForKey:@"_activationSettings"];
            if ([activationSettings respondsToSelector:@selector(clearActivationSettings)])
                [activationSettings performSelector:@selector(clearActivationSettings)];
        } @catch (NSException *e) {}

        SEL sCreateTx = NSSelectorFromString(@"_createSceneUpdateTransactionForApplicationSceneEntity:deliveringActions:");
        if ([self.appViewController respondsToSelector:sCreateTx]) {
            __weak CarPlayPlusHostedWindow *weakSelf = self;
            id transaction = ((id (*)(id, SEL, id, BOOL))objc_msgSend)(
                self.appViewController, sCreateTx, entity, YES);
            if (transaction) {
                SEL sCompletion = NSSelectorFromString(@"setCompletionBlock:");
                if ([transaction respondsToSelector:sCompletion]) {
                    void (^completion)(int) = ^(int arg1) {
                        @autoreleasepool {
                            CPAnyAppLog(@"hosted app launch completed: %@", bundleID);
                            id transitions = [weakSelf.appViewController valueForKey:@"_activeTransitions"];
                            if ([transitions isKindOfClass:[NSMutableArray class]])
                                [transitions removeObject:transaction];
                        }
                    };
                    [transaction performSelector:sCompletion withObject:completion];
                }
            }
        }

        // 5) Present the scene view on the CarPlay display.
        UIView *appView = nil;
        @try { appView = [self.appViewController valueForKey:@"view"]; } @catch (NSException *e) {}
        if (appView) {
            appView.frame = self.appContainerView.bounds;
            appView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [self.appContainerView addSubview:appView];
        }

        self.hostedBundleID = bundleID;
        [self.lockAssertions addObject:bundleID];
        gCPHostedWindowActive = YES;

        [self.rootWindow setHidden:NO];
        [self.rootWindow setAlpha:0];
        [UIView animateWithDuration:0.35 animations:^{
            self.rootWindow.alpha = 1.0;
        }];
        CPAnyAppLog(@"hosted %@ on CarPlay display", bundleID);
    } @catch (NSException *e) {
        CPAnyAppLog(@"presentAppWithBundleID error: %@", e);
        [self dismiss];
    }
}

@end

// ---------------------------------------------------------------------------
#pragma mark - Hooks (CarPlayApp process)
// ---------------------------------------------------------------------------

%hook CARApplication

// Build an all-apps library + forged declarations so every user app appears in
// the dashboard grid. (Gated to the CarPlayApp process; other processes keep
// their native library.)
+ (id)_newApplicationLibrary {
    if (!CPAnyAppEnabled()) return %orig;
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.CarPlayApp"])
        return %orig;
    @try {
        Class configClass = NSClassFromString(@"FBSApplicationLibraryConfiguration");
        Class libraryClass = NSClassFromString(@"FBSApplicationLibrary");
        Class carAppInfoClass = NSClassFromString(@"CARApplicationInfo");
        if (!configClass || !libraryClass || !carAppInfoClass) return %orig;

        id configuration = [[configClass alloc] init];
        SEL sAppInfo = NSSelectorFromString(@"setApplicationInfoClass:");
        if ([configuration respondsToSelector:sAppInfo])
            [configuration performSelector:sAppInfo withObject:carAppInfoClass];
        Class placeholderClass = NSClassFromString(@"FBSApplicationPlaceholder");
        SEL sPlaceholder = NSSelectorFromString(@"setApplicationPlaceholderClass:");
        if ([configuration respondsToSelector:sPlaceholder])
            [configuration performSelector:sPlaceholder withObject:placeholderClass];
        SEL sConcurrent = NSSelectorFromString(@"setAllowConcurrentLoading:");
        if ([configuration respondsToSelector:sConcurrent])
            [configuration performSelector:sConcurrent withObject:@YES];
        SEL sFilter = NSSelectorFromString(@"setInstalledApplicationFilter:");
        if ([configuration respondsToSelector:sFilter]) {
            BOOL (^filterBlock)(id, NSSet *) = ^BOOL(id appProxy, NSSet *ignored) {
                @try {
                    NSArray *appTags = CPPInvoke(appProxy, @"appTags");
                    if ([appTags containsObject:@"hidden"]) return NO;
                } @catch (NSException *e) {}
                return YES;
            };
            [configuration performSelector:sFilter withObject:filterBlock];
        }

        id library = [[libraryClass alloc] performSelector:NSSelectorFromString(@"initWithConfiguration:")
                                                 withObject:configuration];
        if (!library) return %orig;

        CPAddCarplayDeclarationsToAppLibrary(library);

        NSArray *systemIdentifiers = @[
            @"com.apple.CarPlayTemplateUIHost", @"com.apple.MusicUIService",
            @"com.apple.springboard", @"com.apple.InCallService",
            @"com.apple.CarPlaySettings", @"com.apple.CarPlayApp"];
        Class proxyClass = NSClassFromString(@"LSApplicationProxy");
        SEL sAddProxy = NSSelectorFromString(@"addApplicationProxy:withOverrideURL:");
        if (proxyClass && [library respondsToSelector:sAddProxy]) {
            for (NSString *ident in systemIdentifiers) {
                @try {
                    id proxy = CPPInvoke1(proxyClass, @"applicationProxyForIdentifier:", ident);
                    if (proxy) [library performSelector:sAddProxy withObject:proxy withObject:nil];
                } @catch (NSException *e) {}
            }
        }
        return library;
    } @catch (NSException *e) {
        CPAnyAppLog(@"+_newApplicationLibrary error: %@", e);
        return %orig;
    }
}

%end

%hook CARApplicationLaunchInfo

// Intercept launches of forged apps and forward them to SpringBoard for
// hosting; close the current dashboard foreground scene and refresh the dock.
+ (id)launchInfoForApplication:(id)arg1 withActivationSettings:(id)arg2 {
    if (CPAnyAppEnabled() && CPIsForcedCarPlayApp(arg1)) {
        @try {
            NSString *bundleID = [arg1 valueForKey:@"bundleIdentifier"];
            CPLogLaunchRequest(bundleID);

            UIApplication *sharedApp = [UIApplication sharedApplication];

            // Record the launch in the dashboard app history → updates dock recents.
            SEL sHistory = NSSelectorFromString(@"_currentAppHistory");
            if ([sharedApp respondsToSelector:sHistory]) {
                id appHistory = [sharedApp performSelector:sHistory];
                if (appHistory) {
                    NSString *previousBundleID = nil;
                    SEL sOrdered = NSSelectorFromString(@"orderedAppHistory");
                    if ([appHistory respondsToSelector:sOrdered]) {
                        NSArray *ordered = [appHistory performSelector:sOrdered];
                        if ([ordered isKindOfClass:[NSArray class]] && ordered.count)
                            previousBundleID = [ordered.firstObject valueForKey:@"bundleIdentifier"];
                    }
                    ((void (*)(id, SEL, id, id))objc_msgSend)(
                        appHistory,
                        NSSelectorFromString(@"_bundleIdentifierDidBecomeVisible:previousBundleIdentifier:"),
                        bundleID, previousBundleID);
                }
            }

            // Refresh the dock + close the current dashboard foreground scene.
            SEL sDashboard = NSSelectorFromString(@"_currentDashboard");
            if ([sharedApp respondsToSelector:sDashboard]) {
                id dashboard = [sharedApp performSelector:sDashboard];
                if ([dashboard respondsToSelector:@selector(rootViewController)]) {
                    id rootVC = [dashboard performSelector:@selector(rootViewController)];
                    if ([rootVC respondsToSelector:@selector(appDockViewController)]) {
                        id dock = [rootVC performSelector:@selector(appDockViewController)];
                        if ([dock respondsToSelector:@selector(_refreshAppDock)])
                            [dock performSelector:@selector(_refreshAppDock)];
                    }
                }
                SEL sScenes = NSSelectorFromString(@"identifierToForegroundAppScenesMap");
                if ([dashboard respondsToSelector:sScenes]) {
                    NSDictionary *foregroundScenes = [dashboard valueForKey:@"identifierToForegroundAppScenesMap"];
                    if ([foregroundScenes isKindOfClass:[NSDictionary class]] && foregroundScenes.count) {
                        Class eventClass = NSClassFromString(@"CAREvent");
                        SEL sEvent = NSSelectorFromString(@"eventWithType:context:");
                        if (eventClass && [eventClass respondsToSelector:sEvent]) {
                            id homeEvent = ((id (*)(id, SEL, unsigned long long, id))objc_msgSend)(
                                eventClass, sEvent, (unsigned long long)1, @"Close carplay app");
                            if ([dashboard respondsToSelector:@selector(handleEvent:)])
                                [dashboard performSelector:@selector(handleEvent:) withObject:homeEvent];
                        }
                    }
                }
            }
            return nil; // not a native CarPlay app — SpringBoard will host it
        } @catch (NSException *e) {
            CPAnyAppLog(@"launchInfoForApplication error: %@", e);
        }
    }
    return %orig;
}

%end

%hook CARAppDockViewController

// Keep the dock responsive when a forged app is launched from the recents.
- (void)_dockButtonPressed:(id)arg1 {
    %orig;
    @try {
        if (!CPAnyAppEnabled()) return;
        NSString *bundleID = [arg1 valueForKey:@"bundleIdentifier"];
        if (!bundleID.length) return;
        id library = [[UIApplication sharedApplication] valueForKey:@"sharedApplicationLibrary"];
        if (!library) return;
        id appInfo = [library performSelector:NSSelectorFromString(@"applicationInfoForBundleIdentifier:")
                                   withObject:bundleID];
        if (appInfo && CPIsForcedCarPlayApp(appInfo)) {
            SEL sDockEnabled = NSSelectorFromString(@"setDockEnabled:");
            if ([self respondsToSelector:sDockEnabled])
                [self performSelector:sDockEnabled withObject:@YES];
        }
    } @catch (NSException *e) {}
}

%end

%hook _CARDashboardHomeViewController

// Re-stamp declarations whenever the dashboard refreshes its app library.
- (void)_handleAppLibraryRefresh {
    @try {
        if (CPAnyAppEnabled() && [self respondsToSelector:@selector(library)])
            CPAddCarplayDeclarationsToAppLibrary([self performSelector:@selector(library)]);
    } @catch (NSException *e) {}
    %orig;
}

%end

// ---------------------------------------------------------------------------
#pragma mark - Hooks (SpringBoard process; keep hosted apps alive)
// ---------------------------------------------------------------------------

%hook SBSuspendedUnderLockManager

// Keep forged apps alive when the phone is locked while they are being hosted.
- (int)_shouldBeBackgroundUnderLockForScene:(id)arg2 withSettings:(id)arg3 {
    int shouldBackground = %orig;
    if (shouldBackground) {
        @try {
            CarPlayPlusHostedWindow *host = [CarPlayPlusHostedWindow shared];
            if (host.lockAssertions.count) {
                NSString *sceneAppBundleID =
                    [[[arg2 valueForKey:@"client"] valueForKey:@"process"] valueForKey:@"bundleIdentifier"];
                if (sceneAppBundleID && [host.lockAssertions containsObject:sceneAppBundleID]) {
                    CPAnyAppLog(@"keeping hosted app alive under lock: %@", sceneAppBundleID);
                    shouldBackground = 0;
                }
            }
        } @catch (NSException *e) {}
    }
    return shouldBackground;
}

%end

%hook FBScene

// Prevent forged apps from being backgrounded when other apps are launched on
// the main screen while they are being hosted on CarPlay.
- (void)updateSettings:(id)arg1 withTransitionContext:(id)arg2 completion:(void *)arg3 {
    @try {
        CarPlayPlusHostedWindow *host = [CarPlayPlusHostedWindow shared];
        if (host.lockAssertions.count) {
            NSString *sceneAppBundleID =
                [[[self valueForKey:@"client"] valueForKey:@"process"] valueForKey:@"bundleIdentifier"];
            if (sceneAppBundleID && [host.lockAssertions containsObject:sceneAppBundleID]) {
                BOOL isForeground = CPPInvokeT(arg1, @"isForeground", BOOL);
                if (!isForeground) return;   // swallow the background request
            }
        }
    } @catch (NSException *e) {}
    %orig;
}

%end

%hook SBSceneView

// Scene views do not support Face-Up/Face-Down orientations — override to
// landscape (3) so a hosted app never crashes while the phone sits flat.
- (void)_updateReferenceSize:(struct CGSize)arg1 andOrientation:(long long)arg2 {
    if (arg2 > 4) return %orig(arg1, 3);
    %orig;
}

%end

%end // CarPlayPlusAnyApp

%ctor {
    CPPrefsRegisterDefaults(@{
        kEnabled: @YES,
        kDashboardCustom: @NO, kDashLeft: @"", kDashRightTop: @"", kDashRightBottom: @"",
        kAnyAppCarPlay: @YES,
        kWifiAutoJoin: @NO, kWifiSSID: @"", kWifiPassword: @"",
    });

    // Split-screen dashboard customization (CarPlayApp process; no-op elsewhere)
    CPInstallDashboardHooks();

    // Stage 1 — "any app on CarPlay" (declaration forgery + hosted window)
    %init(CarPlayPlusAnyApp);
    if ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) {
        // SpringBoard listens for launch requests from the CarPlay process and
        // hosts the requested app in a window attached to the CarPlay display.
        [[NSDistributedNotificationCenter defaultCenter]
            addObserverForName:@"xyz.carplayplus.launchAppOnCarPlay"
                        object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            NSString *identifier = note.userInfo[@"identifier"];
            if (identifier.length) [[CarPlayPlusHostedWindow shared] presentAppWithBundleID:identifier];
        }];

        // Auto-join the configured Wi-Fi hotspot when CarPlay connects.
        [[NSNotificationCenter defaultCenter]
            addObserverForName:@"CarPlayIsConnectedDidChange"
                        object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            OnCarPlayConnectForWiFi(note);
        }];

        // Fallback detector: poll AVExternalDevice so the auto-join also fires
        // on iOS builds where the notification never reaches SpringBoard.
        [NSTimer scheduledTimerWithTimeInterval:10.0 repeats:YES block:^(NSTimer *timer) {
            CPWiFiPollCarPlay();
        }];
    }

    // BKS screen-blank hook
    void *bks = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
    if (bks) {
        void *sym = dlsym(bks, "BKSDisplayServicesSetScreenBlanked");
        if (sym)
            MSHookFunction(sym, (void *)&hook_BKSDisplayServicesSetScreenBlanked,
                           (void **)&orig_BKSDisplayServicesSetScreenBlanked);
    }

    // Preferences watcher → re-apply the dashboard configuration whenever the
    // user changes a setting in the Settings app.
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    (CFNotificationCallback)OnPrefsChanged,
                                    CFSTR("xyz.carplayplus.prefsChanged"),
                                    NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
}
