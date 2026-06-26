#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <IOKit/hid/IOHIDEventSystemClient.h>
#import <IOKit/hid/IOHIDEvent.h>
#import <CoreGraphics/CoreGraphics.h>

#define CLICK_INTERVAL 1.0
#define BUTTON_SIZE 60
#define BUTTON_CORNER_RADIUS 30
#define LONG_PRESS_DURATION 0.5

static IOHIDEventSystemClientRef _eventSystemClient = NULL;
static NSTimer *_clickTimer = NULL;
static BOOL _isRunning = NO;
static UIWindow *_floatWindow = NULL;
static UIButton *_floatButton = NULL;
static CGPoint _initialTouchPoint = CGPointZero;
static CGPoint _initialButtonCenter = CGPointZero;

static void sendTouchEvent(CGPoint point, BOOL isDown) {
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
        (int)(point.x * 1000),
        (int)(point.y * 1000),
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

static void performClick(CGPoint point) {
    sendTouchEvent(point, YES);
    usleep(50000);
    sendTouchEvent(point, NO);
}

static void clickTimerFired(NSTimer *timer) {
    CGPoint buttonCenter = [_floatButton convertPoint:_floatButton.center toView:nil];
    performClick(buttonCenter);
}

static void toggleAutoClick(UIButton *button) {
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

static void handleLongPress(UILongPressGestureRecognizer *gesture) {
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

static void createFloatButton() {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                createFloatButton();
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
        [longPress release];
        
        [_floatWindow addSubview:_floatButton];
        [_floatButton release];
    });
}

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
        createFloatButton();
    });
    
    return [self ac_application:application didFinishLaunchingWithOptions:launchOptions];
}

@end

__attribute__((constructor)) static void initialize() {
    _eventSystemClient = IOHIDEventSystemClientCreate(NULL);
}

__attribute__((destructor)) static void cleanup() {
    if (_clickTimer) {
        [_clickTimer invalidate];
        _clickTimer = nil;
    }
    
    if (_floatButton) {
        [_floatButton removeFromSuperview];
        [_floatButton release];
        _floatButton = nil;
    }
    
    if (_floatWindow) {
        [_floatWindow release];
        _floatWindow = nil;
    }
    
    if (_eventSystemClient) {
        CFRelease(_eventSystemClient);
        _eventSystemClient = NULL;
    }
}