#import <Cocoa/Cocoa.h>
#import <math.h>

static NSString *const kStateFile = @"/tmp/claude_traffic_light_state";
static NSString *const kLogFile = @"/tmp/claude_traffic_light.log";
static NSString *currentState = @"idle";
static NSDate *lastWorkingStart = nil;
static NSTimeInterval lastWorkingDuration = 0;
static NSDate *inputStart = nil;
static BOOL inputAlerted = NO;
static NSUInteger frameCount = 0;

void appendLog(NSString *from, NSString *to) {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *time = [fmt stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"%@ %@ -> %@\n", time, from, to];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:kLogFile];
    if (fh) {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    } else {
        [line writeToFile:kLogFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

#pragma mark - 绘制

static NSColor *kColorIdle;
static NSColor *kColorWorking;
static NSColor *kColorInput;

__attribute__((constructor))
static void initColors(void) {
    kColorIdle    = [NSColor colorWithRed:0.1 green:0.75 blue:0.25 alpha:1];  // 绿
    kColorWorking = [NSColor colorWithRed:1.0 green:0.75 blue:0.1 alpha:1];  // 黄
    kColorInput   = [NSColor colorWithRed:0.9 green:0.15 blue:0.1 alpha:1];  // 红
}

NSImage *drawTrafficLight(NSString *active, CGFloat w, CGFloat h, CGFloat r, CGFloat glowScale) {
    NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(w, h)];
    [img lockFocus];

    CGFloat rr = r * 0.8;
    NSRect housing = NSMakeRect(2, 3, w - 4, h - 6);
    [[NSColor colorWithWhite:0.15 alpha:0.92] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:housing xRadius:rr yRadius:rr] fill];

    NSRect inner = NSMakeRect(5, 6, w - 10, h - 12);
    [[NSColor colorWithWhite:0.1 alpha:0.95] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:inner xRadius:rr * 0.6 yRadius:rr * 0.6] fill];

    NSArray *states = @[@"idle", @"working", @"input"];
    NSColor *colors[] = {kColorIdle, kColorWorking, kColorInput};
    CGFloat spacing = (w - 10) / 3.0;
    CGFloat centers[] = {5 + spacing * 0.5, 5 + spacing * 1.5, 5 + spacing * 2.5};
    CGFloat cy = h / 2;

    for (NSInteger i = 0; i < 3; i++) {
        NSColor *color = colors[i];
        BOOL isActive = [states[i] isEqualToString:active];
        CGFloat cx = centers[i];

        CGFloat sr = r + r * 0.25;
        NSRect socketRect = NSMakeRect(cx - sr, cy - sr, sr * 2, sr * 2);
        [[NSColor colorWithWhite:0.05 alpha:1] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:socketRect] fill];

        if (isActive) {
            CGFloat k;
            if ([active isEqualToString:@"working"]) {
                k = ((frameCount / 6) % 2 == 0) ? 1.0 : 0.2;
            } else if ([active isEqualToString:@"input"]) {
                k = ((frameCount / 3) % 2 == 0) ? 1.0 : 0.1;
            } else {
                k = 1.0;
            }

            NSInteger glowCount = (NSInteger)(glowScale * 5);
            CGFloat baseOff = r * 0.2;
            for (NSInteger j = 0; j < glowCount; j++) {
                CGFloat off = baseOff * (glowCount - j);
                CGFloat ba = 0.015 * (j + 1);
                NSRect gRect = NSMakeRect(cx - r - off, cy - r - off, (r + off) * 2, (r + off) * 2);
                [[color colorWithAlphaComponent:ba * k] setFill];
                [[NSBezierPath bezierPathWithOvalInRect:gRect] fill];
            }

            NSRect cRect = NSMakeRect(cx - r, cy - r, r * 2, r * 2);
            [[color colorWithAlphaComponent:k] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:cRect] fill];

            CGFloat hr = r * 0.35;
            NSRect hlRect = NSMakeRect(cx - hr * 0.7, cy - hr * 0.5, hr, hr);
            [[NSColor.whiteColor colorWithAlphaComponent:0.35 * k] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:hlRect] fill];
        } else {
            NSRect cRect = NSMakeRect(cx - r, cy - r, r * 2, r * 2);
            [[color colorWithAlphaComponent:0.12] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:cRect] fill];
        }
    }

    [img unlockFocus];
    return img;
}

