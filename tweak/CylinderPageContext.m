#import "CylinderPageContext.h"

#import "tweak.h"
#import "CylinderDebug.h"

#ifdef CYLINDER_SIMJECT
extern BOOL CylinderHarnessAuditIcons;
extern BOOL CylinderHarnessKeepOffRangePages;
void CylinderHarnessLogLine(NSString *line);
#endif


CGSize CylinderScreenSize;
CGFloat CylinderPerspectiveDistance = 1;

void CylinderUpdateScreenMetrics(void)
{
    CGSize previous = CylinderScreenSize;
    CylinderScreenSize = UIScreen.mainScreen.bounds.size;
    if (!CGSizeEqualToSize(previous, CylinderScreenSize)) CylinderDebugLog(@"[metrics] screen %@", NSStringFromCGSize(CylinderScreenSize));
    CGFloat distance = (CylinderScreenSize.width + CylinderScreenSize.height) / 2;
    CylinderPerspectiveDistance = distance > 0 ? distance : 1;
}

/// Entry storage is never freed: Lua handles point into it, and a context only ever grows.
static const NSUInteger CylinderInitialEntryCapacity = 48;


/// Effects write staged values, and the frame commits each property once, only when it differs from
/// what the layer shows. A property is dirty while its layer shows a Cylinder value and touched once
/// the current frame staged it. Dirty properties the frame leaves alone return to their saved values.
static const CylinderDirtyFlags CylinderDirtyGeometry = CylinderDirtyTransform | CylinderDirtyPosition;

/// Core Animation stores opacity as a float, so a value read back can differ slightly from the one written.
static inline BOOL CylinderNearlyEqual(CGFloat a, CGFloat b)
{
    return fabs(a - b) <= 1e-4 * MAX(1.0, MAX(fabs(a), fabs(b)));
}

static BOOL CylinderTransformsNearlyEqual(CATransform3D a, CATransform3D b)
{
    const CGFloat *x = &a.m11, *y = &b.m11;
    for (int i = 0; i < 16; i++) {
        if (!CylinderNearlyEqual(x[i], y[i])) return NO;
    }
    return YES;
}

/// SpringBoard can change a property after Cylinder wrote it, as it does when it resets an icon view it
/// recycles onto another page. Its value then wins: restoring the saved original over it would leave the
/// icon shrunk or faded wherever SpringBoard puts it next, and the next frame that stages the property
/// saves SpringBoard's value as the new original.
static void CylinderEntryReleaseChangedProperties(CylinderEntry *entry)
{
    CylinderDirtyFlags changed = 0;
    if ((entry->dirty & CylinderDirtyTransform) && !CylinderTransformsNearlyEqual(entry->layer.transform, entry->writtenTransform)) {
        changed |= CylinderDirtyTransform;
    }
    if (entry->dirty & CylinderDirtyPosition) {
        CGPoint position = entry->layer.position;
        if (!CylinderNearlyEqual(position.x, entry->writtenPosition.x) || !CylinderNearlyEqual(position.y, entry->writtenPosition.y)) {
            changed |= CylinderDirtyPosition;
        }
    }
    if ((entry->dirty & CylinderDirtyAlpha) && !CylinderNearlyEqual(entry->view.alpha, entry->writtenAlpha)) {
        changed |= CylinderDirtyAlpha;
    }
    if (!changed) return;
    entry->dirty &= ~changed;
    entry->hasCachedFrame = NO;
}

enum {
    CylinderDebugLoggedTransform = 1 << 0,
    CylinderDebugLoggedAlpha = 1 << 1,
    CylinderDebugLoggedAnimation = 1 << 2,
    CylinderDebugLoggedForeignTransform = 1 << 3,
    CylinderDebugLoggedForeignAlpha = 1 << 4,
    CylinderDebugLoggedForeignPosition = 1 << 5,
};

static NSString *CylinderDebugEntryName(CylinderEntry *entry)
{
    BOOL page = entry == &entry->context->_page;
    return [NSString stringWithFormat:@"%@%@ superview=%@", page ? @"page " : @"", CylinderDebugDescribeView(entry->view),
            NSStringFromClass(entry->view.superview.class)];
}

static BOOL CylinderDebugOnce(CylinderEntry *entry, uint8_t flag)
{
    if (entry->debugLogged & flag) return NO;
    entry->debugLogged |= flag;
    return YES;
}

