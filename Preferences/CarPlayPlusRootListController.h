//
//  CarPlayPlusRootListController.h
//  CarPlayPlus
//

#import "PSListController.h"

extern NSString *const CPPrefsIdentifier;
extern NSString *const CPDataIdentifier;

// called by every preference controller after saving a value
void CPNotifyPrefsChanged(void);

@interface CarPlayPlusRootListController : PSListController
@end