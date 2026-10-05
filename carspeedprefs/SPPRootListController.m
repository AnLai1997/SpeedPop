#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>

#define SPP_DOMAIN      @"carspeed"
#define SPP_PREFS_NOTIF @"carspeed.prefschanged"

@interface SPPRootListController : PSListController
@end

// Man chon kieu hien thi: chia nhom, dau tick o kieu dang dung, chon xong cho xem thu luon
@interface SPPStyleController : PSListController
@end

// Co trong Preferences.framework nhung header cua Theos khong khai bao
@interface PSSpecifier (SPPPrivate)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles shortTitles:(NSArray *)shortTitles;
@end

@interface UIImage (SPPPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bid format:(int)format scale:(CGFloat)scale;
@end

// ---------------------------------------------------------------------
//  Doc / ghi cai dat
// ---------------------------------------------------------------------
static id SPPGet(NSString *key)
{
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)SPP_DOMAIN);
    return v ? (__bridge_transfer id)v : nil;
}

static void SPPSet(NSString *key, id value)
{
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)SPP_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)SPP_DOMAIN);
    notify_post(SPP_PREFS_NOTIF.UTF8String);
}

// ---------------------------------------------------------------------
//  Ngon ngu: Language = 0 tu dong (theo may), 1 Tieng Viet, 2 English
// ---------------------------------------------------------------------
static NSInteger SPPLanguage(void) { return [SPPGet(@"Language") integerValue]; }

static BOOL SPPUseVietnamese(void)
{
    NSInteger lang = SPPLanguage();
    if (lang == 1) return YES;
    if (lang == 2) return NO;
    return [[[NSLocale preferredLanguages] firstObject] hasPrefix:@"vi"];
}

