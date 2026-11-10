//
//  PSCellConstants.m — local definitions of Preferences cell-type identifiers.
//
//  The stripped iOS 14.5 SDK's Preferences.tbd does not export these string
//  constants. They are plain NSString constants that identify cell types; the
//  real values come from the device's Preferences.framework at runtime, but we
//  must provide linkable definitions for the build.
//
#import "PSSpecifier.h"

NSString * const PSGroupCell      = @"PSGroupCell";
NSString * const PSLinkListCell   = @"PSLinkListCell";
NSString * const PSLinkCell       = @"PSLinkCell";
NSString * const PSSwitchCell     = @"PSSwitchCell";
NSString * const PSButtonCell     = @"PSButtonCell";
NSString * const PSSliderCell     = @"PSSliderCell";
NSString * const PSControlCell    = @"PSControlCell";