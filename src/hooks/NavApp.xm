#import "../common.h"
#import <notify.h>
#import <CoreLocation/CoreLocation.h>

// =====================================================================
//  Inject vao app dan duong (SPP_NAV_APPS: Vietmap Live "Runner", GOFA): lay toc do + gioi han, gui sang SpringBoard.
//  - Toc do: GPS rieng cua tweak (dung quyen vi tri cua app) khi app dang bat GPS; du phong = so tren man hinh
//  - Gioi han: quet man hinh (view cua plugin dan duong / vong tron vien do / cay accessibility cua Flutter)
//  Gui qua Darwin notify + state (qua duoc sandbox cua app).
// =====================================================================
static BOOL SPPIsNumeric(NSString *t)
{
    if (t.length == 0 || t.length > 3) return NO;
    for (NSUInteger i = 0; i < t.length; i++) { unichar c = [t characterAtIndex:i]; if (c < '0' || c > '9') return NO; }
    return YES;
}

static BOOL SPPViewVisible(UIView *v)
{
    if (!v.window) return NO;
    for (UIView *x = v; x; x = x.superview) { if (x.hidden || x.alpha < 0.05) return NO; }
    CGRect r = [v convertRect:v.bounds toView:nil];
    return r.size.width > 4 && r.size.height > 4 && CGRectIntersectsRect(r, v.window.bounds);
}

// View tron: vuong (gan bang), cornerRadius >= nua canh - 2, canh 24..140
static BOOL SPPIsCircle(UIView *v)
{
    if (!v) return NO;
    CGSize s = v.bounds.size;
    if (s.width < 24 || s.width > 140 || fabs(s.width - s.height) > 3) return NO;
    return v.layer.cornerRadius >= MIN(s.width, s.height) / 2 - 2;
}

// App dang hien (scene iPhone hoac CarPlay dang o tren cung) -> SpringBoard an bong bong
static BOOL SPPAppForeground(void)
{
    if (![NSThread isMainThread]) return NO;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if (sc.activationState == UISceneActivationStateForegroundActive) return YES;
    }
    return NO;
}

static int sLastSentSpeed = -1, sLastSentLimit = -1;
static int sAppIndex = 0;   // chi so trong SPP_NAV_APPS cua app dang chay tweak

// state: bit 16 = co toc do, bit 17 = co gioi han, bit 18 = app dang hien, bit 19..21 = chi so app;
//        bit 8..15 toc do; bit 0..7 gioi han
static void SPPSendSpeed(int speed, int limit)
{
    static int token = 0;
    if (!token) notify_register_check(SPP_DARWIN_SPEED, &token);
    sLastSentSpeed = speed; sLastSentLimit = limit;
    uint64_t flags = (speed >= 0 ? 1 : 0) | (limit >= 0 ? 2 : 0) | (SPPAppForeground() ? 4 : 0) | ((uint64_t)(sAppIndex & 7) << 3);
    uint64_t state = (flags << 16) | ((uint64_t)(speed < 0 ? 0 : MIN(speed, 255)) << 8) | (uint64_t)(limit < 0 ? 0 : MIN(limit, 255));
    notify_set_state(token, state); notify_post(SPP_DARWIN_SPEED);
}

// App len tren / xuong nen (iPhone hoac CarPlay) -> bao ngay, khong cho ban tin GPS ke tiep
static void SPPWatchForeground(void)
{
    void (^resend)(void) = ^{
        if (sLastSentSpeed >= 0) SPPSendSpeed(sLastSentSpeed, sLastSentLimit);
    };
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    for (NSNotificationName name in @[UISceneDidActivateNotification, UISceneWillDeactivateNotification,
                                      UISceneDidEnterBackgroundNotification, UISceneWillEnterForegroundNotification]) {
        [nc addObserverForName:name object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
            // WillDeactivate: trang thai chua doi -> gui sau 1 nhip va lan nua khi chuyen canh xong
            dispatch_async(dispatch_get_main_queue(), resend);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), resend);
        }];
    }
}

static void SPPCollectLabels(UIView *v, NSMutableArray<UILabel *> *out, int depth)
{
    if (depth > 40) return;
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)v;
        if (SPPIsNumeric(l.text) && SPPViewVisible(l)) [out addObject:l];
    }
    for (UIView *c in v.subviews) SPPCollectLabels(c, out, depth + 1);
}