static NSString *L(NSString *key)
{
    static NSDictionary<NSString *, NSArray<NSString *> *> *t;   // key -> @[tieng Viet, English]
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @{
            @"tagline":        @[@"Bong bóng tốc độ & biển giới hạn khi lái xe", @"Speed & speed-limit bubble while you drive"],
            @"language":       @[@"Ngôn ngữ", @"Language"],
            @"lang.auto":      @[@"Tự động (theo máy)", @"Automatic (system)"],

            @"enabled":        @[@"Bật bong bóng", @"Show bubble"],
            @"enabled.footer": @[@"Bong bóng hiện khi app dẫn đường chạy nền và tự ẩn khi bạn mở lại app. Khi kết nối CarPlay, bong bóng chỉ hiện trên màn hình xe.",
                                 @"The bubble appears while a navigation app runs in the background and hides when you open the app again. With CarPlay connected it shows only on the car screen."],

            @"appearance":     @[@"GIAO DIỆN", @"APPEARANCE"],
            @"style":          @[@"Kiểu hiển thị", @"Style"],
            @"showIcon":       @[@"Hiện icon app", @"Show app icon"],
            @"preview":        @[@"Xem thử 10 giây", @"Preview for 10 seconds"],

            @"size.phone":     @[@"KÍCH THƯỚC TRÊN IPHONE", @"SIZE ON IPHONE"],
            @"size.car":       @[@"KÍCH THƯỚC TRÊN CARPLAY", @"SIZE ON CARPLAY"],
            @"reset":          @[@"Đặt lại vị trí & kích thước", @"Reset position & size"],
            @"size.footer":    @[@"100 là cỡ mặc định. Chụm 2 ngón trên bong bóng cũng đổi cỡ và cập nhật ở đây.",
                                 @"100 is the default size. Pinching the bubble also resizes it and updates this value."],

            @"sources":        @[@"NGUỒN TỐC ĐỘ", @"SPEED SOURCES"],
            @"sources.footer": @[@"Chạy cả hai app thì bong bóng theo app đang chạy nền. Lần đầu cài, mở lại app dẫn đường để tweak được nạp.",
                                 @"With both apps running, the bubble follows the one in the background. After the first install, relaunch the navigation app so the tweak loads."],

            @"gestures":       @[@"THAO TÁC TRÊN BONG BÓNG", @"BUBBLE GESTURES"],
            @"g.drag":         @[@"Kéo", @"Drag"],
            @"g.drag.v":       @[@"Di chuyển", @"Move"],
            @"g.pinch":        @[@"Chụm 2 ngón", @"Pinch"],
            @"g.pinch.v":      @[@"Đổi cỡ", @"Resize"],
            @"g.tap":          @[@"Chạm", @"Tap"],
            @"g.tap.v":        @[@"Mở lại app", @"Reopen app"],
            @"g.hold":         @[@"Giữ 2 giây", @"Hold 2 seconds"],
            @"g.hold.v":       @[@"Thoát hẳn app", @"Quit app"],

            @"about":          @[@"CarSpeed %@ · anlai\nLog: /var/mobile/Documents/CarSpeed.log", @"CarSpeed %@ · anlai\nLog: /var/mobile/Documents/CarSpeed.log"],

            // Nhom kieu + ten kieu (thu tu = enum SPPStyle trong src/SPPBubble.mm)
            @"sg.cards":       @[@"THẺ & VIÊN THUỐC", @"CARDS & PILLS"],
            @"sg.round":       @[@"TRÒN", @"ROUND"],
            @"sg.harmony":     @[@"HARMONYOS", @"HARMONYOS"],
            @"sg.footer":      @[@"Chọn một kiểu để xem thử ngay 10 giây.", @"Pick a style to preview it for 10 seconds."],
            @"style.0":        @[@"Thẻ", @"Card"],
            @"style.1":        @[@"Thẻ sáng", @"Light card"],
            @"style.2":        @[@"Kính mờ", @"Frosted glass"],
            @"style.3":        @[@"Viên thuốc đôi", @"Split pill"],
            @"style.4":        @[@"Live View", @"Live View"],
            @"style.5":        @[@"Cột dọc", @"Tower"],
            @"style.6":        @[@"Đèn LED", @"LED bar"],
            @"style.7":        @[@"Biển báo lớn", @"Big sign"],
            @"style.8":        @[@"Đĩa màu theo tốc độ", @"Speed color disc"],
            @"style.9":        @[@"Đồng hồ cung", @"Arc gauge"],
            @"style.10":       @[@"Đồng hồ kim", @"Analog speedometer"],
            @"style.11":       @[@"Thẻ HarmonyOS", @"HarmonyOS card"],
            @"style.12":       @[@"Vòng kép HarmonyOS", @"HarmonyOS rings"],
            @"style.13":       @[@"Bán nguyệt HarmonyOS", @"HarmonyOS half-moon"],
        };
    });
    NSArray<NSString *> *pair = t[key];
    if (!pair) return key;
    return SPPUseVietnamese() ? pair[0] : pair[1];
}

#define SPP_STYLE_COUNT 14
static NSString *SPPStyleName(NSInteger i) { return L([NSString stringWithFormat:@"style.%ld", (long)i]); }

// ---------------------------------------------------------------------
//  Icon o vuong bo goc kieu Cai dat iOS: nen mau + ky hieu SF trang
// ---------------------------------------------------------------------
static UIColor *SPPHex(uint32_t rgb) { return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1]; }

static UIImage *SPPSymbolIcon(NSString *symbol, UIColor *bg)
{
    CGFloat d = 29;
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(d, d)];
    return [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [bg setFill];
        UIBezierPath *p = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, d, d) cornerRadius:6.5];
        [p fill];
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
        UIImage *s = [[UIImage systemImageNamed:symbol withConfiguration:cfg] imageWithTintColor:[UIColor whiteColor]
                                                                                    renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGFloat k = MIN(1.0, 19.0 / MAX(s.size.width, s.size.height));
        CGSize ss = CGSizeMake(s.size.width * k, s.size.height * k);
        [s drawInRect:CGRectMake((d - ss.width) / 2, (d - ss.height) / 2, ss.width, ss.height)];
    }];
}

// Icon that cua app dan duong (neu khong lay duoc -> icon ky hieu)
static UIImage *SPPAppIcon(NSString *bid, NSString *fallbackSymbol, UIColor *fallbackColor)
{
    UIImage *img = nil;
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
        img = [UIImage _applicationIconImageForBundleIdentifier:bid format:0 scale:[UIScreen mainScreen].scale];
    return img ?: SPPSymbolIcon(fallbackSymbol, fallbackColor);
}

