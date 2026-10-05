#import "SPPPrefs.h"

@implementation SPPPrefs

static NSUserDefaults *defaults(void)
{
    static NSUserDefaults *d; static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [[NSUserDefaults alloc] initWithSuiteName:SPP_PREFS_DOMAIN]; });
    return d;
}

static id value(NSString *key)
{
    NSUserDefaults *d = defaults();
    [d synchronize];
    return [d objectForKey:key];
}

+ (BOOL)enabled    { id v = value(@"Enabled"); return v ? [v boolValue] : YES; }
+ (NSInteger)style { id v = value(@"Style");   NSInteger i = v ? [v integerValue] : 0; return (i >= 0 && i < 18) ? i : 0; }

+ (BOOL)showAppIcon { id v = value(@"ShowAppIcon"); return v ? [v boolValue] : YES; }

// Kich thuoc: SizePhone / SizeCar, 60..220 (%)
+ (double)sizePercentForCar:(BOOL)car
{
    id v = value(car ? @"SizeCar" : @"SizePhone");
    double p = v ? [v doubleValue] : 100;
    return MIN(220, MAX(60, p));
}

+ (void)setSizePercent:(double)pct forCar:(BOOL)car
{
    NSUserDefaults *d = defaults();
    [d setDouble:round(MIN(220, MAX(60, pct))) forKey:(car ? @"SizeCar" : @"SizePhone")];
    [d synchronize];
}

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
