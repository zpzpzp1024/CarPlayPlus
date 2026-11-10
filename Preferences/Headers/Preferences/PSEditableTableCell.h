//
//  Preferences/PSEditableTableCell.h (minimal declarations for stripped SDKs)
//
#import <Preferences/PSTableCell.h>

@interface PSEditableTableCell : PSTableCell <UITextFieldDelegate>
@property (nonatomic, retain) UITextField *textField;
@end