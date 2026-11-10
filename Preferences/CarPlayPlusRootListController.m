//
//  CarPlayPlusRootListController.m
//  CarPlayPlus
//

#import "CarPlayPlusRootListController.h"
#import <Cephei/HBPreferences.h>
#import <MessageUI/MessageUI.h>
#import <spawn.h>
#import <notify.h>

NSString *const CPPrefsIdentifier = @"xyz.carplayplus.tweak";
NSString *const CPDataIdentifier  = @"xyz.carplayplus.data";

void CPNotifyPrefsChanged(void) {
    notify_post("xyz.carplayplus.prefsChanged");
}

__attribute__((constructor)) static void _cp_prefs_enable_welcome(void) {
    // nothing to do at load
}

@implementation CarPlayPlusRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIButton *respringBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [respringBtn setTitle:@"↻" forState:UIControlStateNormal];
    [respringBtn setTitleColor:[UIColor systemOrangeColor] forState:UIControlStateNormal];
    [respringBtn addTarget:self action:@selector(respring) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:respringBtn];
    [self setTitle:@"CarPlayPlus"];
}

- (void)respring {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"CarPlayPlus"
                                            message:@"Apply changes and respring?"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        CPNotifyPrefsChanged();
        pid_t pid = 0;
        const char *argv[] = {"killall", "SpringBoard", NULL};
        posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)argv, NULL);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)RestartCarPlay {
    CPNotifyPrefsChanged();
    pid_t pid = 0;
    const char *argv[] = {"killall", "CarPlay", NULL};
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, (char *const *)argv, NULL);
}

- (void)SupportMail {
    // engraved mail composer
    if (![MFMailComposeViewController canSendMail]) {
        [[UIApplication sharedApplication]
            openURL:[NSURL URLWithString:@"https://github.com"] options:@{} completionHandler:nil];
        return;
    }
    MFMailComposeViewController *vc = [MFMailComposeViewController new];
    vc.mailComposeDelegate = (id)self;
    [vc setToRecipients:@[@"you@example.com"]];
    [vc setSubject:@"CarPlayPlus Feedback"];
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)mailComposeController:(MFMailComposeViewController *)controller
      didFinishWithResult:(MFMailComposeResult)result error:(NSError *)error {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

@end