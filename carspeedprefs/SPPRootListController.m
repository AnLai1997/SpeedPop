#import "SPPRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <UIKit/UIKit.h>
#import <notify.h>

// Read by the tweak in src/SPPPrefs.mm; every stored row posts "carspeed.prefschanged" (Root.plist PostNotification).
#define kPrefsDomain CFSTR("carspeed")
// Darwin notifications handled by SpringBoard (src/hooks/SpringBoard.xm, names in src/common.h).
#define kSPPDemo     "carspeed.demo"
#define kSPPReset    "carspeed.resetlayout"
// Language choice, kept from CarSpeed 1.0: integer 0 = automatic (system), 1 = Vietnamese, 2 = English.
#define kLanguageKey CFSTR("Language")
// Enable switch key (Root.plist), read by the header status chip.
#define kEnabledKey CFSTR("Enabled")

// Set by the Makefile from ../control.
#ifndef TWEAK_VERSION
#define TWEAK_VERSION "?"
#endif

#pragma mark - Localization

// The app language is picked in the nav bar, so strings come from <lang>.lproj by hand
// instead of following the system language.
static NSDictionary<NSString *, NSString *> *sStrings;
static NSString *L(NSString *key);

// Menu order: automatic, Tiếng Việt, English.
static NSArray<NSNumber *> *SPPLanguageSettings(void) {
	return @[@0, @1, @2];
}

static NSString *SPPLanguageName(NSInteger setting) {
	if (setting == 1) return @"Tiếng Việt";
	if (setting == 2) return @"English";
	return L(@"LANGUAGE_AUTO");
}

static NSInteger SPPLanguageSetting(void) {
	id value = (__bridge_transfer id)CFPreferencesCopyAppValue(kLanguageKey, kPrefsDomain);
	NSInteger setting = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
	return (setting == 1 || setting == 2) ? setting : 0;
}

// The .lproj to load: the stored choice, or the system language when set to automatic.
static NSString *SPPLanguage(void) {
	NSInteger setting = SPPLanguageSetting();
	if (setting == 1) return @"vi";
	if (setting == 2) return @"en";
	return [[NSLocale preferredLanguages].firstObject hasPrefix:@"vi"] ? @"vi" : @"en";
}

static void SPPLoadStrings(void) {
	NSString *bundlePath = [NSBundle bundleForClass:NSClassFromString(@"SPPRootListController")].bundlePath;
	NSString *path = [bundlePath stringByAppendingFormat:@"/%@.lproj/Localizable.strings", SPPLanguage()];
	sStrings = [NSDictionary dictionaryWithContentsOfFile:path] ?: @{};
}

static NSString *L(NSString *key) {
	return sStrings[key] ?: key;
}

#pragma mark - HarmonyOS theme

static UIColor *SPPDynamicColor(UInt32 light, UInt32 dark) {
	UIColor *(^rgb)(UInt32) = ^(UInt32 v) {
		return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
	};
	UIColor *l = rgb(light), *d = rgb(dark);
	return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
		return traits.userInterfaceStyle == UIUserInterfaceStyleDark ? d : l;
	}];
}

static UIColor *SPPAccentColor(void)     { return SPPDynamicColor(0x0A59F7, 0x317AF7); }
static UIColor *SPPBackgroundColor(void) { return SPPDynamicColor(0xF1F3F5, 0x000000); }
static UIColor *SPPCardColor(void)       { return SPPDynamicColor(0xFFFFFF, 0x202224); }

static UIColor *SPPColorFromHex(NSString *hex) {
	unsigned int v = 0;
	[[NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&v];
	return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
}

// Row icon: a white SF Symbol on a rounded, softly lit color tile.
static UIImage *SPPIcon(NSString *symbol, UIColor *color) {
	UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold];
	UIImage *glyph = [[UIImage systemImageNamed:symbol withConfiguration:config] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
	if (!glyph) return nil;

	const CGFloat side = 29;
	UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(side, side)];
	return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
		CGRect rect = CGRectMake(0, 0, side, side);
		UIBezierPath *tile = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:8.5];
		[color setFill];
		[tile fill];

		[tile addClip];
		CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
		NSArray *colors = @[(id)[UIColor colorWithWhite:1 alpha:0.22].CGColor, (id)[UIColor colorWithWhite:1 alpha:0].CGColor];
		CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, NULL);
		CGContextDrawLinearGradient(ctx.CGContext, gradient, CGPointZero, CGPointMake(0, side), 0);
		CGGradientRelease(gradient);
		CGColorSpaceRelease(space);

		CGSize s = glyph.size;
		[glyph drawInRect:CGRectMake((side - s.width) / 2, (side - s.height) / 2, s.width, s.height)];
	}];
}

