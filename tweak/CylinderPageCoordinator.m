#import "CylinderPageCoordinator.h"

#import "CylinderDebug.h"
#import "CylinderPageContext.h"
#import "CylinderTransitionCoordinator.h"
#import "luastuff.h"
#import "tweak.h"

#import <objc/runtime.h>

/// Only one foreground folder can be swiped at a time; the generation rejects a completion from an invalidated session.
static __weak SBFolderView *CylinderActiveFolderView;
static uint32_t CylinderRandomSeed;
static NSUInteger CylinderCleanupGeneration;
static NSUInteger CylinderFrameGeneration;
static BOOL CylinderIdleCheckPending;
static __weak UIScrollView *CylinderActiveScrollView;
/// Every effect pass, from a scroll frame or a re-apply. Scroll frames alone keep a session alive.
static NSUInteger CylinderPassGeneration;
/// SpringBoard undid part of the effect after the last pass; one re-apply per transaction is scheduled.
static BOOL CylinderReapplyRequested;
static BOOL CylinderReapplyScheduled;
static CFTimeInterval CylinderReapplyScheduledTime;

/// Debug build bookkeeping for the active session.
static CFTimeInterval CylinderSessionStartTime;
static CFTimeInterval CylinderLastFrameTime;
static NSUInteger CylinderSessionFrames;
static BOOL CylinderSessionLoggedNonUserFrame;
static CFTimeInterval CylinderSessionLastStuckLog;
static NSUInteger CylinderInvalidRangeLogs;

static UIScrollView *CylinderScrollViewOf(SBFolderView *folderView)
{
    return [folderView respondsToSelector:@selector(scrollView)] ? folderView.scrollView : nil;
}

NSString *CylinderDebugSessionDescription(void)
{
    SBFolderView *folderView = CylinderActiveFolderView;
    if (!folderView) return @"no active session";
    CFTimeInterval now = CACurrentMediaTime();
    return [NSString stringWithFormat:@"session gen=%lu age=%.2fs frames=%lu lastFrame=%.2fs ago idleCheckPending=%d %@",
            (unsigned long)CylinderCleanupGeneration, now - CylinderSessionStartTime, (unsigned long)CylinderSessionFrames,
            now - CylinderLastFrameTime, CylinderIdleCheckPending, CylinderDebugDescribeFolderScrollState(folderView)];
}

void CylinderDebugCoordinatorTick(void)
{
    if (!CylinderActiveFolderView) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - CylinderLastFrameTime < 1.5) return;
    if (CylinderSessionLastStuckLog && now - CylinderSessionLastStuckLog < 10) return;
    CylinderSessionLastStuckLog = now;
    CylinderDebugLog(@"[session] STILL ACTIVE with no frames: %@", CylinderDebugSessionDescription());
    CylinderDebugScanPages(@"session still active", YES);
}

void CylinderFinishActiveFolderScroll(const char *reason)
{
    SBFolderView *folderView = CylinderActiveFolderView;
    CylinderCleanupGeneration += 1;
    CylinderActiveFolderView = nil;

    NSMutableArray<SBIconListView *> *pages = [NSMutableArray array];
    [CylinderPageContext restoreAllContexts:pages];
    for (SBIconListView *listView in pages) [listView setIconsNeedLayout];

    CylinderTransitionPagesRestored();

    if (folderView || pages.count) {
        CylinderDebugLog(@"[session] END reason=%s folder=%@<%p> age=%.2fs frames=%lu restoredPages=%lu newGen=%lu",
                         reason, NSStringFromClass(folderView.class), folderView, CACurrentMediaTime() - CylinderSessionStartTime,
                         (unsigned long)CylinderSessionFrames, (unsigned long)pages.count, (unsigned long)CylinderCleanupGeneration);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(400 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
            CylinderDebugScanPages([NSString stringWithFormat:@"400ms after session end (%s)", reason], YES);
        });
    }
}

