//
//  PSEditTextCell.m — local stub.
//
//  The stripped iOS 14.5 SDK's Preferences.tbd does not export the
//  PSEditTextCell class (it is a concrete subclass of PSEditableTableCell).
//  Provide a minimal implementation so the tweak's custom cells that derive
//  from PSEditTextCell can link; at runtime the real class from the device's
//  Preferences.framework is used.
//
#import "PSEditTextCell.h"

@implementation PSEditTextCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
                    specifier:(id)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    return self;
}

@end