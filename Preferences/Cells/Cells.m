//
//  Cells.m
//  CarPlayPlus — custom preference cells
//

#import "Cells.h"
#import "CarPlayPlusRootListController.h"
#import "CPPrefsHelpers.h"
#import <Photos/Photos.h>
#import <objc/runtime.h>

static UIViewController *CPTopViewController(void) {
    UIViewController *top = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

#pragma mark - CarPlayPlusReturnCell (keyboard "return" = save & dismiss)

@interface CarPlayPlusReturnCell () <UITextFieldDelegate>
@end

@implementation CarPlayPlusReturnCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (self) {
        self.textField.delegate = self;
        self.textField.returnKeyType = UIReturnKeyDone;
    }
    return self;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

@end

#pragma mark - AColorPicker (hex color cell + native picker)

@interface AColorPicker () <UIColorPickerViewControllerDelegate>
@property (nonatomic, strong) UIColor *selected;
@property (nonatomic, assign) BOOL supportsAlpha;
@property (nonatomic, strong) NSString *fallback;
@end

@implementation AColorPicker

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (self) {
        self.supportsAlpha = [specifier.properties[@"supportAlpha"] boolValue];
        self.fallback = specifier.properties[@"fallback"] ?: @"FFFFFF";
        self.textField.keyboardType = UIKeyboardTypeAlphabet;
        self.textField.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    NSString *hex = (self.textField.text.length ? self.textField.text : self.fallback);
    [self setSwatchFromHex:hex];
}

- (void)setSwatchFromHex:(NSString *)hex {
    if (!hex.length) return;
    UIColor *c = [UIColor whiteColor];
    NSMutableString *s = [hex mutableCopy];
    [s replaceOccurrencesOfString:@"#" withString:@"" options:0 range:NSMakeRange(0, s.length)];
    unsigned val = 0;
    NSScanner *sc = [NSScanner scannerWithString:s];
    if ([sc scanHexInt:&val]) {
        CGFloat a = 1, r = 0, g = 0, b = 0;
        switch (s.length) {
            case 3:
                r = ((val>>8)&0xF)/15.0; g = ((val>>4)&0xF)/15.0; b = (val&0xF)/15.0; break;
            case 6:
                r = ((val>>16)&0xFF)/255.0; g = ((val>>8)&0xFF)/255.0; b = (val&0xFF)/255.0; break;
            case 8:
                a = ((val>>24)&0xFF)/255.0; r = ((val>>16)&0xFF)/255.0;
                g = ((val>>8)&0xFF)/255.0; b = (val&0xFF)/255.0; break;
        }
        c = [UIColor colorWithRed:r green:g blue:b alpha:a];
    }
    UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 26, 26)];
    swatch.layer.cornerRadius = 13;
    swatch.layer.borderWidth = 1;
    swatch.layer.borderColor = [UIColor grayColor].CGColor;
    swatch.backgroundColor = c;
    self.accessoryView = swatch;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    [self openColorPicker];
    [textField resignFirstResponder];
}

- (void)openColorPicker {
    if (@available(iOS 14.0, *)) {
        UIColorPickerViewController *picker = [UIColorPickerViewController new];
        picker.supportsAlpha = self.supportsAlpha;
        picker.delegate = self;
        [CPTopViewController() presentViewController:picker animated:YES completion:nil];
    }
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)viewController {
    self.selected = viewController.selectedColor;
}

- (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    [viewController dismissViewControllerAnimated:YES completion:nil];
    if (!self.selected) return;
    CGFloat r, g, b, a;
    if (![self.selected getRed:&r green:&g blue:&b alpha:&a]) return;
    NSString *hex = (self.supportsAlpha)
        ? [NSString stringWithFormat:@"%02lX%02lX%02lX%02lX",
              lroundf(r*255), lroundf(g*255), lroundf(b*255), lroundf(a*255)]
        : [NSString stringWithFormat:@"%02lX%02lX%02lX", lroundf(r*255), lroundf(g*255), lroundf(b*255)];
    self.textField.text = hex;
    [self setSwatchFromHex:hex];
    if (self.specifier) {
        PSSpecifier *spec = self.specifier;
        NSString *key = spec.properties[@"key"];
        if (key.length) {
            CPPrefAnySet(CPPrefsIdentifier, key, hex);
            CPNotifyPrefsChanged();
        }
    }
}

@end

#pragma mark - CarPlayPlusSliderCell (live value)

@implementation CarPlayPlusSliderCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (self) {
        self.label = [[UILabel alloc] initWithFrame:CGRectZero];
        self.label.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
        self.label.textColor = [UIColor secondaryLabelColor];
        self.accessoryView = self.label;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self refreshValueBadge];
}

- (void)refreshValueBadge {
    if (!self.label) return;
    UISlider *slider = nil;
    for (UIView *v in self.contentView.subviews) {
        if ([v isKindOfClass:[UISlider class]]) { slider = (UISlider *)v; break; }
    }
    if (slider) self.label.text = [NSString stringWithFormat:@"%.0f", slider.value];
    [self.label sizeToFit];
}

- (void)setValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setValue:value specifier:specifier];
    dispatch_async(dispatch_get_main_queue(), ^{ [self refreshValueBadge]; });
}

