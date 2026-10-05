#import "SPPBubble.h"
#import "SPPPrefs.h"
#import <notify.h>

#define SPP_SPEED_STALE 5.0   // giay khong co du lieu moi -> an bong bong
#define SPP_SCALE_DEFAULT 0.7
#define SPP_SCALE_MIN   0.45
#define SPP_SCALE_MAX   1.6
#define SPP_SCALE_KEY   @"SpeedPopBubbleScale"
#define SPP_HOLD_QUIT   3.0   // giay giu bong bong de thoat han app
#define SPP_HOLD_BEGIN  0.3   // giay giu toi thieu truoc khi bat dau dem (de khong nham voi cham / keo)
#define SPP_STYLE_COUNT 12

// ---------------------------------------------------------------------
//  Cua so: man xe (UIRootSceneWindow tren CADisplay cua CarPlay) hoac man iPhone
//  Co che tao cua so tren man xe: theo carplay-cast (EthanArbuckle)
// ---------------------------------------------------------------------

// CADisplay cua man hinh xe (nil neu chua ket noi)
static id SPPGetCarPlayCADisplay(void)
{
    id carplayDevice = objcInvoke(objc_getClass("AVExternalDevice"), @"currentCarPlayExternalDevice");
    if (!carplayDevice) return nil;
    NSArray *screenIDs = objcInvoke(carplayDevice, @"screenIDs");
    if (screenIDs.count == 0) return nil;
    NSString *carplayScreenID = screenIDs[0];
    for (id display in objcInvoke(objc_getClass("CADisplay"), @"displays")) {
        if ([carplayScreenID isEqualToString:objcInvoke(display, @"uniqueId")]) return display;
    }
    return nil;
}

static UIWindow *SPPMakeCarWindow(void)
{
    id carDisplay = SPPGetCarPlayCADisplay();
    if (!carDisplay) return nil;
    id displayConfig = objcInvoke_2([objc_getClass("FBSDisplayConfiguration") alloc],
                                    @"initWithCADisplay:isMainDisplay:", carDisplay, 0);
    if (!displayConfig) { SPPLog("khong tao duoc FBSDisplayConfiguration"); return nil; }
    UIWindow *w = objcInvoke_1([objc_getClass("UIRootSceneWindow") alloc], @"initWithDisplayConfiguration:", displayConfig);
    if (![w isKindOfClass:[UIWindow class]]) { SPPLog("khong tao duoc UIRootSceneWindow: %@", w); return nil; }
    return w;
}

static UIWindow *SPPMakePhoneWindow(void)
{
    CGRect sb = [UIScreen mainScreen].bounds;
    UIWindowScene *mainScene = nil;
    for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
        if ([sc isKindOfClass:[UIWindowScene class]] && ((UIWindowScene *)sc).screen == [UIScreen mainScreen]) {
            mainScene = (UIWindowScene *)sc; break;
        }
    }
    UIWindow *w = mainScene ? [[UIWindow alloc] initWithWindowScene:mainScene] : [[UIWindow alloc] initWithFrame:sb];
    w.frame = sb;
    return w;
}

// Tat han process app dan duong ngay (nut X)
static void SPPKillApp(NSString *bid)
{
    id svc = objcInvoke(objc_getClass("FBSSystemService"), @"sharedService");
    SEL sel = NSSelectorFromString(@"terminateApplication:forReason:andReport:withDescription:");
    if (svc && [svc respondsToSelector:sel]) {
        ((void (*)(id, SEL, id, long long, BOOL, id))objc_msgSend)(svc, sel, bid, 1, NO, @"SpeedPop: user closed");
        SPPLog("terminate %@ (FBSSystemService)", bid);
        return;
    }
    void (*fn)(NSString *, int, BOOL, NSString *) =
        (void (*)(NSString *, int, BOOL, NSString *))dlsym(RTLD_DEFAULT, "BKSTerminateApplicationForReasonAndReportWithDescription");
    if (fn) { fn(bid, 1, NO, @"SpeedPop"); SPPLog("terminate %@ (BKS)", bid); }
    else SPPLog("khong tim thay API terminate cho %@", bid);
}

// Cua so bong bong phu kin man (de keo tha tu do) nhung PHAI cho cham xuyen qua o moi cho khong co the/nut X.
// Cua so xe la UIRootSceneWindow (class rieng cua SpringBoard) nen khong subclass tinh duoc
// -> tao subclass luc chay va doi class cua instance (object_setClass).
static UIView *SPPPassThroughHitTest(id self, SEL _cmd, CGPoint p, UIEvent *e)
{
    struct objc_super sup = { self, class_getSuperclass(object_getClass(self)) };
    UIView *v = ((UIView *(*)(struct objc_super *, SEL, CGPoint, UIEvent *))objc_msgSendSuper)(&sup, _cmd, p, e);
    return (v == self) ? nil : v;   // cham vao chinh cua so (khong trung subview) -> bo qua, xuong duoi
}

static void SPPMakeWindowPassThrough(UIWindow *w)
{
    Class base = object_getClass(w);
    NSString *name = [NSString stringWithFormat:@"SPPPassThrough_%@", NSStringFromClass(base)];
    Class cls = objc_getClass(name.UTF8String);
    if (!cls) {
        cls = objc_allocateClassPair(base, name.UTF8String, 0);
        Method m = class_getInstanceMethod(base, @selector(hitTest:withEvent:));
        class_addMethod(cls, @selector(hitTest:withEvent:), (IMP)SPPPassThroughHitTest, method_getTypeEncoding(m));
        objc_registerClassPair(cls);
    }
    object_setClass(w, cls);
}

@interface UIImage (SPPPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(CGFloat)scale;
@end

// Icon cua app (API rieng cua UIKit, co trong SpringBoard); khong lay duoc -> o mau co chu viet tat
static UIImage *SPPAppIcon(int app)
{
    static NSMutableDictionary<NSNumber *, UIImage *> *cache;
    if (!cache) cache = [NSMutableDictionary dictionary];
    UIImage *img = cache[@(app)];
    if (img) return img;
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
        img = [UIImage _applicationIconImageForBundleIdentifier:SPPNavAppBundle(app) format:2 scale:[UIScreen mainScreen].scale];
    if (!img) {
        CGFloat d = 60;
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(d, d)];
        img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            UIColor *bg = app == 1 ? [UIColor colorWithRed:0.0 green:0.6 blue:0.45 alpha:1] : [UIColor colorWithRed:0.1 green:0.4 blue:0.85 alpha:1];
            [bg setFill]; UIRectFill(CGRectMake(0, 0, d, d));
            NSString *t = app == 1 ? @"GO" : @"VM";
            NSDictionary *a = @{NSFontAttributeName: [UIFont systemFontOfSize:26 weight:UIFontWeightHeavy], NSForegroundColorAttributeName: [UIColor whiteColor]};
            CGSize ts = [t sizeWithAttributes:a];
            [t drawAtPoint:CGPointMake((d - ts.width) / 2, (d - ts.height) / 2) withAttributes:a];
        }];
        SPPLog("bubble: khong lay duoc icon %@ -> dung chu viet tat", SPPNavAppBundle(app));
    }
    cache[@(app)] = img;
    return img;
}

// ---------------------------------------------------------------------
//  Thanh phan ve bong bong (mau, font, nen kinh, icon app, bien gioi han)
// ---------------------------------------------------------------------
static UIColor *SPPRGB(int r, int g, int b, CGFloat a) { return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:a]; }
static UIColor *SPPSignRed(void) { return SPPRGB(229, 38, 45, 1); }
static UIColor *SPPRed(void)     { return SPPRGB(255, 69, 58, 1); }
static UIColor *SPPOrange(void)  { return SPPRGB(255, 159, 10, 1); }
static UIColor *SPPGreen(void)   { return SPPRGB(48, 209, 88, 1); }
static UIColor *SPPBlue(void)    { return SPPRGB(10, 132, 255, 1); }
static UIColor *SPPUnitGray(void){ return SPPRGB(235, 235, 245, 0.6); }

