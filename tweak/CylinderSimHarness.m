#ifdef CYLINDER_SIMJECT
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <mach-o/loader.h>
#import "tweak.h"

void CylinderHarnessLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
void CylinderHarnessLog(NSString *format, ...)
{
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
#if TARGET_OS_SIMULATOR
    NSLog(@"%@", line);
#else
    static NSFileHandle *handle;
    if (!handle) {
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Cylinder/harness.log"];
        [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:nil];
        handle = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    [handle seekToEndOfFile];
    [handle writeData:[[NSString stringWithFormat:@"%.3f %@\n", CACurrentMediaTime(), line] dataUsingEncoding:NSUTF8StringEncoding]];
#endif
}
#define NSLog CylinderHarnessLog

void CylinderHarnessLogLine(NSString *line)
{
    CylinderHarnessLog(@"%@", line);
}

@interface CylinderHarnessDriver : NSObject
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic, weak) UIScrollView *scrollView;
@property (nonatomic) CGFloat from;
@property (nonatomic) CGFloat to;
@property (nonatomic) CFTimeInterval start;
@property (nonatomic) CFTimeInterval duration;
@property (nonatomic) NSUInteger frames;
@property (nonatomic) CFTimeInterval hold;
@end

static CylinderHarnessDriver *CylinderDriver;
BOOL CylinderHarnessDisableHandoff;
BOOL CylinderHarnessDisableHide;
BOOL CylinderHarnessDisableChurn;
BOOL CylinderHarnessDisableSpringBoardHide;
BOOL CylinderHarnessAuditIcons;
BOOL CylinderHarnessKeepOffRangePages;
static BOOL CylinderHarnessTraceAdds;
extern UIImage *_UICreateScreenUIImage(void);
extern void _SetUIAnimationDragCoefficient(float coefficient);

static void CylinderHarnessCapture(NSString *name)
{
    UIImage *image = _UICreateScreenUIImage();
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Cylinder/shots"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [UIImagePNGRepresentation(image) writeToFile:[dir stringByAppendingPathComponent:[name stringByAppendingString:@".png"]] atomically:NO];
}

static void CylinderHarnessScheduleShots(NSDictionary *args)
{
    NSString *prefix = args[@"prefix"] ?: @"shot";
    for (NSString *ms in [args[@"shots"] componentsSeparatedByString:@","]) {
        if (!ms.length) continue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ms.doubleValue * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            CylinderHarnessCapture([NSString stringWithFormat:@"%@-%04d", prefix, ms.intValue]);
        });
    }
}
static __weak UIScrollView *CylinderDraggedScrollView;
static __weak SBIconView *CylinderHarnessLaunchedIconView;

static NSString *CylinderHarnessDescribeChain(UIView *view)
{
    NSMutableArray *chain = [NSMutableArray array];
    for (UIView *v = view; v && chain.count < 8; v = v.superview) {
        [chain addObject:NSStringFromClass(v.class)];
    }
    return [chain componentsJoinedByString:@" < "];
}

static void CylinderHarnessCollect(UIView *view, Class cls, NSMutableArray *out)
{
    if ([view isKindOfClass:cls]) [out addObject:view];
    for (UIView *sub in view.subviews) CylinderHarnessCollect(sub, cls, out);
}

static NSArray *CylinderHarnessAllViews(Class cls)
{
    NSMutableArray *out = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) CylinderHarnessCollect(window, cls, out);
    }
    return out;
}

static SBFolderView *CylinderHarnessRootFolderView(void)
{
    Class rootClass = objc_getClass("SBRootFolderView");
    for (SBFolderView *folderView in CylinderHarnessAllViews(rootClass)) {
        if (folderView.window && !folderView.window.hidden) return folderView;
    }
    return CylinderHarnessAllViews(rootClass).firstObject;
}

static NSInteger CylinderHarnessPageIndex(SBFolderView *folderView, NSDictionary *args)
{
    NSInteger first = ((NSInteger (*)(id, SEL))objc_msgSend)(folderView, NSSelectorFromString(@"firstIconPageIndex"));
    return first + [args[@"page"] integerValue];
}

static UIScrollView *CylinderHarnessScrollView(SBFolderView *folderView)
{
    NSMutableArray *scrollViews = [NSMutableArray array];
    CylinderHarnessCollect(folderView, objc_getClass("SBIconScrollView"), scrollViews);
    return scrollViews.firstObject;
}

static void CylinderHarnessState(NSString *tag)
{
    SBFolderView *folderView = CylinderHarnessRootFolderView();
    UIScrollView *scrollView = CylinderHarnessScrollView(folderView);
    NSMutableString *pages = [NSMutableString string];
    for (SBIconListView *listView in [folderView valueForKey:@"iconListViews"]) {
        CATransform3D t = listView.layer.transform;
        [pages appendFormat:@" [%p x=%.0f icons=%lu m11=%.2f m41=%.1f m43=%.1f]", listView, listView.frame.origin.x,
            (unsigned long)listView.subviews.count, t.m11, t.m41, t.m43];
    }
    NSLog(@"[CylinderHarness] %@: offset=%@ size=%@ scrolling=%d%@", tag,
          NSStringFromCGPoint(scrollView.contentOffset), NSStringFromCGSize(scrollView.contentSize),
          [folderView isScrolling], pages);
}

static void CylinderHarnessDump(NSString *tag)
{
    CylinderHarnessState(tag);
    SBIconView *launched = CylinderHarnessLaunchedIconView;
    SBIcon *icon = launched.icon;
    if (!icon) {
        NSLog(@"[CylinderHarness] %@: no launched icon", tag);
        return;
    }

    for (SBIconView *iconView in CylinderHarnessAllViews(objc_getClass("SBIconView"))) {
        if (iconView.icon != icon) continue;
        CGRect windowFrame = [iconView convertRect:iconView.bounds toView:nil];
        NSLog(@"[CylinderHarness] %@: %p hidden=%d alpha=%.2f inWindow=%@ frame=%@ chain=%@",
              tag, iconView, iconView.hidden, iconView.alpha,
              NSStringFromCGRect(windowFrame), NSStringFromCGRect(iconView.frame),
              CylinderHarnessDescribeChain(iconView));
    }
}

@implementation CylinderHarnessDriver
- (void)tick:(CADisplayLink *)link
{
    UIScrollView *scrollView = self.scrollView;
    CFTimeInterval t = (CACurrentMediaTime() - self.start) / MAX(self.duration, 0.001);
    if (t > 1) t = 1;
    CGFloat before = scrollView.contentOffset.x;
    CGFloat wanted = self.from + (self.to - self.from) * t;
    if (scrollView) {
        static IMP rawSetter;
        if (!rawSetter) rawSetter = class_getMethodImplementation(UIScrollView.class, @selector(setContentOffset:));
        ((void (*)(id, SEL, CGPoint))rawSetter)(scrollView, @selector(setContentOffset:), CGPointMake(wanted, scrollView.contentOffset.y));
    }
    if (self.frames == 0) NSLog(@"[CylinderHarness] classes sv=%@ delegate=%@ enabled=%d", scrollView.class, [(id)scrollView.delegate class], scrollView.scrollEnabled);
    if (self.frames < 3) NSLog(@"[CylinderHarness] tick before=%.1f wanted=%.1f after=%.1f sv=%p", before, wanted, scrollView.contentOffset.x, scrollView);
    if ((self.frames++ % 3) == 0) CylinderHarnessDump([NSString stringWithFormat:@"scroll t=%.2f", t]);
    if (t >= 1) {
        [link invalidate];
        self.link = nil;
        CylinderHarnessDump(@"scroll done");
        UIScrollView *strongScrollView = scrollView;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.hold * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (CylinderDraggedScrollView != strongScrollView || CylinderDriver != self) return;
            NSLog(@"[CylinderHarness] releasing drag");
            [strongScrollView.delegate scrollViewWillEndDragging:strongScrollView withVelocity:CGPointZero targetContentOffset:&(CGPoint){strongScrollView.contentOffset.x, 0}];
            CylinderDraggedScrollView = nil;
            [strongScrollView.delegate scrollViewDidEndDragging:strongScrollView willDecelerate:YES];
            SEL update = NSSelectorFromString(@"_updateScrolling");
            if ([strongScrollView respondsToSelector:update]) ((void (*)(id, SEL))objc_msgSend)(strongScrollView, update);
            CGFloat width = strongScrollView.bounds.size.width;
            [strongScrollView setContentOffset:CGPointMake(round(strongScrollView.contentOffset.x / width) * width, 0) animated:YES];
            CylinderHarnessDump(@"released");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                CylinderHarnessState(@"settled");
            });
        });
    }
}
@end