// View tron bao quanh nhan (toi da 3 cap cha)
static UIView *SPPCircleAround(UIView *v)
{
    for (UIView *x = v.superview; x && x != v.window; x = x.superview) {
        if (SPPIsCircle(x)) return x;
        if (x.superview && x.superview.superview == nil) break;
        if (x == v.superview.superview.superview) break;
    }
    return nil;
}

// Mau vien cua vong tron: layer.borderColor, hoac CAShapeLayer strokeColor, hoac view con tron co vien
static UIColor *SPPRingColor(UIView *v, int depth)
{
    if (!v || depth > 2) return nil;
    if (v.layer.borderWidth >= 1 && v.layer.borderColor) return [UIColor colorWithCGColor:v.layer.borderColor];
    for (CALayer *l in v.layer.sublayers) {
        if ([l isKindOfClass:[CAShapeLayer class]]) {
            CAShapeLayer *sh = (CAShapeLayer *)l;
            if (sh.lineWidth >= 1 && sh.strokeColor) return [UIColor colorWithCGColor:sh.strokeColor];
        }
    }
    for (UIView *c in v.subviews) {
        if ([c isKindOfClass:[UILabel class]]) continue;
        UIColor *col = SPPRingColor(c, depth + 1);
        if (col) return col;
    }
    return nil;
}

// 1 = do (gioi han), 2 = xanh duong (toc do), 0 = khong ro
static int SPPClassifyRing(UIColor *c)
{
    if (!c) return 0;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) return 0;
    if (r > 0.55 && g < 0.45 && b < 0.45) return 1;
    if (b > 0.5 && r < 0.45) return 2;
    return 0;
}

// Trong vong tron co nhan "km/h" (Vietmap: vong xanh "0 km/h")
static BOOL SPPHasUnitLabel(UIView *circle)
{
    for (UIView *c in circle.subviews) {
        if ([c isKindOfClass:[UILabel class]] && [[((UILabel *)c).text lowercaseString] containsString:@"km"]) return YES;
        for (UIView *cc in c.subviews) if ([cc isKindOfClass:[UILabel class]] && [[((UILabel *)cc).text lowercaseString] containsString:@"km"]) return YES;
    }
    return NO;
}

// ---------------------------------------------------------------------
//  App Flutter (vd Vietmap Live = process "Runner"): khong co UILabel, moi thu ve bang Skia.
//  Flutter chi xuat cay ngu nghia (semantics) cho iOS khi thay co cong cu tro nang dang chay
//  -> gia "Switch Control dang chay" trong RIENG tien trinh nay, roi doc cac phan tu accessibility.
// ---------------------------------------------------------------------
static BOOL (*orig_UIAccessibilityIsSwitchControlRunning)(void);
static BOOL hook_UIAccessibilityIsSwitchControlRunning(void) { return YES; }

static void SPPEnableFlutterSemantics(void)
{
    void *fn = dlsym(RTLD_DEFAULT, "UIAccessibilityIsSwitchControlRunning");
    if (!fn) { SPPLog("speed scan: khong tim thay UIAccessibilityIsSwitchControlRunning"); return; }
    MSHookFunction(fn, (void *)hook_UIAccessibilityIsSwitchControlRunning, (void **)&orig_UIAccessibilityIsSwitchControlRunning);
    // Flutter nghe thong bao nay de bat/tat semantics -> phat lai vai lan sau khi app len
    for (NSNumber *d in @[@2.0, @6.0, @12.0]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:UIAccessibilitySwitchControlStatusDidChangeNotification object:nil];
        });
    }
}

// Han thoi gian cho 1 lan duyet cay accessibility (chay tren luong chinh -> khong duoc lam treo app)
static CFAbsoluteTime sAXDeadline = 0;
static BOOL sAXTimedOut = NO;

