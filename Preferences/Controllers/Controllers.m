//
//  Controllers.m
//  CarPlayPlus — preference controllers
//

#import "PSSpecifier.h"
#import <notify.h>
#import <spawn.h>
#import <objc/runtime.h>

#import "CarPlayPlusRootListController.h"
#import "Cells/Cells.h"
#import "CPPrefsHelpers.h"

#pragma mark - Base

@interface CarPlayPlusBaseController : PSListController
@end

@implementation CarPlayPlusBaseController

- (instancetype)init {
    self = [super init];
    return self;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = specifier.properties[@"key"];
    if (!key.length) return nil;
    id val = CPPrefAnyGet(CPPrefsIdentifier, key);
    if (!val) val = specifier.properties[@"default"];
    return val;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = specifier.properties[@"key"];
    if (!key.length) return;
    CPPrefAnySet(CPPrefsIdentifier, key, value);
    CPNotifyPrefsChanged();
}

// Forward the `userDidSelect` action (used by CarPlayPlusImagePickerCell rows)
// to the visible cell so the photo-picker flow can run.
- (void)userDidSelect {
    NSIndexPath *selected = self.table.indexPathForSelectedRow;
    if (!selected) return;
    PSTableCell *cell = (PSTableCell *)[self.table cellForRowAtIndexPath:selected];
    if ([cell respondsToSelector:@selector(userDidSelect)])
        [cell performSelector:@selector(userDidSelect)];
}

- (void)RestartCarPlay {
    CPNotifyPrefsChanged();
    pid_t pid = 0;
    const char *argv[] = {"killall", "CarPlay", NULL};
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)argv, NULL);
}

- (void)respring {
    CPNotifyPrefsChanged();
    pid_t pid = 0;
    const char *argv[] = {"killall", "SpringBoard", NULL};
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)argv, NULL);
}

- (void)ResetSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CarPlayPlus"
        message:@"All settings will be restored to default and device will respring. Continue?"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *a) {
            NSDictionary *all = [NSDictionary dictionaryWithContentsOfFile:
                @"/var/mobile/Library/Preferences/xyz.carplayplus.tweak.plist"];
            for (NSString *k in all.allKeys) CPPrefAnyRemove(CPPrefsIdentifier, k);
            [[NSFileManager defaultManager] removeItemAtPath:
                @"/var/mobile/Library/Preferences/xyz.carplayplus.tweak.plist" error:nil];
            [self respring];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - Icon Layout

@interface CarPlayPlusLayoutController : CarPlayPlusBaseController
@end

@implementation CarPlayPlusLayoutController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Layout" target:self];
    return _specifiers;
}

- (void)LayoutChange {
    CPNotifyPrefsChanged();
    notify_post("xyz.carplayplus.iconLayouChanged");
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CarPlayPlus"
        message:@"Icon layout restored. CarPlay will refresh." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)ResetIconLayout {
    NSArray *keys = @[@"kRows", @"kColumns", @"kIconSize", @"kTop_inset", @"kBottom_inset",
                      @"kLeft_inset", @"kRight_inset", @"kHideLabel", @"kHideLabelback",
                      @"kDots", @"klblColor"];
    [keys enumerateObjectsUsingBlock:^(NSString *k, NSUInteger i, BOOL *stop) {
        CPPrefAnyRemove(CPPrefsIdentifier, k);
    }];
    CPNotifyPrefsChanged();
    notify_post("xyz.carplayplus.iconLayouChanged");
}