// ---------------------------------------------------------------------
//  Tao o cai dat
// ---------------------------------------------------------------------
static PSSpecifier *SPPGroup(NSString *name, NSString *footer)
{
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:name];
    if (footer) [g setProperty:footer forKey:@"footerText"];
    return g;
}

// O cai dat luu vao domain carspeed, bao SpringBoard ve lai ngay
static PSSpecifier *SPPPref(id target, NSString *name, NSString *key, PSCellType cell, id def, Class detail)
{
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name target:target set:@selector(setPreferenceValue:specifier:)
                                                       get:@selector(readPreferenceValue:) detail:detail cell:cell edit:nil];
    [s setProperty:SPP_DOMAIN forKey:@"defaults"];
    [s setProperty:key forKey:@"key"];
    [s setProperty:def forKey:@"default"];
    [s setProperty:SPP_PREFS_NOTIF forKey:@"PostNotification"];
    return s;
}

@implementation SPPRootListController

- (NSString *)version
{
    return [[NSBundle bundleForClass:[self class]] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
}

// Thanh truot kich thuoc 60..220 %, nhay buoc 10, hien so; chu A nho / lon o 2 dau
- (PSSpecifier *)sizeSlider:(NSString *)key
{
    PSSpecifier *s = SPPPref(self, @"", key, PSSliderCell, @100, nil);
    [s setProperty:@60 forKey:@"min"];
    [s setProperty:@220 forKey:@"max"];
    [s setProperty:@YES forKey:@"showValue"];
    [s setProperty:@YES forKey:@"isSegmented"];
    [s setProperty:@16 forKey:@"segmentCount"];
    UIImageSymbolConfiguration *small = [UIImageSymbolConfiguration configurationWithPointSize:11 weight:UIImageSymbolWeightMedium];
    UIImageSymbolConfiguration *big = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
    UIImage *a = [[UIImage systemImageNamed:@"textformat.size.smaller" withConfiguration:small] imageWithTintColor:[UIColor secondaryLabelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIImage *b = [[UIImage systemImageNamed:@"textformat.size.larger" withConfiguration:big] imageWithTintColor:[UIColor secondaryLabelColor] renderingMode:UIImageRenderingModeAlwaysOriginal];
    if (a) [s setProperty:a forKey:@"leftImage"];
    if (b) [s setProperty:b forKey:@"rightImage"];
    return s;
}

- (PSSpecifier *)button:(NSString *)name action:(SEL)action icon:(UIImage *)icon
{
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    s.buttonAction = action;
    if (icon) [s setProperty:icon forKey:@"iconImage"];
    return s;
}

// Dong thao tac: [icon] Ten ........ tac dung
- (PSSpecifier *)gesture:(NSString *)key symbol:(NSString *)symbol color:(UIColor *)color
{
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:L(key) target:self set:nil get:@selector(gestureValue:)
                                                    detail:nil cell:PSTitleValueCell edit:nil];
    [s setProperty:L([key stringByAppendingString:@".v"]) forKey:@"sppValue"];
    [s setProperty:SPPSymbolIcon(symbol, color) forKey:@"iconImage"];
    return s;
}

- (id)gestureValue:(PSSpecifier *)s { return [s propertyForKey:@"sppValue"]; }

- (NSArray *)specifiers
{
    if (!_specifiers) {
        NSMutableArray *a = [NSMutableArray array];

        // Bat / tat
        [a addObject:SPPGroup(nil, L(@"enabled.footer"))];
        PSSpecifier *en = SPPPref(self, L(@"enabled"), @"Enabled", PSSwitchCell, @YES, nil);
        [en setProperty:SPPSymbolIcon(@"speedometer", SPPHex(0x0A59F7)) forKey:@"iconImage"];
        [a addObject:en];

        // Giao dien
        [a addObject:SPPGroup(L(@"appearance"), nil)];
        PSSpecifier *style = SPPPref(self, L(@"style"), @"Style", PSLinkListCell, @0, [SPPStyleController class]);
        NSMutableArray *values = [NSMutableArray array], *titles = [NSMutableArray array];
        for (NSInteger i = 0; i < SPP_STYLE_COUNT; i++) { [values addObject:@(i)]; [titles addObject:SPPStyleName(i)]; }
        [style setValues:values titles:titles shortTitles:titles];
        [style setProperty:@"style" forKey:@"id"];
        [style setProperty:SPPSymbolIcon(@"paintpalette.fill", SPPHex(0xAF52DE)) forKey:@"iconImage"];
        [a addObject:style];
        PSSpecifier *icon = SPPPref(self, L(@"showIcon"), @"ShowAppIcon", PSSwitchCell, @YES, nil);
        [icon setProperty:SPPSymbolIcon(@"app.fill", SPPHex(0x5856D6)) forKey:@"iconImage"];
        [a addObject:icon];
        [a addObject:[self button:L(@"preview") action:@selector(bubbleDemo) icon:SPPSymbolIcon(@"play.fill", SPPHex(0x34C759))]];

        // Kich thuoc: rieng iPhone / CarPlay (%), buoc 10
        [a addObject:SPPGroup(L(@"size.phone"), nil)];
        [a addObject:[self sizeSlider:@"SizePhone"]];
        [a addObject:SPPGroup(L(@"size.car"), L(@"size.footer"))];
        [a addObject:[self sizeSlider:@"SizeCar"]];
        [a addObject:[self button:L(@"reset") action:@selector(resetLayout) icon:SPPSymbolIcon(@"arrow.counterclockwise", SPPHex(0x8E8E93))]];

        // Nguon toc do: icon that cua tung app
        [a addObject:SPPGroup(L(@"sources"), L(@"sources.footer"))];
        PSSpecifier *vm = SPPPref(self, @"Vietmap Live", @"AppVietmap", PSSwitchCell, @YES, nil);
        [vm setProperty:SPPAppIcon(@"vn.vietmap.live", @"map.fill", SPPHex(0x1A66D9)) forKey:@"iconImage"];
        [a addObject:vm];
        PSSpecifier *go = SPPPref(self, @"GOFA", @"AppGOFA", PSSwitchCell, @YES, nil);
        [go setProperty:SPPAppIcon(@"com.lumi.GOFA", @"location.fill", SPPHex(0x00996E)) forKey:@"iconImage"];
        [a addObject:go];

        // Thao tac tren bong bong
        [a addObject:SPPGroup(L(@"gestures"), nil)];
        [a addObject:[self gesture:@"g.drag" symbol:@"hand.draw.fill" color:SPPHex(0x007AFF)]];
        [a addObject:[self gesture:@"g.pinch" symbol:@"arrow.up.left.and.arrow.down.right" color:SPPHex(0xFF9500)]];
        [a addObject:[self gesture:@"g.tap" symbol:@"hand.tap.fill" color:SPPHex(0x34C759)]];
        [a addObject:[self gesture:@"g.hold" symbol:@"xmark" color:SPPHex(0xFF3B30)]];

        // Thong tin
        PSSpecifier *about = SPPGroup(nil, [NSString stringWithFormat:L(@"about"), [self version]]);
        [about setProperty:@1 forKey:@"footerAlignment"];   // can giua
        [a addObject:about];

        _specifiers = a;
    }
    return _specifiers;
}

// ---------------------------------------------------------------------
//  Dau trang + nut ngon ngu goc phai
// ---------------------------------------------------------------------
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"CarSpeed";
    [self updateHeader];
    [self updateLanguageButton];
}

// Quay lai tu man chon kieu -> cap nhat ten kieu dang dung
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self reloadSpecifierID:@"style" animated:NO];
}

