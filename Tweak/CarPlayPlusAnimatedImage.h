//
//  CarPlayPlusAnimatedImage.h
//  CarPlayPlus
//
//  A compact GIF player built on ImageIO. Clean-room implementation used for
//  animated CarPlay wallpapers.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CarPlayPlusAnimatedImage : NSObject

@property (nonatomic, strong, readonly) UIView *view;
@property (nonatomic, assign, readonly, getter=isAnimating) BOOL animating;

- (instancetype)initWithPath:(NSString *)path frame:(CGRect)frame;
- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END