static BOOL SPPEnabled(void) {
	id value = (__bridge_transfer id)CFPreferencesCopyAppValue(kEnabledKey, kPrefsDomain);
	return value ? [value boolValue] : YES;
}

#pragma mark - Header card

// Blue gradient card: app icon on the left, name + tagline in white, and an On/Off chip
// (no version - that lives in the footer card).
@interface SPPHeaderCard : UIView
@property (nonatomic, strong) UIView *card, *clip, *glowLarge, *glowSmall, *chip, *dot;
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, strong) UIImageView *logo;
@property (nonatomic, strong) UILabel *nameLabel, *taglineLabel, *statusLabel;
- (void)updateWithTagline:(NSString *)tagline status:(NSString *)status enabled:(BOOL)enabled;
@end

@implementation SPPHeaderCard

- (instancetype)initWithFrame:(CGRect)frame {
	if (!(self = [super initWithFrame:frame])) return nil;
	self.preservesSuperviewLayoutMargins = YES;

	// card carries the shadow, clip rounds the content
	_card = [UIView new];
	_card.layer.cornerRadius = 24;
	_card.layer.cornerCurve = kCACornerCurveContinuous;
	_card.layer.shadowColor = [UIColor colorWithRed:0.04 green:0.27 blue:0.88 alpha:1].CGColor;
	_card.layer.shadowOpacity = 0.30;
	_card.layer.shadowRadius = 14;
	_card.layer.shadowOffset = CGSizeMake(0, 6);
	[self addSubview:_card];

	_clip = [UIView new];
	_clip.layer.cornerRadius = 24;
	_clip.layer.cornerCurve = kCACornerCurveContinuous;
	_clip.clipsToBounds = YES;
	[_card addSubview:_clip];

	_gradient = [CAGradientLayer layer];
	_gradient.colors = @[(id)[UIColor colorWithRed:0.36 green:0.71 blue:1.00 alpha:1].CGColor,
	                     (id)[UIColor colorWithRed:0.12 green:0.42 blue:1.00 alpha:1].CGColor,
	                     (id)[UIColor colorWithRed:0.04 green:0.27 blue:0.88 alpha:1].CGColor];
	_gradient.locations = @[@0, @0.55, @1];
	_gradient.startPoint = CGPointZero;
	_gradient.endPoint = CGPointMake(1, 1);
	[_clip.layer addSublayer:_gradient];

	// Two soft circles on the right (glass highlight)
	_glowLarge = [UIView new];
	_glowLarge.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
	[_clip addSubview:_glowLarge];
	_glowSmall = [UIView new];
	_glowSmall.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
	[_clip addSubview:_glowSmall];

	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	_logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"logo" inBundle:bundle compatibleWithTraitCollection:nil]];
	_logo.layer.shadowColor = UIColor.blackColor.CGColor;
	_logo.layer.shadowOpacity = 0.18;
	_logo.layer.shadowRadius = 8;
	_logo.layer.shadowOffset = CGSizeMake(0, 4);
	[_clip addSubview:_logo];

	_nameLabel = [UILabel new];
	_nameLabel.text = @"CarSpeed";
	_nameLabel.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
	_nameLabel.textColor = UIColor.whiteColor;
	[_clip addSubview:_nameLabel];

	_taglineLabel = [UILabel new];
	_taglineLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
	_taglineLabel.textColor = [UIColor colorWithWhite:1 alpha:0.85];
	_taglineLabel.numberOfLines = 2;
	[_clip addSubview:_taglineLabel];

	_chip = [UIView new];
	_chip.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
	_chip.layer.cornerRadius = 11;
	[_clip addSubview:_chip];

	_dot = [UIView new];
	_dot.layer.cornerRadius = 3.5;
	[_chip addSubview:_dot];

	_statusLabel = [UILabel new];
	_statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
	_statusLabel.textColor = UIColor.whiteColor;
	[_chip addSubview:_statusLabel];
	return self;
}