// Tron 2 mau: t = 0 -> a, 1 -> b
static UIColor *SPPMix(UIColor *a, UIColor *b, CGFloat t)
{
    CGFloat r1 = 0, g1 = 0, b1 = 0, a1 = 1, r2 = 0, g2 = 0, b2 = 0, a2 = 1;
    [a getRed:&r1 green:&g1 blue:&b1 alpha:&a1]; [b getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
    return [UIColor colorWithRed:r1 + (r2 - r1) * t green:g1 + (g2 - g1) * t blue:b1 + (b2 - b1) * t alpha:a1 + (a2 - a1) * t];
}

// So: SF Rounded dam, chu so cung do rong (khong nhay khi doi so)
static UIFont *SPPNumFont(CGFloat size)
{
    UIFont *f = [UIFont systemFontOfSize:size weight:UIFontWeightHeavy];
    UIFontDescriptor *d = [f.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded] ?: f.fontDescriptor;
    d = [d fontDescriptorByAddingAttributes:@{UIFontDescriptorFeatureSettingsAttribute:
            @[@{@"CTFeatureTypeIdentifier": @6, @"CTFeatureSelectorIdentifier": @0}]}];   // kNumberSpacingType / kMonospacedNumbersSelector
    return [UIFont fontWithDescriptor:d size:size];
}

static UIFont *SPPUnitFont(CGFloat size)
{
    UIFont *f = [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
    UIFontDescriptor *d = [f.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded] ?: f.fontDescriptor;
    return [UIFont fontWithDescriptor:d size:size];
}

static UILabel *SPPLabel(UIFont *font, UIColor *color, NSTextAlignment align)
{
    UILabel *l = [[UILabel alloc] init];
    l.font = font; l.textColor = color; l.textAlignment = align;
    l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.6;
    return l;
}

// Nen kinh toi: gradient doc + vien mong + bong do (bong do o view ngoai, gradient cat theo goc bo o layer trong)
@interface SPPGlassView : UIView
@property (nonatomic, strong) CAGradientLayer *fill;
@property (nonatomic) CGFloat corner;
- (void)setTop:(UIColor *)top bottom:(UIColor *)bottom;
@end

@implementation SPPGlassView
- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        _fill = [CAGradientLayer layer];
        _fill.masksToBounds = YES;
        _fill.borderWidth = 1;
        _fill.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
        if (@available(iOS 13.0, *)) _fill.cornerCurve = kCACornerCurveContinuous;
        [self.layer addSublayer:_fill];
        [self setTop:SPPRGB(34, 36, 46, 0.9) bottom:SPPRGB(14, 15, 20, 0.9)];
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.35; self.layer.shadowRadius = 6; self.layer.shadowOffset = CGSizeMake(0, 3);
    }
    return self;
}
- (void)setTop:(UIColor *)top bottom:(UIColor *)bottom { self.fill.colors = @[(id)top.CGColor, (id)bottom.CGColor]; }
- (void)setCorner:(CGFloat)corner { _corner = corner; [self setNeedsLayout]; }
- (void)layoutSubviews
{
    [super layoutSubviews];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.fill.frame = self.bounds;
    self.fill.cornerRadius = self.corner;
    [CATransaction commit];
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:self.corner].CGPath;
}
@end

// Icon app: o vuong bo goc kieu iOS, vien sang mong, bong do nhe
@interface SPPIconView : UIView
@property (nonatomic, strong) UIImageView *imageView;
@end

@implementation SPPIconView
- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        _imageView = [[UIImageView alloc] init];
        _imageView.layer.masksToBounds = YES;
        _imageView.layer.borderWidth = 0.75;
        _imageView.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
        if (@available(iOS 13.0, *)) _imageView.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_imageView];
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.4; self.layer.shadowRadius = 2.5; self.layer.shadowOffset = CGSizeMake(0, 1.5);
    }
    return self;
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat r = self.bounds.size.width * 0.225;
    self.imageView.frame = self.bounds;
    self.imageView.layer.cornerRadius = r;
    self.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:r].CGPath;
}
@end

// Bien gioi han toc do: tron trang, vien do (12% duong kinh), so den dam
@interface SPPSignView : UIView
@property (nonatomic, strong) UILabel *label;
@end

@implementation SPPSignView
- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor whiteColor];
        self.layer.borderColor = SPPSignRed().CGColor;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.4; self.layer.shadowRadius = 3; self.layer.shadowOffset = CGSizeMake(0, 1.5);
        _label = SPPLabel(SPPNumFont(20), SPPRGB(20, 20, 20, 1), NSTextAlignmentCenter);
        [self addSubview:_label];
    }
    return self;
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat d = self.bounds.size.width, bw = d * 0.12;
    self.layer.cornerRadius = d / 2;
    self.layer.borderWidth = bw;
    self.label.font = SPPNumFont(d * (self.label.text.length >= 3 ? 0.32 : 0.40));
    self.label.frame = CGRectInset(self.bounds, bw * 0.9, bw);
}
@end


@interface SpringBoard : UIApplication
- (BOOL)launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended;
@end

@interface SPPBubble ()
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *card;
@property (nonatomic, strong) SPPGlassView *glass;   // nen kinh cua kieu dang ve
@property (nonatomic, strong) SPPIconView *iconView; // icon app dang cap toc do
@property (nonatomic, strong) SPPSignView *sign;     // bien gioi han toc do
@property (nonatomic, strong) UILabel *speedLabel, *unitLabel;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic) int speed, limit;
@property (nonatomic) CFAbsoluteTime lastUpdate;
@property (nonatomic) BOOL onPhone;
@property (nonatomic) CGFloat scale;                 // phong to/thu nho bang 2 ngon (SPP_SCALE_MIN .. SPP_SCALE_MAX), luu lai
@property (nonatomic) int app;                       // chi so SPP_NAV_APPS cua app dang cap toc do (cham / X dung app nay)
@property (nonatomic) int iconApp;                   // app dang ve tren iconView (-1 = chua ve)
@property (nonatomic, strong) CAShapeLayer *holdRing;   // giu bong bong: vien do chay quanh, du 3 giay -> thoat app
@property (nonatomic, strong) NSTimer *holdTimer;
@property (nonatomic) CGPoint holdStart;                // diem bat dau giu (keo xa -> chuyen sang di chuyen the)
@property (nonatomic) BOOL holdDragging;
@property (nonatomic) CGRect outlineRect;               // hinh chinh cua kieu dang ve (vien giu chay quanh)
@property (nonatomic) CGFloat outlineCorner;
@property (nonatomic) NSInteger builtStyle;          // kieu dang ve trong the (-1 = chua ve)
@property (nonatomic, strong) CAShapeLayer *gaugeTrack, *gaugeArc;   // kieu Dong ho (gaugeArc = mat na cua gaugeFill)
@property (nonatomic, strong) CAGradientLayer *gaugeFill;            // kieu Dong ho: gradient non xanh -> do
@property (nonatomic, strong) CAShapeLayer *stateRing;               // kieu Dia nho: vien mau trang thai
@property (nonatomic, strong) CAGradientLayer *glow;                 // kieu HUD: anh mau trang thai ben trai
@property (nonatomic, strong) UIView *separator;                     // kieu HUD / Cot doc: vach ngan truoc bien
@property (nonatomic, strong) CALayer *panel;                        // kieu Vien thuoc doi: nua phai mau trang
@property (nonatomic, strong) UIView *meterTrack, *meterFill, *meterMark;   // kieu Thanh do
@property (nonatomic, strong) UIView *flashView;     // nen / quang do nhay khi vuot gioi han (moi kieu)
@property (nonatomic, strong) NSTimer *demoTimer;    // "Xem thu bong bong" trong Cai dat
@property (nonatomic) CGFloat appliedRotation;       // goc xoay dang ap cho cua so tren iPhone
@property (nonatomic) CGPoint phoneFraction, carFraction;   // vi tri the theo ti le man (-1 = mac dinh), rieng iPhone / xe
@end

