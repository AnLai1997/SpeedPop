#import <Foundation/Foundation.h>

#define SPP_PREFS_DOMAIN @"csbubble"

// Doc cau hinh tu domain csbubble (Settings ghi qua cfprefsd), doc moi lan -> co hieu luc ngay
@interface SPPPrefs : NSObject
+ (BOOL)enabled;          // bat bong bong
+ (NSInteger)style;       // 0..17, xem danh sach kieu trong SPPBubble.mm
+ (BOOL)showAppIcon;      // hien icon app dang cap toc do tren bong bong
+ (BOOL)appEnabled:(int)appIndex;   // nhan toc do tu app nay (chi so trong SPP_NAV_APPS)
+ (double)sizePercentForCar:(BOOL)car;               // kich thuoc bong bong (%), rieng iPhone / CarPlay; 100 = mac dinh
+ (void)setSizePercent:(double)pct forCar:(BOOL)car;  // ghi tu SpringBoard (chum 2 ngon / dat lai)
@end