// Thu thap phan tu accessibility co chu: @{ @"t": text, @"f": NSValue(CGRect man hinh) }
static void SPPCollectAX(id node, NSMutableArray<NSDictionary *> *out, NSMutableSet *seen, int depth)
{
    if (!node || depth > 80 || out.count > 600 || seen.count > 4000 || sAXTimedOut) return;
    if (CFAbsoluteTimeGetCurrent() > sAXDeadline) { sAXTimedOut = YES; return; }
    NSValue *key = [NSValue valueWithNonretainedObject:node];
    if ([seen containsObject:key]) return;
    [seen addObject:key];

    @try {
        NSString *label = [node respondsToSelector:@selector(accessibilityLabel)] ? [node accessibilityLabel] : nil;
        NSString *value = [node respondsToSelector:@selector(accessibilityValue)] ? [node accessibilityValue] : nil;
        NSMutableString *text = [NSMutableString string];
        if ([label isKindOfClass:[NSString class]] && label.length) [text appendString:label];
        if ([value isKindOfClass:[NSString class]] && value.length) { if (text.length) [text appendString:@" "]; [text appendString:value]; }
        if (text.length && ![node isKindOfClass:[UIView class]]) {   // UIView thuong la container; phan tu that la UIAccessibilityElement
            CGRect f = [node respondsToSelector:@selector(accessibilityFrame)] ? [node accessibilityFrame] : CGRectZero;
            [out addObject:@{@"t": [text copy], @"f": [NSValue valueWithCGRect:f]}];
        }
        NSArray *els = [node respondsToSelector:@selector(accessibilityElements)] ? [node accessibilityElements] : nil;
        if ([els isKindOfClass:[NSArray class]] && els.count) {
            for (id e in els) SPPCollectAX(e, out, seen, depth + 1);
        } else if ([node respondsToSelector:@selector(accessibilityElementCount)]) {
            NSInteger n = [node accessibilityElementCount];
            if (n != NSNotFound && n > 0 && n < 400) {
                for (NSInteger i = 0; i < n; i++) SPPCollectAX([node accessibilityElementAtIndex:i], out, seen, depth + 1);
            }
        }
    } @catch (NSException *e) {}
    if ([node isKindOfClass:[UIView class]]) for (UIView *c in ((UIView *)node).subviews) SPPCollectAX(c, out, seen, depth + 1);
}

// Cac so (toi da 3 chu so) xuat hien TRUOC chu "km/h" trong chuoi, theo thu tu
static NSArray<NSNumber *> *SPPNumbersBeforeKmh(NSString *t)
{
    NSString *l = [t lowercaseString];
    NSRange kr = [l rangeOfString:@"km"];
    NSString *head = (kr.location == NSNotFound) ? t : [t substringToIndex:kr.location];
    NSMutableArray<NSNumber *> *out = [NSMutableArray array];
    NSScanner *sc = [NSScanner scannerWithString:head];
    while (!sc.isAtEnd) {
        [sc scanUpToCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] intoString:nil];
        int v = 0;
        if ([sc scanInt:&v]) { if (v >= 0 && v <= 999) [out addObject:@(v)]; } else break;
    }
    return out;
}

static BOOL SPPMentionsKmh(NSString *t)
{
    NSString *l = [[t lowercaseString] stringByReplacingOccurrencesOfString:@" " withString:@""];
    return [l containsString:@"km/h"] || [l containsString:@"kmh"] || [l containsString:@"km/g"];
}