NSImage *makeSmallImage(NSString *active) {
    return drawTrafficLight(active, 60, 22, 6, 1.0);
}

NSImage *makeLargeImage(NSString *active) {
    return drawTrafficLight(active, 200, 74, 20, 2.0);
}

NSString *stateLabel(NSString *s) {
    if ([s isEqualToString:@"working"]) return @"运行中";
    if ([s isEqualToString:@"input"]) return @"需确认";
    return @"已完成";
}

NSString *formatDuration(NSTimeInterval sec) {
    if (sec < 60) return [NSString stringWithFormat:@"%.0f 秒", sec];
    int m = (int)sec / 60, s = (int)sec % 60;
    if (s == 0) return [NSString stringWithFormat:@"%d 分", m];
    return [NSString stringWithFormat:@"%d 分 %d 秒", m, s];
}

#pragma mark - 悬浮窗

@interface DraggableImageView : NSImageView
@end

@implementation DraggableImageView
- (BOOL)mouseDownCanMoveWindow { return YES; }
@end

#pragma mark - App

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSWindow *overlayWindow;
@property (nonatomic, strong) NSImageView *overlayImageView;
@property (nonatomic, assign) BOOL overlayVisible;
@end

@implementation AppDelegate

- (NSString *)readStateFile {
    NSString *content = [NSString stringWithContentsOfFile:kStateFile encoding:NSUTF8StringEncoding error:nil];
    return content ? [content stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"idle";
}

- (void)playAlertSound {
    NSSound *sound = [NSSound soundNamed:@"Ping"];
    if (sound) [sound play];
}

- (void)openTerminal {
    NSString *script = @"tell application \"System Events\"\n"
                        @"  if (exists process \"iTerm2\") then\n"
                        @"    tell application \"iTerm\" to activate\n"
                        @"  else\n"
                        @"    tell application \"Terminal\" to activate\n"
                        @"  end if\n"
                        @"end tell";
    NSAppleScript *as = [[NSAppleScript alloc] initWithSource:script];
    [as executeAndReturnError:nil];
}

#pragma mark 悬浮窗

- (void)createOverlayWindow {
    CGFloat w = 210, h = 84;
    NSRect frame = NSMakeRect(
        [NSScreen mainScreen].frame.size.width - w - 30,
        [NSScreen mainScreen].frame.size.height - h - 80,
        w, h
    );

    self.overlayWindow = [[NSWindow alloc]
        initWithContentRect:frame
        styleMask:NSWindowStyleMaskBorderless
        backing:NSBackingStoreBuffered
        defer:NO];

    self.overlayWindow.opaque = NO;
    self.overlayWindow.backgroundColor = [NSColor clearColor];
    self.overlayWindow.level = NSFloatingWindowLevel;
    self.overlayWindow.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary;
    self.overlayWindow.hasShadow = NO;
    [self.overlayWindow setMovableByWindowBackground:YES];

    self.overlayImageView = [[DraggableImageView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
    self.overlayImageView.image = makeLargeImage(@"idle");
    self.overlayImageView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.overlayWindow.contentView = self.overlayImageView;

    [self.overlayWindow orderFront:nil];
    self.overlayVisible = YES;
}

- (void)toggleOverlay {
    if (self.overlayVisible) {
        [self.overlayWindow orderOut:nil];
        self.overlayVisible = NO;
    } else {
        [self.overlayWindow orderFront:nil];
        self.overlayVisible = YES;
    }
}

#pragma mark 菜单

- (NSMenu *)buildMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    NSString *t;
    if ([currentState isEqualToString:@"idle"] && lastWorkingDuration > 0) {
        t = [NSString stringWithFormat:@"已完成 · 耗时 %@", formatDuration(lastWorkingDuration)];
    } else {
        t = stateLabel(currentState);
    }
    NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:t action:nil keyEquivalent:@""];
    header.enabled = NO;
    [menu addItem:header];

    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"打开终端" action:@selector(openTerminalAction) keyEquivalent:@""]];

    NSString *overlayTitle = self.overlayVisible ? @"✓ 桌面悬浮窗" : @"桌面悬浮窗";
    [menu addItem:[[NSMenuItem alloc] initWithTitle:overlayTitle action:@selector(toggleOverlayAction) keyEquivalent:@""]];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"退出" action:@selector(terminate:) keyEquivalent:@"q"]];
    return menu;
}

