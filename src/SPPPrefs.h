#import <Foundation/Foundation.h>

#define SPP_PREFS_DOMAIN @"com.anlai97.speedpop"

// Doc cau hinh tu domain com.anlai97.speedpop (Settings ghi qua cfprefsd), doc moi lan -> co hieu luc ngay
@interface SPPPrefs : NSObject
+ (BOOL)enabled;          // bat bong bong
+ (NSInteger)style;       // 0 Vietmap, 1 Toi gian, 2 Bien bao, 3 Dong ho, 4 HUD, 5 Mau toc do
+ (BOOL)appEnabled:(int)appIndex;   // nhan toc do tu app nay (chi so trong SPP_NAV_APPS)
@end