static void CylinderScheduleIdleCheck(SBFolderView *folderView, NSUInteger session)
{
    if (CylinderIdleCheckPending) return;
    CylinderIdleCheckPending = YES;

    NSUInteger frame = CylinderFrameGeneration;
    __weak SBFolderView *weakFolderView = folderView;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        CylinderIdleCheckPending = NO;
        SBFolderView *strongFolderView = weakFolderView;
        if (!strongFolderView || CylinderActiveFolderView != strongFolderView) return;
        if (CylinderCleanupGeneration != session) return;

        BOOL framesChanged = CylinderFrameGeneration != frame;
        BOOL scrolling = [strongFolderView isScrolling];
        if (!framesChanged && scrolling && CylinderDebugFixEnabled()) {
            UIScrollView *scrollView = CylinderScrollViewOf(strongFolderView);
            if (!scrollView.isTracking && !scrollView.isDragging && !scrollView.isDecelerating) {
                CylinderDebugLog(@"[fix] ending session although isScrolling=YES: %@", CylinderDebugSessionDescription());
                CylinderFinishActiveFolderScroll("idle check (fix: no frames, finger up)");
                return;
            }
        }

        if (framesChanged || scrolling) {
            if (!framesChanged) {
                static CFTimeInterval lastLog;
                CFTimeInterval now = CACurrentMediaTime();
                if (now - lastLog > 2) {
                    lastLog = now;
                    CylinderDebugLog(@"[session] idle check: no new frames but isScrolling=YES, waiting: %@", CylinderDebugSessionDescription());
                }
            }
            CylinderScheduleIdleCheck(strongFolderView, session);
        } else {
            CylinderFinishActiveFolderScroll("idle check");
        }
    });
}

static void CylinderBeginFolderScroll(SBFolderView *folderView) API_AVAILABLE(ios(11.0));
static void CylinderBeginFolderScroll(SBFolderView *folderView)
{
    CylinderFrameGeneration += 1;
    CylinderSessionFrames += 1;
    CylinderLastFrameTime = CACurrentMediaTime();
    if (CylinderActiveFolderView == folderView) return;

    if (CylinderActiveFolderView) CylinderDebugLog(@"[session] new folder view %@<%p> replaces active one", NSStringFromClass(folderView.class), folderView);
    CylinderFinishActiveFolderScroll("new folder view began scrolling");
    CylinderActiveFolderView = folderView;
    CylinderRandomSeed = arc4random();
    CylinderUpdateScreenMetrics();
    NSUInteger generation = ++CylinderCleanupGeneration;

    CylinderSessionStartTime = CylinderLastFrameTime;
    CylinderSessionFrames = 1;
    CylinderSessionLoggedNonUserFrame = NO;
    CylinderSessionLastStuckLog = 0;

    BOOL scrolling = [folderView isScrolling];
    CylinderDebugLog(@"[session] BEGIN gen=%lu end-path=%@%@ %@", (unsigned long)generation,
                     scrolling ? @"SpringBoard completion block" : @"idle check",
                     scrolling && CylinderDebugFixEnabled() ? @" + idle check (fix)" : @"",
                     CylinderDebugDescribeFolderScrollState(folderView));

    if (!scrolling) {
        CylinderScheduleIdleCheck(folderView, generation);
        return;
    }

    // With the fix on, the idle check also runs so a completion block SpringBoard never calls cannot keep the session alive.
    if (CylinderDebugFixEnabled()) CylinderScheduleIdleCheck(folderView, generation);

    __weak SBFolderView *weakFolderView = folderView;
    [folderView performWhenScrollingEndsUsingBlock:^{
        SBFolderView *strongFolderView = weakFolderView;
        BOOL stale = !strongFolderView || CylinderActiveFolderView != strongFolderView || CylinderCleanupGeneration != generation;
        CylinderDebugLog(@"[session] completion block for gen=%lu fired%@", (unsigned long)generation, stale ? @" (stale, ignored)" : @"");
        if (stale) return;
        CylinderFinishActiveFolderScroll("SpringBoard scrolling completion block");
    }];
}

