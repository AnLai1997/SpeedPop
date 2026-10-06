// Trang cai dat CarSpeed kieu HarmonyOS (rootless).
// Cai dat chi do SpringBoard doc (khong bi sandbox) qua cfprefsd, nen ghi thang vao domain carspeed
// roi bao carspeed.prefschanged; khong can truyen bitmask qua notify state.
#import "SPPRootListController.h"
#import <notify.h>
#import <objc/message.h>

#define kSPPSuite        CFSTR("carspeed")
#define kSPPPrefsChanged "carspeed.prefschanged"
#define kSPPDemo         "carspeed.demo"
#define kSPPReset        "carspeed.resetlayout"
#define kSPPLanguage     CFSTR("Language")   // 0 tu dong (theo may), 1 Tieng Viet, 2 English
#define kSPPName         @"CarSpeed"

#ifndef SPP_VERSION
#define SPP_VERSION "?"
#endif

// Kich thuoc bong bong (%): 100 = mac dinh, buoc 10 (giong SPPPrefs)
#define kSPPSizeMin  60
#define kSPPSizeMax  220
#define kSPPSizeStep 10
#define kSPPStyleCount 18

#pragma mark - Khai bao cac dong

// Moi nhom: tieu de, chu thich duoi the va cac dong.
// type: switch / menu (chon 1 trong count gia tri) / slider (kich thuoc %) / action (nut, goi selector)
// key: khoa trong domain carspeed (action: khoa chuoi); icon: SF Symbol; color: mau nen icon (hex).
static NSArray<NSDictionary *> *SPPSections(void)
{
    return @[
        @{@"title": @"general", @"footer": @"general.footer", @"items": @[
            @{@"type": @"switch", @"key": @"Enabled", @"default": @YES, @"icon": @"power", @"color": @0x0A59F7},
        ]},
        @{@"title": @"appearance", @"footer": @"appearance.footer", @"items": @[
            @{@"type": @"menu", @"key": @"Style", @"default": @0, @"count": @kSPPStyleCount, @"icon": @"paintpalette.fill", @"color": @0x8A3FFC},
            @{@"type": @"switch", @"key": @"ShowAppIcon", @"default": @YES, @"icon": @"app.badge.fill", @"color": @0xFF7500},
            @{@"type": @"action", @"key": @"preview", @"action": @"bubbleDemo", @"icon": @"play.fill", @"color": @0x41BA41},
        ]},
        @{@"title": @"size", @"footer": @"size.footer", @"items": @[
            @{@"type": @"slider", @"key": @"SizePhone", @"default": @100, @"icon": @"iphone", @"color": @0x0A59F7},
            @{@"type": @"slider", @"key": @"SizeCar", @"default": @100, @"icon": @"car.fill", @"color": @0x00A6C7},
            @{@"type": @"action", @"key": @"reset", @"action": @"resetLayout", @"icon": @"arrow.counterclockwise", @"color": @0xF7365D},
        ]},
        @{@"title": @"sources", @"footer": @"sources.footer", @"items": @[
            @{@"type": @"switch", @"key": @"AppVietmap", @"default": @YES, @"icon": @"map.fill", @"color": @0x41BA41},
            @{@"type": @"switch", @"key": @"AppGOFA", @"default": @YES, @"icon": @"location.fill", @"color": @0xFF7500},
        ]},
    ];
}

static id SPPPrefValue(CFStringRef key)
{
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, kSPPSuite);
    return value ? (__bridge_transfer id)value : nil;
}

static NSNumber *SPPPrefNumber(NSDictionary *item)
{
    id obj = SPPPrefValue((__bridge CFStringRef)item[@"key"]);
    return [obj isKindOfClass:[NSNumber class]] ? obj : item[@"default"];
}

// Ghi 1 gia tri roi bao SpringBoard ve lai bong bong
static void SPPSetPref(NSString *key, id value)
{
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kSPPSuite);
    CFPreferencesAppSynchronize(kSPPSuite);
    notify_post(kSPPPrefsChanged);
}

#pragma mark - Ngon ngu

static NSInteger SPPLanguageSetting(void)
{
    id v = SPPPrefValue(kSPPLanguage);
    return [v respondsToSelector:@selector(integerValue)] ? [v integerValue] : 0;
}

