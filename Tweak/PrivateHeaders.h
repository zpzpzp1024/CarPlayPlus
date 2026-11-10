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
- (void)setIconSize:(CGFloat)size;
@end

@interface CARIconListPageControl : UIPageControl
@end

#pragma mark - Wallpaper / splash

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