- (void)CreateIcons {
    NSNumber *vicon = CPPrefAnyGet(CPPrefsIdentifier, @"kVicon");
    NSInteger count = vicon ? vicon.integerValue : 0;
    if (count <= 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CarPlayPlus"
            message:@"Set the number of icons first (1–20)." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CarPlayPlus"
        message:@"Creating transparent icons may take more than 10 seconds. Continue?"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            pid_t pid = 0;
            char countBuf[16];
            snprintf(countBuf, sizeof(countBuf), "%ld", (long)count);
            const char *argv[] = {"/usr/bin/CarPlayPlusIconsGenerator", countBuf, NULL};
            posix_spawn(&pid, argv[0], NULL, NULL, (char *const *)argv, NULL);
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)OpenCarPlay {
    // Jump to the stock CarPlay Settings section of Settings.
    NSURL *url = [NSURL URLWithString:@"App-prefs:root=CarPlay"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

@end

#pragma mark - Wallpaper

@interface CarPlayPlusWallpaperController : CarPlayPlusBaseController
@end

@implementation CarPlayPlusWallpaperController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Wallpaper" target:self];
    return _specifiers;
}

- (void)ResetWallpaper {
    CPPrefAnyRemove(CPPrefsIdentifier, @"kWallpaper");
    CPNotifyPrefsChanged();
    notify_post("xyz.carplayplus.changedImg");
}

@end

@interface CarPlayPlusSlideshowController : CarPlayPlusBaseController
@end

@implementation CarPlayPlusSlideshowController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *specs = [NSMutableArray array];
        [specs addObject:[PSSpecifier groupSpecifierWithName:@"Wallpaper Slideshow"]];
        [specs addObject:[PSSpecifier preferenceSpecifierNamed:@"Wallpaper Slideshow"
                    target:self set:NULL get:NULL detail:Nil cell:PSSwitchCell edit:Nil]];
        PSSpecifier *iv = [PSSpecifier preferenceSpecifierNamed:@"Time interval (seconds)"
                    target:self set:@selector(setPreferenceValue:specifier:)
                    get:@selector(readPreferenceValue:) detail:Nil cell:PSGroupCell edit:Nil];
        [specs addObject:iv];

        PSSpecifier *interval = [PSSpecifier preferenceSpecifierNamed:@"Time interval"
                    target:self set:@selector(setPreferenceValue:specifier:)
                    get:@selector(readPreferenceValue:) detail:Nil cell:PSGroupCell edit:Nil];
        interval.properties[@"key"] = @"kInterval";
        interval.properties[@"default"] = @5;
        interval.properties[@"min"] = @2;
        interval.properties[@"max"] = @60;
        interval.properties[@"cellClass"] = @"CarPlayPlusStepperCell";
        interval.properties[@"label"] = @"Time interval: %is";
        [specs addObject:interval];

        for (NSInteger i = 0; i < 5; i++) {
            NSString *title = [NSString stringWithFormat:@"Wallpaper No.%ld", (long)(i + 1)];
            PSSpecifier *grp = [PSSpecifier groupSpecifierWithName:title];
            [specs addObject:grp];
            PSSpecifier *picker = [PSSpecifier preferenceSpecifierNamed:title
                        target:self set:NULL get:NULL detail:Nil cell:PSGroupCell edit:Nil];
            picker.properties[@"key"] = [NSString stringWithFormat:@"kWallpaper%ld", (long)i];
            picker.properties[@"cellClass"] = @"CarPlayPlusImagePickerCell";
            picker.properties[@"action"] = @"userDidSelect";
            [specs addObject:picker];
        }

        PSSpecifier *applied = [PSSpecifier groupSpecifierWithName:@"Apply"];
        [specs addObject:applied];
        PSSpecifier *apply = [PSSpecifier preferenceSpecifierNamed:@"Apply on CarPlay"
                    target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
        apply.buttonAction = @selector(RestartCarPlay);
        [specs addObject:apply];
        _specifiers = specs;
    }
    return _specifiers;
}

@end

#pragma mark - Status Bar

@interface CarPlayPlusStatusBarController : CarPlayPlusBaseController
@end

@implementation CarPlayPlusStatusBarController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"StatusBar" target:self];
    return _specifiers;
}

