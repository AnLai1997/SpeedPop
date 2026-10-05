#import "SPPPrefs.h"

@implementation SPPPrefs

static id value(NSString *key)
{
    static NSUserDefaults *d; static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [[NSUserDefaults alloc] initWithSuiteName:SPP_PREFS_DOMAIN]; });
    [d synchronize];
    return [d objectForKey:key];
}

+ (BOOL)enabled    { id v = value(@"Enabled"); return v ? [v boolValue] : YES; }
+ (NSInteger)style { id v = value(@"Style");   NSInteger i = v ? [v integerValue] : 0; return (i >= 0 && i < 12) ? i : 0; }

+ (BOOL)showAppIcon { id v = value(@"ShowAppIcon"); return v ? [v boolValue] : YES; }

// Khoa theo chi so SPP_NAV_APPS: AppVietmap, AppGOFA
+ (BOOL)appEnabled:(int)appIndex
{
    static NSArray *keys; static dispatch_once_t once;
    dispatch_once(&once, ^{ keys = @[@"AppVietmap", @"AppGOFA"]; });
    if (appIndex < 0 || appIndex >= (int)keys.count) return NO;
    id v = value(keys[appIndex]);
    return v ? [v boolValue] : YES;
}

@end