// Tu cay accessibility (Flutter): toc do = phan tu "NN km/h" (hoac so gan nhan "km/h"); gioi han = so 5..200
// nam cung hang, ben trai toc do (bo cuc Vietmap: [vong do gioi han] [vong xanh toc do]).
static BOOL SPPScanSpeedAX(UIWindow *win, int *outSpeed, int *outLimit, NSString **outDesc)
{
    NSMutableArray<NSDictionary *> *items = [NSMutableArray array];
    sAXDeadline = CFAbsoluteTimeGetCurrent() + 0.04; sAXTimedOut = NO;   // toi da 40ms moi cua so
    SPPCollectAX(win, items, [NSMutableSet set], 0);
    if (sAXTimedOut) {
        static CFAbsoluteTime lastWarn;
        if (CFAbsoluteTimeGetCurrent() - lastWarn > 20) { lastWarn = CFAbsoluteTimeGetCurrent(); SPPLog("speed scan: duyet AX qua 40ms -> dung giua chung (%lu phan tu)", (unsigned long)items.count); }
    }
    if (!items.count) return NO;

    // Flutter gop ca cum thanh 1 phan tu, vd Vietmap: "60 | 0 | km/h" = [gioi han] [toc do] km/h.
    // -> toc do = so dung NGAY TRUOC "km/h"; so con lai (neu co) = gioi han.
    NSDictionary *speedItem = nil; int speed = -1, limitFromSame = -1;
    for (NSDictionary *it in items) {
        NSString *t = it[@"t"];
        if (!SPPMentionsKmh(t)) continue;
        NSArray<NSNumber *> *nums = SPPNumbersBeforeKmh(t);
        if (!nums.count) continue;
        speedItem = it; speed = nums.lastObject.intValue;
        if (nums.count >= 2) { int cand = nums[nums.count - 2].intValue; if (cand >= 5 && cand <= 200) limitFromSame = cand; }
        break;
    }
    if (!speedItem) {
        // "km/h" dung rieng -> so gan no nhat
        NSDictionary *unit = nil;
        for (NSDictionary *it in items) if (SPPMentionsKmh(it[@"t"])) { unit = it; break; }
        if (unit) {
            CGRect uf = [unit[@"f"] CGRectValue]; CGFloat best = 1e9;
            for (NSDictionary *it in items) {
                NSString *t = [it[@"t"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (!SPPIsNumeric(t)) continue;
                CGRect f = [it[@"f"] CGRectValue];
                CGFloat d = hypot(CGRectGetMidX(f) - CGRectGetMidX(uf), CGRectGetMidY(f) - CGRectGetMidY(uf));
                if (d < best) { best = d; speedItem = it; speed = t.intValue; }
            }
        }
    }
    int limit = limitFromSame;
    if (speedItem && limit < 0) {
        CGRect sf = [speedItem[@"f"] CGRectValue]; CGFloat best = 1e9;
        for (NSDictionary *it in items) {
            if (it == speedItem) continue;
            NSString *t = [it[@"t"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (!SPPIsNumeric(t)) continue;
            int v = t.intValue; if (v < 5 || v > 200) continue;
            CGRect f = [it[@"f"] CGRectValue];
            CGFloat dy = fabs(CGRectGetMidY(f) - CGRectGetMidY(sf));
            if (dy > MAX(sf.size.height, f.size.height) * 1.2) continue;   // phai cung hang
            CGFloat dx = fabs(CGRectGetMidX(f) - CGRectGetMidX(sf));
            if (dx < best) { best = dx; limit = v; }
        }
    }
    if (outDesc) {
        NSMutableString *d = [NSMutableString stringWithFormat:@"AX %lu phan tu:", (unsigned long)items.count];
        int shown = 0;
        for (NSDictionary *it in items) {
            NSString *t = it[@"t"];
            if ([t rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location == NSNotFound) continue;
            CGRect f = [it[@"f"] CGRectValue];
            [d appendFormat:@" \"%@\"@(%.0f,%.0f %.0fx%.0f)", [t length] > 24 ? [[t substringToIndex:24] stringByAppendingString:@"…"] : t,
                 f.origin.x, f.origin.y, f.size.width, f.size.height];
            if (++shown >= 25) { [d appendString:@" …"]; break; }
        }
        *outDesc = d;
    }
    *outSpeed = speed; *outLimit = limit;
    return speed >= 0;
}

// ---------------------------------------------------------------------
//  Toc do theo GPS: 1 CLLocationManager RIENG trong tien trinh app (dung quyen vi tri cua app),
//  chi chay khi app dang bat GPS. Khong sua manager cua app.
// ---------------------------------------------------------------------
static int sScanSpeed = -1, sScanLimit = -1;
static CFAbsoluteTime sScanSpeedAt = 0, sScanLimitAt = 0;

#define SPP_GPS_FRESH    3.0    // giay: vi tri cu hon -> coi nhu khong co GPS
#define SPP_SCAN_FRESH   2.0    // giay: toc do quet duoc cu hon -> bo
#define SPP_LIMIT_FRESH 15.0    // giay: giu bien gioi han sau lan cuoi thay tren man hinh

static int SPPCurrentLimit(void)
{
    return (CFAbsoluteTimeGetCurrent() - sScanLimitAt) < SPP_LIMIT_FRESH ? sScanLimit : -1;
}

// Toc do km/h tu 1 vi tri; -1 neu vi tri cu / sai so qua lon
static int SPPSpeedFromFix(CLLocation *fix, double *outAge)
{
    double age = fix ? -[fix.timestamp timeIntervalSinceNow] : -1;
    if (outAge) *outAge = age;
    if (!fix || age > SPP_GPS_FRESH || fix.horizontalAccuracy < 0 || fix.horizontalAccuracy > 100) return -1;
    double v = fix.speed;                // m/s, < 0 = khong hop le (thuong la dang dung yen)
    if (v < 0) v = 0;
    int kmh = (int)lround(v * 3.6);
    return kmh > 300 ? -1 : kmh;
}

@interface SPPSpeedGPS : NSObject <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *mgr;
@property (nonatomic, strong) CLLocation *last;
@property (nonatomic, strong) NSHashTable *appManagers;   // manager cua app dang chay (chi dung tren luong chinh)
@property (nonatomic) BOOL loggedFirst;
+ (instancetype)shared;
- (void)appManager:(CLLocationManager *)m running:(BOOL)running;
@end

@implementation SPPSpeedGPS

+ (instancetype)shared
{
    static SPPSpeedGPS *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [SPPSpeedGPS new]; });
    return s;
}

// App bat / tat GPS tren 1 manager. Luon goi tren luong chinh.
- (void)appManager:(CLLocationManager *)m running:(BOOL)running
{
    if (!self.appManagers) self.appManagers = [NSHashTable weakObjectsHashTable];
    if (running) [self.appManagers addObject:m]; else [self.appManagers removeObject:m];
    BOOL active = self.appManagers.allObjects.count > 0;
    if (active && !self.mgr) [self start];
    else if (!active && self.mgr) [self stop];
}

- (void)start
{
    CLLocationManager *m = [CLLocationManager new];
    m.delegate = self;
    m.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
    m.distanceFilter = kCLDistanceFilterNone;
    m.activityType = CLActivityTypeAutomotiveNavigation;
    m.pausesLocationUpdatesAutomatically = NO;
    // Chi bat cap nhat nen khi app co khai bao UIBackgroundModes=location (khong thi CoreLocation nem exception)
    NSArray *modes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UIBackgroundModes"];
    BOOL bg = [modes isKindOfClass:[NSArray class]] && [modes containsObject:@"location"];
    if (bg) {
        @try { m.allowsBackgroundLocationUpdates = YES; } @catch (NSException *e) {}
    }
    self.mgr = m;
    self.loggedFirst = NO;
    [m startUpdatingLocation];
    SPPLog("speed gps: bat GPS rieng (nen=%d)", bg);
}

- (void)stop
{
    [self.mgr stopUpdatingLocation];
    self.mgr.delegate = nil;
    self.mgr = nil;
    self.last = nil;
    SPPLog("speed gps: app tat GPS -> tat GPS rieng");
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    CLLocation *fix = locations.lastObject;
    if (!fix || manager != self.mgr) return;
    // Manager cua app bi huy ma khong goi stop -> tat GPS rieng
    if (self.appManagers.allObjects.count == 0) { [self stop]; return; }
    self.last = fix;
    int kmh = SPPSpeedFromFix(fix, NULL);
    if (!self.loggedFirst) {
        self.loggedFirst = YES;
        SPPLog("speed gps: vi tri dau tien, %d km/h (sai so %.0fm)", kmh, fix.horizontalAccuracy);
    }
    if (kmh >= 0) SPPSendSpeed(kmh, SPPCurrentLimit());   // moi ban tin GPS -> gui ngay
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    SPPLog("speed gps: loi %@", error.localizedDescription);
}

@end

static int SPPGPSSpeed(double *outAge) { return SPPSpeedFromFix([SPPSpeedGPS shared].last, outAge); }

// App bat / tat GPS: chi ghi nhan. Bo qua manager rieng cua tweak.
static void SPPAppGPSChanged(CLLocationManager *m, BOOL running)
{
    void (^apply)(void) = ^{
        if (m == [SPPSpeedGPS shared].mgr) return;
        [[SPPSpeedGPS shared] appManager:m running:running];
    };
    if ([NSThread isMainThread]) apply(); else dispatch_async(dispatch_get_main_queue(), apply);
}

%group NAVAPP
%hook CLLocationManager
- (void)startUpdatingLocation
{
    %orig;
    SPPAppGPSChanged(self, YES);
}

- (void)stopUpdatingLocation
{
    %orig;
    SPPAppGPSChanged(self, NO);
}
%end
%end // NAVAPP

// ---------------------------------------------------------------------
//  Quet man hinh moi 0.5s
// ---------------------------------------------------------------------
static void SPPNoteScan(int speed, int limit)
{
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (speed >= 0 && speed <= 300) { sScanSpeed = speed; sScanSpeedAt = now; }
    if (limit >= 5 && limit <= 200) { sScanLimit = limit; sScanLimitAt = now; }
}

// Cua so de quet: cua so chinh tren iPhone + cua so CarPlay (CPTemplateApplicationScene.carWindow) neu dang hien
static NSArray<UIWindow *> *SPPAllWindows(void)
{
    UIWindow *phone = nil, *car = nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if ([sc isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)sc).windows) {
                if (w.isKeyWindow) { phone = w; break; }
                if (!phone && w.rootViewController) phone = w;
            }
        } else if (!car && sc.activationState == UISceneActivationStateForegroundActive
                   && [sc respondsToSelector:NSSelectorFromString(@"carWindow")]) {
            id cw = ((id (*)(id, SEL))objc_msgSend)(sc, NSSelectorFromString(@"carWindow"));
            if ([cw isKindOfClass:[UIWindow class]]) car = cw;
        }
    }
    NSMutableArray<UIWindow *> *out = [NSMutableArray array];
    if (phone) [out addObject:phone];
    if (car && car != phone) [out addObject:car];
    return out;
}

