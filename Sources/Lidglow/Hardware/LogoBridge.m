// SPDX-License-Identifier: GPL-3.0-or-later

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
+ (BOOL)logoHardwarePresent {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("bklb-backlight"));
    if (!service) return NO;
    IOObjectRelease(service);
    return YES;
}
// CoreBrightness is private and can change with any macOS update. Every call checks the types it gets
// back and catches Objective-C exceptions, so a changed interface leads to "unavailable" and an error
// in the panel, never a crash.
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    if (!LogoBridge.logoHardwarePresent) return self;
    _hardwarePresent = YES;

    @try {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY | RTLD_LOCAL);
        NSObject<BrightnessService> *client = [[NSClassFromString(@"BrightnessSystemClient") alloc] init];
        NSObject<BrightnessService> *keyboard = [[NSClassFromString(@"KeyboardBrightnessClient") alloc] init];
        if ([client respondsToSelector:@selector(copyPropertyForKey:)] &&
            [client respondsToSelector:@selector(setProperty:forKey:)] &&
            [client respondsToSelector:@selector(setProperty:withKey:keyboardID:)] &&
            [keyboard respondsToSelector:@selector(copyKeyboardBacklightIDs)]) {
            NSArray *keyboards = [keyboard copyKeyboardBacklightIDs];
            BOOL valid = [keyboards isKindOfClass:NSArray.class];
            for (id item in valid ? keyboards : @[]) {
                if (![item isKindOfClass:NSNumber.class]) valid = NO;
            }
            if (valid) {
                _client = client;
                _keyboards = keyboards;
            }
        }
    } @catch (NSException *exception) {
        _client = nil;
        _keyboards = nil;
    }
    return self;
}
- (BOOL)serviceAvailable {
    return _client != nil && _keyboards.count > 0;
}
- (nullable id)propertyForKey:(NSString *)key {
    if (!_client) return nil;
    @try { return [_client copyPropertyForKey:key]; }
    @catch (NSException *exception) { return nil; }
}
- (BOOL)setValue:(id)value forProperty:(NSString *)key {
    if (!_client) return NO;
    @try { return [_client setProperty:value forKey:key]; }
    @catch (NSException *exception) { return NO; }
}
- (NSInteger)mode {
    NSNumber *value = [self propertyForKey:@"LEBacklightMode"];
    return [value isKindOfClass:NSNumber.class] ? value.integerValue : -1;
}
- (double)level {
    NSDictionary *state = [self propertyForKey:@"LEPWMState"];
    NSNumber *factor = [state isKindOfClass:NSDictionary.class] ? state[@"Factor"] : nil;
    return [factor isKindOfClass:NSNumber.class] ? factor.doubleValue : NAN;
}
- (BOOL)lidClosed {
    NSNumber *value = [self propertyForKey:@"CBClamshellState"];
    return [value isKindOfClass:NSNumber.class] && value.boolValue;
}
- (BOOL)enableLogo:(BOOL)enabled {
    return [self setValue:@(enabled ? 2 : 0) forProperty:@"LEBacklightMode"];
}
- (BOOL)fadeTowardLight:(BOOL)lit duration:(double)duration displayAwake:(BOOL)awake {
    // CoreBrightness applies the duration to the next transition. Restore its default immediately.
    if (!self.serviceAvailable || ![self setValue:@(duration) forProperty:@"LEPWMFactorFadeDuration"]) return NO;
    BOOL sent = [self setValue:@(lit ? 2 : 1) forProperty:@"DisplayLogicalState"];
    if (!lit && awake) {
        for (NSNumber *keyboard in _keyboards) {
            @try {
                [_client setProperty:@2 withKey:@"DisplayLogicalState" keyboardID:keyboard.unsignedLongLongValue];
            } @catch (NSException *exception) {}
        }
    }
    [self setValue:@0 forProperty:@"LEPWMFactorFadeDuration"];
    return sent;
}
@end
