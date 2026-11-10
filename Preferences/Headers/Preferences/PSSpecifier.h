//
//  Preferences/PSSpecifier.h (minimal declarations for stripped SDKs)
//
#import <Foundation/Foundation.h>

extern NSString * const PSGroupCell;
extern NSString * const PSLinkListCell;
extern NSString * const PSLinkCell;
extern NSString * const PSSwitchCell;
extern NSString * const PSButtonCell;
extern NSString * const PSEditTextCell;
extern NSString * const PSSliderCell;
extern NSString * const PSControlCell;

@interface PSSpecifier : NSObject
@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSString *label;
@property (nonatomic, retain) NSString *identifier;
@property (nonatomic, retain) NSString *property;
@property (nonatomic, retain) NSDictionary *titleDictionary;
@property (nonatomic, retain) NSMutableDictionary *properties;
@property (nonatomic, retain) id target;
@property (nonatomic, assign) SEL action;
@property (nonatomic, assign) SEL setter;
@property (nonatomic, assign) SEL getter;
@property (nonatomic, assign) SEL buttonAction;
@property (nonatomic, retain) NSString *cellType;
@property (nonatomic, assign) Class detailControllerClass;

+ (PSSpecifier *)groupSpecifierWithName:(NSString *)name;
+ (PSSpecifier *)preferenceSpecifierNamed:(NSString *)name
                                   target:(id)target
                                      set:(SEL)setter
                                      get:(SEL)getter
                                   detail:(Class)detail
                                     cell:(NSString *)cell
                                     edit:(Class)edit;

- (id)performGetter;
- (void)performSetterWithValue:(id)value;
- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)value forKey:(NSString *)key;
- (void)performButtonAction;
@end