static BOOL SPPUseVietnamese(void)
{
    NSInteger lang = SPPLanguageSetting();
    if (lang == 1) return YES;
    if (lang == 2) return NO;
    return [[[NSLocale preferredLanguages] firstObject] hasPrefix:@"vi"];
}

// Moi dong can "<key>" va "<key>.info" (slider khong can .info); moi nhom can tieu de va footer
static NSString *SPPText(NSString *key)
{
    static NSDictionary<NSString *, NSArray<NSString *> *> *t;   // key -> @[tieng Viet, English]
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        t = @{
            @"tagline":           @[@"Tốc độ & biển giới hạn từ app dẫn đường", @"Speed & speed limit from your navigation app"],
            @"language":          @[@"Ngôn ngữ", @"Language"],
            @"lang.auto":         @[@"Tự động (theo máy)", @"Automatic (system)"],

            @"general":           @[@"Chung", @"General"],
            @"general.footer":    @[@"Bong bóng hiện khi app dẫn đường chạy nền và tự ẩn khi app được mở lại. Khi kết nối CarPlay, bong bóng chỉ hiện trên màn hình xe; không có xe thì hiện trên iPhone.",
                                    @"The bubble appears while a navigation app runs in the background and hides when the app is opened again. With CarPlay connected it shows only on the car screen; otherwise on the iPhone."],
            @"Enabled":           @[@"Bong bóng tốc độ", @"Speed bubble"],
            @"Enabled.info":      @[@"Hiện tốc độ hiện tại và biển giới hạn.", @"Show current speed and the speed limit."],

            @"appearance":        @[@"Giao diện", @"Appearance"],
            @"appearance.footer": @[@"Kéo để di chuyển · chụm 2 ngón để đổi cỡ · chạm để mở lại app · giữ 2 giây (viền đỏ chạy hết vòng) để thoát hẳn app.",
                                    @"Drag to move · pinch to resize · tap to reopen the app · hold for 2 seconds (until the red ring completes) to quit the app."],
            @"Style":             @[@"Kiểu hiển thị", @"Style"],
            @"Style.info":        @[@"Chọn 1 trong 18 kiểu bong bóng.", @"Pick one of 18 bubble styles."],
            @"ShowAppIcon":       @[@"Hiện icon app", @"Show app icon"],
            @"ShowAppIcon.info":  @[@"Cho biết tốc độ đang lấy từ app nào.", @"Shows which app the speed comes from."],
            @"preview":           @[@"Xem thử", @"Preview"],
            @"preview.info":      @[@"Hiện bong bóng trong 10 giây.", @"Show the bubble for 10 seconds."],

            @"size":              @[@"Kích thước", @"Size"],
            @"size.footer":       @[@"100% = cỡ mặc định (60 – 220%). Chụm 2 ngón trên bong bóng cũng đổi cỡ của màn đang dùng và cập nhật ở đây.",
                                    @"100% = default size (60 – 220%). Pinching the bubble also resizes it on the current screen and updates this value."],
            @"SizePhone":         @[@"Trên iPhone", @"On iPhone"],
            @"SizeCar":           @[@"Trên CarPlay", @"On CarPlay"],
            @"reset":             @[@"Đặt lại vị trí & kích thước", @"Reset position & size"],
            @"reset.info":        @[@"Đưa bong bóng về chỗ cũ, cỡ 100%.", @"Move the bubble back to default, 100% size."],

            @"sources":           @[@"Nguồn tốc độ", @"Speed sources"],
            @"sources.footer":    @[@"Chạy cả hai app: bong bóng theo app đang chạy nền. Lần đầu cài, mở lại app dẫn đường để tweak được nạp.",
                                    @"With both apps running, the bubble follows the one in the background. After the first install, relaunch the navigation app so the tweak loads."],
            @"AppVietmap":        @[@"Vietmap Live", @"Vietmap Live"],
            @"AppVietmap.info":   @[@"Nhận tốc độ và biển giới hạn từ Vietmap Live.", @"Take speed and limits from Vietmap Live."],
            @"AppGOFA":           @[@"GOFA", @"GOFA"],
            @"AppGOFA.info":      @[@"Nhận tốc độ và biển giới hạn từ GOFA.", @"Take speed and limits from GOFA."],

            @"Style.0":           @[@"Thẻ ngang", @"Card"],
            @"Style.1":           @[@"Đĩa nhỏ", @"Mini disc"],
            @"Style.2":           @[@"Biển báo lớn", @"Big sign"],
            @"Style.3":           @[@"Đồng hồ", @"Gauge"],
            @"Style.4":           @[@"Thanh HUD", @"HUD bar"],
            @"Style.5":           @[@"Màu theo tốc độ", @"Speed color"],
            @"Style.6":           @[@"Cột dọc", @"Tower"],
            @"Style.7":           @[@"Viên thuốc đôi", @"Split pill"],
            @"Style.8":           @[@"Neon", @"Neon"],
            @"Style.9":           @[@"Thanh đo", @"Meter bar"],
            @"Style.10":          @[@"Chữ nổi (không nền)", @"Floating text"],
            @"Style.11":          @[@"Thẻ sáng", @"Light card"],
            @"Style.12":          @[@"Vô lăng", @"Steering wheel"],
            @"Style.13":          @[@"Bánh xe (mâm quay)", @"Wheel (spinning rim)"],
            @"Style.14":          @[@"Thẻ HarmonyOS", @"HarmonyOS card"],
            @"Style.15":          @[@"Đồng hồ kim", @"Analog speedometer"],
            @"Style.16":          @[@"Vòng kép HarmonyOS", @"HarmonyOS rings"],
            @"Style.17":          @[@"Live View", @"Live View capsule"],

            @"about":             @[@"Phiên bản %@ · anlai\nLog: /var/mobile/Documents/CarSpeed.log",
                                    @"Version %@ · anlai\nLog: /var/mobile/Documents/CarSpeed.log"],
        };
    });
    NSArray<NSString *> *pair = t[key];
    if (!pair) return key;
    return SPPUseVietnamese() ? pair[0] : pair[1];
}

