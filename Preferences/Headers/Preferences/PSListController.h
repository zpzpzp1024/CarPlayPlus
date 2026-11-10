//
//  Preferences/PSListController.h (minimal declarations for stripped SDKs)
//
#import "PSViewController.h"
#import "PSSpecifier.h"

@interface PSListController : PSViewController {
@protected
    NSMutableArray *_specifiers;
}
@property (nonatomic, retain) UITableView *table;
@property (nonatomic, retain) NSMutableArray *specifiers;

- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (void)reloadSpecifiers;
- (void)reloadSpecifier:(PSSpecifier *)specifier;
- (PSSpecifier *)specifierForID:(NSString *)identifier;
@end