//
//  Preferences/PSEditableTableCell.h (minimal declarations for stripped SDKs)
//
#import "PSTableCell.h"

@interface PSEditableTableCell : PSTableCell <UITextFieldDelegate>
@property (nonatomic, retain) UITextField *textField;
@end