/// Running animations on a layer while Cylinder records its values mean SpringBoard is moving it.
static void CylinderDebugCheckAnimations(CylinderEntry *entry, NSString *property)
{
    NSArray<NSString *> *keys = entry->layer.animationKeys;
    if (keys.count && CylinderDebugOnce(entry, CylinderDebugLoggedAnimation)) {
        CylinderDebugLog(@"[capture] %@ recorded while layer animates (%@): %@", property, [keys componentsJoinedByString:@","], CylinderDebugEntryName(entry));
    }
}

/// SpringBoard changed a property Cylinder wrote, so its value is kept rather than the one saved before Cylinder's write.
static void CylinderDebugCheckForeignWrites(CylinderEntry *entry, CylinderDirtyFlags flags)
{
    if (!entry->layer) return;
    if ((flags & CylinderDirtyTransform) && !CylinderTransformsNearlyEqual(entry->layer.transform, entry->writtenTransform) &&
        CylinderDebugOnce(entry, CylinderDebugLoggedForeignTransform)) {
        CylinderDebugLog(@"[release] transform changed by someone else, kept: now {%@} cylinder wrote {%@} saved {%@} on %@",
                         CylinderDebugDescribeTransform(entry->layer.transform), CylinderDebugDescribeTransform(entry->writtenTransform),
                         CylinderDebugDescribeTransform(entry->savedTransform), CylinderDebugEntryName(entry));
    }
    if ((flags & CylinderDirtyAlpha) && !CylinderNearlyEqual(entry->view.alpha, entry->writtenAlpha) &&
        CylinderDebugOnce(entry, CylinderDebugLoggedForeignAlpha)) {
        CylinderDebugLog(@"[release] alpha changed by someone else, kept: now %.3f cylinder wrote %.3f saved %.3f on %@",
                         entry->view.alpha, entry->writtenAlpha, entry->savedAlpha, CylinderDebugEntryName(entry));
    }
    if ((flags & CylinderDirtyPosition) && (!CylinderNearlyEqual(entry->layer.position.x, entry->writtenPosition.x) ||
                                            !CylinderNearlyEqual(entry->layer.position.y, entry->writtenPosition.y)) &&
        CylinderDebugOnce(entry, CylinderDebugLoggedForeignPosition)) {
        CylinderDebugLog(@"[release] position changed by someone else, kept: now %@ cylinder wrote %@ saved %@ on %@",
                         NSStringFromCGPoint(entry->layer.position), NSStringFromCGPoint(entry->writtenPosition),
                         NSStringFromCGPoint(entry->savedPosition), CylinderDebugEntryName(entry));
    }
}

static void CylinderEntryRestore(CylinderEntry *entry, CylinderDirtyFlags flags)
{
    flags &= entry->dirty;
    entry->touched &= ~flags;
    if (!flags) return;
    CylinderDebugCheckForeignWrites(entry, flags);

    CylinderEntryReleaseChangedProperties(entry);
    flags &= entry->dirty;
    if (!flags) return;

    if (flags & CylinderDirtyTransform) entry->layer.transform = entry->savedTransform;
    if (flags & CylinderDirtyPosition) entry->layer.position = entry->savedPosition;
    if (flags & CylinderDirtyAlpha) entry->view.alpha = entry->savedAlpha;
    entry->dirty &= ~flags;
    entry->hasCachedFrame = NO;
}

/// A transform that only scales and translates in the plane, whose frame is its bounds scaled by m11 and m22.
static inline BOOL CylinderTransformIsPlanarScale(CATransform3D t)
{
    return t.m12 == 0 && t.m13 == 0 && t.m14 == 0 && t.m21 == 0 && t.m23 == 0 && t.m24 == 0 &&
           t.m31 == 0 && t.m32 == 0 && t.m34 == 0 && t.m44 == 1;
}

@interface CylinderPageContext ()
- (void)antialiasEntry:(CylinderEntry *)entry;
- (void)keepStackingOfIconContainers;
@end

@interface CALayer (CylinderPrivate)
/// Private, YES by default: sublayers draw in zPosition order rather than in the order of `sublayers`.
@property (nonatomic) BOOL sortsSublayers;
@end