@end

#pragma mark - CarPlayPlusStepperCell

@interface CarPlayPlusStepperCell () <UITextFieldDelegate>
@end

@implementation CarPlayPlusStepperCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (self) {
        self.stepper = [UIStepper new];
        self.stepper.minimumValue = [specifier.properties[@"min"] doubleValue] ?: 0;
        self.stepper.maximumValue = [specifier.properties[@"max"] doubleValue] ?: 10;
        self.stepper.stepValue = [specifier.properties[@"step"] doubleValue] ?: 1;
        [self.stepper addTarget:self action:@selector(valueChanged:) forControlEvents:UIControlEventValueChanged];
        self.accessoryView = self.stepper;
        self.selectedControl = self.stepper;
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    id val = [specifier performGetter];
    self.stepper.value = [val doubleValue] ?: [specifier.properties[@"default"] doubleValue];
    [self updateLabel];
}

- (void)valueChanged:(UIStepper *)sender {
    [self.specifier performSetterWithValue:@(sender.value)];
    [self updateLabel];
}

- (void)updateLabel {
    NSString *fmt = self.specifier.properties[@"label"] ?: @"%i";
    self.textLabel.text = [NSString stringWithFormat:fmt, (int)self.stepper.value];
}

@end

#pragma mark - CarPlayPlusImagePickerCell

@interface CarPlayPlusImagePickerCell () <UINavigationControllerDelegate, UIImagePickerControllerDelegate>
@property (nonatomic, strong) NSString *targetKey;
@end

@implementation CarPlayPlusImagePickerCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (self) {
        self.targetKey = specifier.properties[@"key"];
    }
    return self;
}

- (void)userDidSelect {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) return;
    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self;
    [CPTopViewController() presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHAsset *asset = info[UIImagePickerControllerPHAsset];
    if (!asset || !self.targetKey.length) return;

    PHImageRequestOptions *opts = [PHImageRequestOptions new];
    opts.synchronous = YES;
    opts.networkAccessAllowed = YES;
    [[PHImageManager defaultManager] requestImageDataForAsset:asset options:opts
                                                resultHandler:^(NSData *data, NSString *uti,
                                                                UIImageOrientation o, NSDictionary *info2) {
        if (!data) return;
        NSString *dir = @"/Library/CarPlayPlus/Wallpapers";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *ext = [uti.lowercaseString containsString:@"gif"] ? @"gif" : @"png";
        NSString *path = [dir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"wp_%.0f.%@", [NSDate date].timeIntervalSince1970, ext]];
        if (![data writeToFile:path atomically:YES]) return;
        CPPrefAnySet(CPPrefsIdentifier, self.targetKey, path);
        CPNotifyPrefsChanged();
    }];
}

@end

#pragma mark - CarPlayPlusStylePickerCell

@interface CarPlayPlusStylePickerCell ()
@property (nonatomic, strong) NSString *selectedStr;
@property (nonatomic, strong) NSArray<NSDictionary *> *options;
@end

@implementation CarPlayPlusStylePickerCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:identifier specifier:specifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _options = specifier.properties[@"options"];
        self.selectedStr = [[specifier performGetter] description] ?: @"0";
        [self buildUI];
    }
    return self;
}

- (void)setValue:(id)value specifier:(PSSpecifier *)specifier {
    self.selectedStr = [value description];
    if ([specifier.properties[@"key"] isKindOfClass:[NSString class]])
        CPPrefAnySet(CPPrefsIdentifier, specifier.properties[@"key"], value);
    [self buildUI];
    CPNotifyPrefsChanged();
}

- (void)buildUI {
    for (UIView *v in self.contentView.subviews) [v removeFromSuperview];
    if (!_options.count) return;
    NSInteger selectedIndex = [_options indexOfObjectPassingTest:^BOOL(NSDictionary *o, NSUInteger i, BOOL *stop) {
        return [o[@"appearanceOption"] isEqualToString:self.selectedStr];
    }];
    if (selectedIndex == NSNotFound) selectedIndex = 0;

    CGFloat width = self.contentView.bounds.size.width;
    CGFloat pad = 12, itemW = (width - pad * 3) / (CGFloat)_options.count;
    [_options enumerateObjectsUsingBlock:^(NSDictionary *opt, NSUInteger i, BOOL *stop) {
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        btn.frame = CGRectMake(pad + i * (itemW + pad), 8, itemW, self.contentView.bounds.size.height - 16);
        btn.layer.cornerRadius = 8;
        btn.layer.borderWidth = 1;
        btn.layer.borderColor = (i == selectedIndex)
            ? [UIColor systemBlueColor].CGColor : [UIColor tertiaryLabelColor].CGColor;
        [btn setTitle:opt[@"label"] forState:UIControlStateNormal];
        [btn addTarget:self action:@selector(optionTapped:) forControlEvents:UIControlEventTouchUpInside];
        btn.tag = i;
        [self.contentView addSubview:btn];
    }];
    self.layoutMargins = UIEdgeInsetsZero;
}

- (void)optionTapped:(UIButton *)sender {
    NSDictionary *opt = _options[sender.tag];
    [self setValue:opt[@"appearanceOption"] specifier:self.specifier];
    [self buildUI];
}

@end