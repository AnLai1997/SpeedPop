#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>

#define SPP_DOMAIN      @"csbubble"
#define SPP_PREFS_NOTIF @"csbubble.prefschanged"

@interface SPPRootListController : PSListController
@end

// Co trong Preferences.framework nhung header cua Theos khong khai bao
@interface PSSpecifier (SPPPrivate)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles shortTitles:(NSArray *)shortTitles;
@end

// ---------------------------------------------------------------------
//  Ngon ngu: Language = 0 tu dong (theo may), 1 Tieng Viet, 2 English
// ---------------------------------------------------------------------
static BOOL SPPUseVietnamese(void)
{
    CFPropertyListRef v = CFPreferencesCopyAppValue(CFSTR("Language"), (__bridge CFStringRef)SPP_DOMAIN);
    NSInteger lang = v ? [(__bridge_transfer NSNumber *)v integerValue] : 0;
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
            @"tagline":        @[@"Tốc độ & biển giới hạn từ app dẫn đường", @"Speed & speed limit from your navigation app"],
            @"general":        @[@"CHUNG", @"GENERAL"],
            @"enabled":        @[@"Bật bong bóng tốc độ", @"Enable speed bubble"],
            @"language":       @[@"Ngôn ngữ", @"Language"],
            @"lang.auto":      @[@"Tự động (theo máy)", @"Automatic (system)"],
            @"general.footer": @[@"Bong bóng hiện khi app dẫn đường chạy nền và tự ẩn khi app được mở lại. Khi kết nối CarPlay, bong bóng chỉ hiện trên màn hình xe; không có xe thì hiện trên iPhone.",
                                 @"The bubble appears while a navigation app runs in the background and hides when the app is opened again. With CarPlay connected it shows only on the car screen; otherwise on the iPhone."],
            @"appearance":     @[@"GIAO DIỆN", @"APPEARANCE"],
            @"style":          @[@"Kiểu hiển thị", @"Style"],
            @"style.0":        @[@"Thẻ ngang", @"Card"],
            @"style.1":        @[@"Đĩa nhỏ", @"Mini disc"],
            @"style.2":        @[@"Biển báo lớn", @"Big sign"],
            @"style.3":        @[@"Đồng hồ", @"Gauge"],
            @"style.4":        @[@"Thanh HUD", @"HUD bar"],
            @"style.5":        @[@"Màu theo tốc độ", @"Speed color"],
            @"style.6":        @[@"Cột dọc", @"Tower"],
            @"style.7":        @[@"Viên thuốc đôi", @"Split pill"],
            @"style.8":        @[@"Neon", @"Neon"],
            @"style.9":        @[@"Thanh đo", @"Meter bar"],
            @"style.10":       @[@"Chữ nổi (không nền)", @"Floating text"],
            @"style.11":       @[@"Thẻ sáng", @"Light card"],
            @"style.12":       @[@"Vô lăng", @"Steering wheel"],
            @"style.13":       @[@"Bánh xe (mâm quay)", @"Wheel (spinning rim)"],
            @"style.14":       @[@"Thẻ HarmonyOS", @"HarmonyOS card"],
            @"style.15":       @[@"Đồng hồ kim", @"Analog speedometer"],
            @"style.16":       @[@"Vòng kép HarmonyOS", @"HarmonyOS rings"],
            @"style.17":       @[@"Live View", @"Live View capsule"],
            @"showIcon":       @[@"Hiện icon app", @"Show app icon"],
            @"preview":        @[@"Xem thử (10 giây)", @"Preview (10 seconds)"],
            @"reset":          @[@"Đặt lại vị trí & kích thước", @"Reset position & size"],
            @"size.phone":     @[@"KÍCH THƯỚC TRÊN IPHONE", @"SIZE ON IPHONE"],
            @"size.car":       @[@"KÍCH THƯỚC TRÊN CARPLAY", @"SIZE ON CARPLAY"],
            @"size.footer":    @[@"100 = cỡ mặc định (60 – 220). Chụm 2 ngón trên bong bóng cũng đổi cỡ của màn đang dùng và cập nhật ở đây.",
                                 @"100 = default size (60 – 220). Pinching the bubble also resizes it on the current screen and updates this value."],
            @"appearance.footer": @[@"Kéo để di chuyển · chụm 2 ngón để đổi cỡ · chạm để mở lại app · giữ 2 giây (viền đỏ chạy hết vòng) để thoát hẳn app.",
                                    @"Drag to move · pinch to resize · tap to reopen the app · hold for 2 seconds (until the red ring completes) to quit the app."],
            @"sources":        @[@"NGUỒN TỐC ĐỘ", @"SPEED SOURCES"],
            @"sources.footer": @[@"Icon trên bong bóng cho biết tốc độ đang lấy từ app nào. Chạy cả hai app: bong bóng theo app đang chạy nền. Lần đầu cài, mở lại app dẫn đường để tweak được nạp.",
                                 @"The icon on the bubble shows which app the speed comes from. With both apps running, the bubble follows the one in the background. After the first install, relaunch the navigation app so the tweak loads."],
            @"about":          @[@"CSBubble %@ · anlai\nLog: /var/mobile/Documents/CSBubble.log", @"CSBubble %@ · anlai\nLog: /var/mobile/Documents/CSBubble.log"],
        };
    });
    NSArray<NSString *> *pair = t[key];
    if (!pair) return key;
    return SPPUseVietnamese() ? pair[0] : pair[1];
}

