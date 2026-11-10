//
//  Preferences/PSTableCell.h (minimal declarations for stripped SDKs)
//
#import <UIKit/UIKit.h>
#import "PSSpecifier.h"

@interface PSTableCell : UITableViewCell
@property (nonatomic, retain) PSSpecifier *specifier;
@property (nonatomic, assign) BOOL cellOn;
@property (nonatomic, readonly) id value;

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
                    specifier:(PSSpecifier *)specifier;
+ (UITableViewCellStyle)cellStyleFromString:(NSString *)cellStyle;
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier;
- (void)setValue:(id)value specifier:(PSSpecifier *)specifier;
@end