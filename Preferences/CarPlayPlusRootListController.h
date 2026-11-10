//
//  CarPlayPlusRootListController.h
//  CarPlayPlus
//

#import <Preferences/PSListController.h>
#import <CepheiPrefs/HBListController.h>

extern NSString *const CPPrefsIdentifier;
extern NSString *const CPDataIdentifier;

// called by every preference controller after saving a value
void CPNotifyPrefsChanged(void);

@interface CarPlayPlusRootListController : HBListController
@end