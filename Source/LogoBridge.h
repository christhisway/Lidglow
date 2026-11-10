#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LogoBridge : NSObject
@property (nonatomic, readonly) BOOL hardwarePresent;
@property (nonatomic, readonly) NSInteger mode;
@property (nonatomic, readonly) double level;
@property (nonatomic, readonly) BOOL lidClosed;
- (BOOL)enableLogo:(BOOL)enabled;
- (BOOL)fadeTowardLight:(BOOL)lit duration:(double)duration displayAwake:(BOOL)awake NS_SWIFT_NAME(fade(towardLight:duration:displayAwake:));
@end

NS_ASSUME_NONNULL_END