@implementation SPPBubble

+ (instancetype)shared
{
    static SPPBubble *s; static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [SPPBubble new]; s.speed = -1; s.limit = -1; s.builtStyle = -1;
        double saved = [[NSUserDefaults standardUserDefaults] doubleForKey:SPP_SCALE_KEY];
        s.scale = (saved >= SPP_SCALE_MIN && saved <= SPP_SCALE_MAX) ? saved : SPP_SCALE_DEFAULT;
        s.phoneFraction = CGPointMake(-1, -1); s.carFraction = CGPointMake(-1, -1);
        [s startOrientationTracking];
    });
    return s;
}

// Transform goc cua the = ti le nguoi dung chon (moi animation deu nhan them vao day)
- (CGAffineTransform)baseTransform { return CGAffineTransformMakeScale(self.scale, self.scale); }
- (CGAffineTransform)baseScaled:(CGFloat)k { return CGAffineTransformMakeScale(self.scale * k, self.scale * k); }

- (void)updateSpeed:(int)speed limit:(int)limit
{
    [self updateSpeed:speed limit:limit appForeground:NO];
}

- (void)updateSpeed:(int)speed limit:(int)limit appForeground:(BOOL)fg
{
    [self updateSpeed:speed limit:limit appForeground:fg app:self.app];
}

// Trang thai hien/an cua tung app (co the chay ca Vietmap lan GOFA cung luc)
static BOOL sAppFg[8];
static CFAbsoluteTime sAppSeenAt[8];

// Co app dan duong nao dang hien (va con gui du lieu) -> an bong bong
- (BOOL)anyAppForeground
{
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    for (int i = 0; i < 8; i++) if (sAppFg[i] && now - sAppSeenAt[i] < SPP_SPEED_STALE) return YES;
    return NO;
}

- (void)updateSpeed:(int)speed limit:(int)limit appForeground:(BOOL)fg app:(int)app
{
    app &= 7;
    if (fg != sAppFg[app]) SPPLog("bubble: %@ %@", SPPNavAppName(app), fg ? @"dang hien -> an bong bong" : @"chay nen -> hien bong bong");
    sAppFg[app] = fg; sAppSeenAt[app] = CFAbsoluteTimeGetCurrent();
    // App dang hien khong gianh nguon cua app khac dang chay nen (bong bong van an toi khi het app nao dang hien)
    BOOL otherFresh = app != self.app && !sAppFg[self.app] && (CFAbsoluteTimeGetCurrent() - self.lastUpdate) < SPP_SPEED_STALE;
    if (!(fg && otherFresh)) {
        if (app != self.app) SPPLog("bubble: nguon toc do -> %@", SPPNavAppName(app));
        self.app = app;
        self.speed = speed; self.limit = limit;
        self.lastUpdate = CFAbsoluteTimeGetCurrent();
    }
    [self refresh];
}

// App dang cap toc do con chay khong (SBApplication). Chi tin ket qua "da tat" sau khi API tung bao "dang chay"
// trong phien nay - API khac di tren ban iOS khac thi khong bao gio an nham bong bong.
static BOOL sSeenRunning[8];

- (BOOL)sourceAppRunning
{
    int app = self.app & 7;
    id ctl = objcInvoke(objc_getClass("SBApplicationController"), @"sharedInstance");
    id sbApp = ctl ? objcInvoke_1(ctl, @"applicationWithBundleIdentifier:", SPPNavAppBundle(app)) : nil;
    if (!sbApp) return YES;
    BOOL running = YES, known = NO;
    if ([sbApp respondsToSelector:NSSelectorFromString(@"isRunning")]) { running = objcInvokeT(sbApp, @"isRunning", BOOL); known = YES; }
    else if ([sbApp respondsToSelector:NSSelectorFromString(@"processState")]) {
        id ps = objcInvoke(sbApp, @"processState");
        running = ps && (![ps respondsToSelector:NSSelectorFromString(@"isRunning")] || objcInvokeT(ps, @"isRunning", BOOL));
        known = YES;
    }
    if (!known) return YES;
    if (running) { sSeenRunning[app] = YES; return YES; }
    return !sSeenRunning[app];
}

- (void)refresh
{
    BOOL fresh = (CFAbsoluteTimeGetCurrent() - self.lastUpdate) < SPP_SPEED_STALE && self.speed >= 0;
    // Chi hien khi app dan duong chay nen (khong co app dan duong nao dang hien)
    BOOL show = fresh && [SPPPrefs enabled] && ![self anyAppForeground];
    // App vua bi tat (vuot khoi da nhiem / bi he thong dong) -> an ngay, khong cho het SPP_SPEED_STALE
    if (show && !self.demoTimer && ![self sourceAppRunning]) {
        SPPLog("bubble: %@ da tat -> an bong bong ngay", SPPNavAppName(self.app));
        self.speed = -1; self.limit = -1; self.lastUpdate = 0;
        show = NO;
    }
    if (!show) { [self hide]; return; }
    [self ensureWindow];
    if (!self.window) return;
    if (self.onPhone) [self applyPhoneOrientationForce:NO];

    NSInteger style = [SPPPrefs style];
    if (style != self.builtStyle) [self buildStyle:style];
    // So doi muot: chi dat text, khong animation (cap nhat lien tuc)
    [self renderStyle];

    if (self.window.hidden) {
        self.window.hidden = NO;
        self.card.alpha = 0; self.card.transform = [self baseScaled:0.7];
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.5 options:0
                         animations:^{ self.card.alpha = 1; self.card.transform = [self baseTransform]; } completion:nil];
    }
    if (!self.timer) {
        __weak SPPBubble *weakSelf = self;
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { [weakSelf refresh]; }];
    }
}

- (void)hide
{
    if (self.window && !self.window.hidden) {
        UIView *card = self.card; UIWindow *win = self.window;
        [self cancelHold];
        [UIView animateWithDuration:0.18 animations:^{ card.alpha = 0; card.transform = [self baseScaled:0.8]; }
                         completion:^(BOOL f) { if (card.alpha < 0.01) win.hidden = YES; }];
    }
    [self.timer invalidate]; self.timer = nil;
}

// =====================================================================
//  Cac kieu bong bong (Cai dat > SpeedPop > Kieu hien thi). Moi kieu deu co icon app dang cap toc do.
//    0 The ngang     : the kinh toi [icon] [toc do / km/h] [bien gioi han]
//    1 Dia nho       : dia tron, vien mau theo trang thai, icon nho tren so, bien goc tren phai
//    2 Bien bao      : bien gioi han lon + vien toc do (icon + so) o goc duoi phai
//    3 Dong ho       : cung 270 do mau xanh -> cam -> do, icon o khe duoi, bien goc tren phai
//    4 Thanh HUD     : thanh ngang [icon] [so km/h] | [bien], anh mau trang thai ben trai
//    5 Mau toc do    : dia to mau xanh / cam / do, icon nho tren so, bien goc tren phai
//    6 Cot doc       : cot dung [icon] [so / km/h] --- [bien]
//    7 Vien thuoc doi: nua trai mau trang thai (icon + so), nua phai trang (bien)
//    8 Neon          : nen den, so phat sang theo mau trang thai, vien mau
//    9 Thanh do      : [icon] [so km/h] [bien] + thanh tien do, vach o muc gioi han
//   10 Chu noi       : khong nen, so lon co bong, icon + km/h nho, bien ben canh
//   11 The sang      : nhu The ngang nhung nen trang chu toi
// =====================================================================
// 0 = binh thuong, 1 = sap cham gioi han (>= 90%), 2 = vuot
- (int)speedState
{
    if (self.limit <= 0) return 0;
    if (self.speed > self.limit) return 2;
    if (self.speed >= self.limit * 0.9) return 1;
    return 0;
}