// View gioi han / toc do cua plugin dan duong (vd Vietmap: vietmap_live_navigation_plugin.SpeedLimitView2,
// ...CurrentSpeedView). Giu tham chieu yeu de doc tiep ca khi app chay nen (luc bong bong dang hien).
static __weak UIView *sLimitView, *sSpeedView;

// To tien gan nhat (toi da 6 cap) co ten lop chua `part`
static UIView *SPPAncestorNamed(UIView *v, NSString *part)
{
    int depth = 0;
    for (UIView *x = v.superview; x && depth < 6; x = x.superview, depth++) {
        if ([NSStringFromClass([x class]) rangeOfString:part options:NSCaseInsensitiveSearch].location != NSNotFound) return x;
    }
    return nil;
}

// Nhan chu so co co chu lon nhat trong cay view (khong xet view co tren man hinh hay khong)
static void SPPBestNumberLabel(UIView *v, UILabel **best, int depth)
{
    if (depth > 6 || v.hidden || v.alpha < 0.05) return;
    if ([v isKindOfClass:[UILabel class]]) {
        UILabel *l = (UILabel *)v;
        NSString *t = [l.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (SPPIsNumeric(t) && (!*best || l.font.pointSize > (*best).font.pointSize)) *best = l;
    }
    for (UIView *c in v.subviews) SPPBestNumberLabel(c, best, depth + 1);
}

static int SPPNumberInView(UIView *root)
{
    if (!root) return -1;
    UILabel *best = nil;
    SPPBestNumberLabel(root, &best, 0);
    return best ? [best.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].intValue : -1;
}

// Doc truc tiep 2 view da gap. Tra ve NO neu khong con view nao (app da huy) -> quet lai tu dau.
static BOOL SPPReadCachedViews(BOOL doLog)
{
    UIView *lv = sLimitView, *cv = sSpeedView;
    if (!lv && !cv) return NO;
    int limit = lv ? SPPNumberInView(lv) : -1, speed = cv ? SPPNumberInView(cv) : -1;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (lv) { sScanLimit = (limit >= 5 && limit <= 200) ? limit : -1; sScanLimitAt = now; }   // view an = duong khong co bien
    if (speed >= 0 && speed <= 300) { sScanSpeed = speed; sScanSpeedAt = now; }
    if (doLog) SPPLog("speed scan (view app, %@): toc do=%d gioi han=%d", lv.window ? @"tren man hinh" : @"chay nen", speed, limit);
    return YES;
}

static void SPPScanSpeed(BOOL doLog)
{
    NSArray<UIWindow *> *wins = SPPAllWindows();
    UIWindow *win = wins.firstObject;
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    if (win) SPPCollectLabels(win, labels, 0);

    // Khong thay nhan nao tren man hinh (app chay nen / dang o man khac): doc view da gap truoc do
    if (labels.count == 0 && SPPReadCachedViews(doLog)) return;
    if (!win) return;

    // App Flutter (khong co UILabel): doc cay accessibility, thu lan luot tung cua so (iPhone roi CarPlay)
    if (labels.count == 0) {
        int axSpeed = -1, axLimit = -1; NSString *axDesc = nil, *firstDesc = nil; NSUInteger hit = NSNotFound;
        for (NSUInteger i = 0; i < wins.count; i++) {
            int sp = -1, li = -1; NSString *d = nil;
            BOOL ok = SPPScanSpeedAX(wins[i], &sp, &li, doLog ? &d : NULL);
            if (i == 0) firstDesc = d;
            if (ok || li >= 0) { axSpeed = sp; axLimit = li; axDesc = d; hit = i; if (ok) break; }
        }
        if (doLog) SPPLog("speed scan (AX, %lu cua so, trung %@): toc do=%d gioi han=%d; %@", (unsigned long)wins.count,
                          hit == NSNotFound ? @"-" : NSStringFromClass([wins[hit] class]), axSpeed, axLimit,
                          (axDesc ?: firstDesc) ?: @"(khong co phan tu)");
        SPPNoteScan(axSpeed, axLimit);
        return;
    }

    // Uu tien theo ten lop view cua plugin (SpeedLimitView / CurrentSpeedView);
    // khong co thi theo vong tron: vien DO = gioi han, vien XANH (+ "km/h") = toc do hien tai
    UILabel *speedL = nil, *limitL = nil, *bigPlain = nil;
    UIView *limitView = nil, *speedView = nil;
    NSMutableString *desc = [NSMutableString string];
    for (UILabel *l in labels) {
        UIView *lv = SPPAncestorNamed(l, @"SpeedLimit");
        UIView *cv = lv ? nil : SPPAncestorNamed(l, @"CurrentSpeed");
        UIView *circle = SPPCircleAround(l);
        int kind = lv ? 1 : (cv ? 2 : 0);
        if (!kind && circle) {
            kind = SPPClassifyRing(SPPRingColor(circle, 0));
            if (kind == 0 && SPPHasUnitLabel(circle)) kind = 2;
        }
        [desc appendFormat:@" %@(f%.0f %@%@)", l.text, l.font.pointSize, NSStringFromClass([l.superview class]),
             kind == 1 ? @" gioi-han" : (kind == 2 ? @" toc-do" : (circle ? @" vong" : @""))];
        if (kind == 1)      { if (!limitL || l.font.pointSize > limitL.font.pointSize) { limitL = l; limitView = lv; } }
        else if (kind == 2) { if (!speedL || l.font.pointSize > speedL.font.pointSize) { speedL = l; speedView = cv; } }
        else if (!circle)   { if (!bigPlain || l.font.pointSize > bigPlain.font.pointSize) bigPlain = l; }
    }
    if (limitView) sLimitView = limitView;
    if (speedView) sSpeedView = speedView;
    if (!speedL) speedL = bigPlain;   // du phong: khong nhan ra vong xanh -> so to nhat ngoai vong tron
    int speed = speedL ? speedL.text.intValue : -1;
    int limit = limitL ? limitL.text.intValue : -1;
    if (speed > 300) speed = -1;
    if (limit > 200 || limit < 5) limit = -1;

    SPPNoteScan(speed, limit);
    // Da tung thay view gioi han ma lan nay khong thay so -> duong hien tai khong co bien
    if (limit < 0 && sLimitView && !limitL) { sScanLimit = -1; sScanLimitAt = CFAbsoluteTimeGetCurrent(); }
    if (doLog) SPPLog("speed scan: toc do=%d gioi han=%d; ung vien:%@", speed, limit, desc);
}

// Nhip quet man hinh 0.5s: lay gioi han (va toc do du phong khi khong co GPS)
static void SPPSpeedTick(void)
{
    static CFAbsoluteTime lastLog = 0;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    BOOL doLog = (now - lastLog > 20);
    if (doLog) lastLog = now;

    SPPScanSpeed(doLog);
    double age = -1;
    int gps = SPPGPSSpeed(&age);
    int scan = (now - sScanSpeedAt) < SPP_SCAN_FRESH ? sScanSpeed : -1;
    int limit = SPPCurrentLimit();
    if (gps < 0 && scan >= 0) SPPSendSpeed(scan, limit);   // co GPS thi nhip GPS da gui
    if (doLog) SPPLog("speed: gps=%d (vi tri cach %.1fs, GPS rieng %@) quet=%d gioi han=%d -> gui %d", gps, age,
                      [SPPSpeedGPS shared].mgr ? @"bat" : @"tat", scan, limit, gps >= 0 ? gps : scan);
}

%ctor
{
    int idx = SPPNavAppIndex([[NSBundle mainBundle] bundleIdentifier]);
    if (idx < 0) return;
    sAppIndex = idx;
    SPPLog("loaded into %@ (%@)", SPPNavAppName(idx), SPPNavAppBundle(idx));
    %init(NAVAPP);
    SPPEnableFlutterSemantics();
    SPPWatchForeground();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SPPLog("speed scan: bat dau");
        [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { SPPSpeedTick(); }];
    });
}