- (void)ResetStatusBar {
    NSArray *keys = @[@"kStatusBar", @"kOrienation", @"kShowDate", @"kDateFormat",
                      @"kLocation", @"kFontSize", @"kPosDate", @"kWeather_icon",
                      @"kWeather_temperature", @"kPosWeather", @"kdevice_icon",
                      @"kBattery", @"kRemoveBattery"];
    [keys enumerateObjectsUsingBlock:^(NSString *k, NSUInteger i, BOOL *stop) {
        CPPrefAnyRemove(CPPrefsIdentifier, k);
    }];
    CPNotifyPrefsChanged();
}

- (void)ShowFormatHelp {
    NSURL *url = [NSURL URLWithString:@"https://nsdateformatter.com/"];
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

@end

@interface CarPlayPlusStatusBarColorController : CarPlayPlusBaseController
@end

@implementation CarPlayPlusStatusBarColorController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"StatusBarColor" target:self];
    return _specifiers;
}

- (void)ResetColor {
    [@[@"kEnaTimeColor", @"kTimeColor", @"kCarrierColor",
       @"kEnaWifiColor", @"kWifiColor", @"kEnaLteColor", @"kLTEOnColor", @"kLTEOffColor"]
        enumerateObjectsUsingBlock:^(NSString *k, NSUInteger i, BOOL *stop) {
            CPPrefAnyRemove(CPPrefsIdentifier, k);
    }];
    CPNotifyPrefsChanged();
}

@end

#pragma mark - Widgets / API

@interface CarPlayPlusWidgetsController : CarPlayPlusBaseController
@end

@implementation CarPlayPlusWidgetsController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Widgets" target:self];
    return _specifiers;
}

+ (NSArray *)discoverWidgets {
    NSMutableArray *found = [NSMutableArray array];
    NSArray *roots = @[
        @[@"/var/mobile/Library/SBHTML", @"SBHTML"],
        @[@"/var/mobile/Library/iWidgets", @"iWidgets"],
        @[@"/var/mobile/Library/Widgets/Universal", @"Universal"],
        @[@"/Library/CarPlayPlus/Widgets/Controls", @"Controls"],
    ];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSArray *pair in roots) {
        NSString *dir = pair[0];
        NSArray *names = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *name in names) {
            if ([name hasPrefix:@"."]) continue;
            BOOL isDir = NO;
            NSString *full = [dir stringByAppendingPathComponent:name];
            if (![fm fileExistsAtPath:full isDirectory:&isDir] || !isDir) continue;
            NSString *html;
            if ([pair[1] isEqualToString:@"SBHTML"]) html = [full stringByAppendingPathComponent:@"Wallpaper.html"];
            else if ([pair[1] isEqualToString:@"iWidgets"]) html = [full stringByAppendingPathComponent:@"Widget.html"];
            else if ([pair[1] isEqualToString:@"Universal"]) html = [full stringByAppendingPathComponent:@"index.html"];
            else html = [full stringByAppendingPathComponent:@"index.html"];
            if (![fm fileExistsAtPath:html]) continue;
            [found addObject:@{@"Widget_name": name, @"Widget": pair[1]}];
        }
    }
    return found;
}

- (void)AddWidget {
    NSArray *widgets = [self.class discoverWidgets];
    if (!widgets.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CarPlayPlus"
            message:@"Widgets were not found. Drop a widget folder into\n/Library/CarPlayPlus/Widgets/ first."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Add Widget"
        message:@"Choose a widget" preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *w in widgets) {
        NSString *label = [NSString stringWithFormat:@"%@  (%@)", w[@"Widget_name"], w[@"Widget"]];
        [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *a) { [self addWidgetEntry:w]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController)
        sheet.popoverPresentationController.sourceView = self.view;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)addWidgetEntry:(NSDictionary *)widget {
    NSMutableArray *active = [NSMutableArray arrayWithArray:
        (id)CPPrefAnyGet(CPPrefsIdentifier, @"kActiveWidgets") ?: @[]];
    NSMutableDictionary *entry = [widget mutableCopy];
    CGFloat side = [UIScreen mainScreen].bounds.size.width;
    entry[@"PosX"] = @(0);
    entry[@"PosY"] = @(30);
    entry[@"width"] = @(side * 0.9);
    entry[@"height"] = @(100);
    entry[@"zoom_lbl"] = @1.0;
    entry[@"pageIndex"] = @0;
    [active addObject:entry];
    CPPrefAnySet(CPPrefsIdentifier, @"kActiveWidgets", active);
    CPNotifyPrefsChanged();
    notify_post("xyz.carplayplus/updateWidgets");
}

- (void)ApplyWidgets {
    CPNotifyPrefsChanged();
    notify_post("xyz.carplayplus.updateWidgets");
}

@end

#pragma mark - Other functions

@interface CarPlayPlusOtherController : CarPlayPlusBaseController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) NSMutableArray *selectedApps;
@end