static void CylinderHarnessScroll(NSDictionary *args)
{
    SBFolderView *folderView = CylinderHarnessRootFolderView();
    UIScrollView *scrollView = CylinderHarnessScrollView(folderView);
    if (!scrollView) {
        NSLog(@"[CylinderHarness] no scroll view");
        return;
    }

    [CylinderDriver.link invalidate];
    CylinderDriver = [CylinderHarnessDriver new];
    CylinderDriver.scrollView = scrollView;
    CGFloat width = scrollView.bounds.size.width;
    NSInteger page = CylinderHarnessPageIndex(folderView, args);
    CGFloat base = [folderView _scrollOffsetForPageAtIndex:page].x;
    CylinderDriver.from = [args[@"fromCurrent"] boolValue] ? scrollView.contentOffset.x : base;
    CylinderDriver.to = base + width * [(args[@"fraction"] ?: @0.35) doubleValue];
    CylinderDriver.duration = [(args[@"durationMs"] ?: @600) doubleValue] / 1000.0;
    CylinderDriver.hold = [(args[@"holdMs"] ?: @1500) doubleValue] / 1000.0;
    CylinderDraggedScrollView = scrollView;
    [scrollView.delegate scrollViewWillBeginDragging:scrollView];
    CylinderDriver.start = CACurrentMediaTime();
    CylinderDriver.link = [CADisplayLink displayLinkWithTarget:CylinderDriver selector:@selector(tick:)];
    [CylinderDriver.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    NSLog(@"[CylinderHarness] scrolling %.1f -> %.1f", CylinderDriver.from, CylinderDriver.to);
}

static void CylinderHarnessBench(NSDictionary *args)
{
    SBFolderView *folderView = CylinderHarnessRootFolderView();
    UIScrollView *scrollView = CylinderHarnessScrollView(folderView);
    if (!scrollView) return;

    NSInteger frames = [(args[@"frames"] ?: @600) integerValue];
    CGFloat width = scrollView.bounds.size.width;
    CGFloat base = [folderView _scrollOffsetForPageAtIndex:CylinderHarnessPageIndex(folderView, args)].x;
    IMP rawSetter = class_getMethodImplementation(UIScrollView.class, @selector(setContentOffset:));

    CylinderDraggedScrollView = scrollView;
    [scrollView.delegate scrollViewWillBeginDragging:scrollView];

    BOOL flush = [args[@"flush"] boolValue];
    CFTimeInterval worst = 0;
    CFTimeInterval start = CACurrentMediaTime();
    for (NSInteger i = 0; i < frames; i++) {
        CGFloat phase = (CGFloat)i / (CGFloat)frames;
        CGFloat fraction = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
        CFTimeInterval frameStart = CACurrentMediaTime();
        ((void (*)(id, SEL, CGPoint))rawSetter)(scrollView, @selector(setContentOffset:), CGPointMake(base + width * 0.98 * fraction, 0));
        if (flush) [CATransaction flush];
        worst = MAX(worst, CACurrentMediaTime() - frameStart);
    }
    CFTimeInterval elapsed = CACurrentMediaTime() - start;

    CylinderDraggedScrollView = nil;
    [scrollView setContentOffset:CGPointMake(base, 0) animated:NO];
    [scrollView.delegate scrollViewDidEndDecelerating:scrollView];
    NSLog(@"[CylinderHarness] bench %@: %ld frames, mean %.1f us, worst %.1f us", args[@"label"] ?: @"",
          (long)frames, elapsed / frames * 1e6, worst * 1e6);
}

static NSArray *CylinderHarnessLayerState(UIView *view)
{
    CATransform3D t = view.layer.transform;
    return @[@(t.m11), @(t.m12), @(t.m13), @(t.m14), @(t.m21), @(t.m22), @(t.m23), @(t.m24),
             @(t.m31), @(t.m32), @(t.m33), @(t.m34), @(t.m41), @(t.m42), @(t.m43), @(t.m44),
             @(view.layer.position.x), @(view.layer.position.y), @(view.alpha)];
}

static void CylinderHarnessDumpModel(SBFolderView *folderView, NSString *name)
{
    NSMutableArray *pages = [NSMutableArray array];
    for (SBIconListView *listView in [folderView valueForKey:@"iconListViews"]) {
        NSMutableArray *icons = [NSMutableArray array];
        [listView enumerateIconViewsUsingBlock:^(SBIconView *iconView, NSUInteger index, BOOL *stop) {
            [icons addObject:CylinderHarnessLayerState(iconView)];
        }];
        [pages addObject:@{@"page": CylinderHarnessLayerState(listView), @"icons": icons}];
    }
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Cylinder/shots"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:pages options:0 error:nil];
    [data writeToFile:[dir stringByAppendingPathComponent:[name stringByAppendingString:@".json"]] atomically:NO];
}

/// Logs every page SpringBoard reports as visible: whether it is a custom page such as the Today view, and how
/// many of its icons carry a transform or draw antialiased edges.
static void CylinderHarnessVisiblePages(NSString *tag)
{
    SBFolderView *folderView = CylinderHarnessRootFolderView();
    NSInteger leading, trailing;
    [folderView getLeadingVisiblePageIndex:&leading trailingVisiblePageIndex:&trailing];
    if (leading == NSIntegerMax || trailing == NSIntegerMax) return;
    NSInteger first = ((NSInteger (*)(id, SEL))objc_msgSend)(folderView, NSSelectorFromString(@"firstIconPageIndex"));
    NSInteger last = ((NSInteger (*)(id, SEL))objc_msgSend)(folderView, NSSelectorFromString(@"lastIconPageIndex"));
    for (NSInteger index = leading; index <= trailing; index++) {
        SBIconListView *listView = [folderView iconListViewForPageIndex:index];
        __block NSUInteger icons = 0, transformed = 0, antialiased = 0, layers = 0, antialiasedLayers = 0;
        __block __weak void (^countLayers)(CALayer *);
        void (^count)(CALayer *) = ^(CALayer *layer) {
            layers++;
            if (layer.allowsEdgeAntialiasing) antialiasedLayers++;
            for (CALayer *sublayer in layer.sublayers) countLayers(sublayer);
        };
        countLayers = count;
        [listView enumerateIconViewsUsingBlock:^(SBIconView *iconView, NSUInteger i, BOOL *stop) {
            icons++;
            if (!CATransform3DIsIdentity(iconView.layer.transform)) transformed++;
            if (iconView.layer.allowsEdgeAntialiasing) antialiased++;
            count(iconView.layer);
        }];
        CATransform3D t = listView.layer.transform;
        NSLog(@"[CylinderHarness] %@ visible page %ld (%@) %@ pageIdentity=%d m11=%.3f m13=%.3f m34=%.5f alpha=%.2f icons=%lu transformed=%lu "
              @"iconLayersAntialiased=%lu allLayersAntialiased=%lu/%lu", tag, (long)(index - first),
              index < first ? @"leading custom" : index > last ? @"trailing custom" : @"icon page", listView.class,
              CATransform3DIsIdentity(t), t.m11, t.m13, t.m34, listView.alpha, (unsigned long)icons, (unsigned long)transformed,
              (unsigned long)antialiased, (unsigned long)antialiasedLayers, (unsigned long)layers);
    }
}

static void CylinderHarnessPose(NSDictionary *args)
{
    SBFolderView *folderView = CylinderHarnessRootFolderView();
    UIScrollView *scrollView = CylinderHarnessScrollView(folderView);
    if (!scrollView) return;

    CGFloat width = scrollView.bounds.size.width;
    CGFloat base = [folderView _scrollOffsetForPageAtIndex:CylinderHarnessPageIndex(folderView, args)].x;
    CGFloat fraction = [args[@"fraction"] doubleValue];
    IMP rawSetter = class_getMethodImplementation(UIScrollView.class, @selector(setContentOffset:));

    CylinderDraggedScrollView = scrollView;
    [scrollView.delegate scrollViewWillBeginDragging:scrollView];
    ((void (*)(id, SEL, CGPoint))rawSetter)(scrollView, @selector(setContentOffset:), CGPointMake(base + width * fraction * 0.5, 0));
    ((void (*)(id, SEL, CGPoint))rawSetter)(scrollView, @selector(setContentOffset:), CGPointMake(base + width * fraction, 0));

    NSString *name = args[@"name"] ?: @"pose";
    CylinderHarnessDumpModel(folderView, name);
    CylinderHarnessVisiblePages(name);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(120 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        CylinderHarnessCapture(name);
        CylinderDraggedScrollView = nil;
        [scrollView setContentOffset:CGPointMake(base, 0) animated:NO];
        [scrollView.delegate scrollViewDidEndDecelerating:scrollView];
        NSLog(@"[CylinderHarness] posed %@", name);
    });
}

static void CylinderHarnessLaunch(NSDictionary *args)
{
    SBFolderView *folderView = CylinderHarnessRootFolderView();
    SBIconListView *listView = [folderView iconListViewForPageIndex:CylinderHarnessPageIndex(folderView, args)];
    NSInteger wanted = [args[@"index"] integerValue];
    __block SBIconView *target = nil;
    [listView enumerateIconViewsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
        if ((NSInteger)idx == wanted) {
            target = iconView;
            *stop = YES;
        }
    }];
    if (!target) {
        NSLog(@"[CylinderHarness] no icon at index %ld", (long)wanted);
        return;
    }
    CylinderHarnessLaunchedIconView = target;
    NSLog(@"[CylinderHarness] launching %@", target.icon.displayName);
    ((void (*)(id, SEL))objc_msgSend)(target, @selector(performTap));
}

