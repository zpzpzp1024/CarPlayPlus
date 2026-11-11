//
//  PrivateHeaders.h
//  CarPlayPlus
//
//  Minimal declarations of CarPlay/SpringBoard private classes used by the
//  tweak. Members below are only those referenced by this project; adjust the
//  layout-related bits (insets / grid configuration) for the target iOS
//  version if a key differs. Everything else is resolved at runtime.
//

#import <UIKit/UIKit.h>

#pragma mark - Icon layout (CarPlay UI framework / SpringBoard)

@interface SBIconListGridLayoutConfiguration : NSObject
@property (nonatomic, assign) NSUInteger numberOfPortraitColumns;
@property (nonatomic, assign) NSUInteger numberOfPortraitRows;
@property (nonatomic, assign) NSUInteger numberOfLandscapeColumns;
@property (nonatomic, assign) NSUInteger numberOfLandscapeRows;
@property (nonatomic, assign) CGFloat iconSize;
@end

@interface CARIconListView : UIScrollView
@property (nonatomic, strong, readonly) SBIconListGridLayoutConfiguration *iconListViewLayoutConfiguration;
@property (nonatomic, strong, readonly) SBIconListGridLayoutConfiguration *layoutConfiguration;
@property (nonatomic, strong, readonly) NSArray<UIView *> *iconViews;
@end

@interface CARIconView : UIView
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIView *labelLegibilityView;
@property (nonatomic, strong) id icon;                   // SBIcon — resolves applicationBundleID at runtime
- (void)setIconSize:(CGFloat)size;
@end

@class SBIcon;                                   // resolve at runtime

#pragma mark - Split-screen dashboard (CarPlayApp process)

// [UIApplication sharedApplication]._currentDashboard  → CARDashboard
@interface CARDashboard : NSObject
@property (nonatomic, strong) UIViewController *rootViewController;
@property (nonatomic, strong) NSDictionary *identifierToForegroundAppScenesMap;
- (void)handleEvent:(id)event;
@end

@interface CAREvent : NSObject
+ (id)eventWithType:(unsigned long long)type context:(id)context;
@end

// Root controller of the CarPlay dashboard (home) screen
@interface _CARDashboardHomeViewController : UIViewController
- (void)appDockViewController;   // CARAppDockViewController (vertical dock bar)
- (void)_refreshAppDock;
@end

@interface CARApplicationLaunchInfo : NSObject
+ (id)launchInfoForApplication:(id)application withActivationSettings:(id)settings;
@end

@interface CARIconListPageControl : UIPageControl
@end

// App grid built by the CarPlay dashboard. Hooked so ANY installed app can be
// stamped with a forged CRCarPlayAppDeclaration (see CarPlayPlus.xm, Stage 1).
@interface CARApplication : NSObject
+ (id)_newApplicationLibrary;
@end

@interface CARAppDockViewController : UIViewController
- (void)_dockButtonPressed:(id)arg1;
- (void)_refreshAppDock;
- (void)setDockEnabled:(BOOL)enabled;
@end

@interface CARApplicationInfo : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSArray *tags;
@end

#pragma mark - CarKit declaration (resolved at runtime) / LS

@interface LSApplicationProxy : NSObject
+ (id)applicationProxyForIdentifier:(NSString *)identifier;
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSArray *appTags;
@end

#pragma mark - SpringBoard hosted-window support (Stage 1; app on CarPlay display)

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (id)applicationWithBundleIdentifier:(NSString *)identifier;
- (NSArray *)allInstalledApplications;
@end

@interface SBApplication : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSURL *bundleURL;
@property (nonatomic, readonly) NSString *bundleType;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) NSArray *tags;
@property (nonatomic, readonly) id info;
@end

@interface SBSceneManagerCoordinator : NSObject
+ (instancetype)mainDisplaySceneManager;
@end

@interface SBDeviceApplicationSceneEntity : NSObject
- (id)initWithApplicationSceneHandle:(id)handle;
@end

@interface SBApplicationSceneHandleRequest : NSObject
+ (id)defaultRequestForApplication:(id)application sceneIdentity:(id)identity displayIdentity:(id)display;
@end

@interface SBAppViewController : NSObject
- (id)initWithIdentifier:(NSString *)identifier andApplicationSceneEntity:(id)entity;
@property (nonatomic, readonly) UIView *view;
@end

@interface SBSuspendedUnderLockManager : NSObject
- (int)_shouldBeBackgroundUnderLockForScene:(id)scene withSettings:(id)settings;
@end

@interface FBScene : NSObject
- (id)client;
- (void)updateSettings:(id)settings withTransitionContext:(id)context completion:(id)completion;
@end

@interface SBSceneView : UIView
- (void)_updateReferenceSize:(struct CGSize)size andOrientation:(long long)orientation;
@end

@interface FBSDisplayConfiguration : NSObject
- (id)initWithCADisplay:(id)display isMainDisplay:(BOOL)isMain;
@end

@interface UIRootSceneWindow : UIWindow
- (id)initWithDisplayConfiguration:(id)configuration;
@end

#pragma mark - Wallpaper / splash

@interface BCBatteryDeviceController : NSObject
+ (instancetype)sharedInstance;               // private framework
- (NSArray *)connectedDevices;
@end

@interface CPWRootViewController : UIViewController
@end

@interface CARSplashScreenViewController : UIViewController
@end

#pragma mark - Status bar

@interface CARStatusBarViewController : UIViewController
@end

@interface CARRootStatusBarViewController : UIViewController
@end

#pragma mark - Fullscreen

@interface CARAppDockButton : UIView         // dock button container on the dashboard
- (void)carPlayPlusToggleFullscreen;
@end

@interface _UIContextLayerHostView : UIView
@end

#pragma mark - Widgets

@interface WALockscreenWidgetViewController : UIViewController
@end

#pragma mark - Misc layout environment

// Used by iOS 14+ CarPlay to describe the current display/orientation context.
@interface CAREnvironmentConfiguration : NSObject
@property (nonatomic, assign, readonly) BOOL isRightHandDrive;
@property (nonatomic, assign, readonly) NSInteger interfaceStyle;
@end