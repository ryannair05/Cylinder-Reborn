#import "CylinderDebug.h"

#import "CylinderPageContext.h"
#import "CylinderPageCoordinator.h"
#import "tweak.h"
#import "../Defines.h"

#import <dlfcn.h>
#import <execinfo.h>
#import <notify.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>

#define CYLINDER_DEBUG_VERSION @"1.2.0+debug1"
/// Logs past this size start over in debug.old.log so a long-running SpringBoard cannot fill the disk.
static const unsigned long long CylinderDebugMaxLogSize = 16 * 1024 * 1024;

static dispatch_queue_t CylinderDebugQueue;
static NSFileHandle *CylinderDebugHandle;
static unsigned long long CylinderDebugWritten;
static CFTimeInterval CylinderDebugStart;
static BOOL CylinderDebugFix;

#pragma mark - Logging

static void CylinderDebugOpenLog(void)
{
    NSFileManager *manager = NSFileManager.defaultManager;
    [manager createDirectoryAtPath:CYLINDER_DEBUG_LOG_DIR withIntermediateDirectories:YES attributes:nil error:nil];

    unsigned long long size = [[manager attributesOfItemAtPath:CYLINDER_DEBUG_LOG_PATH error:nil] fileSize];
    if (size > CylinderDebugMaxLogSize) {
        NSString *old = CYLINDER_DEBUG_LOG_DIR @"debug.old.log";
        [manager removeItemAtPath:old error:nil];
        [manager moveItemAtPath:CYLINDER_DEBUG_LOG_PATH toPath:old error:nil];
        size = 0;
    }
    if (![manager fileExistsAtPath:CYLINDER_DEBUG_LOG_PATH]) {
        [manager createFileAtPath:CYLINDER_DEBUG_LOG_PATH contents:nil attributes:nil];
    }
    CylinderDebugHandle = [NSFileHandle fileHandleForWritingAtPath:CYLINDER_DEBUG_LOG_PATH];
    [CylinderDebugHandle seekToEndOfFile];
    CylinderDebugWritten = size;
}

void CylinderDebugLog(NSString *format, ...)
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
#ifdef CYLINDER_SIMJECT
    // The simulator has no /var/mobile, so its log goes to the unified log instead.
    for (NSString *part in [message componentsSeparatedByString:@"\n"]) NSLog(@"[CylinderDebug] %@", part);
    return;
#endif

    NSString *line = [NSString stringWithFormat:@"%10.3f%@ %@\n", CACurrentMediaTime() - CylinderDebugStart,
                      NSThread.isMainThread ? @"" : @" [bg]", message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (!CylinderDebugQueue) return;
    dispatch_async(CylinderDebugQueue, ^{
        if (!CylinderDebugHandle) return;
        if (CylinderDebugWritten > CylinderDebugMaxLogSize) {
            [CylinderDebugHandle closeFile];
            CylinderDebugOpenLog();
        }
        // NSFileHandle writes straight to the descriptor, so a SpringBoard crash keeps every line written so far.
        [CylinderDebugHandle writeData:data];
        CylinderDebugWritten += data.length;
    });
}

NSString *CylinderDebugBacktrace(NSUInteger depth)
{
    void *frames[64];
    int count = backtrace(frames, 64);
    NSMutableString *result = [NSMutableString string];
    // Frame 0 is this function. Private SpringBoard symbols are often <redacted>, so each frame also
    // carries its image and offset, which can be symbolicated against an iOS 14 shared cache later.
    for (int i = 1; i < count && (NSUInteger)i <= depth; i++) {
        Dl_info info;
        if (dladdr(frames[i], &info) && info.dli_fname) {
            const char *image = strrchr(info.dli_fname, '/');
            image = image ? image + 1 : info.dli_fname;
            uintptr_t offset = (uintptr_t)frames[i] - (uintptr_t)info.dli_fbase;
            [result appendFormat:@"\n        #%d %s+0x%lx %s", i, image, (unsigned long)offset, info.dli_sname ?: "?"];
        } else {
            [result appendFormat:@"\n        #%d %p", i, frames[i]];
        }
    }
    return result;
}