#pragma mark - Mau va icon kieu HarmonyOS

static UIColor *SPPHex(uint32_t hex)
{
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0 green:((hex >> 8) & 0xFF) / 255.0 blue:(hex & 0xFF) / 255.0 alpha:1];
}

static UIColor *SPPDynamic(uint32_t light, uint32_t dark)
{
    UIColor *l = SPPHex(light), *d = SPPHex(dark);
    return [UIColor colorWithDynamicProvider:^(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark ? d : l;
    }];
}

// Nen xam nhat, the trang, mau nhan xanh HarmonyOS
#define kSPPBackground SPPDynamic(0xF1F3F5, 0x000000)
#define kSPPCard       SPPDynamic(0xFFFFFF, 0x202224)
#define kSPPPrimary    SPPDynamic(0x182431, 0xE5E5E5)
#define kSPPSecondary  SPPDynamic(0x7A8086, 0x8C9196)
#define kSPPDivider    SPPDynamic(0xE3E5E8, 0x323436)
#define kSPPAccent     SPPDynamic(0x0A59F7, 0x317AF7)

// O vuong bo goc mau, SF Symbol trang o giua
static UIImage *SPPIcon(NSString *symbol, UIColor *color)
{
    CGRect rect = CGRectMake(0, 0, 32, 32);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:rect.size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:9] fill];
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightMedium];
        UIImage *glyph = [[UIImage systemImageNamed:symbol withConfiguration:config] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize size = glyph.size;
        [glyph drawInRect:CGRectMake((rect.size.width - size.width) / 2, (rect.size.height - size.height) / 2, size.width, size.height)];
    }];
}

static UILabel *SPPLabel(NSString *text, CGFloat size, UIFontWeight weight, UIColor *color)
{
    UILabel *l = [UILabel new];
    l.text = text;
    l.font = [UIFont systemFontOfSize:size weight:weight];
    l.textColor = color;
    l.numberOfLines = 0;
    return l;
}

#pragma mark - Dong trong the

@interface SPPRootListController ()
- (void)rebuildAnimated;
@end

// Mot dong: icon, ten, mo ta va phan ben phai tuy loai.
// switch / action: cham ca dong la bat-tat / bam nut; menu: ca dong mo UIMenu; slider: keo thanh truot.
@interface SPPRow : UIControl
@property (nonatomic, copy) NSDictionary *item;
@property (nonatomic, weak) SPPRootListController *target;
@property (nonatomic, strong) UISwitch *toggle;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, assign) NSInteger lastSize;
@end

