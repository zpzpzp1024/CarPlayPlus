//
//  CarPlayPlusAnimatedImage.m
//  CarPlayPlus
//
//  GIF frame decoder (ImageIO) + CADisplayLink player. Clean-room code.
//

#import "CarPlayPlusAnimatedImage.h"
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>

static const NSUInteger kMaxCachedFrames = 32;

@interface CarPlayPlusAnimatedImage ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) CGImageSourceRef source;
@property (nonatomic, assign) NSUInteger frameCount;
@property (nonatomic, assign) NSUInteger currentIndex;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UIImage *> *frameCache;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *delayTimes;
@property (nonatomic, assign) CFTimeInterval accumulator;
@end

@implementation CarPlayPlusAnimatedImage

- (void)dealloc {
    [self stop];
    if (_source) { CFRelease(_source); _source = NULL; }
}

- (instancetype)initWithPath:(NSString *)path frame:(CGRect)frame {
    self = [super init];
    if (self) {
        NSURL *url = [NSURL fileURLWithPath:path];
        _source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        if (!_source) { return nil; }
        _frameCount = CGImageSourceGetCount(_source);
        _delayTimes = [NSMutableArray arrayWithCapacity:_frameCount];
        _frameCache = [NSMutableDictionary dictionaryWithCapacity:MIN(_frameCount, kMaxCachedFrames)];
        _accumulator = 0;

        for (NSUInteger i = 0; i < _frameCount; i++) {
            CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(_source, i, NULL);
            NSDictionary *gif = CFBridgingRelease(props)[(__bridge NSString *)kCGImagePropertyGIFDictionary];
            NSNumber *delay = gif[(__bridge NSString *)kCGImagePropertyGIFUnclampedDelayTime]
                                ?: gif[(__bridge NSString *)kCGImagePropertyGIFDelayTime];
            double seconds = (delay ? delay.doubleValue : 0.1);
            if (seconds < 0.02) seconds = 0.1;
            [_delayTimes addObject:@(seconds)];
        }

        _imageView = [[UIImageView alloc] initWithFrame:frame];
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        _view = _imageView;
        _currentIndex = 0;
        [self loadFrame:0 into:self.imageView];
    }
    return self;
}

- (UIImage *)frameImageAtIndex:(NSUInteger)index {
    NSNumber *key = @(index);
    UIImage *cached = self.frameCache[key];
    if (cached) return cached;
    CGImageRef cg = CGImageSourceCreateImageAtIndex(_source, index, NULL);
    UIImage *img = cg ? [UIImage imageWithCGImage:cg] : nil;
    if (cg) CGImageRelease(cg);
    if (img && self.frameCache.count < kMaxCachedFrames) self.frameCache[key] = img;
    return img;
}

- (void)loadFrame:(NSUInteger)index into:(UIImageView *)iv {
    UIImage *img = [self frameImageAtIndex:index];
    if (img) iv.image = img;
}

- (void)start {
    if (self.animating) return;
    if (self.frameCount <= 1) return;
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayDidRefresh:)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.accumulator = 0;
}

- (void)stop {
    [self.displayLink invalidate];
    self.displayLink = nil;
    self.accumulator = 0;
}

- (void)displayDidRefresh:(CADisplayLink *)link {
    if (!self.imageView.window) return;
    double delay = self.delayTimes[self.currentIndex].doubleValue;
    self.accumulator += link.duration;
    if (self.accumulator < delay) return;
    self.accumulator = 0;
    self.currentIndex = (self.currentIndex + 1) % self.frameCount;
    [self loadFrame:self.currentIndex into:self.imageView];
}

- (BOOL)isAnimating { return self.displayLink != nil; }

@end