NSString *CylinderDebugDescribeTransform(CATransform3D t)
{
    if (CATransform3DIsIdentity(t)) return @"identity";
    CGFloat sx = sqrt(t.m11 * t.m11 + t.m12 * t.m12 + t.m13 * t.m13);
    CGFloat sy = sqrt(t.m21 * t.m21 + t.m22 * t.m22 + t.m23 * t.m23);
    CGFloat rotation = atan2(t.m12, t.m11) * 180 / M_PI;
    return [NSString stringWithFormat:@"scale=%.3fx%.3f rotZ=%.1f t=(%.1f,%.1f,%.1f) m34=%.5f m44=%.3f",
            sx, sy, rotation, t.m41, t.m42, t.m43, t.m34, t.m44];
}

static NSString *CylinderDebugIconName(id icon)
{
    if (!icon) return @"(no icon)";
    for (NSString *name in @[@"displayName", @"applicationBundleID", @"nodeIdentifier", @"uniqueIdentifier"]) {
        SEL selector = NSSelectorFromString(name);
        if (![icon respondsToSelector:selector]) continue;
        id value = ((id (*)(id, SEL))objc_msgSend)(icon, selector);
        if ([value isKindOfClass:NSString.class] && [value length]) return value;
    }
    return NSStringFromClass([icon class]);
}

NSString *CylinderDebugDescribeView(UIView *view)
{
    if (!view) return @"(nil)";
    NSString *name = @"";
    if ([view respondsToSelector:@selector(icon)]) {
        name = [NSString stringWithFormat:@" '%@'", CylinderDebugIconName(((SBIconView *)view).icon)];
    }
    return [NSString stringWithFormat:@"%@<%p>%@", NSStringFromClass(view.class), view, name];
}

#pragma mark - Ivars

static Ivar CylinderDebugIvar(id object, const char *name)
{
    return object ? class_getInstanceVariable(object_getClass(object), name) : NULL;
}

/// Reads a BOOL ivar, or returns -1 when SpringBoard has no such ivar or it is not a BOOL.
static int CylinderDebugBoolIvar(id object, const char *name)
{
    Ivar ivar = CylinderDebugIvar(object, name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type || (type[0] != 'B' && type[0] != 'c')) return -1;
    return *((uint8_t *)(__bridge void *)object + ivar_getOffset(ivar)) ? 1 : 0;
}

static id CylinderDebugObjectIvar(id object, const char *name)
{
    Ivar ivar = CylinderDebugIvar(object, name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    if (!type || type[0] != '@') return nil;
    return object_getIvar(object, ivar);
}

static UIScrollView *CylinderDebugScrollViewOf(SBFolderView *folderView)
{
    if ([folderView respondsToSelector:@selector(scrollView)]) return folderView.scrollView;
    id scrollView = CylinderDebugObjectIvar(folderView, "_scrollView");
    return [scrollView isKindOfClass:UIScrollView.class] ? scrollView : nil;
}

NSString *CylinderDebugDescribeFolderScrollState(SBFolderView *folderView)
{
    if (!folderView) return @"folder=(nil)";
    UIScrollView *scrollView = CylinderDebugScrollViewOf(folderView);
    id blocks = CylinderDebugObjectIvar(folderView, "_scrollCompletionBlocks");
    id overrides = CylinderDebugObjectIvar(folderView, "_scrollViewIsScrollingOverrides");
    return [NSString stringWithFormat:@"folder=%@<%p> isScrolling=%d _wasScrolling=%d completionBlocks=%@ overrides=%@ "
            @"sv.tracking=%d sv.dragging=%d sv.decelerating=%d sv.offset=%.1f sv.width=%.1f",
            NSStringFromClass(folderView.class), folderView,
            [folderView respondsToSelector:@selector(isScrolling)] ? [folderView isScrolling] : -1,
            CylinderDebugBoolIvar(folderView, "_wasScrolling"),
            blocks ? @([blocks count]) : @"n/a",
            overrides ? [[overrides allObjects] componentsJoinedByString:@","] : @"n/a",
            scrollView.isTracking, scrollView.isDragging, scrollView.isDecelerating,
            scrollView.contentOffset.x, CGRectGetWidth(scrollView.bounds)];
}

#pragma mark - Fix flag

void CylinderDebugReloadFixFlag(void)
{
    BOOL fix = [NSFileManager.defaultManager fileExistsAtPath:CYLINDER_DEBUG_FIX_PATH];
    if (fix != CylinderDebugFix) CylinderDebugLog(@"[fix] session-end fallback %@", fix ? @"ON" : @"OFF");
    CylinderDebugFix = fix;
}

BOOL CylinderDebugFixEnabled(void)
{
    return CylinderDebugFix;
}

#pragma mark - Hooking helpers

/// "v24@0:8B16" becomes "v@:B", so a hook only goes in when SpringBoard's method has the signature it expects.
static NSString *CylinderDebugSimplifiedEncoding(const char *encoding)
{
    NSMutableString *result = [NSMutableString string];
    for (const char *c = encoding; c && *c; c++) {
        if (isdigit(*c) || strchr("rnNoORV", *c)) continue;
        [result appendFormat:@"%c", *c];
    }
    return result;
}

static BOOL CylinderDebugClassImplements(Class cls, SEL selector)
{
    unsigned int count;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count && !found; i++) found = method_getName(methods[i]) == selector;
    free(methods);
    return found;
}