- (UIColor *)stateColor
{
    switch ([self speedState]) {
        case 2: return SPPRed();
        case 1: return SPPOrange();
        default: return self.limit > 0 ? SPPGreen() : SPPBlue();
    }
}

// Mau so toc do tren nen toi: trang / cam / do
- (UIColor *)numberColor
{
    switch ([self speedState]) {
        case 2: return SPPRed();
        case 1: return SPPOrange();
        default: return [UIColor whiteColor];
    }
}

- (void)buildStyle:(NSInteger)style
{
    UIView *card = self.card;
    for (UIView *v in [card.subviews copy]) [v removeFromSuperview];
    for (CALayer *l in [card.layer.sublayers copy]) [l removeFromSuperlayer];
    self.glass = nil; self.iconView = nil; self.sign = nil; self.flashView = nil; self.separator = nil;
    self.speedLabel = nil; self.unitLabel = nil;
    self.gaugeTrack = nil; self.gaugeArc = nil; self.gaugeFill = nil; self.stateRing = nil; self.glow = nil;
    self.panel = nil; self.meterTrack = nil; self.meterFill = nil; self.meterMark = nil;
    if (style < 0 || style >= SPP_STYLE_COUNT) style = 0;

    UIView *flash = [[UIView alloc] init];
    flash.backgroundColor = SPPRed();
    flash.alpha = 0;
    flash.userInteractionEnabled = NO;
    self.flashView = flash;

    // Nen kinh (kieu 2: chi la vien toc do nho; kieu 10: khong co nen). Kieu tron (1 / 2 / 3 / 5 / 10): quang do nhay
    // quanh hinh chinh (nam sau nen); kieu the / thanh: nhay phu kin nen (tren nen, duoi chu - chu la view them sau)
    SPPGlassView *g = [[SPPGlassView alloc] init];
    BOOL flashInside = (style == 0 || style == 4 || style == 6 || style == 7 || style == 8 || style == 9 || style == 11);
    if (flashInside) { [card addSubview:g]; [g addSubview:flash]; }
    else { [card addSubview:flash]; [card addSubview:g]; }
    g.hidden = (style == 10);
    self.glass = g;

    UIColor *unitColor = SPPUnitGray();
    switch (style) {
    case 0:     // The ngang
        self.speedLabel = SPPLabel(SPPNumFont(30), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(11), unitColor, NSTextAlignmentCenter);
        break;
    case 1: {   // Dia nho
        self.speedLabel = SPPLabel(SPPNumFont(28), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(10), unitColor, NSTextAlignmentCenter);
        CAShapeLayer *ring = [CAShapeLayer layer];
        ring.fillColor = [UIColor clearColor].CGColor; ring.lineWidth = 2.5;
        [self.glass.layer addSublayer:ring];
        self.stateRing = ring;
        break;
    }
    case 2:     // Bien bao: vien toc do
        self.speedLabel = SPPLabel(SPPNumFont(20), [UIColor whiteColor], NSTextAlignmentLeft);
        self.unitLabel = SPPLabel(SPPUnitFont(9), unitColor, NSTextAlignmentLeft);
        self.speedLabel.adjustsFontSizeToFitWidth = NO; self.unitLabel.adjustsFontSizeToFitWidth = NO;
        break;
    case 3: {   // Dong ho
        self.speedLabel = SPPLabel(SPPNumFont(32), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(10), unitColor, NSTextAlignmentCenter);
        CAShapeLayer *track = [CAShapeLayer layer], *arc = [CAShapeLayer layer];
        for (CAShapeLayer *l in @[track, arc]) { l.fillColor = [UIColor clearColor].CGColor; l.lineWidth = 8; l.lineCap = kCALineCapRound; }
        track.strokeColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        arc.strokeColor = [UIColor blackColor].CGColor;   // chi lam mat na cho gradient
        // Gradient non xanh -> cam -> do chay theo cung (bat dau o 125 do de dau tron cua cung van mau xanh)
        CAGradientLayer *fill = [CAGradientLayer layer];
        fill.type = kCAGradientLayerConic;
        fill.startPoint = CGPointMake(0.5, 0.5);
        fill.endPoint = CGPointMake(0.5 + cos(125 * M_PI / 180), 0.5 + sin(125 * M_PI / 180));
        CGFloat lead = 10.0 / 360, sweep = 270.0 / 360;
        fill.colors = @[(id)SPPGreen().CGColor, (id)SPPGreen().CGColor, (id)SPPOrange().CGColor, (id)SPPRed().CGColor, (id)SPPRed().CGColor];
        fill.locations = @[@0, @(lead), @(lead + sweep * 0.6), @(lead + sweep), @1];
        fill.mask = arc;
        [self.glass.layer addSublayer:track];
        [self.glass.layer addSublayer:fill];
        self.gaugeTrack = track; self.gaugeArc = arc; self.gaugeFill = fill;
        break;
    }
    case 4: {   // Thanh HUD
        self.speedLabel = SPPLabel(SPPNumFont(26), [UIColor whiteColor], NSTextAlignmentRight);
        self.unitLabel = SPPLabel(SPPUnitFont(11), unitColor, NSTextAlignmentLeft);
        CAGradientLayer *glow = [CAGradientLayer layer];
        glow.startPoint = CGPointMake(0, 0.5); glow.endPoint = CGPointMake(1, 0.5);
        [self.glass.fill addSublayer:glow];   // bi cat theo vien bo tron cua nen
        self.glow = glow;
        UIView *sep = [[UIView alloc] init];
        sep.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
        sep.userInteractionEnabled = NO;
        [card addSubview:sep];
        self.separator = sep;
        break;
    }
    case 5:     // Mau toc do
        self.speedLabel = SPPLabel(SPPNumFont(30), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(9.5), [UIColor colorWithWhite:1 alpha:0.85], NSTextAlignmentCenter);
        self.glass.fill.borderWidth = 3;
        self.glass.fill.borderColor = [UIColor whiteColor].CGColor;
        break;
    case 6: {   // Cot doc
        self.speedLabel = SPPLabel(SPPNumFont(30), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(10), unitColor, NSTextAlignmentCenter);
        UIView *sep = [[UIView alloc] init];
        sep.backgroundColor = [UIColor colorWithWhite:1 alpha:0.16];
        sep.userInteractionEnabled = NO;
        [card addSubview:sep];
        self.separator = sep;
        break;
    }
    case 7: {   // Vien thuoc doi
        self.speedLabel = SPPLabel(SPPNumFont(26), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(9.5), [UIColor colorWithWhite:1 alpha:0.85], NSTextAlignmentCenter);
        self.glass.fill.borderWidth = 0;
        CALayer *panel = [CALayer layer];
        panel.backgroundColor = SPPRGB(250, 250, 252, 1).CGColor;
        [self.glass.fill addSublayer:panel];   // bi cat theo vien bo tron cua nen
        self.panel = panel;
        break;
    }
    case 8:     // Neon
        self.speedLabel = SPPLabel(SPPNumFont(32), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(8), unitColor, NSTextAlignmentCenter);
        [self.glass setTop:SPPRGB(6, 6, 10, 0.94) bottom:SPPRGB(2, 2, 4, 0.94)];
        self.glass.fill.borderWidth = 1.5;
        self.speedLabel.layer.shadowOffset = CGSizeZero;
        self.speedLabel.layer.shadowRadius = 6;
        self.speedLabel.layer.shadowOpacity = 1;
        break;
    case 9: {   // Thanh do
        self.speedLabel = SPPLabel(SPPNumFont(30), [UIColor whiteColor], NSTextAlignmentLeft);
        self.unitLabel = SPPLabel(SPPUnitFont(10), unitColor, NSTextAlignmentLeft);
        self.speedLabel.adjustsFontSizeToFitWidth = NO;
        UIView *track = [[UIView alloc] init], *fill = [[UIView alloc] init], *mark = [[UIView alloc] init];
        track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.15];
        mark.backgroundColor = [UIColor colorWithWhite:1 alpha:0.92];
        for (UIView *v in @[track, fill, mark]) { v.userInteractionEnabled = NO; [card addSubview:v]; }
        self.meterTrack = track; self.meterFill = fill; self.meterMark = mark;
        break;
    }
    case 10:    // Chu noi: so co bong do de doc duoc tren nen ban do
        self.speedLabel = SPPLabel(SPPNumFont(40), [UIColor whiteColor], NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(11), [UIColor colorWithWhite:1 alpha:0.92], NSTextAlignmentLeft);
        for (UILabel *l in @[self.speedLabel, self.unitLabel]) {
            l.layer.shadowColor = [UIColor blackColor].CGColor;
            l.layer.shadowOffset = CGSizeMake(0, 1); l.layer.shadowRadius = 3; l.layer.shadowOpacity = 0.75;
        }
        break;
    case 11:    // The sang
        self.speedLabel = SPPLabel(SPPNumFont(30), SPPRGB(20, 20, 24, 1), NSTextAlignmentCenter);
        self.unitLabel = SPPLabel(SPPUnitFont(11), SPPRGB(60, 60, 67, 0.6), NSTextAlignmentCenter);
        [self.glass setTop:SPPRGB(255, 255, 255, 0.96) bottom:SPPRGB(238, 239, 243, 0.96)];
        self.glass.fill.borderColor = [UIColor colorWithWhite:0 alpha:0.1].CGColor;
        break;
    }
    self.unitLabel.text = (style == 8) ? @"KM/H" : @"km/h";
    [card addSubview:self.speedLabel];
    [card addSubview:self.unitLabel];
    self.sign = [[SPPSignView alloc] init];
    [card addSubview:self.sign];
    self.iconView = [[SPPIconView alloc] init];
    [card addSubview:self.iconView];
    self.iconApp = -1;
    self.builtStyle = style;
    SPPLog("bubble: kieu %ld", (long)style);
}

