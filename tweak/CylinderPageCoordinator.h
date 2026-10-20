#import <Foundation/Foundation.h>

@class SBFolderView;
@class SBIconScrollView;

NS_ASSUME_NONNULL_BEGIN

/// Applies the legacy effect to icon-list subviews intersecting the scroll view's visible bounds.
BOOL CylinderHandleLegacyFolderScroll(SBFolderView *folderView, SBIconScrollView *scrollView);
/// Applies Cylinder only to the leading-through-trailing page range reported by SpringBoard.
BOOL CylinderHandleModernFolderScroll(SBFolderView *folderView, SBIconScrollView *scrollView) API_AVAILABLE(ios(14.0));
/// Restores the pages belonging to the foreground folder's current scroll session.
void CylinderFinishActiveFolderScroll(void);

NS_ASSUME_NONNULL_END