@implementation SPPRow

- (instancetype)initWithItem:(NSDictionary *)item target:(SPPRootListController *)target
{
    if ((self = [super initWithFrame:CGRectZero])) {
        _item = item;
        _target = target;
        NSString *key = item[@"key"];
        NSString *type = item[@"type"];

        UIImageView *icon = [[UIImageView alloc] initWithImage:SPPIcon(item[@"icon"], SPPHex([item[@"color"] unsignedIntValue]))];
        [icon setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

        UILabel *title = SPPLabel(SPPText(key), 16, UIFontWeightMedium, kSPPPrimary);
        UIStackView *texts = [UIStackView new];
        texts.axis = UILayoutConstraintAxisVertical;
        texts.spacing = 2;

        UIView *accessory = nil;
        if ([type isEqualToString:@"slider"]) {
            // Ten va gia tri tren cung 1 dong, thanh truot ben duoi
            _valueLabel = SPPLabel(nil, 15, UIFontWeightMedium, kSPPAccent);
            _valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium];
            [_valueLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[title, _valueLabel]];
            top.spacing = 8;

            _slider = [UISlider new];
            _slider.minimumValue = kSPPSizeMin;
            _slider.maximumValue = kSPPSizeMax;
            _slider.minimumTrackTintColor = kSPPAccent;
            [_slider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
            [texts addArrangedSubview:top];
            [texts addArrangedSubview:_slider];
            texts.spacing = 6;
            [self setSize:[SPPPrefNumber(item) integerValue]];
        } else {
            [texts addArrangedSubview:title];
            UILabel *info = SPPLabel(SPPText([key stringByAppendingString:@".info"]), 13, UIFontWeightRegular, kSPPSecondary);
            [texts addArrangedSubview:info];
            self.accessibilityLabel = title.text;
            self.accessibilityHint = info.text;
        }

        if ([type isEqualToString:@"switch"]) {
            _toggle = [UISwitch new];
            _toggle.onTintColor = kSPPAccent;
            _toggle.on = [SPPPrefNumber(item) boolValue];
            [_toggle addTarget:self action:@selector(toggleChanged) forControlEvents:UIControlEventValueChanged];
            accessory = _toggle;
        } else if ([type isEqualToString:@"menu"]) {
            UILabel *value = SPPLabel(SPPText([NSString stringWithFormat:@"%@.%ld", key, (long)[self menuValue]]), 14, UIFontWeightRegular, kSPPSecondary);
            value.numberOfLines = 1;
            value.textAlignment = NSTextAlignmentRight;
            UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.up.chevron.down"
                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightMedium]]];
            chevron.tintColor = kSPPSecondary;
            [chevron setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            UIStackView *box = [[UIStackView alloc] initWithArrangedSubviews:@[value, chevron]];
            box.alignment = UIStackViewAlignmentCenter;
            box.spacing = 6;
            [value.widthAnchor constraintLessThanOrEqualToConstant:140].active = YES;
            accessory = box;
        } else if ([type isEqualToString:@"action"]) {
            UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"
                withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightMedium]]];
            chevron.tintColor = kSPPSecondary;
            accessory = chevron;
        }

        NSMutableArray *parts = [NSMutableArray arrayWithObjects:icon, texts, nil];
        if (accessory) {
            [accessory setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [accessory setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
            [parts addObject:accessory];
        }
        UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:parts];
        row.alignment = UIStackViewAlignmentCenter;
        row.spacing = 12;
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.userInteractionEnabled = (_slider || _toggle);   // dong khac: de UIControl nhan cham
        [self addSubview:row];
        [NSLayoutConstraint activateConstraints:@[
            [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
            [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14],
            [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
            [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        ]];

        if ([type isEqualToString:@"menu"]) {
            // Nut trong suot phu ca dong de cham dau cung mo menu
            UIButton *cover = [UIButton buttonWithType:UIButtonTypeCustom];
            cover.menu = [self styleMenu];
            cover.showsMenuAsPrimaryAction = YES;
            cover.accessibilityLabel = title.text;
            cover.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:cover];
            [NSLayoutConstraint activateConstraints:@[
                [cover.topAnchor constraintEqualToAnchor:self.topAnchor],
                [cover.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
                [cover.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
                [cover.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            ]];
        } else if (!_slider) {
            [self addTarget:self action:@selector(rowTapped) forControlEvents:UIControlEventTouchUpInside];
        }
    }
    return self;
}

// Cham vao cong tac thi de cong tac xu ly, cham cho khac trong dong thi dong nhan
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    if (!self.toggle) return [super hitTest:point withEvent:event];
    if (![self pointInside:point withEvent:event]) return nil;
    CGPoint inToggle = [self convertPoint:point toView:self.toggle];
    if ([self.toggle pointInside:inToggle withEvent:event]) return self.toggle;
    return self;
}

- (void)setHighlighted:(BOOL)highlighted
{
    [super setHighlighted:highlighted];
    [UIView animateWithDuration:0.15 animations:^{
        self.backgroundColor = highlighted ? [kSPPPrimary colorWithAlphaComponent:0.05] : UIColor.clearColor;
    }];
}

- (void)rowTapped
{
    if (self.toggle) {
        [self.toggle setOn:!self.toggle.on animated:YES];
        [self toggleChanged];
        return;
    }
    // action: goi selector cua controller (khong tra ve gia tri)
    SEL sel = NSSelectorFromString(self.item[@"action"]);
    if ([self.target respondsToSelector:sel]) ((void (*)(id, SEL))objc_msgSend)(self.target, sel);
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

- (void)toggleChanged
{
    SPPSetPref(self.item[@"key"], @(self.toggle.on));
    [[UISelectionFeedbackGenerator new] selectionChanged];
}

#pragma mark menu

- (NSInteger)menuValue
{
    NSInteger v = [SPPPrefNumber(self.item) integerValue];
    return (v >= 0 && v < [self.item[@"count"] integerValue]) ? v : [self.item[@"default"] integerValue];
}

- (UIMenu *)styleMenu
{
    NSString *key = self.item[@"key"];
    NSInteger current = [self menuValue];
    NSMutableArray *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSInteger i = 0; i < [self.item[@"count"] integerValue]; i++) {
        UIAction *action = [UIAction actionWithTitle:SPPText([NSString stringWithFormat:@"%@.%ld", key, (long)i]) image:nil identifier:nil
                                             handler:^(UIAction *a) { [weakSelf menuPicked:i]; }];
        action.state = (i == current) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }
    return [UIMenu menuWithTitle:SPPText(key) children:actions];
}

- (void)menuPicked:(NSInteger)value
{
    SPPSetPref(self.item[@"key"], @(value));
    [[UISelectionFeedbackGenerator new] selectionChanged];
    // Dung lai trang de dong nay hien gia tri moi
    [self.target rebuildAnimated];
}

#pragma mark slider

- (void)setSize:(NSInteger)size
{
    size = MIN(kSPPSizeMax, MAX(kSPPSizeMin, size));
    self.lastSize = size;
    self.slider.value = size;
    self.valueLabel.text = [NSString stringWithFormat:@"%ld%%", (long)size];
    self.slider.accessibilityLabel = SPPText(self.item[@"key"]);
}

// Nhay theo buoc 10; moi buoc ghi ngay de bong bong doi co truc tiep
- (void)sliderChanged
{
    NSInteger size = lround(self.slider.value / kSPPSizeStep) * kSPPSizeStep;
    self.slider.value = size;
    if (size == self.lastSize) return;
    [self setSize:size];
    SPPSetPref(self.item[@"key"], @(size));
    [[UISelectionFeedbackGenerator new] selectionChanged];
}

@end

#pragma mark - Man hinh chinh

@implementation SPPRootListController {
    UIScrollView *_scroll;
    UIStackView *_content;
    UILabel *_largeTitle;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = kSPPBackground;
    _scroll = [UIScrollView new];
    _scroll.alwaysBounceVertical = YES;
    _scroll.delegate = self;
    _scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_scroll];

    _content = [UIStackView new];
    _content.axis = UILayoutConstraintAxisVertical;
    _content.translatesAutoresizingMaskIntoConstraints = NO;
    [_scroll addSubview:_content];

    [NSLayoutConstraint activateConstraints:@[
        [_scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_content.topAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.topAnchor constant:4],
        [_content.bottomAnchor constraintEqualToAnchor:_scroll.contentLayoutGuide.bottomAnchor constant:-24],
        [_content.leadingAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.leadingAnchor constant:16],
        [_content.trailingAnchor constraintEqualToAnchor:_scroll.frameLayoutGuide.trailingAnchor constant:-16],
    ]];
}

// SpringBoard ghi lai kich thuoc khi chum 2 ngon -> moi lan mo trang doc lai
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    CFPreferencesAppSynchronize(kSPPSuite);
    [self rebuild];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self updateNavigationTitle];
}