static void CylinderHarnessHome(void)
{
    NSLog(@"[CylinderHarness] simulating home press");
    ((void (*)(id, SEL, id))objc_msgSend)(UIApplication.sharedApplication,
                                         NSSelectorFromString(@"_simulateHomeButtonPressWithCompletion:"),
                                         nil);
}

static void CylinderHarnessReset(void)
{
    SBFolderView *folderView = CylinderHarnessRootFolderView();
    UIScrollView *scrollView = CylinderHarnessScrollView(folderView);
    [CylinderDriver.link invalidate];
    CylinderDriver = nil;
    [scrollView setContentOffset:[folderView _scrollOffsetForPageAtIndex:CylinderHarnessPageIndex(folderView, @{})] animated:NO];
    [scrollView.delegate scrollViewDidEndDecelerating:scrollView];
}

static CGRect CylinderHarnessPresentedRect(UIView *view)
{
    CALayer *layer = view.layer.presentationLayer ?: view.layer;
    CALayer *root = view.window.layer.presentationLayer ?: view.window.layer;
    return [layer convertRect:layer.bounds toLayer:root];
}

static NSString *CylinderHarnessShortRect(CGRect r)
{
    return [NSString stringWithFormat:@"(%.1f,%.1f %.1fx%.1f)", r.origin.x, r.origin.y, r.size.width, r.size.height];
}

@interface CylinderHarnessTracer : NSObject
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) CFTimeInterval start;
@property (nonatomic) CFTimeInterval duration;
@property (nonatomic) BOOL dumpedTree;
@end

static CylinderHarnessTracer *CylinderTracer;

@implementation CylinderHarnessTracer
- (void)tick:(CADisplayLink *)link
{
    CFTimeInterval elapsed = CACurrentMediaTime() - self.start;
    SBIcon *icon = CylinderHarnessLaunchedIconView.icon;
    NSMutableString *line = [NSMutableString stringWithFormat:@"t=%4.0fms", elapsed * 1000];
    for (SBIconView *iconView in CylinderHarnessAllViews(objc_getClass("SBIconView"))) {
        if (iconView.icon != icon) continue;
        BOOL onPage = [iconView.superview isKindOfClass:objc_getClass("SBIconListView")];
        if (!onPage) {
            NSString *matched = @"none";
            for (CALayer *layer = iconView.layer; layer; layer = layer.superlayer) {
                if ([layer animationForKey:@"MatchMoveToIconViewAnimation"]) {
                    matched = [NSString stringWithFormat:@"%@ sub=%d op=%.2f", layer.delegate.class, !CATransform3DIsIdentity(layer.sublayerTransform), layer.opacity];
                    break;
                }
            }
            [line appendFormat:@" mm=%@", matched];
        }
        [line appendFormat:@" %@%@ model%@ a=%.2f", onPage ? @"page" : @"fly", CylinderHarnessShortRect(CylinderHarnessPresentedRect(iconView)),
            CylinderHarnessShortRect([iconView convertRect:iconView.bounds toView:nil]),
            ((CALayer *)(iconView.layer.presentationLayer ?: iconView.layer)).opacity];
        if (!onPage && !self.dumpedTree) {
            self.dumpedTree = YES;
            for (UIView *v = iconView; v; v = v.superview) {
                NSMutableArray *subs = [NSMutableArray array];
                for (UIView *s in v.superview.subviews) [subs addObject:[NSString stringWithFormat:@"%@%@", s == v ? @"*" : @"", NSStringFromClass(s.class)]];
                NSLog(@"[CylinderHarness] tree %@ %p frame=%@ win=%@ siblings=%@", NSStringFromClass(v.class), v,
                      NSStringFromCGRect(v.frame), CylinderHarnessShortRect(CylinderHarnessPresentedRect(v)), [subs componentsJoinedByString:@","]);
                for (NSString *key in v.layer.animationKeys) {
                    CAAnimation *animation = [v.layer animationForKey:key];
                    NSMutableString *info = [NSMutableString stringWithFormat:@"%@ %@", key, animation.class];
                    if ([animation isKindOfClass:objc_getClass("CAMatchMoveAnimation")]) {
                        id source = [animation valueForKey:@"sourceLayer"];
                        [info appendFormat:@" source=%@ %p delegate=%@ points=%@ targetsSuperlayer=%@ appliesX=%@ appliesY=%@ appliesScale=%@ appliesRotation=%@ additive=%@",
                            [source class], source, [[source delegate] class], [animation valueForKey:@"sourcePoints"],
                            [animation valueForKey:@"targetsSuperlayer"], [animation valueForKey:@"appliesX"], [animation valueForKey:@"appliesY"],
                            [animation valueForKey:@"appliesScale"], [animation valueForKey:@"appliesRotation"], [animation valueForKey:@"additive"]];
                    } else if ([animation isKindOfClass:CAPropertyAnimation.class]) {
                        [info appendFormat:@" keyPath=%@ additive=%d dur=%.2f", ((CAPropertyAnimation *)animation).keyPath, ((CAPropertyAnimation *)animation).additive, animation.duration];
                    }
                    NSLog(@"[CylinderHarness] tree   anim %@", info);
                }
            }
        }
    }
    NSLog(@"[CylinderHarness] trace %@", line);
    if (elapsed > self.duration) {
        [link invalidate];
        self.link = nil;
    }
}
@end

@interface CylinderHarnessWatcher : NSObject
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) CFTimeInterval start;
@property (nonatomic) CFTimeInterval duration;
@property (nonatomic, weak) UIWindow *switcherWindow;
@end

static CylinderHarnessWatcher *CylinderWatcher;

static void CylinderHarnessCollectFlights(UIView *view, Class overlayClass, Class iconViewClass, BOOL inOverlay, NSMutableArray *out)
{
    inOverlay = inOverlay || [view isKindOfClass:overlayClass];
    if (inOverlay && [view isKindOfClass:iconViewClass]) [out addObject:view];
    for (UIView *sub in view.subviews) CylinderHarnessCollectFlights(sub, overlayClass, iconViewClass, inOverlay, out);
}

@implementation CylinderHarnessWatcher
- (void)tick:(CADisplayLink *)link
{
    CFTimeInterval elapsed = CACurrentMediaTime() - self.start;
    if (elapsed > self.duration) {
        [link invalidate];
        self.link = nil;
        NSLog(@"[CylinderHarness] watch done");
        return;
    }

    UIWindow *window = self.switcherWindow;
    if (!window) {
        for (UIWindow *candidate in CylinderHarnessAllViews(UIWindow.class)) {
            if ([NSStringFromClass(candidate.class) isEqualToString:@"SBMainSwitcherWindow"]) window = candidate;
        }
        self.switcherWindow = window;
    }

    NSMutableArray *flights = [NSMutableArray array];
    CylinderHarnessCollectFlights(window, objc_getClass("SBFluidSwitcherIconOverlayView"), objc_getClass("SBIconView"), NO, flights);
    NSMutableArray *cards = [NSMutableArray array];
    CylinderHarnessCollect(window, objc_getClass("SBReusableSnapshotItemContainer"), cards);
    NSMutableString *cardInfo = [NSMutableString string];
    for (UIView *card in cards) {
        float opacity = 1;
        for (CALayer *layer = card.layer; layer; layer = layer.superlayer) opacity *= (layer.presentationLayer ?: layer).opacity;
        [cardInfo appendFormat:@" card%p%@ op=%.2f hidden=%d alpha=%.2f super=%@", card, CylinderHarnessShortRect(CylinderHarnessPresentedRect(card)), opacity,
            card.hidden, card.alpha, card.superview.class];
        for (CALayer *layer = card.layer; layer; layer = layer.superlayer) {
            if (![layer animationForKey:@"MatchMoveToIconViewAnimation"]) continue;
            [cardInfo appendFormat:@" switcherOp=%.2f", layer.opacity];
            break;
        }
    }
    if (!flights.count && !cardInfo.length) return;

    SBFolderView *folderView = CylinderHarnessRootFolderView();
    UIScrollView *scrollView = CylinderHarnessScrollView(folderView);
    NSMutableString *line = [NSMutableString stringWithFormat:@"watch t=%5.0fms offset=%.1f scrolling=%d%@", elapsed * 1000,
                             scrollView.contentOffset.x, [folderView isScrolling], cardInfo];
    for (SBIconView *flight in flights) {
        CALayer *presented = flight.layer.presentationLayer ?: flight.layer;
        [line appendFormat:@" | fly %@ %@ a=%.2f hidden=%d", flight.icon.displayName, CylinderHarnessShortRect(CylinderHarnessPresentedRect(flight)),
            presented.opacity, flight.hidden];
        for (CALayer *layer = flight.layer; layer; layer = layer.superlayer) {
            CAAnimation *animation = [layer animationForKey:@"MatchMoveToIconViewAnimation"];
            if (!animation) continue;
            CALayer *source = [animation valueForKey:@"sourceLayer"];
            SBIconView *sourceView = (SBIconView *)source.delegate;
            NSString *sourceIcon = [sourceView respondsToSelector:@selector(icon)] ? sourceView.icon.displayName : @"?";
            CALayer *presentedLayer = layer.presentationLayer ?: layer;
            [line appendFormat:@" mm=%@ op=%.2f/%.2f sub=%d src=%@ %p in=%@ win=%@", layer.delegate.class, layer.opacity, presentedLayer.opacity,
                !CATransform3DIsIdentity(layer.sublayerTransform), sourceIcon, sourceView,
                NSStringFromClass(((UIView *)sourceView).superview.class), CylinderHarnessShortRect(CylinderHarnessPresentedRect(sourceView))];
            break;
        }
    }
    NSLog(@"[CylinderHarness] %@", line);
}
@end

