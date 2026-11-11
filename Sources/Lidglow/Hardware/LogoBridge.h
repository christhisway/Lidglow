// SPDX-License-Identifier: GPL-3.0-or-later

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LogoBridge : NSObject
/// Whether this Mac has a light-up lid logo (the `bklb-backlight` IOKit service). A single IOKit lookup
/// that loads nothing, so the app can check before it creates anything else.
@property (class, nonatomic, readonly) BOOL logoHardwarePresent;
@property (nonatomic, readonly) BOOL hardwarePresent;
/// The CoreBrightness classes and selectors Lidglow needs were all found. When this is NO (for example
/// after a macOS update), every call below fails safely and changes nothing.
@property (nonatomic, readonly) BOOL serviceAvailable;
@property (nonatomic, readonly) NSInteger mode;
@property (nonatomic, readonly) double level;
@property (nonatomic, readonly) BOOL lidClosed;
- (BOOL)enableLogo:(BOOL)enabled;
- (BOOL)fadeTowardLight:(BOOL)lit duration:(double)duration displayAwake:(BOOL)awake NS_SWIFT_NAME(fade(towardLight:duration:displayAwake:));
@end

NS_ASSUME_NONNULL_END