/// Writes the staged values of `flags` that differ from what the layer shows.
static void CylinderEntryCommit(CylinderEntry *entry, CylinderDirtyFlags flags)
{
    flags &= entry->touched;

    if (flags & CylinderDirtyTransform) {
        CATransform3D current = (entry->dirty & CylinderDirtyTransform) ? entry->writtenTransform : entry->savedTransform;
        if (!CATransform3DEqualToTransform(entry->transform, current)) {
            entry->layer.transform = entry->transform;
            if (!entry->antialiased && !CylinderTransformIsPlanarScale(entry->transform)) [entry->context antialiasEntry:entry];
        }
        entry->writtenTransform = entry->transform;
        if (CATransform3DEqualToTransform(entry->transform, entry->savedTransform)) entry->dirty &= ~CylinderDirtyTransform;
        else entry->dirty |= CylinderDirtyTransform;
    }
    if (flags & CylinderDirtyPosition) {
        CGPoint current = (entry->dirty & CylinderDirtyPosition) ? entry->writtenPosition : entry->savedPosition;
        if (!CGPointEqualToPoint(entry->position, current)) entry->layer.position = entry->position;
        entry->writtenPosition = entry->position;
        if (CGPointEqualToPoint(entry->position, entry->savedPosition)) entry->dirty &= ~CylinderDirtyPosition;
        else entry->dirty |= CylinderDirtyPosition;
    }
    if (flags & CylinderDirtyAlpha) {
        CGFloat current = (entry->dirty & CylinderDirtyAlpha) ? entry->writtenAlpha : entry->savedAlpha;
        if (entry->alpha != current) entry->view.alpha = entry->alpha;
        entry->writtenAlpha = entry->alpha;
        if (entry->alpha == entry->savedAlpha) entry->dirty &= ~CylinderDirtyAlpha;
        else entry->dirty |= CylinderDirtyAlpha;
    }
}

CATransform3D CylinderEntryTransform(CylinderEntry *entry)
{
    if (entry->touched & CylinderDirtyTransform) return entry->transform;
    if (entry->dirty & CylinderDirtyTransform) return entry->savedTransform;
    return entry->layer.transform;
}

void CylinderEntrySetTransform(CylinderEntry *entry, CATransform3D transform)
{
    if (!(entry->touched & CylinderDirtyTransform)) {
        if (!(entry->dirty & CylinderDirtyTransform)) {
            entry->savedTransform = entry->layer.transform;
            if (!CATransform3DIsIdentity(entry->savedTransform) && CylinderDebugOnce(entry, CylinderDebugLoggedTransform)) {
                CylinderDebugLog(@"[capture] non-identity original transform {%@} on %@",
                                 CylinderDebugDescribeTransform(entry->savedTransform), CylinderDebugEntryName(entry));
            }
            CylinderDebugCheckAnimations(entry, @"transform");
        }
        entry->touched |= CylinderDirtyTransform;
    }
    entry->transform = transform;
    entry->hasCachedFrame = NO;
}

CGPoint CylinderEntryPosition(CylinderEntry *entry)
{
    if (entry->touched & CylinderDirtyPosition) return entry->position;
    if (entry->dirty & CylinderDirtyPosition) return entry->savedPosition;
    return entry->layer.position;
}

void CylinderEntrySetPosition(CylinderEntry *entry, CGPoint position)
{
    if (!(entry->touched & CylinderDirtyPosition)) {
        if (!(entry->dirty & CylinderDirtyPosition)) {
            entry->savedPosition = entry->layer.position;
            CylinderDebugCheckAnimations(entry, @"position");
        }
        entry->touched |= CylinderDirtyPosition;
    }
    entry->position = position;
    entry->hasCachedFrame = NO;
}

CGFloat CylinderEntryAlpha(CylinderEntry *entry)
{
    if (entry->touched & CylinderDirtyAlpha) return entry->alpha;
    if (entry->dirty & CylinderDirtyAlpha) return entry->savedAlpha;
    return entry->view.alpha;
}

void CylinderEntrySetAlpha(CylinderEntry *entry, CGFloat alpha)
{
    if (!(entry->touched & CylinderDirtyAlpha)) {
        if (!(entry->dirty & CylinderDirtyAlpha)) {
            entry->savedAlpha = entry->view.alpha;
            if (entry->savedAlpha < 0.999 && CylinderDebugOnce(entry, CylinderDebugLoggedAlpha)) {
                CylinderDebugLog(@"[capture] original alpha %.3f on %@", entry->savedAlpha, CylinderDebugEntryName(entry));
            }
            CylinderDebugCheckAnimations(entry, @"alpha");
        }
        entry->touched |= CylinderDirtyAlpha;
    }
    entry->alpha = alpha;
}

