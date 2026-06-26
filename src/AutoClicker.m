#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>

#define CLICK_INTERVAL 1.0
#define BUTTON_SIZE 60
#define BUTTON_CORNER_RADIUS 30
#define LONG_PRESS_DURATION 0.5

#define kIOHIDEventTypeDigitizerTouch 11
#define kIOHIDDigitizerTouchStateTouching 2
#define kIOHIDDigitizerTouchStateNotTouching 0

typedef CFTypeRef IOHIDEventSystemClientRef;
typedef CFTypeRef IOHIDEventRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern IOHIDEventRef IOHIDEventCreateDigitizerEvent(
    CFAllocatorRef allocator,
    uint32_t eventType,
    CFAbsoluteTime eventTime,
    uint64_t senderID,
    uint32_t options,
    uint32_t digitizerOptions,
    uint32_t touchState,
    uint32_t fingerID,
    uint32_t touchIdentifier,
    int32_t x,
    int32_t y,
    uint32_t tipPressure,
    uint32_t barrelPressure,
    uint32_t azimuth,
    uint32_t altitude,
    uint32_t twist,
    uint32_t width,
    uint32_t height,
    uint32_t deviceID,
    uint32_t deviceType,
    uint32_t collectionIndex,
    uint32_t displayWidth,
    uint32_t displayHeight
);
extern void IOHIDEventSystemClientQueueEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event, uint32_t options);

@interface AutoClickerManager : NSObject {
    IOHIDEventSystemClientRef _eventSystemClient;
    NSTimer *_clickTimer;
    BOOL _isRunning;
    UIWindow *_floatWindow;
    UIButton *_floatButton;
    CGPoint _initialTouchPoint;
    CGPoint _initialButtonCenter;
}

+ (instancetype)sharedManager;
- (void)createFloatButton;
- (void)sendTouchEvent:(CGPoint)point isDown:(BOOL)isDown;
- (void)performClick:(CGPoint)point;
- (void)clickTimerFired:(NSTimer *)timer;
- (void)toggleAutoClick:(UIButton *)button;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;

@end

@implementation AutoClickerManager

+ (instancetype)sharedManager {
    static AutoClickerManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _eventSystemClient = IOHIDEventSystemClientCreate(NULL);
        _isRunning = NO;
        _initialTouchPoint = CGPointZero;
        _initialButtonCenter = CGPointZero;
    }
    return self;
}

- (void)sendTouchEvent:(CGPoint)point isDown:(BOOL)isDown {
    if (!_eventSystemClient) return;
    
    IOHIDEventRef event = IOHIDEventCreateDigitizerEvent(
        NULL,
        kIOHIDEventTypeDigitizerTouch,
        CFAbsoluteTimeGetCurrent(),
        0,
        0,
        0,
        (isDown ? kIOHIDDigitizerTouchStateTouching : kIOHIDDigitizerTouchStateNotTouching),
        0,
        0,
        (int32_t)(point.x * 1000),
        (int32_t)(point.y * 1000),
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0
    );
    
    if (event) {
        IOHIDEventSystemClientQueueEvent(_eventSystemClient, event, 0);
        CFRelease(event);
    }
}

- (void)performClick:(CGPoint)point {
    [self sendTouchEvent:point isDown:YES];
    usleep(50000);
    [self sendTouchEvent:point isDown:NO];
}

- (void)clickTimerFired:(NSTimer *)timer {
    CGPoint buttonCenter = [_floatButton convertPoint:_floatButton.center toView:nil];
    [self performClick:buttonCenter];
}

