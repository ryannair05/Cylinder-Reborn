#import <Foundation/Foundation.h>

@class SBFolderView;
@class SBIconScrollView;

NS_ASSUME_NONNULL_BEGIN

/// Applies the legacy effect to icon-list subviews intersecting the scroll view's visible bounds.
BOOL CylinderHandleLegacyFolderScroll(SBFolderView *folderView, SBIconScrollView *scrollView);
/// Applies Cylinder only to the leading-through-trailing page range reported by SpringBoard.
BOOL CylinderHandleModernFolderScroll(SBFolderView *folderView, SBIconScrollView *scrollView) API_AVAILABLE(ios(14.0));
/// Restores the pages belonging to the foreground folder's current scroll session. `reason` is logged.
void CylinderFinishActiveFolderScroll(const char *reason);
/// SpringBoard laid out or changed the icon views of a page in the active session, which undid its effect.
/// With the finger held still no scroll frame follows, so the effect runs again before the change is committed.
void CylinderActiveFolderScrollNeedsReapply(void);

/// Debug build: called once a second to report a session that stopped receiving frames.
void CylinderDebugCoordinatorTick(void);
/// Debug build: the active session's folder, age and frame count.
NSString *CylinderDebugSessionDescription(void);

NS_ASSUME_NONNULL_END