// Vuot gioi han (moi kieu): nen / quang do nhay, bien gioi han dap theo nhip
- (void)setOverLimitWarning:(BOOL)on
{
    UIView *f = self.flashView;
    BOOL running = [f.layer animationForKey:@"sppFlash"] != nil;
    if (on == running) return;
    if (on) {
        CABasicAnimation *blink = [CABasicAnimation animationWithKeyPath:@"opacity"];
        blink.fromValue = @0.0; blink.toValue = @0.55;
        blink.duration = 0.35; blink.autoreverses = YES; blink.repeatCount = HUGE_VALF;
        blink.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        f.alpha = 1; f.layer.opacity = 0;
        [f.layer addAnimation:blink forKey:@"sppFlash"];
        CABasicAnimation *pulse = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        pulse.fromValue = @1.0; pulse.toValue = @1.15;
        pulse.duration = 0.35; pulse.autoreverses = YES; pulse.repeatCount = HUGE_VALF;
        [self.sign.layer addAnimation:pulse forKey:@"sppPulse"];
        SPPLog("bubble: vuot gioi han -> nhay canh bao");
    } else {
        [f.layer removeAnimationForKey:@"sppFlash"];
        f.alpha = 0;
        [self.sign.layer removeAnimationForKey:@"sppPulse"];
    }
}

// Mau so theo kieu: nen mau (5, 7) -> trang; Neon -> mau trang thai nhat; nen sang (11) -> toi / cam / do
- (UIColor *)numberColorForStyle:(NSInteger)style
{
    int st = [self speedState];
    switch (style) {
    case 5: case 7: return [UIColor whiteColor];
    case 8: return SPPMix([self stateColor], [UIColor whiteColor], 0.55);
    case 11: return st == 2 ? SPPRed() : (st == 1 ? SPPRGB(230, 130, 0, 1) : SPPRGB(20, 20, 24, 1));
    default: return [self numberColor];
    }
}

// km/h cung dong day (baseline) voi so toc do dang can giua theo chieu doc tai midY
static void SPPAlignUnit(UILabel *unit, UILabel *number, CGFloat x, CGFloat midY, CGFloat w)
{
    CGFloat base = midY + number.font.capHeight / 2;
    unit.frame = CGRectMake(x, base - unit.font.ascender, w, unit.font.lineHeight);
}

static void SPPPlace(UIView *v, CGFloat cx, CGFloat cy, CGFloat size)
{
    v.bounds = CGRectMake(0, 0, size, size);
    v.center = CGPointMake(cx, cy);
    [v setNeedsLayout];
}