static IMP *CylinderDebugNewOrig(void)
{
    return calloc(1, sizeof(IMP));
}

static BOOL CylinderDebugHook(Class cls, NSString *selectorName, NSString *types, IMP *orig, id block)
{
    SEL selector = NSSelectorFromString(selectorName);
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!method) {
        CylinderDebugLog(@"[hook] skip -[%@ %@]: missing", cls ? NSStringFromClass(cls) : @"(no class)", selectorName);
        return NO;
    }
    NSString *encoding = CylinderDebugSimplifiedEncoding(method_getTypeEncoding(method));
    if (![encoding isEqualToString:types]) {
        CylinderDebugLog(@"[hook] skip -[%@ %@]: encoding %@ != expected %@", NSStringFromClass(cls), selectorName, encoding, types);
        return NO;
    }
#ifdef CYLINDER_SIMJECT
    // The simulator build has no Substrate.
    if (CylinderDebugClassImplements(cls, selector)) {
        *orig = method_setImplementation(method, imp_implementationWithBlock(block));
    } else {
        *orig = method_getImplementation(method);
        class_addMethod(cls, selector, imp_implementationWithBlock(block), method_getTypeEncoding(method));
    }
#else
    MSHookMessageEx(cls, selector, imp_implementationWithBlock(block), orig);
#endif
    CylinderDebugLog(@"[hook] -[%@ %@] (%@)", NSStringFromClass(cls), selectorName,
                     CylinderDebugClassImplements(cls, selector) ? @"own" : @"inherited");
    return YES;
}

#pragma mark - Runtime dump

static void CylinderDebugDumpClass(NSString *className, NSString *pattern, BOOL ivars)
{
    Class cls = NSClassFromString(className);
    if (!cls) {
        CylinderDebugLog(@"[runtime] %@: class missing", className);
        return;
    }
    NSMutableString *chain = [NSMutableString string];
    for (Class c = class_getSuperclass(cls); c; c = class_getSuperclass(c)) [chain appendFormat:@" : %@", NSStringFromClass(c)];

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    unsigned int count;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        if ([regex firstMatchInString:name options:0 range:NSMakeRange(0, name.length)]) {
            [names addObject:[NSString stringWithFormat:@"%@ %@", name, CylinderDebugSimplifiedEncoding(method_getTypeEncoding(methods[i]))]];
        }
    }
    free(methods);
    [names sortUsingSelector:@selector(compare:)];
    CylinderDebugLog(@"[runtime] %@%@ matching /%@/: %lu\n    %@", className, chain, pattern, (unsigned long)names.count,
                     [names componentsJoinedByString:@"\n    "]);

    if (!ivars) return;
    NSMutableArray<NSString *> *ivarNames = [NSMutableArray array];
    Ivar *list = class_copyIvarList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        [ivarNames addObject:[NSString stringWithFormat:@"%s %s", ivar_getName(list[i]), ivar_getTypeEncoding(list[i])]];
    }
    free(list);
    CylinderDebugLog(@"[runtime] %@ ivars:\n    %@", className, [ivarNames componentsJoinedByString:@"\n    "]);
}

static NSArray<Class> *CylinderDebugSubclassesOf(Class base)
{
    NSMutableArray<Class> *result = [NSMutableArray array];
    if (!base) return result;
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        for (Class c = class_getSuperclass(classes[i]); c; c = class_getSuperclass(c)) {
            if (c != base) continue;
            [result addObject:classes[i]];
            break;
        }
    }
    free(classes);
    return result;
}

