//
//  HBPreferences.h
//  Cephei — minimal public-header subset used by CarPlayPlus.
//
//  Real headers live in the Cephei framework (github.com/hbang/cephei),
//  installed on-device by the `ws.hbang.common` dependency. This project-local
//  copy keeps the Theos build self-contained.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HBPreferences : NSObject

- (instancetype)initWithIdentifier:(NSString *)identifier;

- (nullable id)objectForKey:(NSString *)key;
- (void)setObject:(nullable id)object forKey:(NSString *)key;
- (void)removeObjectForKey:(NSString *)key;
- (void)removeAllObjects;

- (void)registerDefaults:(NSDictionary<NSString *, id> *)defaults;
- (void)reload;

@property (nonatomic, readonly, copy) NSDictionary<NSString *, id> *dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END