/// Scripts read UIKit's frame after their own writes, so a frame read commits this frame's geometry
/// and restores any geometry the frame has not touched before asking UIKit.
CGRect CylinderEntryFrame(CylinderEntry *entry)
{
    if (!entry->hasCachedFrame) {
        if (!(entry->touched & CylinderDirtyGeometry)) {
            entry->cachedFrame = (entry->dirty & CylinderDirtyGeometry) ? entry->baseFrame : entry->view.frame;
        } else {
            CylinderEntryRestore(entry, CylinderDirtyGeometry & ~entry->touched);
            CylinderEntryCommit(entry, CylinderDirtyGeometry);
            entry->cachedFrame = entry->view.frame;
        }
        entry->hasCachedFrame = YES;
        entry->hasCachedSize = NO;
    }
    return entry->cachedFrame;
}

/// Every write that changes the transform also drops the cached frame, so the size is cached with it.
CGSize CylinderEntrySize(CylinderEntry *entry)
{
    CGRect frame = CylinderEntryFrame(entry);
    if (!entry->hasCachedSize) {
        CATransform3D transform = CylinderEntryTransform(entry);
        if (CylinderTransformIsPlanarScale(transform)) {
            // Core Animation measures a translated frame as the difference of its translated edges, which
            // rounds away from the bounds. A page translated by the scroll offset would then report a width
            // a hair off its real one each frame, and scripts that compare against its middle would flicker.
            CGSize bounds = entry->layer.bounds.size;
            entry->cachedSize = CGSizeMake(copysign(bounds.width, transform.m11), copysign(bounds.height, transform.m22));
        } else {
            entry->cachedSize = CGSizeMake(CGRectGetWidth(frame) / transform.m11, CGRectGetHeight(frame) / transform.m22);
        }
        entry->hasCachedSize = YES;
    }
    return entry->cachedSize;
}

static inline void CylinderEntryBeginFrame(CylinderEntry *entry)
{
    entry->touched = 0;
    entry->hasCachedFrame = NO;
    if (entry->dirty) {
        CylinderDebugCheckForeignWrites(entry, entry->dirty);
        CylinderEntryReleaseChangedProperties(entry);
    }
}

static inline void CylinderEntryFinishFrame(CylinderEntry *entry)
{
    CylinderEntryCommit(entry, entry->touched);
    CylinderEntryRestore(entry, entry->dirty & ~entry->touched);
    entry->touched = 0;
}

static void CylinderEntryAttach(CylinderEntry *entry, UIView *view, CylinderPageContext *context)
{
    entry->view = view;
    entry->layer = view.layer;
    entry->context = context;
    entry->dirty = 0;
    entry->touched = 0;
    entry->hasCachedFrame = NO;
    entry->hasGridCoordinate = NO;
    entry->baseFrame = view.frame;
    entry->viewHandle = (CylinderHandle){CylinderHandleKindView, entry};
    entry->layerHandle = (CylinderHandle){CylinderHandleKindLayer, entry};
    entry->antialiased = NO;
    entry->debugLogged = 0;
}

/// Core Animation draws a tilted or rotated layer's edges aliased unless the layer allows antialiasing, and
/// SpringBoard leaves that off. An icon's artwork lives in its sublayers, so the whole tree needs it.
static void CylinderAntialiasLayerTree(CALayer *layer, NSMutableArray<CALayer *> *changed, int depth)
{
    if (!layer.allowsEdgeAntialiasing) {
        layer.allowsEdgeAntialiasing = YES;
        [changed addObject:layer];
    }
    if (depth == 0) return;
    for (CALayer *sublayer in layer.sublayers) CylinderAntialiasLayerTree(sublayer, changed, depth - 1);
}

/// The share of the view's opacity the effect is responsible for.
static CGFloat CylinderEntryEffectAlpha(CylinderEntry *entry)
{
    if (!(entry->dirty & CylinderDirtyAlpha) || entry->savedAlpha <= 0) return 1;
    return MIN(MAX(entry->writtenAlpha / entry->savedAlpha, 0), 1);
}

static NSMutableArray<CylinderPageContext *> *CylinderIdleContexts;
static NSMutableArray<CylinderPageContext *> *CylinderActiveContexts;