- (void)updateWithTagline:(NSString *)tagline status:(NSString *)status enabled:(BOOL)enabled {
	_taglineLabel.text = tagline;
	_statusLabel.text = status;
	_dot.backgroundColor = enabled ? [UIColor colorWithRed:0.45 green:0.95 blue:0.55 alpha:1]
	                               : [UIColor colorWithRed:1.00 green:0.55 blue:0.45 alpha:1];
	[self setNeedsLayout];
}

- (void)layoutSubviews {
	[super layoutSubviews];
	// Lines up with the inset-grouped rows below
	UIEdgeInsets m = self.layoutMargins;
	CGRect r = CGRectMake(m.left, 16, self.bounds.size.width - m.left - m.right, self.bounds.size.height - 32);
	_card.frame = r;
	_clip.frame = _card.bounds;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	_gradient.frame = _clip.bounds;
	[CATransaction commit];
	_card.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_card.bounds cornerRadius:24].CGPath;

	CGFloat W = r.size.width, H = r.size.height;
	_glowLarge.frame = CGRectMake(W - 120, -50, 170, 170);
	_glowLarge.layer.cornerRadius = 85;
	_glowSmall.frame = CGRectMake(W - 60, H - 70, 110, 110);
	_glowSmall.layer.cornerRadius = 55;

	const CGFloat side = 64;
	_logo.frame = CGRectMake(20, (H - side) / 2, side, side);
	CGFloat x = CGRectGetMaxX(_logo.frame) + 16, w = W - x - 16;
	// Name, tagline (1-2 lines) and chip as one block, centered vertically
	CGFloat taglineH = ceil([_taglineLabel sizeThatFits:CGSizeMake(w, CGFLOAT_MAX)].height);
	_nameLabel.frame = CGRectMake(x, (H - (32 + taglineH + 8 + 22)) / 2, w, 32);
	_taglineLabel.frame = CGRectMake(x, CGRectGetMaxY(_nameLabel.frame), w, taglineH);

	CGSize s = [_statusLabel sizeThatFits:CGSizeMake(w, 22)];
	_chip.frame = CGRectMake(x, CGRectGetMaxY(_taglineLabel.frame) + 8, s.width + 30, 22);
	_dot.frame = CGRectMake(10, 7.5, 7, 7);
	_statusLabel.frame = CGRectMake(22, 0, s.width, 22);
}

@end

@interface SPPRootListController ()
@property (nonatomic, strong) SPPHeaderCard *headerCard;
@end

@implementation SPPRootListController

#pragma mark - Specifiers

- (NSArray *)specifiers {
	if (!_specifiers) {
		SPPLoadStrings();
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
		[self localizeSpecifiers:_specifiers];
	}
	return _specifiers;
}

// Root.plist holds string keys; swap them for the chosen language and attach the row icons.
- (void)localizeSpecifiers:(NSArray<PSSpecifier *> *)specifiers {
	for (PSSpecifier *spec in specifiers) {
		if (spec.name.length) spec.name = L(spec.name);
		NSString *footer = [spec propertyForKey:@"footerText"];
		if (footer) [spec setProperty:L(footer) forKey:@"footerText"];

		// Lists filled at runtime (file names etc.) set "dynamicTitles" so they are left alone.
		if (spec.titleDictionary.count && ![[spec propertyForKey:@"dynamicTitles"] boolValue]) {
			NSMutableDictionary *titles = [NSMutableDictionary dictionary];
			[spec.titleDictionary enumerateKeysAndObjectsUsingBlock:^(id value, NSString *title, BOOL *stop) {
				titles[value] = L(title);
			}];
			spec.titleDictionary = titles;
		}

		NSString *symbol = [spec propertyForKey:@"symbol"];
		if (symbol) {
			UIImage *icon = SPPIcon(symbol, SPPColorFromHex([spec propertyForKey:@"symbolColor"] ?: @"#0A59F7"));
			if (icon) [spec setProperty:icon forKey:@"iconImage"];
		}
	}
}

#pragma mark - Appearance