static void CylinderDebugDumpRuntime(void)
{
    NSString *scrolling = @"scroll|visib|page|column|recycl";
    CylinderDebugDumpClass(@"SBFolderView", scrolling, YES);
    CylinderDebugDumpClass(@"SBRootFolderView", scrolling, NO);
    CylinderDebugDumpClass(@"SBIconScrollView", @".", NO);
    CylinderDebugDumpClass(@"SBIconListView", @"alpha|layout|visib|recycl|enumerate|iconView|subview|coordinate", NO);
    CylinderDebugDumpClass(@"SBIconView", @"tap|highlight|crossfade|launch|alpha|allow|touch|gesture|hidden|visib", NO);
    CylinderDebugDumpClass(@"SBIconController", @"tap|launch|allow|animat|scroll|zoom|fly", NO);
    CylinderDebugDumpClass(@"SBHIconManager", @"tap|launch|allow|animat|scroll|zoom|fly", NO);
    CylinderDebugDumpClass(@"SBIconAnimator", @".", YES);

    Class animator = NSClassFromString(@"SBIconAnimator");
    for (Class cls in CylinderDebugSubclassesOf(animator)) {
        CylinderDebugDumpClass(NSStringFromClass(cls), @"prepare|cleanup|fraction|alpha|animat|position|zoom|icon", NO);
    }
}

#pragma mark - Logging-only hooks

static void CylinderDebugFollowUpTap(SBIconView *iconView)
{
    __weak SBIconView *weakIconView = iconView;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SBIconView *strongIconView = weakIconView;
        id front = nil;
        UIApplication *app = UIApplication.sharedApplication;
        SEL frontSelector = NSSelectorFromString(@"_accessibilityFrontMostApplication");
        if ([app respondsToSelector:frontSelector]) front = ((id (*)(id, SEL))objc_msgSend)(app, frontSelector);
        id bundle = [front respondsToSelector:@selector(bundleIdentifier)] ? [front bundleIdentifier] : nil;
        CylinderDebugLog(@"[tap] 1s after tap on %@: highlighted=%@ front=%@ window=%d superview=%@ transform=%@ alpha=%.3f",
                         CylinderDebugDescribeView(strongIconView),
                         [strongIconView respondsToSelector:NSSelectorFromString(@"isHighlighted")] ? [strongIconView valueForKey:@"highlighted"] : @"n/a",
                         bundle ?: @"(home screen)", strongIconView.window != nil,
                         NSStringFromClass(strongIconView.superview.class),
                         CylinderDebugDescribeTransform(strongIconView.layer.transform), strongIconView.alpha);
        CylinderDebugScanPages(@"1s after tap", YES);
    });
}

static NSString *CylinderDebugTapContext(SBIconView *iconView)
{
    return [NSString stringWithFormat:@"%@ superview=%@ transform=%@ alpha=%.3f opacity=%.3f hidden=%d animations=%@",
            CylinderDebugDescribeView(iconView), NSStringFromClass(iconView.superview.class),
            CylinderDebugDescribeTransform(iconView.layer.transform), iconView.alpha, iconView.layer.opacity,
            iconView.hidden, [iconView.layer.animationKeys componentsJoinedByString:@","] ?: @"none"];
}