@implementation CarPlayPlusOtherController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Other" target:self];
    return _specifiers;
}

- (void)LoadApps {
    id ws = [NSClassFromString(@"LSApplicationWorkspace") performSelector:@selector(defaultWorkspace)];
    NSArray *apps = [ws performSelector:@selector(allApplications)];
    NSMutableArray *list = [NSMutableArray array];
    for (id proxy in apps) {
        NSString *bid = [proxy performSelector:@selector(applicationBundleIdentifier)];
        if (!bid || [bid hasPrefix:@"com.apple."]) continue;
        NSString *name = [proxy performSelector:@selector(localizedName)] ?: bid;
        [list addObject:@{@"id": bid, @"name": name}];
    }
    [list sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] compare:b[@"name"]];
    }];
    self.selectedApps = [NSMutableArray arrayWithArray:
        (id)CPPrefAnyGet(CPPrefsIdentifier, @"kFullApps") ?: @[]];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Fullscreen Apps"
        message:@"Select applications to open in full screen on your CarPlay." preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *app in list) {
        NSString *title = [NSString stringWithFormat:@"%@  %@", app[@"name"],
                           [self.selectedApps containsObject:app[@"id"]] ? @"✓" : @""];
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *a) {
                 if ([self.selectedApps containsObject:app[@"id"]])
                     [self.selectedApps removeObject:app[@"id"]];
                 else
                     [self.selectedApps addObject:app[@"id"]];
                 CPPrefAnySet(CPPrefsIdentifier, @"kFullApps", self.selectedApps);
                 CPNotifyPrefsChanged();
            }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
    if (sheet.popoverPresentationController) sheet.popoverPresentationController.sourceView = self.view;
    [self presentViewController:sheet animated:YES completion:nil];
}

@end

#pragma mark - Backup / Restore

@interface CarPlayPlusBackupController : UITableViewController
@property (nonatomic, strong) NSMutableArray *backups;   // {name, time, ...}
@end

static NSString *const kBackupRoot = @"/Library/CarPlayPlus/backup";

@implementation CarPlayPlusBackupController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Backup / Restore";
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.allowsSelection = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(createBackup:)];
    [self reloadBackups];
}

- (void)reloadBackups {
    NSFileManager *fm = [NSFileManager defaultManager];
    self.backups = [NSMutableArray array];
    for (NSString *name in [fm contentsOfDirectoryAtPath:kBackupRoot error:nil]) {
        if ([name hasPrefix:@"."]) continue;
        NSString *dir = [kBackupRoot stringByAppendingPathComponent:name];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:dir isDirectory:&isDir] || !isDir) continue;
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:
            [dir stringByAppendingPathComponent:@"meta.plist"]];
        [self.backups addObject:@{
            @"name": name,
            @"time": meta[@"time"] ?: @0,
        }];
    }
    [self.backups sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"time"] compare:a[@"time"]];
    }];
    [self.tableView reloadData];
}