/// Logs each frame on one line, and who moved the scroll view the first time a frame arrives without a finger or deceleration.
static void CylinderLogFrame(SBFolderView *folderView, UIScrollView *scrollView, NSString *detail)
{
    BOOL user = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating;
    CylinderDebugLog(@"[frame] gen=%lu n=%lu off=%.1f %@ isScrolling=%d tracking=%d dragging=%d decel=%d%@",
                     (unsigned long)CylinderCleanupGeneration, (unsigned long)CylinderSessionFrames, scrollView.contentOffset.x, detail,
                     [folderView isScrolling], scrollView.isTracking, scrollView.isDragging, scrollView.isDecelerating,
                     user ? @"" : @" NON-USER");
    if (!user && !CylinderSessionLoggedNonUserFrame) {
        CylinderSessionLoggedNonUserFrame = YES;
        CylinderDebugLog(@"[frame] first non-user frame this session, called from:%@", CylinderDebugBacktrace(16));
    }
}

/// Runs the effect on the legacy folder's visible pages for the scroll view's current offset.
static BOOL CylinderApplyLegacyFrame(UIScrollView *scrollView)
{
    CylinderReapplyRequested = NO;
    CGRect visibleRect = scrollView.bounds;
    Class iconListViewClass = objc_getClass("SBIconListView");

    for (UIView *subview in scrollView.subviews) {
        if (![subview isMemberOfClass:iconListViewClass]) continue;

        SBIconListView *listView = (SBIconListView *)subview;
        CGRect frame = listView.frame;
        if (!CGRectIntersectsRect(visibleRect, frame)) {
            // A page that scrolled out of view returns to its layout until it is visible again.
            [[CylinderPageContext existingContextForPage:listView] restoreLayout];
            continue;
        }
        if (CGRectGetWidth(frame) <= 0) continue;

        CylinderPageContext *context = [CylinderPageContext contextForPage:listView];
        [context prepareForFrame];
        BOOL succeeded = manipulate(context, scrollView.contentOffset.x - CGRectGetMinX(frame), CylinderRandomSeed);
        [context finishFrame];
        if (!succeeded) return NO;
    }

    return YES;
}

BOOL CylinderHandleLegacyFolderScroll(SBFolderView *folderView, SBIconScrollView *scrollView)
{
    CylinderBeginFolderScroll(folderView);
    CylinderActiveScrollView = scrollView;
    CylinderLogFrame(folderView, scrollView, @"legacy");
    return CylinderApplyLegacyFrame(scrollView);
}

/// The pages SpringBoard reports as visible, limited to icon pages. The Today view and App Library are custom
/// pages whose icon lists SBRootFolderView also returns, and Cylinder never animated them before iOS 14.
static BOOL CylinderGetVisiblePageRange(SBFolderView *folderView, UIScrollView *scrollView, NSInteger *leading, NSInteger *trailing) API_AVAILABLE(ios(14.0))
{
    [folderView getLeadingVisiblePageIndex:leading trailingVisiblePageIndex:trailing];

    if (*leading == NSIntegerMax || *trailing == NSIntegerMax || *leading > *trailing || *trailing - *leading > 16) {
        if (CylinderInvalidRangeLogs++ < 200) {
            CylinderDebugLog(@"[frame] skipped: invalid page range %ld..%ld off=%.1f %@", (long)*leading, (long)*trailing,
                             scrollView.contentOffset.x, CylinderDebugDescribeFolderScrollState(folderView));
        }
        return NO;
    }

    // A range that only covers a custom page becomes empty, so the frame still restores the icon page that left.
    if ([folderView respondsToSelector:@selector(firstIconPageIndex)] && [folderView respondsToSelector:@selector(lastIconPageIndex)]) {
        *leading = MAX(*leading, [folderView firstIconPageIndex]);
        *trailing = MIN(*trailing, [folderView lastIconPageIndex]);
    }
    return YES;
}