// Dat so + mau + bo cuc theo kieu, giu tam the co dinh
- (void)renderStyle
{
    BOOL hasLimit = self.limit > 0;
    BOOL showIcon = [SPPPrefs showAppIcon];
    int state = [self speedState];
    UIColor *sc = [self stateColor];
    self.speedLabel.text = [NSString stringWithFormat:@"%d", self.speed];
    self.speedLabel.textColor = [self numberColorForStyle:self.builtStyle];
    self.sign.label.text = hasLimit ? [NSString stringWithFormat:@"%d", self.limit] : @"";
    self.sign.hidden = !hasLimit;
    self.iconView.hidden = !showIcon;
    if (showIcon && self.iconApp != self.app) { self.iconView.imageView.image = SPPAppIcon(self.app); self.iconApp = self.app; }

    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CGPoint c = self.card.center;
    CGSize size;
    UIView *halo = nil;   // hinh chinh de ve quang do nhay xung quanh (nil = nhay trong nen)
    switch (self.builtStyle) {
    case 1: {   // Dia nho: icon nho ben trong, tren so
        CGFloat d = 78, r = d / 2, k = r * 0.74;
        size = CGSizeMake(d, d);
        self.glass.frame = CGRectMake(0, 0, d, d); self.glass.corner = r;
        self.stateRing.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(3, 3, d - 6, d - 6)].CGPath;
        self.stateRing.strokeColor = sc.CGColor;
        CGFloat dy = showIcon ? 3 : -4;
        SPPPlace(self.iconView, r, 17, 17);
        self.speedLabel.frame = CGRectMake(9, 26 + dy, d - 18, 32);
        self.unitLabel.frame = CGRectMake(9, 55 + dy, d - 18, 12);
        SPPPlace(self.sign, r + k, r - k, 32);
        halo = self.glass;
        break;
    }
    case 2: {   // Bien bao
        CGFloat sd = 80, ch = hasLimit ? 34 : 44;
        CGFloat ic = showIcon ? ch - 10 : 0;
        self.speedLabel.font = SPPNumFont(ch * 0.58);
        self.unitLabel.font = SPPUnitFont(ch * 0.27);
        CGFloat nw = ceil([self.speedLabel sizeThatFits:CGSizeMake(200, ch)].width);
        CGFloat uw = ceil([self.unitLabel sizeThatFits:CGSizeMake(200, ch)].width);
        CGFloat cw = (showIcon ? 5 + ic + 6 : 12) + nw + 3 + uw + 12;
        CGFloat x = hasLimit ? sd - 34 : 0, y = hasLimit ? sd - 18 : 0;
        if (hasLimit) SPPPlace(self.sign, sd / 2, sd / 2, sd);
        self.glass.frame = CGRectMake(x, y, cw, ch); self.glass.corner = ch / 2;
        if (showIcon) SPPPlace(self.iconView, x + 5 + ic / 2, y + ch / 2, ic);
        CGFloat tx = x + (showIcon ? 5 + ic + 6 : 12);
        self.speedLabel.frame = CGRectMake(tx, y, nw, ch);
        SPPAlignUnit(self.unitLabel, self.speedLabel, tx + nw + 3, y + ch / 2, uw);
        size = CGSizeMake(MAX(x + cw, hasLimit ? sd : 0), y + ch);
        halo = hasLimit ? self.sign : self.glass;
        break;
    }
    case 3: {   // Dong ho
        CGFloat d = 108, r = d / 2;
        size = CGSizeMake(d, d);
        self.glass.frame = CGRectMake(0, 0, d, d); self.glass.corner = r;
        UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(r, r) radius:r - 11
                                                        startAngle:M_PI * 0.75 endAngle:M_PI * 2.25 clockwise:YES];
        self.gaugeTrack.path = path.CGPath; self.gaugeArc.path = path.CGPath;
        self.gaugeTrack.frame = CGRectMake(0, 0, d, d); self.gaugeFill.frame = CGRectMake(0, 0, d, d);
        self.gaugeArc.frame = self.gaugeFill.bounds;
        CGFloat maxV = hasLimit ? MAX(self.limit * 1.4, 40) : 140;
        [CATransaction setDisableActions:NO]; [CATransaction setAnimationDuration:0.4];
        self.gaugeArc.strokeEnd = MIN(1.0, MAX(0.0, self.speed / maxV));
        [CATransaction setDisableActions:YES];
        self.speedLabel.frame = CGRectMake(16, 31, d - 32, 38);
        self.unitLabel.frame = CGRectMake(16, 64, d - 32, 12);
        SPPPlace(self.iconView, r, d - 15, 22);
        SPPPlace(self.sign, d - 12, 12, 36);
        halo = self.glass;
        break;
    }
    case 4: {   // Thanh HUD
        CGFloat h = 46, x = showIcon ? 7 + 32 + 10 : 16;
        CGFloat sx = x + 44 + 4 + 30 + 8;
        size = CGSizeMake(hasLimit ? sx + 8 + 34 + 6 : x + 44 + 4 + 30 + 6, h);
        self.glass.frame = CGRectMake(0, 0, size.width, h); self.glass.corner = h / 2;
        self.glow.frame = CGRectMake(0, 0, 100, h);
        self.glow.colors = @[(id)[sc colorWithAlphaComponent:0.38].CGColor, (id)[sc colorWithAlphaComponent:0].CGColor];
        SPPPlace(self.iconView, 7 + 16, h / 2, 32);
        self.speedLabel.frame = CGRectMake(x, 5, 44, h - 10);
        SPPAlignUnit(self.unitLabel, self.speedLabel, x + 48, h / 2, 30);
        self.separator.hidden = !hasLimit;
        self.separator.frame = CGRectMake(sx, 11, 1, h - 22);
        SPPPlace(self.sign, sx + 8 + 17, h / 2, 34);
        break;
    }
    case 5: {   // Mau toc do: icon nho ben trong, tren so
        CGFloat d = 86, r = d / 2;
        size = CGSizeMake(d, d);
        self.glass.frame = CGRectMake(0, 0, d, d); self.glass.corner = r;
        CGFloat hh, ss, bb, aa;
        UIColor *top = sc, *bottom = sc;
        if ([sc getHue:&hh saturation:&ss brightness:&bb alpha:&aa]) {
            top = [UIColor colorWithHue:hh saturation:ss * 0.8 brightness:MIN(1, bb * 1.12) alpha:1];
            bottom = [UIColor colorWithHue:hh saturation:MIN(1, ss * 1.05) brightness:bb * 0.72 alpha:1];
        }
        [self.glass setTop:top bottom:bottom];
        CGFloat dy = showIcon ? 3 : -5;
        SPPPlace(self.iconView, r, 19, 18);
        self.speedLabel.frame = CGRectMake(10, 26 + dy, d - 20, 36);
        self.unitLabel.frame = CGRectMake(10, 59 + dy, d - 20, 12);
        SPPPlace(self.sign, d - 10, 10, 34);
        halo = self.glass;
        break;
    }
    case 6: {   // Cot doc
        CGFloat w = 66, top = showIcon ? 12 + 30 + 8 : 12;
        CGFloat y2 = top + 34 + 14;
        size = CGSizeMake(w, hasLimit ? y2 + 10 + 46 + 10 : y2 + 4);
        self.glass.frame = CGRectMake(0, 0, w, size.height); self.glass.corner = 22;
        SPPPlace(self.iconView, w / 2, 12 + 15, 30);
        self.speedLabel.frame = CGRectMake(5, top, w - 10, 36);
        self.unitLabel.frame = CGRectMake(5, top + 33, w - 10, 13);
        self.separator.hidden = !hasLimit;
        self.separator.frame = CGRectMake(14, y2, w - 28, 1);
        SPPPlace(self.sign, w / 2, y2 + 10 + 23, 46);
        break;
    }
    case 7: {   // Vien thuoc doi
        CGFloat h = 52, x = showIcon ? 8 + 30 + 8 : 14;
        CGFloat lw = x + 50 + 12, rw = hasLimit ? 56 : 0;
        size = CGSizeMake(lw + rw, h);
        self.glass.frame = CGRectMake(0, 0, size.width, h); self.glass.corner = h / 2;
        CGFloat hh, ss, bb, aa;
        UIColor *top = sc, *bottom = sc;
        if ([sc getHue:&hh saturation:&ss brightness:&bb alpha:&aa]) {
            top = [UIColor colorWithHue:hh saturation:ss * 0.85 brightness:MIN(1, bb * 1.1) alpha:1];
            bottom = [UIColor colorWithHue:hh saturation:MIN(1, ss * 1.05) brightness:bb * 0.75 alpha:1];
        }
        [self.glass setTop:top bottom:bottom];
        self.panel.hidden = !hasLimit;
        self.panel.frame = CGRectMake(lw, 0, rw, h);
        SPPPlace(self.iconView, 8 + 15, h / 2, 30);
        self.speedLabel.frame = CGRectMake(x, 5, 50, 31);
        self.unitLabel.frame = CGRectMake(x, 35, 50, 12);
        SPPPlace(self.sign, lw + rw / 2 - 2, h / 2, 40);
        break;
    }
    case 8: {   // Neon
        CGFloat h = 58, x = showIcon ? 10 + 26 + 10 : 12;
        size = CGSizeMake(x + 62 + (hasLimit ? 6 + 40 + 10 : 12), h);
        self.glass.frame = CGRectMake(0, 0, size.width, h); self.glass.corner = 16;
        self.glass.fill.borderColor = [sc colorWithAlphaComponent:0.8].CGColor;
        self.speedLabel.layer.shadowColor = sc.CGColor;
        self.unitLabel.textColor = sc;
        SPPPlace(self.iconView, 10 + 13, h / 2, 26);
        self.speedLabel.frame = CGRectMake(x, 6, 62, 38);
        self.unitLabel.frame = CGRectMake(x, h - 15, 62, 11);
        SPPPlace(self.sign, size.width - 10 - 20, h / 2, 40);
        break;
    }
    case 9: {   // Thanh do
        CGFloat h = 70, x = showIcon ? 10 + 36 + 10 : 14, mid = 27;
        size = CGSizeMake(x + 70 + (hasLimit ? 8 + 40 + 10 : 10), h);
        self.glass.frame = CGRectMake(0, 0, size.width, h); self.glass.corner = 18;
        SPPPlace(self.iconView, 10 + 18, mid, 36);
        CGFloat nw = ceil([self.speedLabel sizeThatFits:CGSizeMake(200, 40)].width);
        self.speedLabel.frame = CGRectMake(x, mid - 19, nw, 38);
        SPPAlignUnit(self.unitLabel, self.speedLabel, x + nw + 3, mid, 34);
        SPPPlace(self.sign, size.width - 10 - 20, mid, 40);
        CGFloat bx = 12, bw = size.width - 24, by = h - 16;
        CGFloat maxV = hasLimit ? self.limit * 1.3 : 140;
        self.meterTrack.frame = CGRectMake(bx, by, bw, 6);
        self.meterTrack.layer.cornerRadius = 3;
        self.meterFill.layer.cornerRadius = 3;
        self.meterFill.backgroundColor = sc;
        [CATransaction setDisableActions:NO];
        [UIView animateWithDuration:0.35 animations:^{
            self.meterFill.frame = CGRectMake(bx, by, MAX(6, bw * MIN(1.0, self.speed / maxV)), 6);
        }];
        [CATransaction setDisableActions:YES];
        self.meterMark.hidden = !hasLimit;
        self.meterMark.frame = CGRectMake(bx + bw * (self.limit / maxV) - 1.25, by - 3, 2.5, 12);
        self.meterMark.layer.cornerRadius = 1.25;
        break;
    }
    case 10: {  // Chu noi
        CGFloat nw = 64;
        size = CGSizeMake(hasLimit ? nw + 8 + 38 : nw, 68);
        SPPPlace(self.iconView, 13, 58, 16);
        self.speedLabel.frame = CGRectMake(0, 2, nw, 48);
        self.unitLabel.frame = showIcon ? CGRectMake(26, 51, 40, 14) : CGRectMake(8, 51, 50, 14);
        self.unitLabel.textAlignment = showIcon ? NSTextAlignmentLeft : NSTextAlignmentCenter;
        SPPPlace(self.sign, nw + 8 + 19, 30, 38);
        halo = self.speedLabel;
        break;
    }
    case 11:    // The sang: bo cuc nhu The ngang
    default: {  // 0 The ngang
        CGFloat h = 60, pad = 9, ic = 42, nw = 58, sg = 44;
        CGFloat x = showIcon ? pad + ic + 10 : 14;
        size = CGSizeMake(x + nw + (hasLimit ? 8 + sg + pad : 14), h);
        self.glass.frame = CGRectMake(0, 0, size.width, h); self.glass.corner = 18;
        SPPPlace(self.iconView, pad + ic / 2, h / 2, ic);
        self.speedLabel.frame = CGRectMake(x, 7, nw, 36);
        self.unitLabel.frame = CGRectMake(x, 40, nw, 13);
        SPPPlace(self.sign, x + nw + 8 + sg / 2, h / 2, sg);
        break;
    }
    }
    // Vung nhay: quang tron quanh hinh chinh, hoac phu kin nen
    if (halo) {
        CGRect hr = CGRectInset(halo.frame, -6, -6);
        self.flashView.frame = hr;
        self.flashView.layer.cornerRadius = MIN(hr.size.width, hr.size.height) / 2;
    } else {
        self.flashView.frame = self.glass.bounds;
        self.flashView.layer.cornerRadius = self.glass.corner;
    }
    // Hinh chinh de ve vien "giu de thoat": bien (kieu 2), ca the (kieu 10), con lai la nen
    if (self.builtStyle == 2 && hasLimit) { self.outlineRect = self.sign.frame; self.outlineCorner = self.sign.frame.size.width / 2; }
    else if (self.builtStyle == 10) { self.outlineRect = CGRectMake(0, 0, size.width, size.height); self.outlineCorner = 16; }
    else { self.outlineRect = self.glass.frame; self.outlineCorner = self.glass.corner; }
    [CATransaction commit];
    self.card.bounds = CGRectMake(0, 0, size.width, size.height);
    self.card.center = c;
    [self setOverLimitWarning:(state == 2)];
    [self clampCard];
}

