#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

@class SBIconListView;
@class CylinderPageContext;

NS_ASSUME_NONNULL_BEGIN

/// Lua receives the address of one of these as light userdata. Every handle lives inside a pooled
/// context that is never freed, so a script that keeps a handle cannot reach freed memory.
typedef NS_ENUM(uint8_t, CylinderHandleKind) {
    CylinderHandleKindView,
    CylinderHandleKindLayer,
};

typedef NS_OPTIONS(uint8_t, CylinderDirtyFlags) {
    CylinderDirtyTransform = 1 << 0,
    CylinderDirtyPosition = 1 << 1,
    CylinderDirtyAlpha = 1 << 2,
    CylinderDirtyAll = CylinderDirtyTransform | CylinderDirtyPosition | CylinderDirtyAlpha,
};

typedef struct CylinderEntry CylinderEntry;

typedef struct CylinderHandle {
    CylinderHandleKind kind;
    CylinderEntry *entry;
} CylinderHandle;

/// One view Cylinder may modify during a scroll session: the page itself or one of its icon views.
struct CylinderEntry {
    __unsafe_unretained UIView *view;
    __unsafe_unretained CALayer *layer;
    __unsafe_unretained CylinderPageContext *context;
    /// Values the current frame has staged, committed once when the frame finishes.
    CATransform3D transform;
    CGPoint position;
    CGFloat alpha;
    /// Values the layer shows while the property is dirty.
    CATransform3D writtenTransform;
    CGPoint writtenPosition;
    CGFloat writtenAlpha;
    /// Pre-Cylinder values, captured when a property is first staged and restored once no frame writes it.
    CATransform3D savedTransform;
    CGPoint savedPosition;
    CGFloat savedAlpha;
    /// SpringBoard's frame when the entry joined the session, which stale geometry reads return.
    CGRect baseFrame;
    /// Properties whose layer shows a Cylinder value.
    CylinderDirtyFlags dirty;
    /// Properties the current frame has staged.
    CylinderDirtyFlags touched;
    /// Zero-based grid cell, resolved on first use. Widgets report the cell of their top-left corner.
    BOOL hasGridCoordinate;
    NSInteger row;
    NSInteger column;
    /// UIView's frame is recomputed from the layer on every call, so geometry reads share one per frame.
    BOOL hasCachedFrame;
    CGRect cachedFrame;
    /// The frame's size before the transform's scale, valid while the cached frame is.
    BOOL hasCachedSize;
    CGSize cachedSize;
    CylinderHandle viewHandle;
    CylinderHandle layerHandle;
    /// The view's layers draw antialiased edges, which a transform that tilts or rotates them needs.
    BOOL antialiased;
    /// Debug build: which unusual captures were already logged since the entry was attached.
    uint8_t debugLogged;
};

/// Per-page state for one scroll session. The page's icon views are retained so entries never dangle.
@interface CylinderPageContext : NSObject {
@public
    CylinderEntry _page;
    CylinderEntry *_entries;
    NSUInteger _count;
}

@property (nonatomic, readonly, nullable) SBIconListView *page;

/// Returns the pooled context for `page`, reusing an idle one when the page has none.
+ (instancetype)contextForPage:(SBIconListView *)page;
/// Returns the page's context only if the current scroll session already uses one.
+ (nullable instancetype)existingContextForPage:(SBIconListView *)page;
/// Restores every page modified during the session, adds those pages to `pages`, and returns the
/// contexts to the pool.
+ (void)restoreAllContexts:(nullable NSMutableArray<SBIconListView *> *)pages;
/// Undoes the changes on every page that `frame` did not run an effect on, keeping their sessions.
+ (void)restoreContextsOutsideFrame:(NSUInteger)frame;
/// SpringBoard is about to lay `page` out again, which invalidates the geometry its context saved, so the
/// page is restored and released. The next frame starts it from the new layout. Returns whether it had a context.
+ (BOOL)pageWillLayOutIcons:(SBIconListView *)page;

/// The page-coordinator frame that last ran an effect on the page.
@property (nonatomic) NSUInteger lastFrame;

/// Synchronises entries with the page's icon views before an effect runs. Reads of properties the
/// previous frame changed return their saved values until the effect stages them again.
- (void)prepareForFrame;
/// Commits the frame's staged values and restores every property the frame left untouched.
- (void)finishFrame;
/// Undoes every change Cylinder made to the page and its subviews but keeps the session.
- (void)restoreLayout;
/// Undoes every change and releases the page.
- (void)restore;
/// SpringBoard is taking `subview` off the page, often to reuse it on another one, so its changes are
/// undone now, while it is still where they were made. The next frame adopts the page's new icon views.
- (void)subviewWillLeave:(UIView *)subview;
/// SpringBoard added a subview to the page, which the next frame adopts.
- (void)subviewDidJoin;
/// SpringBoard is moving `iconView` to another superview. Icon views can leave from outside their page,
/// such as the container they fly in from after an unlock, so this catches what -subviewWillLeave: cannot.
+ (void)iconViewWillMove:(UIView *)iconView;

/// How much the effect multiplied `view`'s opacity, page included, so a flight to it can fade along.
- (CGFloat)effectAlphaOfView:(UIView *)view;

/// Grid metrics are stable for a scroll session, so SpringBoard's layout queries run once.
@property (nonatomic, readonly) NSUInteger maximumIconCount;
@property (nonatomic, readonly) NSUInteger maximumColumnCount;
@property (nonatomic, readonly) NSUInteger maximumRowCount;

/// Resolves `entry`'s grid cell from SpringBoard, or from its position in icon order before iOS 14.
void CylinderEntryLoadGridCoordinate(CylinderEntry *entry);

/// Entries for the page's SBIconViews in SpringBoard's icon order, which is how scripts index icons.
/// The buffer stays valid until the page's icon views change.
- (CylinderEntry *_Nonnull *_Nonnull)iconEntriesWithCount:(NSUInteger *)count NS_RETURNS_INNER_POINTER;

@end

/// Returns the layer's current transform without reading it back after the frame's first access.
CATransform3D CylinderEntryTransform(CylinderEntry *entry);
void CylinderEntrySetTransform(CylinderEntry *entry, CATransform3D transform);
CGPoint CylinderEntryPosition(CylinderEntry *entry);
void CylinderEntrySetPosition(CylinderEntry *entry, CGPoint position);
CGFloat CylinderEntryAlpha(CylinderEntry *entry);
void CylinderEntrySetAlpha(CylinderEntry *entry, CGFloat alpha);
/// The view's frame as the effect sees it, cached for the rest of the frame.
CGRect CylinderEntryFrame(CylinderEntry *entry);
/// The frame's size divided by the transform's scale, which scripts read as `width` and `height`.
CGSize CylinderEntrySize(CylinderEntry *entry);

/// Screen metrics are read once per scroll session instead of on every transform operation.
extern CGSize CylinderScreenSize;
extern CGFloat CylinderPerspectiveDistance;
void CylinderUpdateScreenMetrics(void);

NS_ASSUME_NONNULL_END