@interface CylinderPageContext ()
- (void)loadGridCoordinateOfEntry:(CylinderEntry *)entry;
@end

void CylinderEntryLoadGridCoordinate(CylinderEntry *entry)
{
    if (!entry->hasGridCoordinate) [entry->context loadGridCoordinateOfEntry:entry];
}

@implementation CylinderPageContext {
    SBIconListView *_retainedPage;
    NSArray<UIView *> *_iconViews;
    /// SpringBoard added or removed one of the page's views since the entries were attached.
    BOOL _subviewsChanged;
    NSUInteger _capacity;
    CylinderEntry **_iconOrder;
    BOOL _hasMetrics;
    NSUInteger _maximumIconCount;
    NSUInteger _maximumColumnCount;
    NSUInteger _maximumRowCount;
    /// -1 until resolved; 1 when SBIconCoordinate stores the row first.
    NSInteger _firstCoordinateFieldIsRow;
    /// Layers whose edge antialiasing Cylinder turned on, turned off again when the page is released.
    NSMutableArray<CALayer *> *_antialiasedLayers;
    /// Icon containers on the page whose depth sorting Cylinder turned off, turned on again when the page is released.
    NSMutableArray<CALayer *> *_unsortedContainers;
}

+ (void)initialize
{
    if (self != CylinderPageContext.class) return;
    CylinderIdleContexts = [NSMutableArray array];
    CylinderActiveContexts = [NSMutableArray array];
}

+ (instancetype)existingContextForPage:(SBIconListView *)page
{
    for (CylinderPageContext *context in CylinderActiveContexts) {
        if (context->_retainedPage == page) return context;
    }
    return nil;
}

+ (instancetype)contextForPage:(SBIconListView *)page
{
    CylinderPageContext *existing = [self existingContextForPage:page];
    if (existing) return existing;

    CylinderPageContext *context = CylinderIdleContexts.lastObject;
    if (context) {
        [CylinderIdleContexts removeLastObject];
    } else {
        context = [self new];
    }
    CylinderDebugLog(@"[context] attach %@ window=%d transform={%@} alpha=%.3f (active contexts: %lu)", CylinderDebugDescribeView(page),
                     page.window != nil, CylinderDebugDescribeTransform(page.layer.transform), page.alpha,
                     (unsigned long)CylinderActiveContexts.count + 1);

    [context attachPage:page];
    [CylinderActiveContexts addObject:context];
    return context;
}

+ (void)restoreContextsOutsideFrame:(NSUInteger)frame
{
    for (CylinderPageContext *context in CylinderActiveContexts) {
        if (context.lastFrame == frame) continue;
#ifdef CYLINDER_SIMJECT
        if (CylinderHarnessKeepOffRangePages) continue;
#endif
        [context restoreLayout];
    }
}

+ (BOOL)pageWillLayOutIcons:(SBIconListView *)page
{
    CylinderPageContext *context = [self existingContextForPage:page];
    if (!context) return NO;
    CylinderDebugLog(@"[context] SpringBoard lays out %@ mid-session, restoring and releasing it", CylinderDebugDescribeView(page));
    [context restore];
    [CylinderActiveContexts removeObjectIdenticalTo:context];
    [CylinderIdleContexts addObject:context];
    return YES;
}

+ (void)restoreAllContexts:(NSMutableArray<SBIconListView *> *)pages
{
    if (CylinderActiveContexts.count) CylinderDebugLog(@"[context] restoring %lu active contexts", (unsigned long)CylinderActiveContexts.count);
    for (CylinderPageContext *context in CylinderActiveContexts) {
        if (context->_retainedPage) [pages addObject:context->_retainedPage];
        [context restore];
        [CylinderIdleContexts addObject:context];
    }
    [CylinderActiveContexts removeAllObjects];
}

- (SBIconListView *)page
{
    return _retainedPage;
}

- (void)attachPage:(SBIconListView *)page
{
    [self ensureCapacity:CylinderInitialEntryCapacity];
    _retainedPage = page;
    CylinderEntryAttach(&_page, page, self);
    _iconViews = nil;
    _count = 0;
    _hasMetrics = NO;
    _firstCoordinateFieldIsRow = -1;
}