@implementation SPPRootListController

- (NSString *)version
{
    return [[NSBundle bundleForClass:[self class]] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"";
}

- (PSSpecifier *)group:(NSString *)name footer:(NSString *)footer
{
    PSSpecifier *g = [PSSpecifier groupSpecifierWithName:name];
    if (footer) [g setProperty:footer forKey:@"footerText"];
    return g;
}

// O cai dat luu vao domain csbubble, bao SpringBoard ve lai ngay
- (PSSpecifier *)pref:(NSString *)name key:(NSString *)key cell:(PSCellType)cell default:(id)def
{
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setPreferenceValue:specifier:)
                                                       get:@selector(readPreferenceValue:)
                                                    detail:(cell == PSLinkListCell ? NSClassFromString(@"PSListItemsController") : nil)
                                                      cell:cell edit:nil];
    [s setProperty:SPP_DOMAIN forKey:@"defaults"];
    [s setProperty:key forKey:@"key"];
    [s setProperty:def forKey:@"default"];
    [s setProperty:SPP_PREFS_NOTIF forKey:@"PostNotification"];
    return s;
}

// Thanh truot kich thuoc 60..220 %, nhay buoc 10, hien so
- (PSSpecifier *)sizeSlider:(NSString *)key
{
    PSSpecifier *s = [self pref:@"" key:key cell:PSSliderCell default:@100];
    [s setProperty:@60 forKey:@"min"];
    [s setProperty:@220 forKey:@"max"];
    [s setProperty:@YES forKey:@"showValue"];
    [s setProperty:@YES forKey:@"isSegmented"];
    [s setProperty:@16 forKey:@"segmentCount"];
    return s;
}

- (PSSpecifier *)button:(NSString *)name action:(SEL)action
{
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    s.buttonAction = action;
    return s;
}

