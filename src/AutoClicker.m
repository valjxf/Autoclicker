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
    BOOL _buttonCreated;
    BOOL _observerRegistered;
}

+ (instancetype)sharedManager;
- (void)delayedStart;
- (void)createFloatButton;
- (void)ensureIOHIDClient;
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
        _eventSystemClient = NULL;
        _isRunning = NO;
        _buttonCreated = NO;
        _observerRegistered = NO;
        _initialTouchPoint = CGPointZero;
        _initialButtonCenter = CGPointZero;
    }
    return self;
}

- (void)delayedStart {
    if (_observerRegistered) return;
    _observerRegistered = YES;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onAppDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onWindowDidBecomeKey:)
                                                     name:UIWindowDidBecomeKeyNotification
                                                   object:nil];
        
        [self performSelector:@selector(createFloatButton) withObject:nil afterDelay:1.0];
    });
}

- (void)onAppDidBecomeActive:(NSNotification *)notification {
    if (!_buttonCreated) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self createFloatButton];
        });
    }
}

- (void)onWindowDidBecomeKey:(NSNotification *)notification {
    if (!_buttonCreated) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self createFloatButton];
        });
    }
}

- (void)ensureIOHIDClient {
    if (_eventSystemClient == NULL) {
        _eventSystemClient = IOHIDEventSystemClientCreate(NULL);
    }
}

- (void)sendTouchEvent:(CGPoint)point isDown:(BOOL)isDown {
    [self ensureIOHIDClient];
    
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
        [button setTitle:@"\u25B6" forState:UIControlStateNormal];
    } else {
        _isRunning = YES;
        _clickTimer = [NSTimer scheduledTimerWithTimeInterval:CLICK_INTERVAL
                                                       target:self
                                                     selector:@selector(clickTimerFired:)
                                                     userInfo:nil
                                                      repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_clickTimer forMode:NSDefaultRunLoopMode];
        button.backgroundColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:0.9];
        [button setTitle:@"\u25A0" forState:UIControlStateNormal];
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
    if (_buttonCreated) return;
    
    NSArray *scenes = [UIApplication sharedApplication].connectedScenes.allObjects;
    UIWindow *keyWindow = nil;
    
    for (UIScene *scene in scenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            if (windowScene.windows.count > 0) {
                keyWindow = windowScene.windows.firstObject;
                break;
            }
        }
    }
    
    if (!keyWindow) {
        keyWindow = [UIApplication sharedApplication].keyWindow;
    }
    
    if (!keyWindow) {
        [self performSelector:@selector(createFloatButton) withObject:nil afterDelay:0.5];
        return;
    }
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    _floatWindow = [[UIWindow alloc] initWithFrame:screenBounds];
    _floatWindow.windowLevel = UIWindowLevelAlert + 1;
    _floatWindow.backgroundColor = [UIColor clearColor];
    _floatWindow.hidden = NO;
    
    _floatButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _floatButton.frame = CGRectMake(0, 0, BUTTON_SIZE, BUTTON_SIZE);
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
    [_floatButton setTitle:@"\u25B6" forState:UIControlStateNormal];
    [_floatButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    
    [_floatButton addTarget:self action:@selector(toggleAutoClick:) forControlEvents:UIControlEventTouchUpInside];
    
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = LONG_PRESS_DURATION;
    [_floatButton addGestureRecognizer:longPress];
    
    [_floatWindow addSubview:_floatButton];
    
    _buttonCreated = YES;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    if (_clickTimer) {
        [_clickTimer invalidate];
        _clickTimer = nil;
    }
    
    if (_eventSystemClient) {
        CFRelease(_eventSystemClient);
        _eventSystemClient = NULL;
    }
}

@end

@interface AutoClickerRunner : NSObject
@end

@implementation AutoClickerRunner

+ (void)load {
    [[AutoClickerManager sharedManager] delayedStart];
}

@end