- (void)ensureCapacity:(NSUInteger)count
{
    if (count <= _capacity) return;

    // Handles held by Lua point into the old block, so it is retired rather than freed.
    NSUInteger capacity = MAX(count, MAX(_capacity * 2, CylinderInitialEntryCapacity));
    CylinderEntry *entries = calloc(capacity, sizeof(CylinderEntry));
    CylinderEntry **iconOrder = calloc(capacity, sizeof(CylinderEntry *));
    if (!entries || !iconOrder) abort();
    _entries = entries;
    _iconOrder = iconOrder;
    _capacity = capacity;
}

- (void)prepareForFrame
{
    if (!_iconViews || _subviewsChanged) {
#ifdef CYLINDER_SIMJECT
        if (CylinderHarnessAuditIcons) {
            // Icons flying in after an unlock sit in a container inside the page, so only views outside it count.
            NSUInteger moved = 0;
            for (NSUInteger index = 0; index < _count; index++) {
                if (_entries[index].dirty && ![_entries[index].view isDescendantOfView:_retainedPage]) moved++;
            }
            if (moved) CylinderHarnessLogLine([NSString stringWithFormat:@"[CylinderAudit] page %p restores %lu views that already left it", _retainedPage, (unsigned long)moved]);
        }
#endif
        BOOL firstAttach = !_iconViews;
        // Undo the old layout's changes while its views are still retained, then adopt the new one.
        for (NSUInteger index = 0; index < _count; index++) CylinderEntryRestore(&_entries[index], CylinderDirtyAll);
        // The page enumerates its icon views wherever they are, including inside the container SpringBoard moves
        // them into while they fly in after an unlock, which shares the page's frame.
        NSMutableArray<UIView *> *iconViews = [NSMutableArray array];
        [_retainedPage enumerateIconViewsUsingBlock:^(SBIconView *iconView, __unused NSUInteger index, __unused BOOL *stop) {
            [iconViews addObject:iconView];
        }];
        NSUInteger count = iconViews.count;
        [self ensureCapacity:count];
        NSUInteger index = 0;
        for (UIView *iconView in iconViews) {
            CylinderEntryAttach(&_entries[index], iconView, self);
            _iconOrder[index] = &_entries[index];
            index++;
        }
        _iconViews = iconViews;
        _subviewsChanged = NO;
        _count = count;
        // A tilted page tilts the icons that joined it too.
        if (_page.antialiased) [self antialiasEntry:&_page];
        [self keepStackingOfIconContainers];

        NSMutableString *unusual = [NSMutableString string];
        for (UIView *iconView in iconViews) {
            CALayer *layer = iconView.layer;
            BOOL foreignSuperview = iconView.superview != _retainedPage;
            BOOL transformed = !CATransform3DIsIdentity(layer.transform);
            if (!foreignSuperview && !transformed && iconView.alpha >= 0.999 && !layer.animationKeys.count && !iconView.hidden) continue;
            [unusual appendFormat:@"\n    %@ superview=%@ transform={%@} alpha=%.3f hidden=%d animations=%@", CylinderDebugDescribeView(iconView),
                                  NSStringFromClass(iconView.superview.class), CylinderDebugDescribeTransform(layer.transform), iconView.alpha,
                                  iconView.hidden, [layer.animationKeys componentsJoinedByString:@","] ?: @"none"];
        }
        CylinderDebugLog(@"[context] %@ icon views for %@: %lu%@", firstAttach ? @"adopted" : @"re-adopted (subviews changed)",
                         CylinderDebugDescribeView(_retainedPage), (unsigned long)count, unusual);
    }

    for (NSUInteger index = 0; index < _count; index++) CylinderEntryBeginFrame(&_entries[index]);
    CylinderEntryBeginFrame(&_page);
}

- (void)finishFrame
{
    for (NSUInteger index = 0; index < _count; index++) CylinderEntryFinishFrame(&_entries[index]);
    CylinderEntryFinishFrame(&_page);
}

- (void)restoreLayout
{
    for (NSUInteger index = 0; index < _count; index++) CylinderEntryRestore(&_entries[index], CylinderDirtyAll);
    CylinderEntryRestore(&_page, CylinderDirtyAll);
}

- (void)subviewWillLeave:(UIView *)subview
{
    CylinderDebugLog(@"[context] %@ leaves %@ mid-session", CylinderDebugDescribeView(subview), CylinderDebugDescribeView(_retainedPage));
    for (NSUInteger index = 0; index < _count; index++) {
        if (_entries[index].view != subview) continue;
        CylinderEntryRestore(&_entries[index], CylinderDirtyAll);
        break;
    }
    _subviewsChanged = YES;
}