static void CylinderHarnessStartWatch(NSDictionary *args)
{
    [CylinderWatcher.link invalidate];
    CylinderWatcher = [CylinderHarnessWatcher new];
    CylinderWatcher.start = CACurrentMediaTime();
    CylinderWatcher.duration = [(args[@"watchMs"] ?: @20000) doubleValue] / 1000.0;
    CylinderWatcher.link = [CADisplayLink displayLinkWithTarget:CylinderWatcher selector:@selector(tick:)];
    [CylinderWatcher.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    NSLog(@"[CylinderHarness] watching for %.0f s", CylinderWatcher.duration);
}

static void CylinderHarnessProbeView(UIView *view, CGPoint point, float opacity, NSMutableArray *out)
{
    CALayer *presented = view.layer.presentationLayer ?: view.layer;
    opacity *= presented.opacity;
    if (view.hidden || opacity < 0.01) return;
    CGRect rect = CylinderHarnessPresentedRect(view);
    if (CGRectContainsPoint(rect, point) && rect.size.width < 300 && view.window) {
        NSMutableArray *chain = [NSMutableArray array];
        for (UIView *v = view; v && chain.count < 9; v = v.superview) [chain addObject:NSStringFromClass(v.class)];
        [out addObject:[NSString stringWithFormat:@"%@ op=%.2f rect=%@ win=%@ chain=%@", view, opacity, CylinderHarnessShortRect(rect),
                        view.window.class, [chain componentsJoinedByString:@"<"]]];
    }
    for (UIView *sub in view.subviews) CylinderHarnessProbeView(sub, point, opacity, out);
}

static void CylinderHarnessScheduleProbe(NSDictionary *args)
{
    if (!args[@"probeMs"]) return;
    CGPoint point = CGPointMake([args[@"px"] doubleValue], [args[@"py"] doubleValue]);
    for (NSString *ms in [args[@"probeMs"] componentsSeparatedByString:@","]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ms.doubleValue * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            NSMutableArray *out = [NSMutableArray array];
            for (UIWindow *window in CylinderHarnessAllViews(UIWindow.class)) {
                if (!window.hidden) CylinderHarnessProbeView(window, point, 1, out);
            }
            NSLog(@"[CylinderHarness] probe %@ms at %@: %lu views", ms, NSStringFromCGPoint(point), (unsigned long)out.count);
            for (NSString *line in out) NSLog(@"[CylinderHarness] probe   %@", line);
        });
    }
}

static void CylinderHarnessStartTrace(NSDictionary *args)
{
    if (![args[@"traceMs"] doubleValue]) return;
    [CylinderTracer.link invalidate];
    CylinderTracer = [CylinderHarnessTracer new];
    CylinderTracer.start = CACurrentMediaTime();
    CylinderTracer.duration = [args[@"traceMs"] doubleValue] / 1000.0;
    CylinderTracer.link = [CADisplayLink displayLinkWithTarget:CylinderTracer selector:@selector(tick:)];
    [CylinderTracer.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

static void CylinderHarnessShuttle(NSDictionary *args)
{
    NSInteger count = [(args[@"count"] ?: @8) integerValue];
    double period = [(args[@"periodMs"] ?: @350) doubleValue];
    NSInteger pageA = [args[@"page"] integerValue];
    NSInteger pageB = [(args[@"page2"] ?: @(pageA + 1)) integerValue];
    for (NSInteger i = 0; i < count; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * period * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            NSInteger target = (i % 2) ? pageA : pageB;
            NSMutableDictionary *step = [args mutableCopy];
            step[@"page"] = @(target);
            step[@"fraction"] = @([(args[@"overshoot"] ?: @0) doubleValue] * ((i % 2) ? 1 : -1));
            step[@"fromCurrent"] = @YES;
            CylinderHarnessScroll(step);
        });
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((count * period + 2500) * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        CylinderHarnessState(@"shuttle done");
    });
}

/// Shows the Lock Screen, dismisses it after `lockMs` so the icons fly in, and drags the Home Screen `delayMs`
/// into the fly-in.
static void CylinderHarnessFlyInScroll(NSDictionary *args)
{
    Class managerClass = objc_getClass("SBCoverSheetPresentationManager");
    id manager = nil;
    // iOS 27 keeps one manager per display.
    for (NSString *name in @[@"sharedInstanceForMainDisplay", @"sharedInstance", @"sharedInstanceIfExists"]) {
        SEL accessor = NSSelectorFromString(name);
        if ([managerClass respondsToSelector:accessor]) {
            manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, accessor);
            if (manager) break;
        }
    }
    SEL setPresented = NSSelectorFromString(@"setCoverSheetPresented:animated:withCompletion:");
    if (![manager respondsToSelector:setPresented]) {
        unsigned int count = 0;
        Method *methods = class_copyMethodList(object_getClass(managerClass), &count);
        NSMutableArray *names = [NSMutableArray array];
        for (unsigned int i = 0; i < count; i++) [names addObject:NSStringFromSelector(method_getName(methods[i]))];
        free(methods);
        NSLog(@"[CylinderHarness] no cover sheet presentation manager; class methods: %@", [names componentsJoinedByString:@", "]);
        return;
    }

    ((void (*)(id, SEL, BOOL, BOOL, id))objc_msgSend)(manager, setPresented, YES, NO, nil);
    double lock = [(args[@"lockMs"] ?: @800) doubleValue];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(lock * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        ((void (*)(id, SEL, BOOL, BOOL, id))objc_msgSend)(manager, setPresented, NO, YES, nil);
        double delay = [args[@"delayMs"] doubleValue];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            CylinderHarnessDump(@"before scroll");
            CylinderHarnessScroll(args);
        });
        // At each comma-separated `modelMs` after the dismissal, records every icon's model state and the view that
        // holds it.
        for (NSString *ms in [args[@"modelMs"] componentsSeparatedByString:@","]) {
            if (!ms.length) continue;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ms.doubleValue * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                SBFolderView *folderView = CylinderHarnessRootFolderView();
                CylinderHarnessDumpModel(folderView, [NSString stringWithFormat:@"%@-%@", args[@"name"] ?: @"flyin", ms]);
                for (SBIconListView *listView in [folderView valueForKey:@"iconListViews"]) {
                    [listView enumerateIconViewsUsingBlock:^(SBIconView *iconView, NSUInteger index, BOOL *stop) {
                        CALayer *layer = iconView.layer;
                        CALayer *presented = layer.presentationLayer ?: layer;
                        CALayer *container = layer.superlayer;
                        NSLog(@"[CylinderHarness] flyin@%@ %@ super=%@ frame=%@ z=%.1f pz=%.1f pm43=%.1f idx=%lu tx=%.1f m11=%.3f anims=%@ superSub=%d superSuperSub=%d", ms,
                              iconView.icon.displayName, NSStringFromClass(iconView.superview.class), NSStringFromCGRect(iconView.frame),
                              layer.zPosition, presented.zPosition, presented.transform.m43, (unsigned long)[container.sublayers indexOfObjectIdenticalTo:layer],
                              layer.transform.m41, layer.transform.m11, [layer.animationKeys componentsJoinedByString:@","],
                              !CATransform3DIsIdentity(container.sublayerTransform), !CATransform3DIsIdentity(container.superlayer.sublayerTransform));
                    }];
                }
            });
        }
    });
}

static NSString *const CylinderHarnessFolderMatchMoveKey = @"SBFolderSourceViewTrackingMatchMoveAnimation";

@interface CylinderHarnessFolderTracer : NSObject
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) CFTimeInterval start;
@property (nonatomic) CFTimeInterval duration;
@property (nonatomic, weak) SBIconView *folderIconView;
@property (nonatomic, weak) UIView *zoomView;
@end

static CylinderHarnessFolderTracer *CylinderFolderTracer;

static UIView *CylinderHarnessFindFolderZoomView(void)
{
    for (UIView *view in CylinderHarnessAllViews(UIView.class)) {
        if ([view.layer animationForKey:CylinderHarnessFolderMatchMoveKey]) return view;
    }
    return nil;
}