/// Runs the effect on the modern folder's visible pages for the scroll view's current offset.
static BOOL CylinderApplyModernFrame(SBFolderView *folderView, UIScrollView *scrollView, NSInteger leading, NSInteger trailing) API_AVAILABLE(ios(14.0))
{
    CylinderReapplyRequested = NO;
    NSUInteger pass = ++CylinderPassGeneration;
    CGFloat contentOffsetX = scrollView.contentOffset.x;

    for (NSInteger pageIndex = leading; pageIndex <= trailing; pageIndex++) {
        SBIconListView *listView = [folderView iconListViewForPageIndex:pageIndex];
        if (!listView || CGRectGetWidth(listView.bounds) <= 0) continue;

        CylinderPageContext *context = [CylinderPageContext contextForPage:listView];
        context.lastFrame = pass;
        [context prepareForFrame];

        CGPoint nativePageOffset = [folderView _scrollOffsetForPageAtIndex:pageIndex];
        SBIconView *transitionTarget = CylinderTransitionTargetOnPage(listView);
        if (transitionTarget) {
            CylinderDebugLog(@"[transition] page %ld holds transition target %@", (long)pageIndex, CylinderDebugDescribeView(transitionTarget));
            [context restoreLayout];
            CylinderTransitionCaptureBaseline(transitionTarget, nativePageOffset.x);
        }

        BOOL succeeded = manipulate(context, contentOffsetX - nativePageOffset.x, CylinderRandomSeed);
        [context finishFrame];
        if (!succeeded) return NO;

        if (transitionTarget) CylinderTransitionFollow(transitionTarget, [context effectAlphaOfView:transitionTarget]);
    }
    [CylinderPageContext restoreContextsOutsideFrame:pass];
    CylinderTransitionFinishFrame(contentOffsetX, CGRectGetWidth(scrollView.bounds));

    return YES;
}

BOOL CylinderHandleModernFolderScroll(SBFolderView *folderView, SBIconScrollView *scrollView)
{
    NSInteger leading;
    NSInteger trailing;
    if (!CylinderGetVisiblePageRange(folderView, scrollView, &leading, &trailing)) return YES;

    CylinderBeginFolderScroll(folderView);
    CylinderActiveScrollView = scrollView;
    CylinderLogFrame(folderView, scrollView, [NSString stringWithFormat:@"pages=%ld..%ld", (long)leading, (long)trailing]);
    return CylinderApplyModernFrame(folderView, scrollView, leading, trailing);
}

/// Runs the active session's effect again at the scroll view's unchanged offset.
static void CylinderReapplyActiveFolderScroll(void)
{
    SBFolderView *folderView = CylinderActiveFolderView;
    UIScrollView *scrollView = CylinderActiveScrollView;
    if (!folderView || !scrollView) return;

    BOOL succeeded;
    if (@available(iOS 14, *)) {
        NSInteger leading;
        NSInteger trailing;
        if (!CylinderGetVisiblePageRange(folderView, scrollView, &leading, &trailing)) return;
        succeeded = CylinderApplyModernFrame(folderView, scrollView, leading, trailing);
    } else {
        succeeded = CylinderApplyLegacyFrame(scrollView);
    }
    CylinderDebugLog(@"[reapply] effect ran again between scroll frames (succeeded=%d) %@", succeeded, CylinderDebugSessionDescription());
    // The next scroll frame fails the same way and turns Cylinder off.
    if (!succeeded) CylinderFinishActiveFolderScroll("script failed while re-applying");
}

@interface CATransaction (CylinderPrivate)
+ (void)addCommitHandler:(void (^)(void))handler forPhase:(int)phase;
@end

/// Runs after the transaction's layout pass and before it reaches the render server.
static const int CylinderTransactionPhasePreCommit = 1;

void CylinderActiveFolderScrollNeedsReapply(void)
{
    if (!CylinderActiveFolderView) return;
    CylinderReapplyRequested = YES;

    // A handler the transaction never ran must not block every later request.
    CFTimeInterval now = CACurrentMediaTime();
    if (CylinderReapplyScheduled && now - CylinderReapplyScheduledTime < 0.5) return;
    CylinderReapplyScheduled = YES;
    CylinderReapplyScheduledTime = now;

    NSUInteger session = CylinderCleanupGeneration;
    void (^reapply)(void) = ^{
        CylinderReapplyScheduled = NO;
        // A scroll frame that ran after the request already put the effect back.
        if (!CylinderReapplyRequested || CylinderCleanupGeneration != session) return;
        CylinderReapplyActiveFolderScroll();
    };
    if ([CATransaction respondsToSelector:@selector(addCommitHandler:forPhase:)]) {
        [CATransaction addCommitHandler:reapply forPhase:CylinderTransactionPhasePreCommit];
    } else {
        dispatch_async(dispatch_get_main_queue(), reapply);
    }
}