- (void)viewDidLoad {
	[super viewDidLoad];
	// Scoped to this controller so the rest of Settings keeps its own look.
	[UISwitch appearanceWhenContainedInInstancesOfClasses:@[[self class]]].onTintColor = SPPAccentColor();
	[UISlider appearanceWhenContainedInInstancesOfClasses:@[[self class]]].minimumTrackTintColor = SPPAccentColor();
	[self applyLanguage];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	// SpringBoard writes SizePhone/SizeCar when the bubble is pinched, so re-read on every visit.
	CFPreferencesAppSynchronize(kPrefsDomain);
	[self reloadSpecifiers];
	[self updateHeaderStatus];
	self.table.backgroundColor = SPPBackgroundColor();
	self.table.tintColor = SPPAccentColor();
}

- (void)applyLanguage {
	SPPLoadStrings();
	self.title = @"CarSpeed";
	self.table.tableHeaderView = [self headerView];
	self.table.tableFooterView = [self footerView];
	self.navigationItem.rightBarButtonItem = [self languageButton];
}

- (UIBarButtonItem *)languageButton {
	NSInteger current = SPPLanguageSetting();
	NSMutableArray *actions = [NSMutableArray array];
	__weak typeof(self) weakSelf = self;
	for (NSNumber *value in SPPLanguageSettings()) {
		NSInteger setting = value.integerValue;
		UIAction *action = [UIAction actionWithTitle:SPPLanguageName(setting) image:nil identifier:nil handler:^(UIAction *a) {
			[weakSelf setLanguageSetting:setting];
		}];
		action.state = setting == current ? UIMenuElementStateOn : UIMenuElementStateOff;
		[actions addObject:action];
	}
	UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"globe"] style:UIBarButtonItemStylePlain target:nil action:nil];
	item.menu = [UIMenu menuWithTitle:L(@"LANGUAGE") children:actions];
	item.tintColor = SPPAccentColor();
	return item;
}

- (void)setLanguageSetting:(NSInteger)setting {
	if (setting == SPPLanguageSetting()) return;
	CFPreferencesSetAppValue(kLanguageKey, (__bridge CFPropertyListRef)@(setting), kPrefsDomain);
	CFPreferencesAppSynchronize(kPrefsDomain);
	[self applyLanguage];
	_specifiers = nil;
	[self reloadSpecifiers];
}

// A full-width table header/footer holding one rounded card: an image beside a column of text lines.
// The card follows the table's layout margins so it lines up with the inset-grouped rows.
- (UIView *)cardContainerWithHeight:(CGFloat)height insets:(UIEdgeInsets)insets image:(UIImage *)image side:(CGFloat)side imageOnRight:(BOOL)imageOnRight lines:(NSArray<UILabel *> *)lines {
	UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, height)];
	container.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	container.preservesSuperviewLayoutMargins = YES;

	UIView *card = [UIView new];
	card.backgroundColor = SPPCardColor();
	card.layer.cornerRadius = 20;
	card.layer.cornerCurve = kCACornerCurveContinuous;
	card.translatesAutoresizingMaskIntoConstraints = NO;
	[container addSubview:card];

	UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
	imageView.translatesAutoresizingMaskIntoConstraints = NO;

	UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:lines];
	text.axis = UILayoutConstraintAxisVertical;
	text.spacing = 3;

	UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:imageOnRight ? @[text, imageView] : @[imageView, text]];
	row.alignment = UIStackViewAlignmentCenter;
	row.spacing = 14;
	row.translatesAutoresizingMaskIntoConstraints = NO;
	[card addSubview:row];

	UILayoutGuide *margins = container.layoutMarginsGuide;
	[NSLayoutConstraint activateConstraints:@[
		[card.leadingAnchor constraintEqualToAnchor:margins.leadingAnchor],
		[card.trailingAnchor constraintEqualToAnchor:margins.trailingAnchor],
		[card.topAnchor constraintEqualToAnchor:container.topAnchor constant:insets.top],
		[card.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-insets.bottom],
		[imageView.widthAnchor constraintEqualToConstant:side],
		[imageView.heightAnchor constraintEqualToConstant:side],
		[row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
		imageOnRight ? [row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16]
		             : [row.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-16],
		[row.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
	]];
	return container;
}

- (UILabel *)labelWithText:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
	UILabel *label = [UILabel new];
	label.text = text;
	label.font = [UIFont systemFontOfSize:size weight:weight];
	label.textColor = color;
	label.numberOfLines = 0;
	return label;
}