static void CylinderDebugInstallTapHooks(void)
{
    for (NSString *className in @[@"SBIconController", @"SBHIconManager"]) {
        Class cls = NSClassFromString(className);
        if (!cls) {
            CylinderDebugLog(@"[hook] %@ missing", className);
            continue;
        }

        IMP *allowOrig = CylinderDebugNewOrig();
        CylinderDebugHook(cls, @"iconShouldAllowTap:", @"B@:@", allowOrig, ^BOOL(id self, SBIconView *iconView) {
            BOOL allowed = ((BOOL (*)(id, SEL, id))*allowOrig)(self, NSSelectorFromString(@"iconShouldAllowTap:"), iconView);
            CylinderDebugLog(@"[tap] -[%@ iconShouldAllowTap:] -> %d for %@", className, allowed, CylinderDebugTapContext(iconView));
            return allowed;
        });

        IMP *reasonOrig = CylinderDebugNewOrig();
        SEL reasonSelector = NSSelectorFromString(@"reasonToDisallowTapOnIconView:");
        CylinderDebugHook(cls, @"reasonToDisallowTapOnIconView:", @"@@:@", reasonOrig, ^id(id self, SBIconView *iconView) {
            id reason = ((id (*)(id, SEL, id))*reasonOrig)(self, reasonSelector, iconView);
            CylinderDebugLog(@"[tap] -[%@ reasonToDisallowTapOnIconView:] -> %@ for %@", className, reason ?: @"(none)", CylinderDebugDescribeView(iconView));
            return reason;
        });

        IMP *tappedOrig = CylinderDebugNewOrig();
        SEL tappedSelector = NSSelectorFromString(@"iconTapped:");
        CylinderDebugHook(cls, @"iconTapped:", @"v@:@", tappedOrig, ^(id self, SBIconView *iconView) {
            CylinderDebugLog(@"[tap] -[%@ iconTapped:] %@\n    %@", className, CylinderDebugTapContext(iconView),
                             CylinderDebugSessionDescription());
            ((void (*)(id, SEL, id))*tappedOrig)(self, tappedSelector, iconView);
            CylinderDebugFollowUpTap(iconView);
        });

        IMP *tappedFlagsOrig = CylinderDebugNewOrig();
        SEL tappedFlagsSelector = NSSelectorFromString(@"iconTapped:modifierFlags:");
        CylinderDebugHook(cls, @"iconTapped:modifierFlags:", @"v@:@q", tappedFlagsOrig, ^(id self, SBIconView *iconView, long flags) {
            CylinderDebugLog(@"[tap] -[%@ iconTapped:modifierFlags:] %@", className, CylinderDebugTapContext(iconView));
            ((void (*)(id, SEL, id, long))*tappedFlagsOrig)(self, tappedFlagsSelector, iconView, flags);
            CylinderDebugFollowUpTap(iconView);
        });

        IMP *launchOrig = CylinderDebugNewOrig();
        SEL launchSelector = NSSelectorFromString(@"launchFromIconView:withActions:modifierFlags:");
        CylinderDebugHook(cls, @"launchFromIconView:withActions:modifierFlags:", @"v@:@@q", launchOrig, ^(id self, SBIconView *iconView, id actions, long flags) {
            CylinderDebugLog(@"[tap] -[%@ launchFromIconView:] %@", className, CylinderDebugDescribeView(iconView));
            ((void (*)(id, SEL, id, id, long))*launchOrig)(self, launchSelector, iconView, actions, flags);
        });

        IMP *managerLaunchOrig = CylinderDebugNewOrig();
        SEL managerLaunchSelector = NSSelectorFromString(@"iconManager:launchIconForIconView:withActions:modifierFlags:");
        CylinderDebugHook(cls, @"iconManager:launchIconForIconView:withActions:modifierFlags:", @"v@:@@@q", managerLaunchOrig,
                          ^(id self, id manager, SBIconView *iconView, id actions, long flags) {
            CylinderDebugLog(@"[tap] -[%@ iconManager:launchIconForIconView:] %@", className, CylinderDebugDescribeView(iconView));
            ((void (*)(id, SEL, id, id, id, long))*managerLaunchOrig)(self, managerLaunchSelector, manager, iconView, actions, flags);
        });
    }

    Class iconViewClass = NSClassFromString(@"SBIconView");
    IMP *highlightOrig = CylinderDebugNewOrig();
    SEL highlightSelector = NSSelectorFromString(@"setHighlighted:");
    CylinderDebugHook(iconViewClass, @"setHighlighted:", @"v@:B", highlightOrig, ^(UIView *self, BOOL highlighted) {
        BOOL was = [self respondsToSelector:NSSelectorFromString(@"isHighlighted")] && [[self valueForKey:@"highlighted"] boolValue];
        ((void (*)(id, SEL, BOOL))*highlightOrig)(self, highlightSelector, highlighted);
        if (was != highlighted) CylinderDebugLog(@"[tap] highlighted=%d %@", highlighted, CylinderDebugDescribeView(self));
    });

    IMP *tapGestureOrig = CylinderDebugNewOrig();
    SEL tapGestureSelector = NSSelectorFromString(@"tapGestureDidChange:");
    CylinderDebugHook(iconViewClass, @"tapGestureDidChange:", @"v@:@", tapGestureOrig, ^(UIView *self, UIGestureRecognizer *gesture) {
        CylinderDebugLog(@"[tap] tapGestureDidChange state=%ld %@", (long)gesture.state, CylinderDebugTapContext((SBIconView *)self));
        ((void (*)(id, SEL, id))*tapGestureOrig)(self, tapGestureSelector, gesture);
    });
}

