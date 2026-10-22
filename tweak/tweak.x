#import "tweak.h"
#import "luastuff.h"
#import "../Defines.h"
#import "CylinderPageContext.h"
#import "CylinderPageCoordinator.h"
#import "CylinderTransitionCoordinator.h"
#import "CylinderDebug.h"

#import <objc/runtime.h>

static BOOL _enabled;

#ifdef CYLINDER_SIMJECT
extern BOOL CylinderHarnessDisableChurn;
#endif

/// Each change below undoes part of the page's effect, which the next commit would otherwise show unanimated
/// for as long as no scroll frame arrives, such as when a fly-in ends under a finger held still.
%hook SBIconListView
- (void)willRemoveSubview:(UIView *)subview
{
#ifdef CYLINDER_SIMJECT
    if (CylinderHarnessDisableChurn) {
        %orig;
        return;
    }
#endif
    CylinderPageContext *context = [CylinderPageContext existingContextForPage:self];
    [context subviewWillLeave:subview];
    if (context) CylinderActiveFolderScrollNeedsReapply();
    %orig;
}

- (void)didAddSubview:(UIView *)subview
{
    %orig;
#ifdef CYLINDER_SIMJECT
    if (CylinderHarnessDisableChurn) return;
#endif
    CylinderPageContext *context = [CylinderPageContext existingContextForPage:self];
    [context subviewDidJoin];
    if (context) CylinderActiveFolderScrollNeedsReapply();
}

- (void)setIconsNeedLayout
{
    if ([CylinderPageContext pageWillLayOutIcons:self]) CylinderActiveFolderScrollNeedsReapply();
    %orig;
}
%end

%hook SBIconView
- (void)willMoveToSuperview:(UIView *)superview
{
    if (superview != self.superview) [CylinderPageContext iconViewWillMove:self];
    %orig;
}
%end

%group LegacyPageHooks
%hook SBFolderView
-(void)scrollViewDidScroll:(SBIconScrollView *)scrollView
{
    %orig;
    if(!_enabled) return;

    _enabled = CylinderHandleLegacyFolderScroll(self, scrollView);
    if (!_enabled) {
        CylinderDebugLog(@"[prefs] every script failed, Cylinder disabled until settings change");
        CylinderFinishActiveFolderScroll("every script failed");
    }
}
%end
%end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"

%group ModernPageHooks
%hook SBFolderView
-(void)scrollViewDidScroll:(SBIconScrollView *)scrollView
{
    %orig;
    if(!_enabled) return;

    _enabled = CylinderHandleModernFolderScroll(self, scrollView);
    if (!_enabled) {
        CylinderDebugLog(@"[prefs] every script failed, Cylinder disabled until settings change");
        CylinderFinishActiveFolderScroll("every script failed");
    }
}
%end
%end

%group ModernTransitionHooks
%hook SBIconView
- (void)prepareToCrossfadeImageWithView:(UIView *)view
                            anchorPoint:(CGPoint)anchorPoint
                                options:(SBIconViewCrossfadeOptions)options
{
    %orig;
    CylinderDebugLog(@"[transition] prepareToCrossfadeImageWithView options=0x%lx icon=%@ crossfadeView=%@ %@",
                     (unsigned long)options, CylinderDebugDescribeView(self), NSStringFromClass(view.class), CylinderDebugSessionDescription());
    if (options & SBIconViewCrossfadeOptionMasksCorners) CylinderTransitionPrepared(self);
}
%end

%hook SBFluidSwitcherViewController
- (void)_temporarilyHideMatchMovedZoomDownAnimationViewAnimated:(BOOL)animated
{
    CylinderDebugLog(@"[transition] _temporarilyHideMatchMovedZoomDownAnimationViewAnimated:%d", animated);
    CylinderTransitionWillBeHiddenBySpringBoard();
    %orig;
}
%end
%end

%group FolderTransitionHooks
%hook SBFolderIconZoomAnimator
- (void)_setupMatchMoveAnimation
{
    %orig;
    CylinderTransitionFolderPrepared(self);
}

- (void)_cleanupAnimation
{
    CylinderTransitionFolderWillCleanup(self);
    %orig;
}
%end
%end

%group TransitionCleanupHooks
%hook SBIconView
- (void)cleanupAfterCrossfade
{
    CylinderDebugLog(@"[transition] cleanupAfterCrossfade %@", CylinderDebugDescribeView(self));
    CylinderTransitionWillCleanup(self);
    %orig;
}
%end
%end

#pragma clang diagnostic pop

%group ModernVisibilityHooks
%hook SBFolderView
- (SBIconVisibilityHandling)iconVisibilityHandling
{
    return SBIconVisibilityHandlingNone;
}
%end
%end

%group LegacyVisibilityHooks
%hook SBFolderView 
-(void)updateVisibleColumnRangeWithTotalLists:(NSUInteger)arg1 columnsPerList:(NSUInteger)arg2 iconVisibilityHandling:(SBIconVisibilityHandling)arg3
{
    %orig(arg1, arg2, SBIconVisibilityHandlingNone);
}

%end
%end