/// The four corners of `view`'s bounds on screen, following every 3D transform on the way, from the presentation tree.
static NSString *CylinderHarnessPresentedQuad(UIView *view)
{
    if (!view.window) return @"(off window)";
    CALayer *root = view.window.layer.presentationLayer ?: view.window.layer;
    CALayer *layer = view.layer.presentationLayer ?: view.layer;
    CGRect b = layer.bounds;
    NSMutableArray *corners = [NSMutableArray array];
    for (NSValue *value in @[[NSValue valueWithCGPoint:CGPointMake(CGRectGetMinX(b), CGRectGetMinY(b))],
                             [NSValue valueWithCGPoint:CGPointMake(CGRectGetMaxX(b), CGRectGetMinY(b))],
                             [NSValue valueWithCGPoint:CGPointMake(CGRectGetMaxX(b), CGRectGetMaxY(b))],
                             [NSValue valueWithCGPoint:CGPointMake(CGRectGetMinX(b), CGRectGetMaxY(b))]]) {
        CGPoint p = [layer convertPoint:value.CGPointValue toLayer:root];
        [corners addObject:[NSString stringWithFormat:@"%.0f,%.0f", p.x, p.y]];
    }
    return [corners componentsJoinedByString:@" "];
}

/// Logs `view`'s subtree with each view's on-screen quad, layer class and transforms.
static void CylinderHarnessDumpTree(UIView *view, NSString *indent, NSUInteger depth)
{
    CALayer *layer = view.layer.presentationLayer ?: view.layer;
    NSLog(@"[CylinderHarness] tree %@%@ layer=%@ hidden=%d op=%.2f t=%d sub=%d quad[%@]", indent, view.class, view.layer.class, view.hidden,
          layer.opacity, !CATransform3DIsIdentity(layer.transform), !CATransform3DIsIdentity(layer.sublayerTransform), CylinderHarnessPresentedQuad(view));
    for (CALayer *sublayer in view.layer.sublayers) {
        if (sublayer.delegate == nil || ![(id)sublayer.delegate isKindOfClass:UIView.class]) {
            NSLog(@"[CylinderHarness] tree %@  (layer %@ op=%.2f)", indent, sublayer.class, sublayer.opacity);
        }
    }
    if (!depth) return;
    for (UIView *subview in view.subviews) CylinderHarnessDumpTree(subview, [indent stringByAppendingString:@"  "], depth - 1);
}

@implementation CylinderHarnessFolderTracer
- (void)tick:(CADisplayLink *)link
{
    static NSUInteger ticks;
    if (self.zoomView && (++ticks == 8 || ticks == 20)) CylinderHarnessDumpTree(self.zoomView, @"", 7);
    CFTimeInterval elapsed = CACurrentMediaTime() - self.start;
    if (elapsed > self.duration) {
        [link invalidate];
        self.link = nil;
        NSLog(@"[CylinderHarness] folder trace done");
        return;
    }
    if (!self.zoomView) {
        self.zoomView = CylinderHarnessFindFolderZoomView();
        CAAnimation *animation = [self.zoomView.layer animationForKey:CylinderHarnessFolderMatchMoveKey];
        if (animation) {
            id source = [animation valueForKey:@"sourceLayer"];
            NSLog(@"[CylinderHarness] folder match-move source=%@ delegate=%@ points=%@ targetsSuperlayer=%@ additive=%@ appliesX=%@ appliesY=%@",
                  [source class], [[source delegate] class], [animation valueForKey:@"sourcePoints"], [animation valueForKey:@"targetsSuperlayer"],
                  [animation valueForKey:@"additive"], [animation valueForKey:@"appliesX"], [animation valueForKey:@"appliesY"]);
        }
    }
    UIView *zoomView = self.zoomView;
    SBIconView *iconView = self.folderIconView;
    SBFolderView *folderView = CylinderHarnessRootFolderView();
    UIScrollView *scrollView = CylinderHarnessScrollView(folderView);
    CALayer *zoomLayer = zoomView.layer.presentationLayer ?: zoomView.layer;
    NSLog(@"[CylinderHarness] folder t=%4.0fms offset=%.1f icon[%@] zoom=%@ mm=%d sub=%d op=%.2f quad[%@] super=%@",
          elapsed * 1000, scrollView.contentOffset.x, CylinderHarnessPresentedQuad(iconView), zoomView.class,
          [zoomView.layer animationForKey:CylinderHarnessFolderMatchMoveKey] != nil, !CATransform3DIsIdentity(zoomView.layer.sublayerTransform),
          zoomLayer.opacity, zoomView ? CylinderHarnessPresentedQuad(zoomView) : @"", zoomView.superview.class);
}
@end

/// Opens the folder at `index` on `page` (the first folder when absent), presses Home after `openMs` to close it,
/// and drags the Home Screen `delayMs` into the close, tracing the zooming folder against its icon for `folderTraceMs`.
static void CylinderHarnessFolderClose(NSDictionary *args)
{
    SBFolderView *folderView = CylinderHarnessRootFolderView();
    SBIconListView *listView = [folderView iconListViewForPageIndex:CylinderHarnessPageIndex(folderView, args)];
    __block SBIconView *target = nil;
    [listView enumerateIconViewsUsingBlock:^(SBIconView *iconView, NSUInteger idx, BOOL *stop) {
        // Folder icon views have their own class only before iOS 14.
        SEL isFolderIcon = NSSelectorFromString(@"isFolderIcon");
        BOOL folder = [iconView.icon respondsToSelector:isFolderIcon] && ((BOOL (*)(id, SEL))objc_msgSend)(iconView.icon, isFolderIcon);
        BOOL wanted = args[@"index"] ? (NSInteger)idx == [args[@"index"] integerValue] : folder;
        if (wanted) {
            target = iconView;
            *stop = YES;
        }
    }];
    if (!target) {
        NSLog(@"[CylinderHarness] no folder icon on that page");
        return;
    }
    NSLog(@"[CylinderHarness] opening folder %@ %@", target.icon.displayName, target.class);
    ((void (*)(id, SEL))objc_msgSend)(target, @selector(performTap));

    double open = [(args[@"openMs"] ?: @1200) doubleValue];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(open * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [CylinderFolderTracer.link invalidate];
        CylinderFolderTracer = [CylinderHarnessFolderTracer new];
        CylinderFolderTracer.folderIconView = target;
        CylinderFolderTracer.start = CACurrentMediaTime();
        CylinderFolderTracer.duration = [(args[@"folderTraceMs"] ?: @1500) doubleValue] / 1000.0;
        CylinderFolderTracer.link = [CADisplayLink displayLinkWithTarget:CylinderFolderTracer selector:@selector(tick:)];
        [CylinderFolderTracer.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        CylinderHarnessHome();
        double delay = [args[@"delayMs"] doubleValue];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            CylinderHarnessScroll(args);
        });
    });
}

#pragma mark - Commit watch

static CFRunLoopObserverRef CylinderCommitObserver;
static NSString *CylinderCommitLast;
static NSUInteger CylinderCommitRepeats;

/// One line describing what the transaction just committed for the visible icon pages: how many icons the effect
/// left at identity, where the icons live, and the order overlapping icons draw in.
static NSString *CylinderHarnessCommitState(void)
{
    SBFolderView *folderView = CylinderHarnessRootFolderView();
    UIScrollView *scrollView = CylinderHarnessScrollView(folderView);
    NSInteger leading, trailing;
    [folderView getLeadingVisiblePageIndex:&leading trailingVisiblePageIndex:&trailing];
    NSMutableString *line = [NSMutableString stringWithFormat:@"scrolling=%d tracking=%d", [folderView isScrolling], scrollView.isTracking];
    if (leading == NSIntegerMax || trailing == NSIntegerMax) return line;
    NSInteger first = ((NSInteger (*)(id, SEL))objc_msgSend)(folderView, NSSelectorFromString(@"firstIconPageIndex"));
    for (NSInteger index = MAX(leading, first); index <= trailing; index++) {
        SBIconListView *listView = [folderView iconListViewForPageIndex:index];
        __block NSUInteger icons = 0, identity = 0, onPage = 0;
        NSMutableArray<CALayer *> *containers = [NSMutableArray array];
        [listView enumerateIconViewsUsingBlock:^(SBIconView *iconView, NSUInteger i, BOOL *stop) {
            icons++;
            if (CATransform3DIsIdentity(iconView.layer.transform)) identity++;
            if (iconView.superview == listView) onPage++;
            else if (iconView.superview && ![containers containsObject:iconView.superview.layer]) [containers addObject:iconView.superview.layer];
        }];
        [line appendFormat:@" | page%ld pageT=%d icons=%lu identity=%lu onPage=%lu", (long)(index - first),
            !CATransform3DIsIdentity(listView.layer.transform), (unsigned long)icons, (unsigned long)identity, (unsigned long)onPage];
        for (CALayer *container in containers) {
            BOOL sorts = [container respondsToSelector:NSSelectorFromString(@"sortsSublayers")]
                ? ((BOOL (*)(id, SEL))objc_msgSend)(container, NSSelectorFromString(@"sortsSublayers")) : -1;
            // Draw order: sublayers sorted by presented zPosition when the container sorts, else array order.
            NSArray<CALayer *> *order = container.sublayers;
            if (sorts) {
                order = [order sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(CALayer *a, CALayer *b) {
                    CGFloat za = (a.presentationLayer ?: a).zPosition, zb = (b.presentationLayer ?: b).zPosition;
                    return za < zb ? NSOrderedAscending : za > zb ? NSOrderedDescending : NSOrderedSame;
                }];
            }
            NSMutableString *indices = [NSMutableString string];
            for (CALayer *layer in order) [indices appendFormat:@"%lu.", (unsigned long)[container.sublayers indexOfObjectIdenticalTo:layer]];
            [line appendFormat:@" in %@ sorts=%d sub=%d order=%@", [container.delegate class], sorts,
                !CATransform3DIsIdentity(container.sublayerTransform), indices];
        }
    }
    return line;
}