- (void)subviewDidJoin
{
    CylinderDebugLog(@"[context] subview joined %@ mid-session", CylinderDebugDescribeView(_retainedPage));
    _subviewsChanged = YES;
}

+ (void)iconViewWillMove:(UIView *)iconView
{
    for (CylinderPageContext *context in CylinderActiveContexts) {
        for (NSUInteger index = 0; index < context->_count; index++) {
            if (context->_entries[index].view != iconView) continue;
            CylinderDebugLog(@"[context] %@ moves out of %@ mid-session", CylinderDebugDescribeView(iconView),
                             NSStringFromClass(iconView.superview.class));
            // Undo the effect while the view is still where it was applied. Otherwise it carries the effect's
            // values to its next page, which saves them as that icon's originals.
            CylinderEntryRestore(&context->_entries[index], CylinderDirtyAll);
            context->_subviewsChanged = YES;
            break;
        }
    }
}

- (void)antialiasEntry:(CylinderEntry *)entry
{
    if (!_antialiasedLayers) _antialiasedLayers = [NSMutableArray array];
    entry->antialiased = YES;
    if (entry != &_page) {
        CylinderAntialiasLayerTree(entry->layer, _antialiasedLayers, 8);
        return;
    }
    // The page draws nothing itself, but its transform tilts every icon on it.
    for (NSUInteger index = 0; index < _count; index++) {
        if (!_entries[index].antialiased) [self antialiasEntry:&_entries[index]];
    }
}

/// After an unlock SpringBoard flies the icons in from a container on the page that sorts them by a zPosition it
/// springs with staggered timing. Effects that overlap icons would swap their stacking many times during the
/// fly-in, so while the page is in a session the container keeps the order the page itself draws them in.
- (void)keepStackingOfIconContainers
{
    for (UIView *iconView in _iconViews) {
        UIView *container = iconView.superview;
        if (!container || container == _retainedPage || ![container isDescendantOfView:_retainedPage]) continue;
        CALayer *layer = container.layer;
        if (![layer respondsToSelector:@selector(setSortsSublayers:)] || !layer.sortsSublayers) continue;
        layer.sortsSublayers = NO;
        if (!_unsortedContainers) _unsortedContainers = [NSMutableArray array];
        [_unsortedContainers addObject:layer];
    }
}

- (CGFloat)effectAlphaOfView:(UIView *)view
{
    CGFloat alpha = CylinderEntryEffectAlpha(&_page);
    for (NSUInteger index = 0; index < _count; index++) {
        if (_entries[index].view == view) return alpha * CylinderEntryEffectAlpha(&_entries[index]);
    }
    return alpha;
}

- (void)restore
{
    [self restoreLayout];
    for (CALayer *layer in _antialiasedLayers) layer.allowsEdgeAntialiasing = NO;
    [_antialiasedLayers removeAllObjects];
    for (CALayer *layer in _unsortedContainers) layer.sortsSublayers = YES;
    [_unsortedContainers removeAllObjects];
    _iconViews = nil;
    _retainedPage = nil;
    _page.view = nil;
    _page.layer = nil;
    _count = 0;
    _hasMetrics = NO;
}

static NSUInteger CylinderGridCount(NSUInteger count)
{
    return count <= 1024 ? count : 0;
}

- (void)loadMetrics
{
    if (_hasMetrics) return;
    SBIconListView *page = _retainedPage;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (@available(iOS 13, *)) {
        _maximumIconCount = CylinderGridCount(page.maximumIconCount);
    } else {
        _maximumIconCount = CylinderGridCount(page.maxIcons);
    }
#pragma clang diagnostic pop
    _maximumColumnCount = CylinderGridCount(page.iconColumnsForCurrentOrientation);
    _maximumRowCount = CylinderGridCount(page.iconRowsForCurrentOrientation);
    _hasMetrics = YES;
}

- (NSUInteger)maximumIconCount
{
    [self loadMetrics];
    return _maximumIconCount;
}

- (NSUInteger)maximumColumnCount
{
    [self loadMetrics];
    return _maximumColumnCount;
}

- (NSUInteger)maximumRowCount
{
    [self loadMetrics];
    return _maximumRowCount;
}