- (void)updateLanguageButton
{
    NSInteger lang = SPPLanguage();
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium];
    [b setImage:[UIImage systemImageNamed:@"globe" withConfiguration:cfg] forState:UIControlStateNormal];
    [b setTitle:(SPPUseVietnamese() ? @" VI" : @" EN") forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];

    NSArray<NSString *> *titles = @[L(@"lang.auto"), @"Tiếng Việt", @"English"];
    NSMutableArray<UIMenuElement *> *items = [NSMutableArray array];
    __weak SPPRootListController *weakSelf = self;
    for (NSInteger i = 0; i < 3; i++) {
        UIAction *act = [UIAction actionWithTitle:titles[i] image:nil identifier:nil handler:^(__kindof UIAction *x) {
            [weakSelf setLanguage:i];
        }];
        act.state = (i == lang) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [items addObject:act];
    }
    b.menu = [UIMenu menuWithTitle:L(@"language") children:items];
    b.showsMenuAsPrimaryAction = YES;
    [b sizeToFit];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:b];
}

// Doi ngon ngu -> dung lai toan bo cac o theo ngon ngu moi
- (void)setLanguage:(NSInteger)lang
{
    if (lang == SPPLanguage()) return;
    SPPSet(@"Language", @(lang));
    [self reloadSpecifiers];
    [self updateHeader];
    [self updateLanguageButton];
}