- (void)updateMenu {
    self.statusItem.menu = [self buildMenu];
    NSString *tip;
    if ([currentState isEqualToString:@"idle"] && lastWorkingDuration > 0) {
        tip = [NSString stringWithFormat:@"耗时 %@", formatDuration(lastWorkingDuration)];
    } else {
        tip = stateLabel(currentState);
    }
    self.statusItem.button.toolTip = tip;
}

#pragma mark 状态轮询

- (void)tick {
    NSString *state = [self readStateFile];
    BOOL changed = ![state isEqualToString:currentState];
    if (changed) {
        appendLog(currentState, state);
    }
    currentState = state;

    if ([state isEqualToString:@"working"]) {
        if (!lastWorkingStart) lastWorkingStart = [NSDate date];
    } else {
        if (lastWorkingStart) {
            lastWorkingDuration = [[NSDate date] timeIntervalSinceDate:lastWorkingStart];
            lastWorkingStart = nil;
        }
    }

    if ([state isEqualToString:@"input"]) {
        if (!inputStart) {
            inputStart = [NSDate date];
            inputAlerted = NO;
        } else if (!inputAlerted && [[NSDate date] timeIntervalSinceDate:inputStart] > 8) {
            [self playAlertSound];
            inputAlerted = YES;
        }
    } else {
        inputStart = nil;
        inputAlerted = NO;
    }

    if (changed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateMenu];
        });
    }
}

#pragma mark 生命周期

static NSString *const kPidFile = @"/tmp/claude_traffic_light.pid";

BOOL checkSingleInstance() {
    NSString *pidStr = [NSString stringWithContentsOfFile:kPidFile encoding:NSUTF8StringEncoding error:nil];
    if (pidStr) {
        int oldPid = [pidStr intValue];
        if (oldPid > 0) {
            // 检查进程是否真的在运行（kill(pid, 0) 不发信号，只检测存在性）
            if (kill(oldPid, 0) == 0 && oldPid != getpid()) {
                return NO;
            }
        }
    }
    NSString *myPid = [NSString stringWithFormat:@"%d", getpid()];
    [myPid writeToFile:kPidFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    if (!checkSingleInstance()) {
        NSLog(@"Another instance is already running, exiting.");
        [NSApp terminate:nil];
        return;
    }

    NSString *iconPath = [NSBundle.mainBundle pathForResource:@"ClaudeTrafficLight" ofType:@"icns"];
    if (iconPath) NSApp.applicationIconImage = [[NSImage alloc] initWithContentsOfFile:iconPath];

    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:62];
    self.statusItem.button.image = makeSmallImage(@"idle");
    [self.statusItem.button sendActionOn:(NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp)];

    [self updateMenu];
    [self createOverlayWindow];

    [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
        frameCount++;
        self.statusItem.button.image = makeSmallImage(currentState);
        self.overlayImageView.image = makeLargeImage(currentState);
    }];

    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        [self tick];
    }];
}

- (void)openTerminalAction { [self openTerminal]; }
- (void)toggleOverlayAction { [self toggleOverlay]; [self updateMenu]; }

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