- (NSArray *)specifiers
{
    if (!_specifiers) {
        NSMutableArray *a = [NSMutableArray array];

        // Chung
        [a addObject:[self group:L(@"general") footer:L(@"general.footer")]];
        [a addObject:[self pref:L(@"enabled") key:@"Enabled" cell:PSSwitchCell default:@YES]];
        PSSpecifier *lang = [self pref:L(@"language") key:@"Language" cell:PSLinkListCell default:@0];
        [lang setValues:@[@0, @1, @2] titles:@[L(@"lang.auto"), @"Tiếng Việt", @"English"]
            shortTitles:@[L(@"lang.auto"), @"Tiếng Việt", @"English"]];
        [a addObject:lang];

        // Giao dien
        [a addObject:[self group:L(@"appearance") footer:L(@"appearance.footer")]];
        PSSpecifier *style = [self pref:L(@"style") key:@"Style" cell:PSLinkListCell default:@0];
        NSMutableArray *titles = [NSMutableArray array];
        NSMutableArray *values = [NSMutableArray array];
        for (int i = 0; i < 18; i++) { [values addObject:@(i)]; [titles addObject:L([NSString stringWithFormat:@"style.%d", i])]; }
        [style setValues:values titles:titles shortTitles:titles];
        [a addObject:style];
        [a addObject:[self pref:L(@"showIcon") key:@"ShowAppIcon" cell:PSSwitchCell default:@YES]];
        [a addObject:[self button:L(@"preview") action:@selector(bubbleDemo)]];

        // Kich thuoc: rieng iPhone / CarPlay (%), buoc 10
        [a addObject:[self group:L(@"size.phone") footer:nil]];
        [a addObject:[self sizeSlider:@"SizePhone"]];
        [a addObject:[self group:L(@"size.car") footer:L(@"size.footer")]];
        [a addObject:[self sizeSlider:@"SizeCar"]];
        [a addObject:[self button:L(@"reset") action:@selector(resetLayout)]];

        // Nguon toc do
        [a addObject:[self group:L(@"sources") footer:L(@"sources.footer")]];
        [a addObject:[self pref:@"Vietmap Live" key:@"AppVietmap" cell:PSSwitchCell default:@YES]];
        [a addObject:[self pref:@"GOFA" key:@"AppGOFA" cell:PSSwitchCell default:@YES]];

        // Thong tin
        [a addObject:[self group:nil footer:[NSString stringWithFormat:L(@"about"), [self version]]]];

        _specifiers = a;
    }
    return _specifiers;
}

// Doi ngon ngu -> dung lai toan bo cac o theo ngon ngu moi
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier
{
    [super setPreferenceValue:value specifier:specifier];
    if ([[specifier propertyForKey:@"key"] isEqualToString:@"Language"]) {
        CFPreferencesAppSynchronize((__bridge CFStringRef)SPP_DOMAIN);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self reloadSpecifiers];
            [self updateHeader];
        });
    }
}

// ---------------------------------------------------------------------
//  Dau trang: icon + ten + mo ta ngan
// ---------------------------------------------------------------------
- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"CSBubble";
    [self updateHeader];
}

- (void)updateHeader
{
    UITableView *table = self.table;
    if (!table) return;
    CGFloat w = table.bounds.size.width ?: [UIScreen mainScreen].bounds.size.width;
    UIView *h = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 168)];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"CSBubble" inBundle:[NSBundle bundleForClass:[self class]]
                                                compatibleWithTraitCollection:nil]];
    icon.frame = CGRectMake((w - 72) / 2, 18, 72, 72);
    icon.layer.cornerRadius = 16;
    icon.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [h addSubview:icon];

    UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(16, 98, w - 32, 30)];
    name.text = @"CSBubble";
    name.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
    name.textAlignment = NSTextAlignmentCenter;
    name.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [h addSubview:name];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(16, 130, w - 32, 20)];
    sub.text = L(@"tagline");
    sub.font = [UIFont systemFontOfSize:14];
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
    notify_post("csbubble.demo");
}

- (void)resetLayout
{
    notify_post("csbubble.resetlayout");
    // SpringBoard ghi lai kich thuoc 100 -> doc lai de thanh truot cap nhat
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize((__bridge CFStringRef)SPP_DOMAIN);
        [self reloadSpecifiers];
        [self updateHeader];
    });
}

@end
