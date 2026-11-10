//
//  main.m
//  CarPlayPlusIconsGenerator
//
//  Generates invisible (fully transparent) CarPlay dashboard icons.
//
//  Reconstructed behavior of the upstream `/usr/bin/IconsGenerator`:
//    1. read the Carbridge preference plist → `bridgedApps` bundle IDs
//    2. for the first N entries, copy `/Applications/<App>.app` into
//       `/Library/CarPlayPlus/invisibleIcon/CarPlayPlusIcon<i>.app`
//    3. rewrite the copy's Info.plist: hidden bundle id, blank display name,
//       `SBAppTags = [hidden]`
//    4. refresh the icon cache with `/usr/bin/uicache`
//
//  The binary must be installed setuid root (see Makefile `after-install`).

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>

// Rootless-aware path helper: rootless jailbreaks (Dopamine / palera1n)
// keep the system root read-only and expose jailbreak data under /var/jb.
static NSString *CPJBPath(NSString *path) {
    static NSString *jbRoot;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ jbRoot = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? @"/var/jb" : @""; });
    return [jbRoot stringByAppendingString:path];
}

static NSString *const kCarBridgePrefs = @"/var/mobile/Library/Preferences/com.leftyfl1p.carbridge13.plist";
static NSString *kDestBase(void) { return CPJBPath(@"/Library/CarPlayPlus/invisibleIcon"); }
static NSString *const kBlindName      = @"\u2800";   // braille blank, renders as nothing
static const NSUInteger kMaxIcons      = 20;

#pragma mark - Installed applications (via LSApplicationWorkspace)

static NSDictionary<NSString *, NSString *> *InstalledAppPaths(void) {
    // Use the runtime so we don't need to link against the full private API.
    void *handle = dlopen(
        "/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices",
        RTLD_NOW);
    Class workspace = handle ? NSClassFromString(@"LSApplicationWorkspace") : Nil;
    if (!workspace) return nil;

    id instance = [workspace performSelector:@selector(defaultWorkspace)];
    NSArray *proxies = [instance performSelector:@selector(allApplications)];

    NSMutableDictionary<NSString *, NSString *> *paths = [NSMutableDictionary dictionary];
    for (id proxy in proxies) {
        NSString *bid = [proxy respondsToSelector:@selector(applicationIdentifier)]
            ? [proxy performSelector:@selector(applicationIdentifier)]
            : ([proxy respondsToSelector:@selector(applicationBundleIdentifier)]
                ? [proxy performSelector:@selector(applicationBundleIdentifier)] : nil);
        id bundleURL = [proxy respondsToSelector:@selector(bundleURL)] ? [proxy performSelector:@selector(bundleURL)] : nil;
        NSString *path = [bundleURL isKindOfClass:[NSURL class]] ? [(NSURL *)bundleURL path] : nil;
        if (bid.length && path.length) paths[bid] = path;
    }
    return paths;
}

#pragma mark - Carbridge bridged applications

static NSArray<NSString *> *BridgedAppIdentifiers(void) {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:kCarBridgePrefs];
    NSArray *bridged = plist[@"bridgedApps"];
    if (![bridged isKindOfClass:[NSArray class]] || !bridged.count) return @[];

    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (id item in bridged) {
        NSString *bid = nil;
        if ([item isKindOfClass:[NSString class]]) {
            bid = item;
        } else if ([item isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = (NSDictionary *)item;
            for (NSString *key in @[@"bundleID", @"bundleIdentifier", @"applicationBundleIdentifier", @"app"]) {
                id v = d[key];
                if ([v isKindOfClass:[NSString class]]) { bid = v; break; }
            }
        }
        if (bid.length && ![ids containsObject:bid]) [ids addObject:bid];
    }
    return ids;
}

#pragma mark - Icon cache refresh

static int RunUicache(void) {
    const char *uicachePath = CPJBPath(@"/usr/bin/uicache").UTF8String;
    const char *argv[] = {uicachePath, NULL};
    pid_t pid = 0;
    if (posix_spawn(&pid, uicachePath, NULL, NULL, argv, NULL) != 0) return -1;
    int status = 0;
    waitpid(pid, &status, 0);
    return WEXITSTATUS(status);
}

#pragma mark - entry

int main(int argc, char **argv) {
    @autoreleasepool {
        printf("CarPlayPlusIconsGenerator\n");

        if (argc < 2) {
            printf("Error:Not enough arguments\n");
            return 1;
        }
        int requested = atoi(argv[1]);
        if (requested <= 0) requested = 1;
        if ((NSUInteger)requested > kMaxIcons) requested = (int)kMaxIcons;

        // Escalate: rely on setuid root install.
        setgid(0);
        setuid(0);

        NSArray<NSString *> *bridged = BridgedAppIdentifiers();
        if (!bridged.count) {
            printf("Error:No bridged apps found in %s\n", kCarBridgePrefs.UTF8String);
            return 1;
        }
        NSDictionary<NSString *, NSString *> *appPaths = InstalledAppPaths();
        NSFileManager *fm = [NSFileManager defaultManager];
        NSError *error = nil;

        [fm createDirectoryAtPath:kDestBase() withIntermediateDirectories:YES
                        attributes:@{NSFilePosixPermissions: @0775} error:&error];
        if (error) {
            printf("Error:failed to create %s (%s)\n", kDestBase().UTF8String,
                   error.localizedDescription.UTF8String ?: "unknown");
            return 1;
        }

        BOOL allOK = YES;
        NSUInteger created = 0;
        NSUInteger limit = MIN((NSUInteger)requested, bridged.count);

        for (NSUInteger i = 0; i < limit; i++) {
            NSString *bid = bridged[i];
            NSString *source = appPaths[bid];
            if (!source.length || ![fm fileExistsAtPath:source]) {
                printf("Warning:skipping %s (app not found)\n", bid.UTF8String);
                continue;
            }

            NSString *destName = [NSString stringWithFormat:@"CarPlayPlusIcon%lu.app", (unsigned long)i];
            NSString *dest = [kDestBase() stringByAppendingPathComponent:destName];
            [fm removeItemAtPath:dest error:nil];

            if (![fm copyItemAtPath:source toPath:dest error:&error]) {
                printf("Faild:saved (%s)\n", error.localizedDescription.UTF8String ?: "copy failed");
                allOK = NO;
                continue;
            }

            NSString *infoPath = [dest stringByAppendingPathComponent:@"Info.plist"];
            NSMutableDictionary *info =
                [NSMutableDictionary dictionaryWithContentsOfFile:infoPath];
            if (!info) info = [NSMutableDictionary dictionary];
            info[@"CFBundleIdentifier"] = [NSString stringWithFormat:@"xyz.carplayplus.icon%lu", (unsigned long)i];
            info[@"CFBundleDisplayName"] = kBlindName;
            info[@"CFBundleName"] = kBlindName;
            info[@"SBAppTags"] = @[ @"hidden" ];
            if (![info writeToFile:infoPath atomically:YES]) {
                printf("Faild:saved (Info.plist write failed)\n");
                allOK = NO;
                continue;
            }

            // Drop the ad-hoc signature so the duplicated binary keeps launching.
            [fm removeItemAtPath:[dest stringByAppendingPathComponent:@"_CodeSignature"] error:nil];
            created++;
        }

        if (created) {
            int rc = RunUicache();
            if (rc != 0) printf("Warning:uicache returned %d\n", rc);
        }

        printf("%s (%lu icons)\n",
               allOK ? "Successful icon generation" : "Faild:saved",
               (unsigned long)created);
        return allOK ? 0 : 1;
    }
}