- (void)toggleAutoClick:(UIButton *)button {
    if (_isRunning) {
        [_clickTimer invalidate];
        _clickTimer = nil;
        _isRunning = NO;
        button.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
        [button setTitle:@"▶" forState:UIControlStateNormal];
    } else {
        _isRunning = YES;
        _clickTimer = [NSTimer scheduledTimerWithTimeInterval:CLICK_INTERVAL
                                                       target:self
                                                     selector:@selector(clickTimerFired:)
                                                     userInfo:nil
                                                      repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_clickTimer forMode:NSDefaultRunLoopMode];
        button.backgroundColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:0.9];
        [button setTitle:@"■" forState:UIControlStateNormal];
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        _initialTouchPoint = [gesture locationInView:_floatWindow];
        _initialButtonCenter = _floatButton.center;
        _floatButton.transform = CGAffineTransformMakeScale(1.1, 1.1);
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint currentTouchPoint = [gesture locationInView:_floatWindow];
        CGFloat deltaX = currentTouchPoint.x - _initialTouchPoint.x;
        CGFloat deltaY = currentTouchPoint.y - _initialTouchPoint.y;
        
        CGPoint newCenter = CGPointMake(_initialButtonCenter.x + deltaX,
                                        _initialButtonCenter.y + deltaY);
        
        CGRect windowBounds = _floatWindow.bounds;
        newCenter.x = MAX(BUTTON_SIZE/2, MIN(windowBounds.size.width - BUTTON_SIZE/2, newCenter.x));
        newCenter.y = MAX(BUTTON_SIZE/2, MIN(windowBounds.size.height - BUTTON_SIZE/2, newCenter.y));
        
        _floatButton.center = newCenter;
    } else if (gesture.state == UIGestureRecognizerStateEnded ||
               gesture.state == UIGestureRecognizerStateCancelled) {
        _floatButton.transform = CGAffineTransformIdentity;
    }
}

- (void)createFloatButton {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindowScene *scene = [[[UIApplication sharedApplication] connectedScenes] allObjects].firstObject;
        UIWindow *keyWindow = scene.windows.firstObject;
        
        if (!keyWindow) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self createFloatButton];
            });
            return;
        }
        
        CGRect screenBounds = [[UIScreen mainScreen] bounds];
        
        _floatWindow = [[UIWindow alloc] initWithFrame:screenBounds];
        _floatWindow.windowLevel = UIWindowLevelAlert + 1;
        _floatWindow.backgroundColor = [UIColor clearColor];
        _floatWindow.hidden = NO;
        
        _floatButton = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, BUTTON_SIZE, BUTTON_SIZE)];
        _floatButton.center = CGPointMake(screenBounds.size.width - BUTTON_SIZE - 20,
                                          screenBounds.size.height / 2);
        _floatButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.9];
        _floatButton.layer.cornerRadius = BUTTON_CORNER_RADIUS;
        _floatButton.layer.masksToBounds = YES;
        _floatButton.layer.shadowColor = [UIColor blackColor].CGColor;
        _floatButton.layer.shadowOpacity = 0.5;
        _floatButton.layer.shadowOffset = CGSizeMake(0, 2);
        _floatButton.layer.shadowRadius = 4;
        _floatButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
        [_floatButton setTitle:@"▶" forState:UIControlStateNormal];
        [_floatButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        
        [_floatButton addTarget:self action:@selector(toggleAutoClick:) forControlEvents:UIControlEventTouchUpInside];
        
        UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPress.minimumPressDuration = LONG_PRESS_DURATION;
        [_floatButton addGestureRecognizer:longPress];
        
        [_floatWindow addSubview:_floatButton];
    });
}

- (void)dealloc {
    if (_clickTimer) {
        [_clickTimer invalidate];
        _clickTimer = nil;
    }
    
    if (_eventSystemClient) {
        CFRelease(_eventSystemClient);
        _eventSystemClient = NULL;
    }
    
    [super dealloc];
}

@end

@interface UIApplication (AutoClickerHook)
@end

@implementation UIApplication (AutoClickerHook)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [self class];
        
        SEL originalSelector = @selector(application:didFinishLaunchingWithOptions:);
        SEL swizzledSelector = @selector(ac_application:didFinishLaunchingWithOptions:);
        
        Method originalMethod = class_getInstanceMethod(class, originalSelector);
        Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
        
        BOOL didAddMethod = class_addMethod(class, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod));
        
        if (didAddMethod) {
            class_replaceMethod(class, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

- (BOOL)ac_application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[AutoClickerManager sharedManager] createFloatButton];
    });
    
    return [self ac_application:application didFinishLaunchingWithOptions:launchOptions];
}

@end

__attribute__((constructor)) static void initialize() {
    [AutoClickerManager sharedManager];
}