// Cai dat > Dat lai: ti le mac dinh, vi tri mac dinh tren ca iPhone lan xe
- (void)resetLayout
{
    self.scale = SPP_SCALE_DEFAULT;
    [[NSUserDefaults standardUserDefaults] setDouble:self.scale forKey:SPP_SCALE_KEY];
    self.phoneFraction = CGPointMake(-1, -1); self.carFraction = CGPointMake(-1, -1);
    if (self.window) {
        self.card.transform = [self baseTransform];
        [self restoreCardPosition];
    }
    SPPLog("bubble: dat lai vi tri + kich thuoc");
}

// "Xem thu bong bong" trong Cai dat: toc do gia 10 giay (tang qua gioi han 60 de thay doi mau)
- (void)runDemo
{
    [self.demoTimer invalidate];
    __block int tick = 0;
    SPPLog("bubble: xem thu 10 giay");
    __weak SPPBubble *weakSelf = self;
    self.demoTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) {
        tick++;
        if (tick > 20) { [t invalidate]; weakSelf.demoTimer = nil; return; }
        int speed = 40 + tick * 2;   // 42 -> 80 km/h
        [weakSelf updateSpeed:speed limit:60];
    }];
}

// ---------------------------------------------------------------------
//  Cham / giu / keo / 2 ngon
// ---------------------------------------------------------------------
// Giu bong bong: sau SPP_HOLD_BEGIN giay hien vien do chay quanh hinh chinh, du SPP_HOLD_QUIT giay -> thoat han app.
// Tha tay som -> huy. Dang giu ma keo di -> huy dem, chuyen sang di chuyen the.
- (void)longPressed:(UILongPressGestureRecognizer *)g
{
    CGPoint p = [g locationInView:self.window];
    switch (g.state) {
    case UIGestureRecognizerStateBegan:
        self.holdStart = p; self.holdDragging = NO;
        [self startHold];
        break;
    case UIGestureRecognizerStateChanged:
        if (!self.holdDragging && hypot(p.x - self.holdStart.x, p.y - self.holdStart.y) > 12) { self.holdDragging = YES; [self cancelHold]; }
        if (self.holdDragging) {
            self.card.center = CGPointMake(self.card.center.x + p.x - self.holdStart.x, self.card.center.y + p.y - self.holdStart.y);
            self.holdStart = p;
            [self clampCard];
        }
        break;
    default:   // Ended / Cancelled / Failed
        if (self.holdDragging) [self saveCardPosition];
        self.holdDragging = NO;
        [self cancelHold];
        break;
    }
}

- (void)startHold
{
    [self cancelHold];
    CGFloat remain = SPP_HOLD_QUIT - SPP_HOLD_BEGIN;
    CGRect r = CGRectInset(self.outlineRect, -5, -5);
    CAShapeLayer *ring = [CAShapeLayer layer];
    ring.path = [UIBezierPath bezierPathWithRoundedRect:r cornerRadius:self.outlineCorner + 5].CGPath;
    ring.fillColor = [UIColor clearColor].CGColor;
    ring.strokeColor = SPPRed().CGColor;
    ring.lineWidth = 4; ring.lineCap = kCALineCapRound;
    ring.shadowColor = SPPRed().CGColor; ring.shadowRadius = 4; ring.shadowOpacity = 0.8; ring.shadowOffset = CGSizeZero;
    ring.strokeEnd = 1;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    a.fromValue = @0; a.toValue = @1; a.duration = remain;
    [ring addAnimation:a forKey:@"sppHold"];
    [self.card.layer addSublayer:ring];
    self.holdRing = ring;
    [UIView animateWithDuration:remain delay:0 options:UIViewAnimationOptionCurveEaseIn | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self.card.transform = [self baseScaled:0.92]; } completion:nil];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    __weak SPPBubble *weakSelf = self;
    self.holdTimer = [NSTimer scheduledTimerWithTimeInterval:remain repeats:NO block:^(NSTimer *t) { [weakSelf quitSourceApp]; }];
}

- (void)cancelHold
{
    [self.holdTimer invalidate]; self.holdTimer = nil;
    if (!self.holdRing) return;
    [self.holdRing removeFromSuperlayer]; self.holdRing = nil;
    [UIView animateWithDuration:0.2 delay:0 options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.card.transform = [self baseTransform]; } completion:nil];
}

// Du 3 giay: thoat han app dang cap toc do, an bong bong ngay
- (void)quitSourceApp
{
    [self cancelHold];
    NSString *bid = SPPNavAppBundle(self.app);
    SPPLog("bubble: giu %.0f giay -> thoat han %@", SPP_HOLD_QUIT, bid);
    [[[UINotificationFeedbackGenerator alloc] init] notificationOccurred:UINotificationFeedbackTypeSuccess];
    SPPKillApp(bid);
    self.speed = -1; self.limit = -1;
    self.lastUpdate = 0;
    [self hide];
}

