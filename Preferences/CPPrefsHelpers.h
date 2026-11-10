//
//  CPPrefsHelpers.h
//  CarPlayPlus — preference bundle
//
//  CFPreferences helpers used by the Settings bundle. Writes and reads the
//  tweak preference domain (xyz.carplayplus.tweak) using the any-user scope
//  so values stay visible to SpringBoard / CarPlay which run as root.
//

#import <Foundation/Foundation.h>

static inline id CPPrefAnyGet(NSString *domain, NSString *key) {
    if (!domain.length || !key.length) return nil;
    return (__bridge_transfer id)CFPreferencesCopyValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)domain,
        kCFPreferencesAnyUser,
        kCFPreferencesCurrentHost);
}

static inline void CPPrefAnySet(NSString *domain, NSString *key, id value) {
    if (!domain.length || !key.length) return;
    CFPreferencesSetValue((__bridge CFStringRef)key,
                          (__bridge CFPropertyListRef)value,
                          (__bridge CFStringRef)domain,
                          kCFPreferencesAnyUser,
                          kCFPreferencesCurrentHost);
    CFPreferencesSynchronize((__bridge CFStringRef)domain,
                             kCFPreferencesAnyUser,
                             kCFPreferencesCurrentHost);
}

static inline void CPPrefAnyRemove(NSString *domain, NSString *key) {
    if (!domain.length || !key.length) return;
    CFPreferencesSetValue((__bridge CFStringRef)key,
                          NULL,
                          (__bridge CFStringRef)domain,
                          kCFPreferencesAnyUser,
                          kCFPreferencesCurrentHost);
    CFPreferencesSynchronize((__bridge CFStringRef)domain,
                             kCFPreferencesAnyUser,
                             kCFPreferencesCurrentHost);
}