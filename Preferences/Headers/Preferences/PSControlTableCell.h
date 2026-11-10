//
//  Preferences/PSControlTableCell.h (minimal declarations for stripped SDKs)
//
#import <Preferences/PSTableCell.h>

@interface PSControlTableCell : PSTableCell
@property (nonatomic, retain) UIControl *control;
@property (nonatomic, retain) UIControl *selectedControl;

- (UIControl *)newControl;
- (id)controlValue;
- (void)setValue:(id)value specifier:(PSSpecifier *)specifier;
@end