@interface CATransaction (CylinderHarness)
+ (BOOL)addCommitHandler:(void (^)(void))handler forPhase:(int)phase;
@end

static void CylinderHarnessLogCommit(CFTimeInterval elapsed, NSString *when)
{
    UIScrollView *scrollView = CylinderHarnessScrollView(CylinderHarnessRootFolderView());
    NSString *state = CylinderHarnessCommitState();
    if ([state isEqualToString:CylinderCommitLast]) {
        CylinderCommitRepeats++;
        return;
    }
    NSLog(@"[CylinderHarness] commit t=%5.0fms %@ off=%.1f (+%lu same) %@", elapsed * 1000, when, scrollView.contentOffset.x,
          (unsigned long)CylinderCommitRepeats, state);
    CylinderCommitLast = state;
    CylinderCommitRepeats = 0;
}

/// Logs the state every Core Animation commit sent for `commitMs`, collapsing repeats. UIKit may commit outside the
/// run loop's before-waiting observers, so a post-commit handler samples each transaction instead.
static void CylinderHarnessStartCommitWatch(NSDictionary *args)
{
    if (CylinderCommitObserver) {
        CFRunLoopObserverInvalidate(CylinderCommitObserver);
        CFRelease(CylinderCommitObserver);
    }
    CFTimeInterval start = CACurrentMediaTime(), duration = [args[@"commitMs"] doubleValue] / 1000.0;
    CylinderCommitLast = nil;
    __block BOOL pending = NO;
    CylinderCommitObserver = CFRunLoopObserverCreateWithHandler(NULL, kCFRunLoopAllActivities, true, 0,
                                                              ^(CFRunLoopObserverRef observer, CFRunLoopActivity activity) {
        CFTimeInterval elapsed = CACurrentMediaTime() - start;
        if (elapsed > duration) {
            CFRunLoopObserverInvalidate(observer);
            NSLog(@"[CylinderHarness] commit watch done");
            return;
        }
        if (pending) return;
        pending = [CATransaction addCommitHandler:^{
            pending = NO;
            CylinderHarnessLogCommit(CACurrentMediaTime() - start, @"post");
        } forPhase:2];
    });
    CFRunLoopAddObserver(CFRunLoopGetMain(), CylinderCommitObserver, kCFRunLoopCommonModes);
}

#pragma mark - Disassembly

/// The function starts of the loaded image `header`, from its LC_FUNCTION_STARTS, which the shared cache keeps.
static NSArray<NSNumber *> *CylinderHarnessFunctionStarts(const struct mach_header_64 *header)
{
    intptr_t slide = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (_dyld_get_image_header(i) == (const struct mach_header *)header) slide = _dyld_get_image_vmaddr_slide(i);
    }
    const struct segment_command_64 *text = NULL, *linkedit = NULL;
    const struct linkedit_data_command *starts = NULL;
    const struct load_command *command = (const struct load_command *)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; i++, command = (const struct load_command *)((const char *)command + command->cmdsize)) {
        if (command->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
            if (!strcmp(segment->segname, SEG_TEXT)) text = segment;
            if (!strcmp(segment->segname, SEG_LINKEDIT)) linkedit = segment;
        } else if (command->cmd == LC_FUNCTION_STARTS) {
            starts = (const struct linkedit_data_command *)command;
        }
    }
    NSMutableArray<NSNumber *> *result = [NSMutableArray array];
    if (!text || !linkedit || !starts || !starts->datasize) return result;
    const uint8_t *p = (const uint8_t *)(linkedit->vmaddr + slide + starts->dataoff - linkedit->fileoff);
    const uint8_t *end = p + starts->datasize;
    uint64_t address = text->vmaddr + slide;
    while (p < end) {
        uint64_t delta = 0;
        int shift = 0;
        do {
            delta |= (uint64_t)(*p & 0x7f) << shift;
            shift += 7;
        } while (*p++ & 0x80 && p < end);
        if (!delta) break;
        address += delta;
        [result addObject:@(address)];
    }
    return result;
}

static int64_t CylinderHarnessSignExtend(uint64_t value, int bits)
{
    return (int64_t)(value << (64 - bits)) >> (64 - bits);
}

/// Names the selector an objc_msgSend stub at `target` sends, or the symbol a dyld stub there jumps to.
static NSString *CylinderHarnessStubName(uint64_t target)
{
    const uint32_t *code = (const uint32_t *)target;
    uint32_t adrp = code[0], ldr = code[1];
    int rd = adrp & 0x1f;
    if ((adrp & 0x9f000000) == 0x90000000 && (ldr & 0xffc00000) == 0xf9400000 && (ldr & 0x1f) == rd && ((ldr >> 5) & 0x1f) == rd) {
        uint64_t page = (target & ~0xfffULL) + (CylinderHarnessSignExtend(((adrp >> 5) & 0x7ffff) << 2 | ((adrp >> 29) & 3), 21) << 12);
        uint64_t slot = page + ((ldr >> 10) & 0xfff) * 8;
        if (rd == 1) return [NSString stringWithFormat:@"objc_msgSend$%s", sel_getName(*(SEL *)slot)];
        if (rd == 16 || rd == 17) {
            Dl_info info;
            if (dladdr(*(void **)slot, &info) && info.dli_sname) return [NSString stringWithFormat:@"%s", info.dli_sname];
        }
    }
    Dl_info info;
    if (dladdr((void *)target, &info) && info.dli_sname && (uint64_t)info.dli_saddr == target) return @(info.dli_sname);
    return nil;
}

