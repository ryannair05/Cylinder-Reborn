#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

@class SBFolderIconZoomAnimator;
@class SBIconListView;
@class SBIconView;

NS_ASSUME_NONNULL_BEGIN

/// Begins tracking the animator-owned icon view that flies between an app and the Home Screen.
void CylinderTransitionPrepared(SBIconView *iconView) API_AVAILABLE(ios(14.0));
/// Stops steering the flying icon before SpringBoard tears down its crossfade.
void CylinderTransitionWillCleanup(SBIconView *iconView) API_AVAILABLE(ios(14.0));
void CylinderTransitionWillBeHiddenBySpringBoard(void) API_AVAILABLE(ios(13.0));
/// Begins tracking the folder view that zooms into its icon on the Home Screen, which SpringBoard keeps on the
/// icon's page with a match-move. Opening a folder prepares one too, but its page cannot scroll meanwhile.
void CylinderTransitionFolderPrepared(SBFolderIconZoomAnimator *animator) API_AVAILABLE(ios(14.0));
void CylinderTransitionFolderWillCleanup(SBFolderIconZoomAnimator *animator) API_AVAILABLE(ios(14.0));

SBIconView *_Nullable CylinderTransitionTargetOnPage(SBIconListView *listView) API_AVAILABLE(ios(14.0));
/// Records where `iconView` would be on screen without Cylinder. Call it while the page and its icons
/// are at their untransformed geometry, immediately before an effect runs.
void CylinderTransitionCaptureBaseline(SBIconView *iconView, CGFloat pageOffsetX) API_AVAILABLE(ios(14.0));
/// Re-aims the flight at the geometry Cylinder just gave `iconView`, fading it by `effectAlpha` along with the icon.
void CylinderTransitionFollow(SBIconView *iconView, CGFloat effectAlpha) API_AVAILABLE(ios(14.0));
/// Returns the flying icon to SpringBoard's own geometry once Cylinder has restored its pages.
void CylinderTransitionPagesRestored(void);
void CylinderTransitionHideIfTargetIsGone(void);
/// Records where the folder's scroll view is after a frame, then hides the flight if its icon is gone.
void CylinderTransitionFinishFrame(CGFloat contentOffsetX, CGFloat pageWidth);

NS_ASSUME_NONNULL_END
