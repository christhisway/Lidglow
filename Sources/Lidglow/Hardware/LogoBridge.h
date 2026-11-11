#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LogoBridge : NSObject
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