// Top card (gradient, see SPPHeaderCard). The enable switch follows as the first row.
- (UIView *)headerView {
	if (!self.headerCard) {
		self.headerCard = [[SPPHeaderCard alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 150)];
		self.headerCard.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	}
	[self updateHeaderStatus];
	return self.headerCard;
}

- (void)updateHeaderStatus {
	[self updateHeaderStatusEnabled:SPPEnabled()];
}

- (void)updateHeaderStatusEnabled:(BOOL)enabled {
	[self.headerCard updateWithTagline:L(@"HEADER_TAGLINE") status:L(enabled ? @"STATUS_ON" : @"STATUS_OFF") enabled:enabled];
}

// The chip follows the enable switch right away (uses the new value, not a possibly stale prefs read).
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
	[super setPreferenceValue:value specifier:specifier];
	if ([[specifier propertyForKey:@"key"] isEqualToString:(__bridge NSString *)kEnabledKey]) [self updateHeaderStatusEnabled:[value boolValue]];
}

// Bottom card: author logo, app name, version and copyright.
- (UIView *)footerView {
	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	UIImage *avatar = [UIImage imageNamed:@"avatar" inBundle:bundle compatibleWithTraitCollection:nil];
	return [self cardContainerWithHeight:136 insets:UIEdgeInsetsMake(8, 0, 32, 0) image:avatar side:56 imageOnRight:NO lines:@[
		[self labelWithText:@"CarSpeed" size:16 weight:UIFontWeightSemibold color:[UIColor labelColor]],
		[self labelWithText:[NSString stringWithFormat:L(@"VERSION_FORMAT"), @TWEAK_VERSION] size:13 weight:UIFontWeightRegular color:[UIColor secondaryLabelColor]],
		[self labelWithText:L(@"COPYRIGHT") size:13 weight:UIFontWeightRegular color:[UIColor secondaryLabelColor]],
	]];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
	cell.backgroundColor = SPPCardColor();
	cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];

	// Action rows read as regular navigation rows; only destructive ones stay red.
	PSSpecifier *spec = [cell isKindOfClass:[PSTableCell class]] ? ((PSTableCell *)cell).specifier : nil;
	if (spec.cellType == PSButtonCell) {
		BOOL destructive = [[spec propertyForKey:@"isDestructive"] boolValue];
		cell.textLabel.textColor = destructive ? [UIColor systemRedColor] : [UIColor labelColor];
		cell.accessoryType = destructive ? UITableViewCellAccessoryNone : UITableViewCellAccessoryDisclosureIndicator;
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
	if ([PSListController instancesRespondToSelector:_cmd]) [super tableView:tableView willDisplayHeaderView:view forSection:section];
	if (![view isKindOfClass:[UITableViewHeaderFooterView class]]) return;
	UILabel *label = ((UITableViewHeaderFooterView *)view).textLabel;
	label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
	label.textColor = [UIColor secondaryLabelColor];
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
	if ([PSListController instancesRespondToSelector:_cmd]) [super tableView:tableView willDisplayFooterView:view forSection:section];
	if (![view isKindOfClass:[UITableViewHeaderFooterView class]]) return;
	UILabel *label = ((UITableViewHeaderFooterView *)view).textLabel;
	label.font = [UIFont systemFontOfSize:12];
	label.textColor = [UIColor secondaryLabelColor];
}

#pragma mark - Helpers for actions

- (void)showMessage:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CarSpeed" message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:L(@"OK") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions
// Darwin notifications handled by SpringBoard (src/hooks/SpringBoard.xm).

// Show the bubble for 10 seconds.
- (void)bubbleDemo {
	notify_post(kSPPDemo);
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
}

// Default position, 100% size. SpringBoard writes SizePhone/SizeCar back to 100, so re-read the sliders.
- (void)resetLayout {
	notify_post(kSPPReset);
	[[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		CFPreferencesAppSynchronize(kPrefsDomain);
		[weakSelf reloadSpecifiers];
	});
}

@end