// Dung lai toan bo noi dung theo cai dat va ngon ngu hien tai
- (void)rebuild
{
    for (UIView *view in _content.arrangedSubviews) [view removeFromSuperview];

    [_content addArrangedSubview:[self makeHeader]];
    [_content setCustomSpacing:28 afterView:_content.arrangedSubviews.lastObject];

    for (NSDictionary *section in SPPSections()) [self addSection:section];

    UILabel *about = SPPLabel([NSString stringWithFormat:SPPText(@"about"), @SPP_VERSION], 12, UIFontWeightRegular, kSPPSecondary);
    about.textAlignment = NSTextAlignmentCenter;
    [_content addArrangedSubview:about];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:[self languageButton]];
}

- (void)rebuildAnimated
{
    [UIView transitionWithView:_content duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        [self rebuild];
    } completion:nil];
}

// Tieu de lon can trai kem dong gioi thieu, icon tweak ben phai
- (UIView *)makeHeader
{
    _largeTitle = SPPLabel(kSPPName, 30, UIFontWeightBold, kSPPPrimary);
    _largeTitle.numberOfLines = 1;
    UILabel *tagline = SPPLabel(SPPText(@"tagline"), 14, UIFontWeightRegular, kSPPSecondary);

    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[_largeTitle, tagline]];
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 4;

    // CarSpeed.png 256px cho net, cung la icon cua goi trong Sileo
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"CarSpeed" inBundle:[NSBundle bundleForClass:self.class] compatibleWithTraitCollection:nil]];
    icon.contentMode = UIViewContentModeScaleAspectFill;
    icon.layer.cornerRadius = 14;
    icon.layer.cornerCurve = kCACornerCurveContinuous;
    icon.clipsToBounds = YES;
    [icon.widthAnchor constraintEqualToConstant:56].active = YES;
    [icon.heightAnchor constraintEqualToConstant:56].active = YES;

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[texts, icon]];
    header.alignment = UIStackViewAlignmentCenter;
    header.spacing = 16;
    header.layoutMarginsRelativeArrangement = YES;
    header.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 8, 0, 4);
    return header;
}

