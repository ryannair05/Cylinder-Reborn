#import "tweak.h"
#import "luastuff.h"
#import "../Defines.h"
#import "CylinderPageContext.h"
#import "CylinderPageCoordinator.h"
#import "CylinderTransitionCoordinator.h"

#import <objc/runtime.h>

static BOOL _enabled;


%hook SBIconListView
- (void)willRemoveSubview:(UIView *)subview
{
    [[CylinderPageContext existingContextForPage:self] subviewWillLeave:subview];
    %orig;
}

- (void)didAddSubview:(UIView *)subview
{
    %orig;
    [[CylinderPageContext existingContextForPage:self] subviewDidJoin];
}

- (void)setIconsNeedLayout
{
    [CylinderPageContext pageWillLayOutIcons:self];
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
    if (!_enabled) CylinderFinishActiveFolderScroll();
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
    if (!_enabled) CylinderFinishActiveFolderScroll();
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
    if (options & SBIconViewCrossfadeOptionMasksCorners) CylinderTransitionPrepared(self);
}
%end

%hook SBFluidSwitcherViewController
- (void)_temporarilyHideMatchMovedZoomDownAnimationViewAnimated:(BOOL)animated
{
    CylinderTransitionWillBeHiddenBySpringBoard();
    %orig;
}
%end
%end

%group TransitionCleanupHooks
%hook SBIconView
- (void)cleanupAfterCrossfade
{
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

#ifndef THEOS_PACKAGE_INSTALL_PREFIX
%group LegacyVisibilityHooks
%hook SBFolderView 
-(void)updateVisibleColumnRangeWithTotalLists:(NSUInteger)arg1 columnsPerList:(NSUInteger)arg2 iconVisibilityHandling:(SBIconVisibilityHandling)arg3
{
    %orig(arg1, arg2, SBIconVisibilityHandlingNone);
}

%end
%end
#endif

static void loadPrefs(void)
{
    CylinderFinishActiveFolderScroll();
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
        _enabled = init_lua(effects, random);
    }
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
	loadPrefs();
}
%end

%ctor{
    %init;

    if (@available(iOS 11, *)) {
        class_addMethod(objc_getClass("SBFolderView"),
                        @selector(performWhenScrollingEndsUsingBlock:),
                        (IMP)CylinderPerformWhenScrollingEnds,
                        "v@:@?");
    }


    if (@available(iOS 14, *)) {
        %init(ModernPageHooks);
        %init(ModernTransitionHooks);
        %init(TransitionCleanupHooks);
    } else {
        %init(LegacyPageHooks);
    }

    if (@available(iOS 15, *)) {
        %init(ModernVisibilityHooks);
    }
    #ifndef THEOS_PACKAGE_INSTALL_PREFIX
    // SpringBoard added this method in iOS 13.
    else if (@available(iOS 13, *)) {
        %init(LegacyVisibilityHooks);
    }
    #endif


    CFNotificationCenterRef r = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(r, NULL, CylinderPreferencesChanged, (CFStringRef)kCylinderSettingsChanged, NULL, CFNotificationSuspensionBehaviorCoalesce);
}