- (void)createBackup:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Backup"
        message:@"Enter a backup name" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.text = @"Backup 1"; }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Create" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            NSString *name = [alert.textFields.firstObject.text
                stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
            if (!name.length) return;
            NSFileManager *fm = [NSFileManager defaultManager];
            NSString *dir = [kBackupRoot stringByAppendingPathComponent:name];
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            [fm copyItemAtPath:@"/var/mobile/Library/Preferences/xyz.carplayplus.tweak.plist"
                        toPath:[dir stringByAppendingPathComponent:@"tweak.plist"] error:nil];
            [fm copyItemAtPath:@"/var/mobile/Library/Preferences/xyz.carplayplus.data.plist"
                        toPath:[dir stringByAppendingPathComponent:@"data.plist"] error:nil];
            [fm copyItemAtPath:@"/Library/CarPlayPlus/Preferences/carplay.plist"
                        toPath:[dir stringByAppendingPathComponent:@"carplay.plist"] error:nil];
            NSDictionary *meta = @{@"time": @([NSDate date].timeIntervalSince1970)};
            [meta writeToFile:[dir stringByAppendingPathComponent:@"meta.plist"] atomically:YES];
            [self reloadBackups];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.backups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"bk";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
    NSDictionary *item = self.backups[indexPath.row];
    cell.textLabel.text = item[@"name"];
    NSDate *d = [NSDate dateWithTimeIntervalSince1970:[item[@"time"] doubleValue]];
    cell.detailTextLabel.text = [NSDateFormatter localizedStringFromDate:d
                                                              dateStyle:NSDateFormatterMediumStyle
                                                              timeStyle:NSDateFormatterShortStyle];
    cell.accessoryType = UITableViewCellAccessoryDetailButton;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *item = self.backups[indexPath.row];
    NSString *dir = [kBackupRoot stringByAppendingPathComponent:item[@"name"]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Restore"
        message:[NSString stringWithFormat:@"Restore \"%@\"?\nPreferences will be replaced.", item[@"name"]]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restore" style:UIAlertActionStyleDestructive
        handler:^(UIAlertAction *a) {
            NSFileManager *fm = [NSFileManager defaultManager];
            [fm copyItemAtPath:[dir stringByAppendingPathComponent:@"tweak.plist"]
                        toPath:@"/var/mobile/Library/Preferences/xyz.carplayplus.tweak.plist" error:nil];
            [fm copyItemAtPath:[dir stringByAppendingPathComponent:@"data.plist"]
                        toPath:@"/var/mobile/Library/Preferences/xyz.carplayplus.data.plist" error:nil];
            [fm copyItemAtPath:[dir stringByAppendingPathComponent:@"carplay.plist"]
                        toPath:@"/Library/CarPlayPlus/Preferences/carplay.plist" error:nil];
            CPNotifyPrefsChanged();
            UIAlertController *done = [UIAlertController alertControllerWithTitle:@"CarPlayPlus"
                message:@"Backup restored successfully.\nMust be respringed for changes to take effect."
                preferredStyle:UIAlertControllerStyleAlert];
            [done addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDefault
                handler:^(UIAlertAction *x) {
                    pid_t pid = 0; const char *argv[] = {"killall", "SpringBoard", NULL};
                    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)argv, NULL);
                }]];
            [self presentViewController:done animated:YES completion:nil];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = self.backups[indexPath.row];
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
        title:@"Delete" handler:^(UIContextualAction *a, UIView *v, void (^done)(BOOL)) {
            NSString *dir = [kBackupRoot stringByAppendingPathComponent:item[@"name"]];
            [[NSFileManager defaultManager] removeItemAtPath:dir error:nil];
            [self reloadBackups];
            done(YES);
        }];
    return [UISwipeActionsConfiguration configurationWithActions:@[del]];
}

@end

#pragma mark - Special Thanks / Info

@interface CarPlayPlusSpecialThanksController : CarPlayPlusBaseController
@end

@implementation CarPlayPlusSpecialThanksController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"SpecialThanks" target:self];
    return _specifiers;
}

- (void)openURL:(PSSpecifier *)specifier {
    NSString *url = specifier.properties[@"url"];
    if (url) [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]
                                                options:@{} completionHandler:nil];
}

@end