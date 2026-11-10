//
//  Preferences/PSEditableListController.h (minimal declarations for stripped SDKs)
//
#import <Preferences/PSListController.h>
#import <Preferences/PSEditableTableCell.h>

@interface PSEditableListController : PSListController <UITextFieldDelegate>
- (void)setValue:(id)value specifier:(PSSpecifier *)specifier;
@end