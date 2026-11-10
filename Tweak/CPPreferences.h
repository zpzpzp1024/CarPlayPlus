//
//  CPPreferences.h
//  CarPlayPlus
//
//  Self-contained preferences access for the tweak process.
//
//  Replaces the Cephei `HBPreferences` dependency with a tiny CFPreferences
//  wrapper so the project builds anywhere with a plain Theos + SDK (no
//  /Library/Frameworks/Cephei.framework required on the build machine).
//
//  Semantics match the upstream behavior:
//    * SpringBoard / CarPlay run as root while the Settings app runs as
//      mobile — we therefore read with kCFPreferencesAnyUser so the tweak
//      always sees the values stored by the preferences bundle, and write
//      back to the same domain.
//

#import <Foundation/Foundation.h>

static NSString *const kCPPrefsDomain = @"xyz.carplayplus.tweak";

static NSDictionary *gCPPrefsDefaults;

static inline void CPPrefsRegisterDefaults(NSDictionary *defaults) {
    gCPPrefsDefaults = defaults;
}

static inline id CPPrefsObjectForKey(NSString *key) {
    if (!key.length) return nil;
    id value = (__bridge_transfer id)CFPreferencesCopyValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)kCPPrefsDomain,
        kCFPreferencesAnyUser,
        kCFPreferencesCurrentHost);
    if (value) return value;
    return gCPPrefsDefaults[key];
}

static inline void CPPrefsSetObject(NSString *key, id value) {
    if (!key.length) return;
    CFPreferencesSetValue((__bridge CFStringRef)key,
                          (__bridge CFPropertyListRef)value,
                          (__bridge CFStringRef)kCPPrefsDomain,
                          kCFPreferencesAnyUser,
                          kCFPreferencesCurrentHost);
    CFPreferencesSynchronize((__bridge CFStringRef)kCPPrefsDomain,
                             kCFPreferencesAnyUser,
                             kCFPreferencesCurrentHost);
}

static inline void CPPrefsRemoveObject(NSString *key) {
    if (!key.length) return;
    CFPreferencesSetValue((__bridge CFStringRef)key,
                          NULL,
                          (__bridge CFStringRef)kCPPrefsDomain,
                          kCFPreferencesAnyUser,
                          kCFPreferencesCurrentHost);
    CFPreferencesSynchronize((__bridge CFStringRef)kCPPrefsDomain,
                             kCFPreferencesAnyUser,
                             kCFPreferencesCurrentHost);
}

static inline BOOL CPPrefsBoolForKey(NSString *key, BOOL def) {
    id value = CPPrefsObjectForKey(key);
    return value ? [value boolValue] : def;
}

static inline NSInteger CPPrefsIntegerForKey(NSString *key, NSInteger def) {
    id value = CPPrefsObjectForKey(key);
    return value ? [value integerValue] : def;
}

static inline CGFloat CPPrefsCGFloatForKey(NSString *key, CGFloat def) {
    return (CGFloat)CPPrefsIntegerForKey(key, (NSInteger)def);
}

static inline NSString *CPPrefsStringForKey(NSString *key, NSString *def) {
    id value = CPPrefsObjectForKey(key);
    return [value isKindOfClass:[NSString class]] ? value : def;
}