static void CylinderDebugInstallScrollHooks(void)
{
    Class cls = NSClassFromString(@"SBFolderView");

    IMP *updateOrig = CylinderDebugNewOrig();
    SEL updateSelector = NSSelectorFromString(@"_updateScrollingState:");
    CylinderDebugHook(cls, @"_updateScrollingState:", @"v@:B", updateOrig, ^(SBFolderView *self, BOOL scrolling) {
        CylinderDebugLog(@"[sb-scroll] _updateScrollingState:%d before: %@", scrolling, CylinderDebugDescribeFolderScrollState(self));
        ((void (*)(id, SEL, BOOL))*updateOrig)(self, updateSelector, scrolling);
        if (!scrolling) CylinderDebugLog(@"[sb-scroll] _updateScrollingState:NO done (completion blocks ran): %@", CylinderDebugDescribeFolderScrollState(self));
    });

    IMP *addBlockOrig = CylinderDebugNewOrig();
    SEL addBlockSelector = NSSelectorFromString(@"_addScrollingCompletionBlock:");
    CylinderDebugHook(cls, @"_addScrollingCompletionBlock:", @"v@:@?", addBlockOrig, ^(SBFolderView *self, id block) {
        ((void (*)(id, SEL, id))*addBlockOrig)(self, addBlockSelector, block);
        CylinderDebugLog(@"[sb-scroll] _addScrollingCompletionBlock: after: %@%@", CylinderDebugDescribeFolderScrollState(self), CylinderDebugBacktrace(6));
    });

    for (NSString *name in @[@"addScrollViewIsScrollingOverrideReason:", @"removeScrollViewIsScrollingOverrideReason:"]) {
        IMP *orig = CylinderDebugNewOrig();
        SEL selector = NSSelectorFromString(name);
        CylinderDebugHook(cls, name, @"v@:@", orig, ^(SBFolderView *self, id reason) {
            ((void (*)(id, SEL, id))*orig)(self, selector, reason);
            CylinderDebugLog(@"[sb-scroll] %@%@ after: %@", name, reason, CylinderDebugDescribeFolderScrollState(self));
        });
    }

    for (NSString *name in @[@"scrollViewWillBeginDragging:", @"scrollViewDidEndDecelerating:",
                             @"scrollViewDidEndScrollingAnimation:", @"scrollViewDidEndScrolling:"]) {
        IMP *orig = CylinderDebugNewOrig();
        SEL selector = NSSelectorFromString(name);
        CylinderDebugHook(cls, name, @"v@:@", orig, ^(SBFolderView *self, UIScrollView *scrollView) {
            ((void (*)(id, SEL, id))*orig)(self, selector, scrollView);
            CylinderDebugLog(@"[sb-scroll] %@ after: %@", name, CylinderDebugDescribeFolderScrollState(self));
        });
    }

    IMP *endDragOrig = CylinderDebugNewOrig();
    SEL endDragSelector = NSSelectorFromString(@"scrollViewDidEndDragging:willDecelerate:");
    CylinderDebugHook(cls, @"scrollViewDidEndDragging:willDecelerate:", @"v@:@B", endDragOrig, ^(SBFolderView *self, UIScrollView *scrollView, BOOL decelerate) {
        ((void (*)(id, SEL, id, BOOL))*endDragOrig)(self, endDragSelector, scrollView, decelerate);
        CylinderDebugLog(@"[sb-scroll] scrollViewDidEndDragging willDecelerate=%d after: %@", decelerate, CylinderDebugDescribeFolderScrollState(self));
    });

    Class listClass = NSClassFromString(@"SBIconListView");
    IMP *layoutOrig = CylinderDebugNewOrig();
    CylinderDebugHook(listClass, @"layoutSubviews", @"v@:", layoutOrig, ^(SBIconListView *self) {
        CylinderDebugRegisterPage(self);
        ((void (*)(id, SEL))*layoutOrig)(self, @selector(layoutSubviews));
    });
}