// 2 ngon: phong to / thu nho the (SPP_SCALE_MIN .. SPP_SCALE_MAX), nho lai co da chon
- (void)pinched:(UIPinchGestureRecognizer *)g
{
    static CGFloat startScale = 1;
    if (g.state == UIGestureRecognizerStateBegan) { startScale = self.scale; [self cancelHold]; }
    if (g.state == UIGestureRecognizerStateBegan || g.state == UIGestureRecognizerStateChanged) {
        self.scale = MIN(SPP_SCALE_MAX, MAX(SPP_SCALE_MIN, startScale * g.scale));
        self.card.transform = [self baseTransform];
        [self clampCard];
    }
    if (g.state == UIGestureRecognizerStateEnded) {
        [self saveCardPosition];
        [[NSUserDefaults standardUserDefaults] setDouble:self.scale forKey:SPP_SCALE_KEY];
    }
}

- (void)panned:(UIPanGestureRecognizer *)g
{
    if (g.state == UIGestureRecognizerStateBegan) [self cancelHold];
    CGPoint t = [g translationInView:self.window];
    self.card.center = CGPointMake(self.card.center.x + t.x, self.card.center.y + t.y);
    [self clampCard];
    [g setTranslation:CGPointZero inView:self.window];
    if (g.state == UIGestureRecognizerStateEnded) [self saveCardPosition];
}

// Cham bong bong -> mo lai app dan duong (tren xe: giao dien CarPlay cua app; khong co xe: tren iPhone)
- (void)tapped:(UITapGestureRecognizer *)g
{
    [UIView animateWithDuration:0.1 animations:^{ self.card.transform = [self baseScaled:0.92]; }
                     completion:^(BOOL f) { [UIView animateWithDuration:0.15 animations:^{ self.card.transform = [self baseTransform]; }]; }];
    if (!self.onPhone) {
        SPPLog("bubble: cham -> mo %@ tren CarPlay", SPPNavAppName(self.app));
        static int tokOpen = 0;
        if (!tokOpen) notify_register_check(SPP_DARWIN_OPEN_CAR, &tokOpen);
        notify_set_state(tokOpen, (uint64_t)self.app);
        notify_post(SPP_DARWIN_OPEN_CAR);   // process CarPlay mo app (CarPlay.xm)
        return;
    }
    SPPLog("bubble: cham -> mo %@ tren iPhone", SPPNavAppName(self.app));
    SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
    if ([sb respondsToSelector:@selector(launchApplicationWithIdentifier:suspended:)])
        [sb launchApplicationWithIdentifier:SPPNavAppBundle(self.app) suspended:NO];
}

// ---------------------------------------------------------------------
//  Cua so rieng: tren man xe neu dang ket noi, neu khong thi tren man iPhone
// ---------------------------------------------------------------------
- (void)ensureWindow
{
    BOOL car = SPPGetCarPlayCADisplay() != nil;
    if (self.window && self.onPhone == !car) return;
    if (self.window) { self.window.hidden = YES; [self.window removeFromSuperview]; self.window = nil; }
    UIWindow *w = car ? SPPMakeCarWindow() : SPPMakePhoneWindow();   // iPhone: xoay theo huong may (applyPhoneOrientation)
    if (!w) return;
    self.onPhone = !car;
    SPPMakeWindowPassThrough(w);
    w.windowLevel = UIWindowLevelStatusBar + 70;
    w.backgroundColor = [UIColor clearColor];

    // The chua noi dung theo kieu da chon (xem buildStyle:)
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    [card addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)]];
    [card addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)]];
    [card addGestureRecognizer:[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinched:)]];
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
    lp.minimumPressDuration = SPP_HOLD_BEGIN;
    lp.allowableMovement = CGFLOAT_MAX;   // tu xu ly keo trong longPressed: (keo xa -> di chuyen the)
    [card addGestureRecognizer:lp];
    card.transform = [self baseTransform];
    [w addSubview:card];

    self.window = w; self.card = card;
    self.builtStyle = -1;   // ve lai noi dung trong the moi
    if (!car) [self applyPhoneOrientationForce:YES];
    [self restoreCardPosition];
    w.hidden = YES;
    SPPLog("bubble: cua so %@ tao xong", car ? @"xe" : @"iPhone");
}

// ---------------------------------------------------------------------
//  Huong & vi tri
//  iPhone: cua so xoay theo huong cam may (doc / ngang trai / ngang phai).
//  CarPlay: cua so nam tren man xe (huong cua man xe), vi tri mac dinh ben phai dock CarPlay.
// ---------------------------------------------------------------------
- (void)startOrientationTracking
{
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    __weak SPPBubble *weakSelf = self;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification object:nil
                                                       queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        SPPBubble *me = weakSelf;
        if (me.window && me.onPhone) [me applyPhoneOrientationForce:NO];
    }];
}

// Goc xoay noi dung tren iPhone (giu goc cu khi may nam ngua / up / khong ro)
- (CGFloat)phoneRotation
{
    switch ([UIDevice currentDevice].orientation) {
        case UIDeviceOrientationPortrait:       return 0;
        case UIDeviceOrientationLandscapeLeft:  return M_PI_2;
        case UIDeviceOrientationLandscapeRight: return -M_PI_2;
        default: return self.appliedRotation;
    }
}

- (void)applyPhoneOrientationForce:(BOOL)force
{
    if (!self.window || !self.onPhone) return;
    CGFloat r = [self phoneRotation];
    if (!force && fabs(r - self.appliedRotation) < 0.01) return;
    BOOL wasVisible = !self.window.hidden && self.card.bounds.size.width > 10;
    if (wasVisible && !force) [self saveCardPosition];
    CGRect sb = [UIScreen mainScreen].bounds;
    BOOL land = fabs(r) > 0.1;
    self.window.transform = CGAffineTransformMakeRotation(r);
    self.window.bounds = land ? CGRectMake(0, 0, sb.size.height, sb.size.width) : CGRectMake(0, 0, sb.size.width, sb.size.height);
    self.window.center = CGPointMake(CGRectGetMidX(sb), CGRectGetMidY(sb));
    self.appliedRotation = r;
    [self restoreCardPosition];
    SPPLog("bubble: iPhone xoay %.0f do", r * 180 / M_PI);
}

// Vi tri mac dinh: iPhone = goc tren trai (duoi thanh trang thai); xe = ngay ben phai dock CarPlay
- (CGPoint)defaultCardCenter
{
    CGRect b = self.window.bounds;
    if (self.onPhone) return CGPointMake(16 + 70, b.size.height > b.size.width ? 70 : 12 + 40);
    return CGPointMake(MIN(b.size.width - 80, 90 + 80), 12 + 40);
}

- (void)saveCardPosition
{
    CGRect b = self.window.bounds;
    if (b.size.width < 1 || b.size.height < 1) return;
    CGPoint f = CGPointMake(self.card.center.x / b.size.width, self.card.center.y / b.size.height);
    if (self.onPhone) self.phoneFraction = f; else self.carFraction = f;
}

- (void)restoreCardPosition
{
    CGRect b = self.window.bounds;
    CGPoint f = self.onPhone ? self.phoneFraction : self.carFraction;
    self.card.center = (f.x < 0) ? [self defaultCardCenter] : CGPointMake(f.x * b.size.width, f.y * b.size.height);
    [self clampCard];
}

- (void)clampCard
{
    CGRect b = self.window.bounds; CGSize s = self.card.frame.size; CGPoint c = self.card.center;   // frame da tinh ti le
    c.x = MIN(CGRectGetMaxX(b) - s.width / 2, MAX(s.width / 2, c.x));
    c.y = MIN(CGRectGetMaxY(b) - s.height / 2, MAX(s.height / 2, c.y));
    self.card.center = c;
}

@end
