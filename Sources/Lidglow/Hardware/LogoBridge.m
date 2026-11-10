#import "LogoBridge.h"
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <math.h>

@protocol BrightnessService
- (id)copyPropertyForKey:(NSString *)key;
- (BOOL)setProperty:(id)value forKey:(NSString *)key;
- (BOOL)setProperty:(id)value withKey:(NSString *)key keyboardID:(uint64_t)keyboardID;
- (NSArray<NSNumber *> *)copyKeyboardBacklightIDs;
@end

@implementation LogoBridge {
    NSObject<BrightnessService> *_client;
    NSArray<NSNumber *> *_keyboards;
}
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("bklb-backlight"));
    if (!service) return self;
    IOObjectRelease(service);
    _hardwarePresent = YES;

    dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY | RTLD_LOCAL);
    NSObject<BrightnessService> *client = [[NSClassFromString(@"BrightnessSystemClient") alloc] init];
    NSObject<BrightnessService> *keyboard = [[NSClassFromString(@"KeyboardBrightnessClient") alloc] init];
    if ([client respondsToSelector:@selector(copyPropertyForKey:)] &&
        [client respondsToSelector:@selector(setProperty:forKey:)] &&
        [client respondsToSelector:@selector(setProperty:withKey:keyboardID:)] &&
        [keyboard respondsToSelector:@selector(copyKeyboardBacklightIDs)]) {
        _client = client;
        _keyboards = [keyboard copyKeyboardBacklightIDs];
    }
    return self;
}
- (NSInteger)mode {
    NSNumber *value = [_client copyPropertyForKey:@"LEBacklightMode"];
    return [value isKindOfClass:NSNumber.class] ? value.integerValue : -1;
}
- (double)level {
    NSDictionary *state = [_client copyPropertyForKey:@"LEPWMState"];
    NSNumber *factor = [state isKindOfClass:NSDictionary.class] ? state[@"Factor"] : nil;
    return [factor isKindOfClass:NSNumber.class] ? factor.doubleValue : NAN;
}
- (BOOL)lidClosed {
    return [[_client copyPropertyForKey:@"CBClamshellState"] boolValue];
}
- (BOOL)enableLogo:(BOOL)enabled {
    return [_client setProperty:@(enabled ? 2 : 0) forKey:@"LEBacklightMode"];
}
- (BOOL)fadeTowardLight:(BOOL)lit duration:(double)duration displayAwake:(BOOL)awake {
    // CoreBrightness applies the duration to the next transition. Restore its default immediately.
    if (!_keyboards.count || ![_client setProperty:@(duration) forKey:@"LEPWMFactorFadeDuration"]) return NO;
    BOOL sent = [_client setProperty:@(lit ? 2 : 1) forKey:@"DisplayLogicalState"];
    if (!lit && awake) {
        for (NSNumber *keyboard in _keyboards) {
            [_client setProperty:@2 withKey:@"DisplayLogicalState" keyboardID:keyboard.unsignedLongLongValue];
        }
    }
    [_client setProperty:@0 forKey:@"LEPWMFactorFadeDuration"];
    return sent;
}
@end
