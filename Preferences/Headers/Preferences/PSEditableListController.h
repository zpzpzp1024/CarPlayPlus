//
//  Preferences/PSEditableListController.h (minimal declarations for stripped SDKs)
//
#import "PSListController.h"
#import "PSEditableTableCell.h"

@interface PSEditableListController : PSListController <UITextFieldDelegate>
- (void)setValue:(id)value specifier:(PSSpecifier *)specifier;
@end