static void loadPrefs(void)
{
    CylinderDebugReloadFixFlag();
    CylinderFinishActiveFolderScroll("preferences loaded");
    NSUserDefaults *settings = [[NSUserDefaults alloc] initWithSuiteName:@"com.ryannair05.cylinder"];
    [settings registerDefaults:@{
        PrefsEnabledKey: @YES,
        PrefsRandomizedKey: @NO,
        PrefsEffectKey: DEFAULT_EFFECTS,
    }];

    if (![settings boolForKey:PrefsEnabledKey])
    {
        close_lua();
        _enabled = NO;
    }
    else
    {
        BOOL random = [settings boolForKey:PrefsRandomizedKey];
        NSArray *effects = [settings arrayForKey:PrefsEffectKey];
#ifdef CYLINDER_SIMJECT
        NSLog(@"[CylinderSimject] initializing Lua with effects: %@; randomized: %@", effects, random ? @"YES" : @"NO");
#endif
        _enabled = init_lua(effects, random);
    }
    CylinderDebugLog(@"[prefs] enabled=%d randomized=%d effects=%@ -> running=%d",
                     [settings boolForKey:PrefsEnabledKey], [settings boolForKey:PrefsRandomizedKey],
                     [[settings arrayForKey:PrefsEffectKey] valueForKey:PrefsEffectKey], _enabled);
}

static void CylinderPerformWhenScrollingEnds(SBFolderView *folderView, __unused SEL selector, dispatch_block_t completion) API_AVAILABLE(ios(11.0));
static void CylinderPerformWhenScrollingEnds(SBFolderView *folderView, __unused SEL selector, dispatch_block_t completion)
{
    if ([folderView isScrolling]) {
        [folderView _addScrollingCompletionBlock:completion];
    } else {
        completion();
    }
}

static void CylinderPreferencesChanged(__unused CFNotificationCenterRef center,
                                       __unused void *observer,
                                       __unused CFStringRef name,
                                       __unused const void *object,
                                       __unused CFDictionaryRef userInfo)
{
    loadPrefs();
}

/// Defers Lua initialization because create_state() reads UIScreen through PERSPECTIVE_DISTANCE;
/// doing that from the tweak constructor causes SpringBoard to bootloop.
%hook SpringBoard
-(void)applicationDidFinishLaunching:(id)application 
{
    %orig;
    CylinderDebugDidFinishLaunching();
	loadPrefs();
#ifdef CYLINDER_SIMJECT
    NSLog(@"[CylinderSimject] SpringBoard finished launching; Cylinder is enabled: %@", _enabled ? @"YES" : @"NO");
#endif
    CylinderDebugScanPages(@"after launch", YES);
}
%end

%ctor{
    CylinderDebugInstall();
    %init;

    if (@available(iOS 11, *)) {
        class_addMethod(objc_getClass("SBFolderView"),
                        @selector(performWhenScrollingEndsUsingBlock:),
                        (IMP)CylinderPerformWhenScrollingEnds,
                        "v@:@?");
    }

#ifdef CYLINDER_SIMJECT
    NSString *pageImplementation;
#endif

    if (@available(iOS 14, *)) {
        %init(ModernPageHooks);
        %init(ModernTransitionHooks);
        %init(TransitionCleanupHooks);
        // SBFolderIconZoomAnimator has had these methods since iOS 12, but only the modern page path steers flights.
        %init(FolderTransitionHooks);
#ifdef CYLINDER_SIMJECT
        pageImplementation = @"iOS 14+";
#endif
    } else {
        %init(LegacyPageHooks);
#ifdef CYLINDER_SIMJECT
        pageImplementation = @"iOS 11-13";
#endif
    }

    // Without these, SpringBoard recycles icon views between pages mid-swipe. Theos defines
    // THEOS_PACKAGE_INSTALL_PREFIX for rootful builds too, so the choice is made at runtime.
    if ([objc_getClass("SBFolderView") instancesRespondToSelector:@selector(iconVisibilityHandling)]) {
        %init(ModernVisibilityHooks);
    } else if (@available(iOS 13, *)) {
        // SpringBoard added this method in iOS 13.
        %init(LegacyVisibilityHooks);
    }

#ifdef CYLINDER_SIMJECT
    NSLog(@"[CylinderSimject] loaded into %@ using the %@ page implementation", NSProcessInfo.processInfo.processName, pageImplementation);
#endif

    NSString *pageHooks = @"legacy", *visibilityHooks = @"none";
    if (@available(iOS 14, *)) pageHooks = @"modern + transition + folder transition";
    if ([objc_getClass("SBFolderView") instancesRespondToSelector:@selector(iconVisibilityHandling)]) visibilityHooks = @"iconVisibilityHandling";
    else if (@available(iOS 13, *)) visibilityHooks = @"updateVisibleColumnRange";
    CylinderDebugLog(@"[launch] hook groups: page=%@ visibility=%@", pageHooks, visibilityHooks);

    CFNotificationCenterRef r = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(r, NULL, CylinderPreferencesChanged, (CFStringRef)kCylinderSettingsChanged, NULL, CFNotificationSuspensionBehaviorCoalesce);
}