// Tieu de nho mau xam, cac dong nam chung mot the bo goc lon, chu thich ben duoi the
- (void)addSection:(NSDictionary *)section
{
    UIStackView *titleWrap = [self indented:SPPLabel(SPPText(section[@"title"]), 14, UIFontWeightMedium, kSPPSecondary)];
    [_content addArrangedSubview:titleWrap];
    [_content setCustomSpacing:8 afterView:titleWrap];

    UIStackView *rows = [UIStackView new];
    rows.axis = UILayoutConstraintAxisVertical;
    for (NSDictionary *item in section[@"items"]) {
        if (rows.arrangedSubviews.count) {
            // Duong ngan cach bat dau tu cot chu, khong cham icon
            UIView *line = [UIView new];
            line.backgroundColor = kSPPDivider;
            line.translatesAutoresizingMaskIntoConstraints = NO;
            UIView *divider = [UIView new];
            [divider addSubview:line];
            [NSLayoutConstraint activateConstraints:@[
                [divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale],
                [line.topAnchor constraintEqualToAnchor:divider.topAnchor],
                [line.bottomAnchor constraintEqualToAnchor:divider.bottomAnchor],
                [line.leadingAnchor constraintEqualToAnchor:divider.leadingAnchor constant:56],
                [line.trailingAnchor constraintEqualToAnchor:divider.trailingAnchor constant:-12],
            ]];
            [rows addArrangedSubview:divider];
        }
        [rows addArrangedSubview:[[SPPRow alloc] initWithItem:item target:self]];
    }

    UIView *card = [UIView new];
    card.backgroundColor = kSPPCard;
    card.layer.cornerRadius = 20;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    rows.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:rows];
    [NSLayoutConstraint activateConstraints:@[
        [rows.topAnchor constraintEqualToAnchor:card.topAnchor constant:4],
        [rows.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-4],
        [rows.leadingAnchor constraintEqualToAnchor:card.leadingAnchor],
        [rows.trailingAnchor constraintEqualToAnchor:card.trailingAnchor],
    ]];
    [_content addArrangedSubview:card];

    UIView *last = card;
    if (section[@"footer"]) {
        [_content setCustomSpacing:8 afterView:card];
        last = [self indented:SPPLabel(SPPText(section[@"footer"]), 13, UIFontWeightRegular, kSPPSecondary)];
        [_content addArrangedSubview:last];
    }
    [_content setCustomSpacing:24 afterView:last];
}