- (void)updateHeader
{
    UITableView *table = self.table;
    if (!table) return;
    CGFloat w = table.bounds.size.width ?: [UIScreen mainScreen].bounds.size.width;
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 176)];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"CarSpeed" inBundle:[NSBundle bundleForClass:[self class]]
                                                compatibleWithTraitCollection:nil]];
    icon.frame = CGRectMake((w - 76) / 2, 16, 76, 76);
    icon.layer.cornerRadius = 17;
    icon.layer.masksToBounds = YES;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [h addSubview:icon];

    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(16, 102, w - 32, 32)];
    name.text = @"CarSpeed";
    name.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    name.textAlignment = NSTextAlignmentCenter;
    name.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [h addSubview:name];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(16, 136, w - 32, 20)];
    sub.text = L(@"tagline");
    sub.font = [UIFont systemFontOfSize:15];
    sub.textColor = [UIColor secondaryLabelColor];
    sub.textAlignment = NSTextAlignmentCenter;
    sub.adjustsFontSizeToFitWidth = YES;
    sub.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [h addSubview:sub];

    table.tableHeaderView = h;
}

// ---------------------------------------------------------------------
//  Nut: gui Darwin notification sang SpringBoard
// ---------------------------------------------------------------------
- (void)bubbleDemo
{
    notify_post("carspeed.demo");
}

- (void)resetLayout
{
    notify_post("carspeed.resetlayout");
    // SpringBoard ghi lai kich thuoc 100 -> doc lai de thanh truot cap nhat
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize((__bridge CFStringRef)SPP_DOMAIN);
        [self reloadSpecifiers];
        [self updateHeader];
    });
}

@end

// ---------------------------------------------------------------------
//  Man chon kieu hien thi
// ---------------------------------------------------------------------
@implementation SPPStyleController

- (NSArray *)specifiers
{
    if (!_specifiers) {
        NSMutableArray *a = [NSMutableArray array];
        // Nhom: [ten nhom, kieu dau, kieu cuoi]
        NSArray *groups = @[@[@"sg.cards", @0, @6], @[@"sg.round", @7, @10], @[@"sg.harmony", @11, @13]];
        for (NSArray *grp in groups) {
            BOOL last = (grp == groups.lastObject);
            [a addObject:SPPGroup(L(grp[0]), last ? L(@"sg.footer") : nil)];
            for (NSInteger i = [grp[1] integerValue]; i <= [grp[2] integerValue]; i++) {
                PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:SPPStyleName(i) target:self set:nil get:nil
                                                                detail:nil cell:PSListItemCell edit:nil];
                [s setProperty:@(i) forKey:@"sppStyle"];
                [a addObject:s];
            }
        }
        _specifiers = a;
    }
    return _specifiers;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = L(@"style");
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip
{
    UITableViewCell *cell = [super tableView:tv cellForRowAtIndexPath:ip];
    NSNumber *st = [[self specifierAtIndexPath:ip] propertyForKey:@"sppStyle"];
    cell.accessoryType = (st && st.integerValue == [SPPGet(@"Style") integerValue]) ? UITableViewCellAccessoryCheckmark
                                                                                     : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip
{
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSNumber *st = [[self specifierAtIndexPath:ip] propertyForKey:@"sppStyle"];
    if (!st) return;
    SPPSet(@"Style", st);
    for (UITableViewCell *c in tv.visibleCells) {
        NSIndexPath *p = [tv indexPathForCell:c];
        NSNumber *v = p ? [[self specifierAtIndexPath:p] propertyForKey:@"sppStyle"] : nil;
        c.accessoryType = (v && v.integerValue == st.integerValue) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    notify_post("carspeed.demo");   // xem thu kieu vua chon
}

@end