/// Writes the words of the function at `address` and notes on its calls and data references to
/// ~/Library/Cylinder/disasm/<name>.json, for llvm-objdump on the Mac. The simulator's shared cache keeps the
/// selector stubs that a device cache extracted for Hopper loses.
static void CylinderHarnessDisassemble(uint64_t address, NSString *name, NSUInteger maximum)
{
    Dl_info image;
    if (!dladdr((void *)address, &image)) {
        NSLog(@"[CylinderHarness] disasm: %#llx is in no image", address);
        return;
    }
    const struct mach_header_64 *header = image.dli_fbase;
    NSArray<NSNumber *> *starts = CylinderHarnessFunctionStarts(header);
    uint64_t end = address + maximum * 4;
    for (NSNumber *start in starts) {
        if (start.unsignedLongLongValue > address) {
            end = MIN(end, start.unsignedLongLongValue);
            break;
        }
    }

    NSMutableDictionary<NSNumber *, NSString *> *ivars = [NSMutableDictionary dictionary];
    unsigned int classCount = 0;
    const char **classNames = objc_copyClassNamesForImage(image.dli_fname, &classCount);
    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = objc_getClass(classNames[i]);
        unsigned int ivarCount = 0;
        Ivar *list = class_copyIvarList(cls, &ivarCount);
        // ivar_t starts with a pointer to the offset variable that code loads.
        for (unsigned int j = 0; j < ivarCount; j++) {
            ivars[@((uint64_t)*(int32_t **)list[j])] = [NSString stringWithFormat:@"%s.%s", classNames[i], ivar_getName(list[j])];
        }
        free(list);
    }
    free(classNames);

    unsigned long selrefsSize = 0, classrefsSize = 0, superrefsSize = 0, cfstringsSize = 0;
    uint8_t *selrefs = getsectiondata(header, "__DATA_CONST", "__objc_selrefs", &selrefsSize) ?: getsectiondata(header, "__DATA", "__objc_selrefs", &selrefsSize);
    uint8_t *classrefs = getsectiondata(header, "__DATA_CONST", "__objc_classrefs", &classrefsSize) ?: getsectiondata(header, "__DATA", "__objc_classrefs", &classrefsSize);
    uint8_t *superrefs = getsectiondata(header, "__DATA_CONST", "__objc_superrefs", &superrefsSize) ?: getsectiondata(header, "__DATA", "__objc_superrefs", &superrefsSize);
    uint8_t *cfstrings = getsectiondata(header, "__DATA_CONST", "__cfstring", &cfstringsSize) ?: getsectiondata(header, "__DATA", "__cfstring", &cfstringsSize);
    NSSet<NSNumber *> *startSet = [NSSet setWithArray:starts];
    NSString * (^describe)(uint64_t) = ^NSString *(uint64_t target) {
        if (ivars[@(target)]) return [@"ivar " stringByAppendingString:ivars[@(target)]];
        if (selrefs && target >= (uint64_t)selrefs && target < (uint64_t)selrefs + selrefsSize) return [NSString stringWithFormat:@"@selector(%s)", sel_getName(*(SEL *)target)];
        if ((classrefs && target >= (uint64_t)classrefs && target < (uint64_t)classrefs + classrefsSize) ||
            (superrefs && target >= (uint64_t)superrefs && target < (uint64_t)superrefs + superrefsSize)) {
            return [NSString stringWithFormat:@"class %s", class_getName((__bridge Class)*(void **)target)];
        }
        if (cfstrings && target >= (uint64_t)cfstrings && target < (uint64_t)cfstrings + cfstringsSize) return [NSString stringWithFormat:@"@\"%@\"", (__bridge NSString *)(void *)target];
        if ([startSet containsObject:@(target)]) {
            Dl_info info;
            if (dladdr((void *)target, &info) && info.dli_sname && (uint64_t)info.dli_saddr == target) return [NSString stringWithFormat:@"%s @%llx", info.dli_sname, target];
            return [NSString stringWithFormat:@"sub_%llx", target];
        }
        Dl_info info;
        if (dladdr((void *)target, &info) && info.dli_sname && (uint64_t)info.dli_saddr == target) return @(info.dli_sname);
        // A pointer slot, such as a class reference into another image.
        if (target % 8 == 0 && dladdr((void *)target, &info) && !strcmp(info.dli_fname, image.dli_fname) &&
            dladdr(*(void **)target, &info) && info.dli_sname && (uint64_t)info.dli_saddr == (uint64_t)*(void **)target) {
            return [NSString stringWithFormat:@"&%s", info.dli_sname];
        }
        return nil;
    };

    NSMutableArray<NSNumber *> *words = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSString *> *notes = [NSMutableDictionary dictionary];
    uint64_t pages[32] = {0};
    for (uint64_t pc = address; pc < end; pc += 4) {
        uint32_t insn = *(const uint32_t *)pc;
        [words addObject:@(insn)];
        NSString *note = nil;
        if ((insn & 0x7c000000) == 0x14000000) {
            // B and BL.
            uint64_t target = pc + (CylinderHarnessSignExtend(insn & 0x3ffffff, 26) << 2);
            if (target < address || target >= end) note = CylinderHarnessStubName(target) ?: describe(target);
        } else if ((insn & 0x9f000000) == 0x90000000) {
            pages[insn & 0x1f] = (pc & ~0xfffULL) + (CylinderHarnessSignExtend(((insn >> 5) & 0x7ffff) << 2 | ((insn >> 29) & 3), 21) << 12);
        } else if ((insn & 0x9f000000) == 0x10000000) {
            // ADR.
            note = describe(pc + CylinderHarnessSignExtend(((insn >> 5) & 0x7ffff) << 2 | ((insn >> 29) & 3), 21));
        } else {
            int rn = (insn >> 5) & 0x1f;
            uint64_t target = 0;
            if ((insn & 0xffc00000) == 0xf9400000 || (insn & 0xffc00000) == 0xf9000000) target = pages[rn] + ((insn >> 10) & 0xfff) * 8;
            else if ((insn & 0xffc00000) == 0xb9800000 || (insn & 0xffc00000) == 0xb9400000) target = pages[rn] + ((insn >> 10) & 0xfff) * 4;
            else if ((insn & 0xffc00000) == 0xfd400000) target = pages[rn] + ((insn >> 10) & 0xfff) * 8;
            else if ((insn & 0xff800000) == 0x91000000 && !(insn & (1 << 22))) target = pages[rn] + ((insn >> 10) & 0xfff);
            if (target && pages[rn]) {
                note = describe(target);
                if (!note && (insn & 0xffc00000) == 0xfd400000) note = [NSString stringWithFormat:@"= %g", *(double *)target];
            }
        }
        if (note) notes[[NSString stringWithFormat:@"%llx", pc]] = note;
    }

    NSDictionary *output = @{@"start": [NSString stringWithFormat:@"%llx", address], @"words": words, @"notes": notes,
                             @"image": @(image.dli_fname)};
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Cylinder/disasm"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSJSONSerialization dataWithJSONObject:output options:0 error:nil] writeToFile:[dir stringByAppendingPathComponent:[name stringByAppendingString:@".json"]] atomically:YES];
    NSLog(@"[CylinderHarness] disasm %@: %lu instructions at %#llx, %lu notes", name, (unsigned long)words.count, address, (unsigned long)notes.count);
}

