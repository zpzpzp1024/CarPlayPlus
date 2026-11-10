//
//  Cells.h
//  CarPlayPlus — custom preference cells
//

#import "PSListController.h"
#import "PSSpecifier.h"
#import "PSTableCell.h"
#import "PSEditableTableCell.h"
#import "PSEditTextCell.h"
#import "PSSliderTableCell.h"
#import "PSControlTableCell.h"

// Two-option image style picker (used for status bar position).
@interface CarPlayPlusStylePickerCell : PSTableCell
@end

// Hex-color text cell with a native color-picker accessory.
@interface AColorPicker : PSEditTextCell
@end

// Edit text cell whose keyboard return saves and dismisses.
@interface CarPlayPlusReturnCell : PSEditTextCell
@end

// Slider cell with a live value badge.
@interface CarPlayPlusSliderCell : PSSliderTableCell
@property (nonatomic, strong) UILabel *label;
@end

// Stepper cell.
@interface CarPlayPlusStepperCell : PSControlTableCell
@property (nonatomic, strong) UIStepper *stepper;
@end

// Button that picks an image (or GIF) from the photo library and saves its
// original data to a preference-stored path.
@interface CarPlayPlusImagePickerCell : PSTableCell
@end