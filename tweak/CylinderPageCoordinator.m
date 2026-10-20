#import "CylinderPageCoordinator.h"

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

void CylinderFinishActiveFolderScroll(void)
{
    CylinderCleanupGeneration += 1;
    CylinderActiveFolderView = nil;

    NSMutableArray<SBIconListView *> *pages = [NSMutableArray array];
    [CylinderPageContext restoreAllContexts:pages];
    for (SBIconListView *listView in pages) [listView setIconsNeedLayout];

    CylinderTransitionPagesRestored();
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

        if (CylinderFrameGeneration != frame || [strongFolderView isScrolling]) {
            CylinderScheduleIdleCheck(strongFolderView, session);
        } else {
            CylinderFinishActiveFolderScroll();
        }
    });
}

static void CylinderBeginFolderScroll(SBFolderView *folderView) API_AVAILABLE(ios(11.0));
static void CylinderBeginFolderScroll(SBFolderView *folderView)
{
    CylinderFrameGeneration += 1;
    if (CylinderActiveFolderView == folderView) return;

    CylinderFinishActiveFolderScroll();
    CylinderActiveFolderView = folderView;
    CylinderRandomSeed = arc4random();
    CylinderUpdateScreenMetrics();
    NSUInteger generation = ++CylinderCleanupGeneration;

    if (![folderView isScrolling]) {
        CylinderScheduleIdleCheck(folderView, generation);
        return;
    }

    __weak SBFolderView *weakFolderView = folderView;
    [folderView performWhenScrollingEndsUsingBlock:^{
        SBFolderView *strongFolderView = weakFolderView;
        if (!strongFolderView || CylinderActiveFolderView != strongFolderView) return;
        if (CylinderCleanupGeneration != generation) return;
        CylinderFinishActiveFolderScroll();
    }];
}

BOOL CylinderHandleLegacyFolderScroll(SBFolderView *folderView, SBIconScrollView *scrollView)
{
    CGRect visibleRect = scrollView.bounds;
    Class iconListViewClass = objc_getClass("SBIconListView");
    CylinderBeginFolderScroll(folderView);

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

BOOL CylinderHandleModernFolderScroll(SBFolderView *folderView, SBIconScrollView *scrollView)
{
    NSInteger leading;
    NSInteger trailing;
    [folderView getLeadingVisiblePageIndex:&leading trailingVisiblePageIndex:&trailing];

    if (leading == NSIntegerMax || trailing == NSIntegerMax || leading > trailing || trailing - leading > 16) return YES;

    CylinderBeginFolderScroll(folderView);
    CGFloat contentOffsetX = scrollView.contentOffset.x;

    for (NSInteger pageIndex = leading; pageIndex <= trailing; pageIndex++) {
        SBIconListView *listView = [folderView iconListViewForPageIndex:pageIndex];
        if (!listView || CGRectGetWidth(listView.bounds) <= 0) continue;

        CylinderPageContext *context = [CylinderPageContext contextForPage:listView];
        context.lastFrame = CylinderFrameGeneration;
        [context prepareForFrame];

        CGPoint nativePageOffset = [folderView _scrollOffsetForPageAtIndex:pageIndex];
        SBIconView *transitionTarget = CylinderTransitionTargetOnPage(listView);
        if (transitionTarget) {
            [context restoreLayout];
            CylinderTransitionCaptureBaseline(transitionTarget, nativePageOffset.x);
        }

        BOOL succeeded = manipulate(context, contentOffsetX - nativePageOffset.x, CylinderRandomSeed);
        [context finishFrame];
        if (!succeeded) return NO;

        if (transitionTarget) CylinderTransitionFollow(transitionTarget);
    }
    [CylinderPageContext restoreContextsOutsideFrame:CylinderFrameGeneration];
    CylinderTransitionFinishFrame(contentOffsetX, CGRectGetWidth(scrollView.bounds));

    return YES;
}