static void CylinderDebugInstallAnimatorHooks(void)
{
    Class base = NSClassFromString(@"SBIconAnimator");
    if (!base) {
        CylinderDebugLog(@"[hook] SBIconAnimator missing");
        return;
    }
    NSMutableArray<Class> *classes = [NSMutableArray arrayWithObject:base];
    [classes addObjectsFromArray:CylinderDebugSubclassesOf(base)];

    // Only methods a class implements itself are hooked, so each override logs once and a subclass that
    // calls super logs a second line naming the base class.
    for (Class cls in classes) {
        NSString *className = NSStringFromClass(cls);
        for (NSString *name in @[@"_prepareAnimation", @"_cleanupAnimation", @"prepare", @"cleanup", @"_cleanupZoom"]) {
            SEL selector = NSSelectorFromString(name);
            if (!CylinderDebugClassImplements(cls, selector)) continue;
            IMP *orig = CylinderDebugNewOrig();
            CylinderDebugHook(cls, name, @"v@:", orig, ^(id self) {
                CylinderDebugLog(@"[animator] %@<%p> -[%@ %@] begin", NSStringFromClass([self class]), self, className, name);
                ((void (*)(id, SEL))*orig)(self, selector);
                CylinderDebugLog(@"[animator] %@<%p> -[%@ %@] end", NSStringFromClass([self class]), self, className, name);
                if ([name containsString:@"leanup"]) {
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
                        CylinderDebugScanPages([NSString stringWithFormat:@"300ms after %@ %@", className, name], YES);
                    });
                }
            });
        }

        SEL dockSelector = NSSelectorFromString(@"_cleanupAnimationIncludingDock:");
        if (CylinderDebugClassImplements(cls, dockSelector)) {
            IMP *orig = CylinderDebugNewOrig();
            CylinderDebugHook(cls, @"_cleanupAnimationIncludingDock:", @"v@:B", orig, ^(id self, BOOL dock) {
                CylinderDebugLog(@"[animator] %@<%p> _cleanupAnimationIncludingDock:%d", NSStringFromClass([self class]), self, dock);
                ((void (*)(id, SEL, BOOL))*orig)(self, dockSelector, dock);
            });
        }

        SEL animateSelector = NSSelectorFromString(@"animateToFraction:afterDelay:withCompletion:");
        if (CylinderDebugClassImplements(cls, animateSelector)) {
            IMP *orig = CylinderDebugNewOrig();
            CylinderDebugHook(cls, @"animateToFraction:afterDelay:withCompletion:", @"v@:dd@?", orig, ^(id self, double fraction, double delay, id completion) {
                CylinderDebugLog(@"[animator] %@<%p> animateToFraction:%.2f afterDelay:%.2f", NSStringFromClass([self class]), self, fraction, delay);
                ((void (*)(id, SEL, double, double, id))*orig)(self, animateSelector, fraction, delay, completion);
            });
        }
    }
}

#pragma mark - Page scanning

static NSHashTable<SBIconListView *> *CylinderDebugPages;
static NSString *CylinderDebugLastScan;

void CylinderDebugRegisterPage(SBIconListView *page)
{
    if (!CylinderDebugPages) CylinderDebugPages = [NSHashTable weakObjectsHashTable];
    if (![CylinderDebugPages containsObject:page]) [CylinderDebugPages addObject:page];
}

static void CylinderDebugAppendAbnormal(NSMutableString *out, UIView *view, UIView *expectedSuperview, NSString *label)
{
    CALayer *layer = view.layer;
    NSMutableArray<NSString *> *problems = [NSMutableArray array];
    if (!CATransform3DIsIdentity(layer.transform)) [problems addObject:[NSString stringWithFormat:@"transform{%@}", CylinderDebugDescribeTransform(layer.transform)]];
    if (view.alpha < 0.999) [problems addObject:[NSString stringWithFormat:@"alpha=%.3f", view.alpha]];
    if (layer.opacity < 0.999) [problems addObject:[NSString stringWithFormat:@"opacity=%.3f", layer.opacity]];
    if (view.hidden) [problems addObject:@"hidden"];
    if (!CATransform3DIsIdentity(layer.sublayerTransform)) [problems addObject:@"sublayerTransform"];
    if (expectedSuperview && view.superview != expectedSuperview) [problems addObject:[NSString stringWithFormat:@"superview=%@", NSStringFromClass(view.superview.class)]];
    if ([view respondsToSelector:NSSelectorFromString(@"isHighlighted")] && [[view valueForKey:@"highlighted"] boolValue]) [problems addObject:@"highlighted"];
    if (layer.animationKeys.count) [problems addObject:[NSString stringWithFormat:@"animations=%@", [layer.animationKeys componentsJoinedByString:@","]]];
    if (!problems.count) return;
    [out appendFormat:@"\n    %@ %@: %@", label, CylinderDebugDescribeView(view), [problems componentsJoinedByString:@" "]];
}