// Thut 12 so voi mep the
- (UIStackView *)indented:(UIView *)view
{
    UIStackView *wrap = [[UIStackView alloc] initWithArrangedSubviews:@[view]];
    wrap.layoutMarginsRelativeArrangement = YES;
    wrap.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 12, 0, 12);
    return wrap;
}

// Nut vien thuoc o goc phai: qua dia cau + ma ngon ngu dang dung, cham de hien menu chon
- (UIButton *)languageButton
{
    NSInteger current = SPPLanguageSetting();
    NSArray *values = @[@0, @2, @1];
    NSArray *names = @[SPPText(@"lang.auto"), @"English", @"Tiếng Việt"];
    NSMutableArray *actions = [NSMutableArray array];
    __weak typeof(self) weakSelf = self;
    for (NSUInteger i = 0; i < values.count; i++) {
        NSInteger value = [values[i] integerValue];
        UIAction *action = [UIAction actionWithTitle:names[i] image:nil identifier:nil handler:^(UIAction *a) {
            [weakSelf setLanguage:value];
        }];
        action.state = (value == current) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:action];
    }

    UIButtonConfiguration *config = [UIButtonConfiguration filledButtonConfiguration];
    config.baseBackgroundColor = [kSPPPrimary colorWithAlphaComponent:0.06];
    config.baseForegroundColor = kSPPPrimary;
    config.image = [UIImage systemImageNamed:@"globe" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightMedium]];
    config.imagePadding = 5;
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.contentInsets = NSDirectionalEdgeInsetsMake(6, 11, 6, 12);
    config.attributedTitle = [[NSAttributedString alloc] initWithString:(SPPUseVietnamese() ? @"VI" : @"EN")
        attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]}];

    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.menu = [UIMenu menuWithTitle:SPPText(@"language") children:actions];
    button.showsMenuAsPrimaryAction = YES;
    button.accessibilityLabel = SPPText(@"language");
    return button;
}

- (void)setLanguage:(NSInteger)value
{
    if (value == SPPLanguageSetting()) return;
    CFPreferencesSetAppValue(kSPPLanguage, (__bridge CFPropertyListRef)@(value), kSPPSuite);
    CFPreferencesAppSynchronize(kSPPSuite);
    [self rebuildAnimated];
}

// Nhu HarmonyOS: ten chi hien tren thanh dieu huong khi tieu de lon da cuon khuat
- (void)updateNavigationTitle
{
    if (!_largeTitle) return;
    CGRect frame = [_largeTitle convertRect:_largeTitle.bounds toView:_scroll];
    BOOL largeVisible = CGRectIsEmpty(frame) || _scroll.contentOffset.y + _scroll.adjustedContentInset.top < CGRectGetMaxY(frame);
    NSString *title = largeVisible ? @"" : kSPPName;
    if (![self.navigationItem.title isEqualToString:title]) self.navigationItem.title = title;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    [self updateNavigationTitle];
}

#pragma mark - Nut: gui Darwin notification sang SpringBoard

- (void)bubbleDemo
{
    notify_post(kSPPDemo);
}

- (void)resetLayout
{
    notify_post(kSPPReset);
    // SpringBoard ghi lai kich thuoc 100 -> doc lai de thanh truot cap nhat
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize(kSPPSuite);
        [self rebuildAnimated];
    });
}

@end
