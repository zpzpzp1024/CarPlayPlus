//
//  CarPlayPlusRootListController.m
//  CarPlayPlus
//

#import "CarPlayPlusRootListController.h"
#import <MessageUI/MessageUI.h>
#import <spawn.h>
#import <notify.h>
#import <signal.h>
#import <execinfo.h>

NSString *const CPPrefsIdentifier = @"xyz.carplayplus.tweak";
NSString *const CPDataIdentifier  = @"xyz.carplayplus.data";

void CPNotifyPrefsChanged(void) {
    notify_post("xyz.carplayplus.prefsChanged");
}

// ---------------------------------------------------------------------------
// Crash logging — the Settings process loads this bundle, so an uncaught
// exception or fatal signal here crashes the whole Preferences app. Write a
// backtrace to a mobile-writable file so it can be fetched over SSH or read
// from Filza (Dopamine/rootless compatible: /var is real, never faked).
// ---------------------------------------------------------------------------
static NSString *CPCrashLogPath(void) {
    return @"/var/mobile/Documents/carplayplus_crash.log";
}

static void CPCrashWrite(NSString *header, NSArray<NSString *> *frames) {
    @autoreleasepool {
        NSString *log = [NSString stringWithFormat:
            @"===== %@ =====\n%@\n%@\n\n",
            [NSDate date], header,
            frames ? [frames componentsJoinedByString:@"\n"] : @"(no backtrace)"];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = [CPCrashLogPath() stringByDeletingLastPathComponent];
        if (![fm fileExistsAtPath:dir])
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:CPCrashLogPath()];
        if (!fh) {
            [log writeToFile:CPCrashLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            [fh seekToEndOfFile];
            [fh writeData:[log dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    }
}

static void CPCrashOnException(NSException *exception) {
    CPCrashWrite([NSString stringWithFormat:@"EXCEPTION: %@\n%@", exception.name, exception.reason],
                 exception.callStackSymbols);
}

static void CPCrashOnSignal(int sig) {
    void *frames[128];
    int n = backtrace(frames, 128);
    char **symbols = backtrace_symbols(frames, n);
    NSMutableArray *lines = [NSMutableArray array];
    for (int i = 0; i < n; i++)
        [lines addObject:symbols ? [NSString stringWithUTF8String:symbols[i]] : @"?"];
    if (symbols) free(symbols);
    CPCrashWrite([NSString stringWithFormat:@"SIGNAL: %d (%s)", sig, strsignal(sig)], lines);
    // restore default and re-raise for the real crash reporter
    signal(sig, SIG_DFL);
    raise(sig);
}

__attribute__((constructor)) static void _cp_prefs_enable_crash_logging(void) {
    NSSetUncaughtExceptionHandler(&CPCrashOnException);
    signal(SIGABRT, CPCrashOnSignal);
    signal(SIGSEGV, CPCrashOnSignal);
    signal(SIGBUS,  CPCrashOnSignal);
    signal(SIGILL,  CPCrashOnSignal);
    signal(SIGFPE,  CPCrashOnSignal);
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
                                            message:@"应用修改并注销重启？"
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"注销重启" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
        CPNotifyPrefsChanged();
        pid_t pid = 0;
        const char *argv[] = {"killall", "SpringBoard", NULL};
        NSString *jb = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? @"/var/jb" : @"";
        posix_spawn(&pid, [[jb stringByAppendingString:@"/usr/bin/killall"] UTF8String],
                    NULL, NULL, (char *const *)argv, NULL);
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