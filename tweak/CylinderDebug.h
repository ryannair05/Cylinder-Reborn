#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@class SBFolderView;
@class SBIconListView;

NS_ASSUME_NONNULL_BEGIN

/// Debug build for issue #23. Everything goes to /var/mobile/Library/Logs/Cylinder/debug.log.
#define CYLINDER_DEBUG_LOG_DIR @"/var/mobile/Library/Logs/Cylinder/"
#define CYLINDER_DEBUG_LOG_PATH CYLINDER_DEBUG_LOG_DIR @"debug.log"
/// Creating this empty file and respringing turns on the experimental session-end fallback.
#define CYLINDER_DEBUG_FIX_PATH CYLINDER_DEBUG_LOG_DIR @"fix"

void CylinderDebugLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
/// The calling stack without this function, trimmed to `depth` frames.
NSString *CylinderDebugBacktrace(NSUInteger depth);
NSString *CylinderDebugDescribeTransform(CATransform3D t);
NSString *CylinderDebugDescribeView(UIView *_Nullable view);
NSString *CylinderDebugDescribeFolderScrollState(SBFolderView *_Nullable folderView);

/// Re-reads the fix flag file. Called on launch and every preference reload.
void CylinderDebugReloadFixFlag(void);
BOOL CylinderDebugFixEnabled(void);

/// Logs the environment, dumps SpringBoard's runtime and installs the logging-only hooks.
void CylinderDebugInstall(void);
/// Starts the watchdog once SpringBoard has launched.
void CylinderDebugDidFinishLaunching(void);

/// Pages seen by SpringBoard layout, scanned for icons left in a modified state.
void CylinderDebugRegisterPage(SBIconListView *page);
/// Logs every icon on visible pages whose transform, alpha, opacity, superview or highlight is unusual.
/// Only logs when the result differs from the previous scan unless `force` is set.
void CylinderDebugScanPages(NSString *reason, BOOL force);

NS_ASSUME_NONNULL_END