void CylinderDebugScanPages(NSString *reason, BOOL force)
{
    NSMutableString *out = [NSMutableString string];
    NSUInteger scanned = 0;
    for (SBIconListView *page in CylinderDebugPages.allObjects) {
        UIWindow *window = page.window;
        if (!window || page.hidden) continue;
        CGRect onScreen = [page convertRect:page.bounds toView:nil];
        if (!CGRectIntersectsRect(onScreen, window.bounds)) continue;
        scanned++;

        NSMutableString *pageOut = [NSMutableString string];
        CylinderDebugAppendAbnormal(pageOut, page, nil, @"page");
        if ([page respondsToSelector:@selector(enumerateIconViewsUsingBlock:)]) {
            [page enumerateIconViewsUsingBlock:^(SBIconView *iconView, __unused NSUInteger index, __unused BOOL *stop) {
                CylinderDebugAppendAbnormal(pageOut, iconView, page, @"icon");
            }];
        }
        if (pageOut.length) {
            [out appendFormat:@"\n  %@ x=%.0f cylinderContext=%d%@", CylinderDebugDescribeView(page), CGRectGetMinX(onScreen),
                              [CylinderPageContext existingContextForPage:page] != nil, pageOut];
        }
    }

    NSString *summary = out.length ? out : @" all visible icons normal";
    if (!force && [summary isEqualToString:CylinderDebugLastScan]) return;
    CylinderDebugLastScan = summary;
    CylinderDebugLog(@"[scan] %@ (%lu visible pages):%@", reason, (unsigned long)scanned, summary);
}

#pragma mark - Install

static void CylinderDebugLogEnvironment(void)
{
    char machine[64] = {0};
    size_t size = sizeof(machine);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);

    Dl_info info;
    dladdr((const void *)CylinderDebugLogEnvironment, &info);

#if __arm64e__
    NSString *slice = @"arm64e";
#else
    NSString *slice = @"arm64";
#endif
    CylinderDebugLog(@"==================== SpringBoard launch ====================");
    CylinderDebugLog(@"Cylinder %@ built %s %s, slice %@, image %s", CYLINDER_DEBUG_VERSION, __DATE__, __TIME__, slice, info.dli_fname);
    CylinderDebugLog(@"%@ on %s, pid %d, date %@", NSProcessInfo.processInfo.operatingSystemVersionString, machine,
                     getpid(), NSDate.date);
}

void CylinderDebugInstall(void)
{
    CylinderDebugStart = CACurrentMediaTime();
    CylinderDebugQueue = dispatch_queue_create("com.ryannair05.cylinder.debuglog", DISPATCH_QUEUE_SERIAL);
    dispatch_sync(CylinderDebugQueue, ^{ CylinderDebugOpenLog(); });
    CylinderDebugLogEnvironment();
    CylinderDebugReloadFixFlag();
    CylinderDebugLog(@"[fix] session-end fallback is %@ (create %@ and respring to turn it on)",
                     CylinderDebugFix ? @"ON" : @"OFF", CYLINDER_DEBUG_FIX_PATH);

    CylinderDebugInstallScrollHooks();
    CylinderDebugInstallTapHooks();
}

static void CylinderDebugWatchLockState(const char *name)
{
    int token;
    NSString *label = @(name);
    notify_register_dispatch(name, &token, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0;
        notify_get_state(t, &state);
        CylinderDebugLog(@"[device] %@ = %llu", label, state);
        CylinderDebugScanPages([NSString stringWithFormat:@"%@ changed", label], YES);
    });
}

void CylinderDebugDidFinishLaunching(void)
{
    CylinderDebugLog(@"[launch] applicationDidFinishLaunching, screen %@", NSStringFromCGRect(UIScreen.mainScreen.bounds));
    CylinderDebugDumpRuntime();
    CylinderDebugInstallAnimatorHooks();
    CylinderDebugWatchLockState("com.apple.springboard.lockstate");
    CylinderDebugWatchLockState("com.apple.springboard.hasBlankedScreen");

    static NSUInteger tick;
    [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer) {
        CylinderDebugCoordinatorTick();
        if (++tick % 3 == 0) CylinderDebugScanPages(@"periodic", NO);
    }];
}