/// SBIconCoordinate's field order changed after iOS 15 without an ABI change, so it is measured
/// once per session. Two icons that share one field lie apart along the other field's axis. Empty
/// cells cannot be probed with originForIconAtCoordinate: instead: iOS 15 answers with the origin of
/// the icon covering the cell, so a widget in the corner makes every probe land on the same point.
- (BOOL)firstCoordinateFieldIsRow API_AVAILABLE(ios(14.0))
{
    static NSInteger measuredFirstCoordinateFieldIsRow = -1;
    if (_firstCoordinateFieldIsRow < 0) _firstCoordinateFieldIsRow = measuredFirstCoordinateFieldIsRow;

    if (_firstCoordinateFieldIsRow < 0) {
        SBIconListView *page = _retainedPage;
        NSUInteger count;
        CylinderEntry **icons = [self iconEntriesWithCount:&count];
        SBIconCoordinate coordinates[MAX(count, 1)];
        CGPoint centers[MAX(count, 1)];
        for (NSUInteger i = 0; i < count; i++) {
            SBIconView *iconView = (SBIconView *)icons[i]->view;
            SBIcon *icon = iconView.icon;
            coordinates[i] = icon ? [page coordinateForIcon:icon] : (SBIconCoordinate){0, 0};
            centers[i] = iconView.center;
        }

        NSInteger rowFirstVotes = 0;
        for (NSUInteger i = 0; i < count; i++) {
            for (NSUInteger j = i + 1; j < count; j++) {
                SBIconCoordinate a = coordinates[i], b = coordinates[j];
                if (!a.first || !b.first) continue;
                CGFloat dx = fabs(centers[i].x - centers[j].x);
                CGFloat dy = fabs(centers[i].y - centers[j].y);
                if (dx == dy) continue;
                if (a.second == b.second && a.first != b.first) {
                    rowFirstVotes += dy > dx ? 1 : -1;
                } else if (a.first == b.first && a.second != b.second) {
                    rowFirstVotes += dx > dy ? 1 : -1;
                }
            }
        }
        if (rowFirstVotes != 0) {
            _firstCoordinateFieldIsRow = rowFirstVotes > 0;
            measuredFirstCoordinateFieldIsRow = _firstCoordinateFieldIsRow;
            return _firstCoordinateFieldIsRow == 1;
        }

        CGPoint base = [page originForIconAtCoordinate:(SBIconCoordinate){1, 1}];
        CGPoint firstIncrement = [page originForIconAtCoordinate:(SBIconCoordinate){2, 1}];
        CGPoint secondIncrement = [page originForIconAtCoordinate:(SBIconCoordinate){1, 2}];
        CGFloat rowFirstScore = fabs(firstIncrement.y - base.y) + fabs(secondIncrement.x - base.x);
        CGFloat columnFirstScore = fabs(firstIncrement.x - base.x) + fabs(secondIncrement.y - base.y);
        _firstCoordinateFieldIsRow = rowFirstScore > columnFirstScore;
    }
    return _firstCoordinateFieldIsRow == 1;
}

- (void)loadGridCoordinateOfEntry:(CylinderEntry *)entry
{
    entry->hasGridCoordinate = YES;
    entry->row = 0;
    entry->column = 0;
    if (entry == &_page) return;

    NSInteger columns = MAX((NSInteger)self.maximumColumnCount, 1);
    NSInteger rows = MAX((NSInteger)self.maximumRowCount, 1);

    NSUInteger count;
    CylinderEntry **icons = [self iconEntriesWithCount:&count];
    NSInteger iconIndex = 0;
    while ((NSUInteger)iconIndex < count && icons[iconIndex] != entry) iconIndex++;
    entry->row = iconIndex / columns;
    entry->column = iconIndex % columns;

    if (@available(iOS 14, *)) {
        SBIcon *icon = ((SBIconView *)entry->view).icon;
        if (!icon) return;

        SBIconCoordinate coordinate = [_retainedPage coordinateForIcon:icon];
        BOOL rowFirst = [self firstCoordinateFieldIsRow];
        NSInteger row = (NSInteger)(rowFirst ? coordinate.first : coordinate.second) - 1;
        NSInteger column = (NSInteger)(rowFirst ? coordinate.second : coordinate.first) - 1;
        if (row >= 0 && column >= 0 && row < rows && column < columns) {
            entry->row = row;
            entry->column = column;
        }
    }
}

- (CylinderEntry **)iconEntriesWithCount:(NSUInteger *)count
{
    *count = _count;
    return _iconOrder;
}

@end
