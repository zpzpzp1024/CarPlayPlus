//
//  Cells.h
//  CarPlayPlus — custom preference cells
//

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <Preferences/PSEditableTableCell.h>
#import <Preferences/PSEditTextCell.h>
#import <Preferences/PSSliderTableCell.h>
#import <Preferences/PSControlTableCell.h>

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
@end

// Stepper cell.
@interface CarPlayPlusStepperCell : PSControlTableCell
@property (nonatomic, strong) UIStepper *stepper;
@end

// Button that picks an image (or GIF) from the photo library and saves its
// original data to a preference-stored path.
@interface CarPlayPlusImagePickerCell : PSTableCell
@end