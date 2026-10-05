#import <Preferences/PSListController.h>
#import <notify.h>

@interface SPPRootListController : PSListController
@end

@implementation SPPRootListController

- (NSArray *)specifiers
{
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// Gui Darwin notification sang SpringBoard
- (void)bubbleDemo
{
    notify_post("com.anlai97.speedpop.demo");
}

@end