static void CylinderHarnessRun(void)
{
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Cylinder/.harness.plist"];
    NSDictionary *args = [NSDictionary dictionaryWithContentsOfFile:path];
    NSString *command = args[@"command"];
    NSLog(@"[CylinderHarness] command %@ %@", command, args);
    CylinderHarnessDisableHandoff = [args[@"noHandoff"] boolValue];
    if (args[@"noSBHide"]) CylinderHarnessDisableSpringBoardHide = [args[@"noSBHide"] boolValue];
    if (args[@"noChurn"]) CylinderHarnessDisableChurn = [args[@"noChurn"] boolValue];
    if (args[@"traceAdds"]) CylinderHarnessTraceAdds = [args[@"traceAdds"] boolValue];
    if (args[@"audit"]) CylinderHarnessAuditIcons = [args[@"audit"] boolValue];
    if (args[@"keepOffRange"]) CylinderHarnessKeepOffRangePages = [args[@"keepOffRange"] boolValue];
    if (args[@"noHide"]) CylinderHarnessDisableHide = [args[@"noHide"] boolValue];
    CylinderHarnessScheduleShots(args);
    CylinderHarnessStartTrace(args);
    CylinderHarnessScheduleProbe(args);
    if (args[@"watchMs"] && ![command isEqualToString:@"watch"]) CylinderHarnessStartWatch(args);
    if (args[@"commitMs"]) CylinderHarnessStartCommitWatch(args);

    if ([command isEqualToString:@"launch"]) {
        CylinderHarnessLaunch(args);
    } else if ([command isEqualToString:@"home"]) {
        CylinderHarnessHome();
    } else if ([command isEqualToString:@"scroll"]) {
        CylinderHarnessScroll(args);
    } else if ([command isEqualToString:@"homeScroll"]) {
        CylinderHarnessHome();
        int64_t delay = (int64_t)([args[@"delayMs"] doubleValue] * NSEC_PER_MSEC);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay), dispatch_get_main_queue(), ^{
            CylinderHarnessDump(@"before scroll");
            CylinderHarnessScroll(args);
        });
    } else if ([command isEqualToString:@"flyInScroll"]) {
        CylinderHarnessFlyInScroll(args);
    } else if ([command isEqualToString:@"folderClose"]) {
        CylinderHarnessFolderClose(args);
    } else if ([command isEqualToString:@"homeOutBack"]) {
        CylinderHarnessHome();
        double delay = [args[@"delayMs"] doubleValue];
        double back = [(args[@"backMs"] ?: @700) doubleValue];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            NSMutableDictionary *step = [args mutableCopy];
            step[@"fraction"] = args[@"fraction"] ?: @0.6;
            CylinderHarnessScroll(step);
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((delay + back) * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            NSMutableDictionary *step = [args mutableCopy];
            step[@"page"] = @([args[@"page"] integerValue] + 1);
            step[@"fraction"] = @(-[(args[@"backFraction"] ?: @0.6) doubleValue]);
            step[@"fromCurrent"] = @YES;
            CylinderHarnessScroll(step);
        });
    } else if ([command isEqualToString:@"homeShuttle"]) {
        CylinderHarnessHome();
        NSMutableDictionary *shuttle = [args mutableCopy];
        shuttle[@"command"] = @"shuttle";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([args[@"delayMs"] doubleValue] * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            CylinderHarnessShuttle(shuttle);
        });
    } else if ([command isEqualToString:@"shuttle"]) {
        CylinderHarnessShuttle(args);
    } else if ([command isEqualToString:@"pose"]) {
        CylinderHarnessPose(args);
    } else if ([command isEqualToString:@"bench"]) {
        CylinderHarnessBench(args);
    } else if ([command isEqualToString:@"slow"]) {
        _SetUIAnimationDragCoefficient([(args[@"factor"] ?: @1) floatValue]);
    } else if ([command isEqualToString:@"page"]) {
        SBFolderView *folderView = CylinderHarnessRootFolderView();
        ((void (*)(id, SEL, NSInteger, BOOL))objc_msgSend)(folderView, NSSelectorFromString(@"setCurrentPageIndex:animated:"),
                                                          CylinderHarnessPageIndex(folderView, args), YES);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1500 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            CylinderHarnessState(@"after page change");
        });
    } else if ([command isEqualToString:@"geom"]) {
        SBFolderView *folderView = CylinderHarnessRootFolderView();
        SBIconListView *listView = [folderView iconListViewForPageIndex:CylinderHarnessPageIndex(folderView, args)];
        NSLog(@"[CylinderHarness] list frame=%@ bounds=%@", NSStringFromCGRect(listView.frame), NSStringFromCGRect(listView.bounds));
        [listView enumerateIconViewsUsingBlock:^(SBIconView *iconView, NSUInteger index, BOOL *stop) {
            NSLog(@"[CylinderHarness] icon %@ frame=%@ center=%@ bounds=%@", iconView.icon.displayName,
                  NSStringFromCGRect(iconView.frame), NSStringFromCGPoint(iconView.center), NSStringFromCGRect(iconView.bounds));
        }];
    } else if ([command isEqualToString:@"watch"]) {
        CylinderHarnessStartWatch(args);
    } else if ([command isEqualToString:@"coords"]) {
        SBFolderView *folderView = CylinderHarnessRootFolderView();
        SBIconListView *listView = [folderView iconListViewForPageIndex:CylinderHarnessPageIndex(folderView, args)];
        NSLog(@"[CylinderHarness] rows=%lu columns=%lu max=%lu", (unsigned long)listView.iconRowsForCurrentOrientation,
              (unsigned long)listView.iconColumnsForCurrentOrientation, (unsigned long)listView.maximumIconCount);
        for (NSArray *probe in @[@[@1, @1], @[@2, @1], @[@1, @2]]) {
            SBIconCoordinate c = {[probe[0] unsignedIntegerValue], [probe[1] unsignedIntegerValue]};
            NSLog(@"[CylinderHarness] origin(%@,%@)=%@", probe[0], probe[1], NSStringFromCGPoint([listView originForIconAtCoordinate:c]));
        }
        [listView enumerateIconViewsUsingBlock:^(SBIconView *iconView, NSUInteger index, BOOL *stop) {
            SBIconCoordinate c = [listView coordinateForIcon:iconView.icon];
            NSLog(@"[CylinderHarness] %lu %@ coord=(%lu,%lu) frame=%@", (unsigned long)index, iconView.icon.displayName,
                  (unsigned long)c.first, (unsigned long)c.second, NSStringFromCGRect(iconView.frame));
        }];
    } else if ([command isEqualToString:@"order"]) {
        SBFolderView *folderView = CylinderHarnessRootFolderView();
        SBIconListView *listView = [folderView iconListViewForPageIndex:CylinderHarnessPageIndex(folderView, args)];
        NSMutableArray *subviews = [NSMutableArray array];
        for (UIView *view in listView.subviews) {
            [subviews addObject:[view respondsToSelector:@selector(icon)] ? (((SBIconView *)view).icon.displayName ?: @"?") : [NSString stringWithFormat:@"%@ %@ hidden=%d alpha=%.2f", NSStringFromClass(view.class), NSStringFromCGRect(view.frame), view.hidden, view.alpha]];
        }
        NSMutableArray *icons = [NSMutableArray array];
        [listView enumerateIconViewsUsingBlock:^(SBIconView *iconView, NSUInteger index, BOOL *stop) {
            [icons addObject:iconView.icon.displayName ?: @"?"];
        }];
        NSLog(@"[CylinderHarness] subviews: %@", [subviews componentsJoinedByString:@", "]);
        NSLog(@"[CylinderHarness] icons: %@", [icons componentsJoinedByString:@", "]);
    } else if ([command isEqualToString:@"disasm"]) {
        // `class` and `selector` (`meta` for a class method), or a hex `address`, such as a sub_ from an earlier dump.
        uint64_t address = strtoull([args[@"address"] UTF8String] ?: "0", NULL, 16);
        if (!address) {
            Class cls = objc_getClass([args[@"class"] UTF8String]);
            if ([args[@"meta"] boolValue]) cls = object_getClass(cls);
            Method method = class_getInstanceMethod(cls, NSSelectorFromString(args[@"selector"]));
            address = (uint64_t)method_getImplementation(method);
        }
        if (address) CylinderHarnessDisassemble(address, args[@"name"] ?: @"disasm", [(args[@"max"] ?: @4000) unsignedIntegerValue]);
        else NSLog(@"[CylinderHarness] disasm: no such method");
    } else if ([command isEqualToString:@"methods"]) {
        for (Class cls = objc_getClass([args[@"class"] UTF8String]); cls && cls != NSObject.class; cls = class_getSuperclass(cls)) {
            for (int meta = 0; meta < 2; meta++) {
                unsigned int count = 0;
                Method *methods = class_copyMethodList(meta ? object_getClass(cls) : cls, &count);
                for (unsigned int i = 0; i < count; i++) {
                    NSLog(@"[CylinderHarness] method %c[%s %s] %p %s", meta ? '+' : '-', class_getName(cls), sel_getName(method_getName(methods[i])),
                          method_getImplementation(methods[i]), method_getTypeEncoding(methods[i]));
                }
                free(methods);
            }
            unsigned int ivarCount = 0;
            Ivar *list = class_copyIvarList(cls, &ivarCount);
            for (unsigned int i = 0; i < ivarCount; i++) {
                NSLog(@"[CylinderHarness] ivar %s.%s %s @%td", class_getName(cls), ivar_getName(list[i]), ivar_getTypeEncoding(list[i]), ivar_getOffset(list[i]));
            }
            free(list);
            if (![args[@"supers"] boolValue]) break;
        }
    } else if ([command isEqualToString:@"state"]) {
        CylinderHarnessState(@"state");
    } else if ([command isEqualToString:@"dump"]) {
        CylinderHarnessDump(@"dump");
    } else if ([command isEqualToString:@"reset"]) {
        CylinderHarnessReset();
    }
}

static IMP CylinderOrigDidAddSubview;
static IMP CylinderOrigWillRemoveSubview;

static void CylinderHarnessLogMembership(UIView *list, UIView *view, NSString *what)
{
    if (!CylinderHarnessTraceAdds || ![view respondsToSelector:@selector(icon)]) return;
    NSArray *stack = [NSThread callStackSymbols];
    NSMutableArray *frames = [NSMutableArray array];
    for (NSUInteger i = 2; i < MIN(stack.count, 14); i++) {
        NSString *frame = stack[i];
        NSRange r = [frame rangeOfString:@"0x"];
        NSRange sp = r.location == NSNotFound ? r : [frame rangeOfString:@" " options:0 range:NSMakeRange(r.location, frame.length - r.location)];
        [frames addObject:sp.location == NSNotFound ? frame : [frame substringFromIndex:sp.location + 1]];
    }
    NSLog(@"[CylinderTrace] %@ %@ %p list=%p subviews=%lu <- %@", what, ((SBIconView *)view).icon.displayName, view, list,
          (unsigned long)list.subviews.count, [frames componentsJoinedByString:@" | "]);
}

static void CylinderHarnessDidAddSubview(UIView *self, SEL _cmd, UIView *view)
{
    ((void (*)(id, SEL, id))CylinderOrigDidAddSubview)(self, _cmd, view);
    CylinderHarnessLogMembership(self, view, @"add");
}

static void CylinderHarnessWillRemoveSubview(UIView *self, SEL _cmd, UIView *view)
{
    CylinderHarnessLogMembership(self, view, @"remove");
    ((void (*)(id, SEL, id))CylinderOrigWillRemoveSubview)(self, _cmd, view);
}

static IMP CylinderOrigIsDragging;
static IMP CylinderOrigIsTracking;

static BOOL CylinderHarnessIsDragging(UIScrollView *self, SEL _cmd)
{
    if (self == CylinderDraggedScrollView) return YES;
    return ((BOOL (*)(id, SEL))CylinderOrigIsDragging)(self, _cmd);
}

static BOOL CylinderHarnessIsTracking(UIScrollView *self, SEL _cmd)
{
    if (self == CylinderDraggedScrollView) return YES;
    return ((BOOL (*)(id, SEL))CylinderOrigIsTracking)(self, _cmd);
}

__attribute__((constructor)) static void CylinderHarnessInit(void)
{
    CylinderOrigIsDragging = method_setImplementation(class_getInstanceMethod(UIScrollView.class, @selector(isDragging)), (IMP)CylinderHarnessIsDragging);
    CylinderOrigIsTracking = method_setImplementation(class_getInstanceMethod(UIScrollView.class, @selector(isTracking)), (IMP)CylinderHarnessIsTracking);
    Class listClass = objc_getClass("SBIconListView");
    CylinderOrigDidAddSubview = class_getMethodImplementation(listClass, @selector(didAddSubview:));
    class_replaceMethod(listClass, @selector(didAddSubview:), (IMP)CylinderHarnessDidAddSubview, "v@:@");
    CylinderOrigWillRemoveSubview = class_getMethodImplementation(listClass, @selector(willRemoveSubview:));
    class_replaceMethod(listClass, @selector(willRemoveSubview:), (IMP)CylinderHarnessWillRemoveSubview, "v@:@");
    int token;
    notify_register_dispatch("com.ryannair05.cylinder.harness", &token, dispatch_get_main_queue(), ^(__unused int t) {
        CylinderHarnessRun();
    });
}

#endif
