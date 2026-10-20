#import "CylinderTransitionCoordinator.h"

#import "tweak.h"

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>


typedef struct {
    double m[3][3];
} CylinderHomography;

static const CylinderHomography CylinderHomographyIdentity = {{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}};

static CylinderHomography CylinderHomographyMultiply(CylinderHomography a, CylinderHomography b)
{
    CylinderHomography r;
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
            r.m[i][j] = a.m[i][0] * b.m[0][j] + a.m[i][1] * b.m[1][j] + a.m[i][2] * b.m[2][j];
        }
    }
    return r;
}

static BOOL CylinderHomographyInvert(CylinderHomography a, CylinderHomography *result)
{
    double (*m)[3] = a.m;
    double c00 = m[1][1] * m[2][2] - m[1][2] * m[2][1];
    double c01 = m[1][2] * m[2][0] - m[1][0] * m[2][2];
    double c02 = m[1][0] * m[2][1] - m[1][1] * m[2][0];
    double det = m[0][0] * c00 + m[0][1] * c01 + m[0][2] * c02;
    if (fabs(det) < 1e-12) return NO;

    double inv = 1.0 / det;
    *result = (CylinderHomography){{
        {c00 * inv, (m[0][2] * m[2][1] - m[0][1] * m[2][2]) * inv, (m[0][1] * m[1][2] - m[0][2] * m[1][1]) * inv},
        {c01 * inv, (m[0][0] * m[2][2] - m[0][2] * m[2][0]) * inv, (m[0][2] * m[1][0] - m[0][0] * m[1][2]) * inv},
        {c02 * inv, (m[0][1] * m[2][0] - m[0][0] * m[2][1]) * inv, (m[0][0] * m[1][1] - m[0][1] * m[1][0]) * inv},
    }};
    return YES;
}

static CylinderHomography CylinderHomographyTranslation(double x, double y)
{
    return (CylinderHomography){{{1, 0, 0}, {0, 1, 0}, {x, y, 1}}};
}

/// Drops the z row and column, which is exactly what flattening into the parent's plane does.
static CylinderHomography CylinderHomographyFromTransform(CATransform3D t)
{
    return (CylinderHomography){{{t.m11, t.m12, t.m14}, {t.m21, t.m22, t.m24}, {t.m41, t.m42, t.m44}}};
}

static CATransform3D CylinderTransformFromHomography(CylinderHomography h)
{
    CATransform3D t = CATransform3DIdentity;
    t.m11 = h.m[0][0]; t.m12 = h.m[0][1]; t.m14 = h.m[0][2];
    t.m21 = h.m[1][0]; t.m22 = h.m[1][1]; t.m24 = h.m[1][2];
    t.m41 = h.m[2][0]; t.m42 = h.m[2][1]; t.m44 = h.m[2][2];
    return t;
}

static CGPoint CylinderAnchorInBounds(CALayer *layer)
{
    CGRect bounds = layer.bounds;
    CGPoint anchor = layer.anchorPoint;
    return CGPointMake(CGRectGetMinX(bounds) + anchor.x * CGRectGetWidth(bounds),
                       CGRectGetMinY(bounds) + anchor.y * CGRectGetHeight(bounds));
}

static CylinderHomography CylinderSublayerStep(CALayer *layer)
{
    CATransform3D sublayerTransform = layer.sublayerTransform;
    if (CATransform3DIsIdentity(sublayerTransform)) return CylinderHomographyIdentity;

    CGPoint anchor = CylinderAnchorInBounds(layer);
    CylinderHomography step = CylinderHomographyTranslation(-anchor.x, -anchor.y);
    step = CylinderHomographyMultiply(step, CylinderHomographyFromTransform(sublayerTransform));
    return CylinderHomographyMultiply(step, CylinderHomographyTranslation(anchor.x, anchor.y));
}

static CylinderHomography CylinderLayerToScreen(CALayer *layer);

/// Maps `layer`'s bounds space to the screen with `layer` drawn at `position` in its superlayer.
static CylinderHomography CylinderLayerToScreenAtPosition(CALayer *layer, CGPoint position)
{
    CGPoint anchor = CylinderAnchorInBounds(layer);
    CylinderHomography result = CylinderHomographyTranslation(-anchor.x, -anchor.y);
    result = CylinderHomographyMultiply(result, CylinderHomographyFromTransform(layer.transform));
    result = CylinderHomographyMultiply(result, CylinderHomographyTranslation(position.x, position.y));

    CALayer *superlayer = layer.superlayer;
    if (!superlayer) return result;
    result = CylinderHomographyMultiply(result, CylinderSublayerStep(superlayer));
    return CylinderHomographyMultiply(result, CylinderLayerToScreen(superlayer));
}

static CylinderHomography CylinderLayerToScreen(CALayer *layer)
{
    return CylinderLayerToScreenAtPosition(layer, layer.position);
}

static BOOL CylinderProjectPoint(CGPoint point, CylinderHomography h, CGPoint *result)
{
    double x = point.x * h.m[0][0] + point.y * h.m[1][0] + h.m[2][0];
    double y = point.x * h.m[0][1] + point.y * h.m[1][1] + h.m[2][1];
    double w = point.x * h.m[0][2] + point.y * h.m[1][2] + h.m[2][2];
    if (fabs(w) < 1e-12) return NO;
    *result = CGPointMake(x / w, y / w);
    return YES;
}

static BOOL CylinderLayerIsInside(CALayer *layer, CALayer *ancestor)
{
    for (CALayer *current = layer; current; current = current.superlayer) {
        if (current == ancestor) return YES;
    }
    return NO;
}

typedef struct {
    __unsafe_unretained CALayer *layer;
    __unsafe_unretained CALayer *source;
    CGPoint point;
} CylinderMatchMove;

static BOOL CylinderFindMatchMove(CALayer *layer, CALayer *icon, CylinderMatchMove *result)
{
    static Class matchMoveClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ matchMoveClass = NSClassFromString(@"CAMatchMoveAnimation"); });
    if (!matchMoveClass) return NO;

    for (CALayer *candidate = layer; candidate; candidate = candidate.superlayer) {
        for (NSString *key in candidate.animationKeys) {
            CAAnimation *animation = [candidate animationForKey:key];
            if (![animation isKindOfClass:matchMoveClass]) continue;
            if ([[animation valueForKey:@"targetsSuperlayer"] boolValue]) continue;

            id source = [animation valueForKey:@"sourceLayer"];
            NSArray<NSValue *> *points = [animation valueForKey:@"sourcePoints"];
            if (![source isKindOfClass:CALayer.class] || (icon && !CylinderLayerIsInside(source, icon))) continue;
            if (![points isKindOfClass:NSArray.class] || points.count == 0) continue;

            *result = (CylinderMatchMove){candidate, source, points.firstObject.CGPointValue};
            return YES;
        }
    }
    return NO;
}

@interface CylinderPendingHandBack : NSObject
- (instancetype)initWithLayer:(CALayer *)layer sublayerTransform:(CATransform3D)sublayerTransform opacity:(float)opacity;
- (void)finish;
/// Leaves the opacity to SpringBoard, which has taken it over.
- (void)leaveOpacity;
@end

@implementation CylinderPendingHandBack {
    __weak CALayer *_layer;
    CATransform3D _sublayerTransform;
    float _opacity;
    BOOL _restoresOpacity;
    CFTimeInterval _deadline;
    CADisplayLink *_link;
}

- (instancetype)initWithLayer:(CALayer *)layer sublayerTransform:(CATransform3D)sublayerTransform opacity:(float)opacity
{
    if ((self = [super init])) {
        _layer = layer;
        _sublayerTransform = sublayerTransform;
        _opacity = opacity;
        _restoresOpacity = YES;
        _deadline = CACurrentMediaTime() + 1;
        _link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
        [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    return self;
}

static BOOL CylinderLayerIsAnimating(CALayer *layer, int depth)
{
    if (layer.animationKeys.count) return YES;
    if (depth == 0) return NO;
    for (CALayer *sublayer in layer.sublayers) {
        if (CylinderLayerIsAnimating(sublayer, depth - 1)) return YES;
    }
    return NO;
}

- (void)tick
{
    CALayer *layer = _layer;
    if (!layer || CACurrentMediaTime() >= _deadline || !CylinderLayerIsAnimating(layer, 2)) [self finish];
}

- (void)finish
{
    [_link invalidate];
    _link = nil;
    CALayer *layer = _layer;
    if (!layer) return;
    _layer = nil;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.sublayerTransform = _sublayerTransform;
    if (_restoresOpacity) layer.opacity = _opacity;
    [CATransaction commit];
}

- (void)leaveOpacity
{
    _restoresOpacity = NO;
}

@end

/// SpringBoard runs one icon zoom at a time, so a single active transition needs no per-animator storage.
static SBIcon *CylinderTransitionIcon;
static __weak SBIconView *CylinderFlyingIconView;
static __weak CALayer *CylinderSteeredLayer;
static CATransform3D CylinderSavedSublayerTransform;
static float CylinderSavedOpacity;
static CylinderHomography CylinderBaselineToScreen;
static CylinderHomography CylinderSourceBaselineToScreen;
/// Looked up again each frame, so its unretained layers never outlive the frame that found them.
static CylinderMatchMove CylinderActiveMatchMove;
static BOOL CylinderHasMatchMove;
static __weak SBIconView *CylinderBaselineIconView;
static BOOL CylinderFlightHidden;
static CylinderPendingHandBack *CylinderHandBack;
static CGFloat CylinderTargetPageOffsetX = NAN;
static CGFloat CylinderContentOffsetX;
static CGFloat CylinderPageWidth;

static void CylinderReleaseSteering(void)
{
    CylinderHasMatchMove = NO;
    CylinderFlightHidden = NO;
    CALayer *layer = CylinderSteeredLayer;
    if (!layer) return;

    layer.sublayerTransform = CylinderSavedSublayerTransform;
    layer.opacity = CylinderSavedOpacity;
    CylinderSteeredLayer = nil;
}

static void CylinderTakeLayer(CALayer *layer)
{
    if (CylinderSteeredLayer == layer) return;
    CylinderReleaseSteering();
    [CylinderHandBack finish];
    CylinderHandBack = nil;
    CylinderSteeredLayer = layer;
    CylinderSavedSublayerTransform = layer.sublayerTransform;
    CylinderSavedOpacity = layer.opacity;
}

void CylinderTransitionPrepared(SBIconView *iconView)
{
    CylinderReleaseSteering();
    CylinderTransitionIcon = iconView.icon;
    CylinderFlyingIconView = iconView;
    CylinderBaselineIconView = nil;
    CylinderTargetPageOffsetX = NAN;
}

void CylinderTransitionWillCleanup(SBIconView *iconView)
{
    if (CylinderFlyingIconView != iconView) return;

    BOOL settledElsewhere = !isnan(CylinderTargetPageOffsetX) &&
        fabs(CylinderContentOffsetX - CylinderTargetPageOffsetX) >= CylinderPageWidth / 2;
    CylinderMatchMove match;
    CALayer *layer = CylinderSteeredLayer;
    if (!layer && CylinderFindMatchMove(iconView.layer, nil, &match)) layer = match.layer;
    if ((CylinderFlightHidden || settledElsewhere) && layer) {
        CylinderTakeLayer(layer);
        CylinderHandBack = [[CylinderPendingHandBack alloc] initWithLayer:layer
                                                       sublayerTransform:CylinderSavedSublayerTransform
                                                                 opacity:CylinderSavedOpacity];
        layer.opacity = 0;
        CylinderSteeredLayer = nil;
    }
    CylinderReleaseSteering();
    CylinderTransitionIcon = nil;
    CylinderFlyingIconView = nil;
    CylinderBaselineIconView = nil;
}

void CylinderTransitionWillBeHiddenBySpringBoard(void)
{
    [CylinderHandBack leaveOpacity];
    CALayer *layer = CylinderSteeredLayer;
    if (layer) {
        [CylinderHandBack finish];
        CylinderHandBack = [[CylinderPendingHandBack alloc] initWithLayer:layer
                                                       sublayerTransform:CylinderSavedSublayerTransform
                                                                 opacity:CylinderSavedOpacity];
        [CylinderHandBack leaveOpacity];
        CylinderSteeredLayer = nil;
    }
    CylinderHasMatchMove = NO;
    CylinderFlightHidden = NO;
    CylinderTransitionIcon = nil;
    CylinderFlyingIconView = nil;
    CylinderBaselineIconView = nil;
    CylinderTargetPageOffsetX = NAN;
}

SBIconView *CylinderTransitionTargetOnPage(SBIconListView *listView)
{
    if (!CylinderTransitionIcon) return nil;

    SBIconView *flyingIconView = CylinderFlyingIconView;
    SBIconView *targetIconView = [listView displayedIconViewForIcon:CylinderTransitionIcon];
    // Some transitions animate the Home Screen icon itself, which already inherits the page transform.
    if (!flyingIconView || targetIconView == flyingIconView) return nil;
    return targetIconView;
}

/// Also records the match-move's source, which SpringBoard adds after preparing the crossfade.
void CylinderTransitionCaptureBaseline(SBIconView *iconView, CGFloat pageOffsetX)
{
    CylinderTargetPageOffsetX = pageOffsetX;
    CylinderBaselineToScreen = CylinderLayerToScreen(iconView.layer);
    CylinderHasMatchMove = CylinderFindMatchMove(CylinderFlyingIconView.layer, iconView.layer, &CylinderActiveMatchMove);
    if (CylinderHasMatchMove && CylinderActiveMatchMove.source != iconView.layer) {
        CylinderSourceBaselineToScreen = CylinderLayerToScreen(CylinderActiveMatchMove.source);
    } else {
        CylinderSourceBaselineToScreen = CylinderBaselineToScreen;
    }
    CylinderBaselineIconView = iconView;
}

void CylinderTransitionFollow(SBIconView *iconView)
{
    SBIconView *flyingIconView = CylinderFlyingIconView;
    if (!flyingIconView || CylinderBaselineIconView != iconView) return;

    CylinderHomography iconToScreen = CylinderLayerToScreen(iconView.layer);
    CALayer *layer;
    CGPoint renderedPosition;
    CGPoint stockPosition;

    CALayer *matchedSuperlayer = CylinderHasMatchMove ? CylinderActiveMatchMove.layer.superlayer : nil;
    if (matchedSuperlayer) {
        CylinderHomography screenToSuperlayer;
        CylinderHomography superlayerToScreen = CylinderHomographyMultiply(CylinderSublayerStep(matchedSuperlayer),
                                                                           CylinderLayerToScreen(matchedSuperlayer));
        if (!CylinderHomographyInvert(superlayerToScreen, &screenToSuperlayer)) return;

        CALayer *source = CylinderActiveMatchMove.source;
        CylinderHomography sourceToScreen = source == iconView.layer ? iconToScreen : CylinderLayerToScreen(source);
        CGPoint point = CylinderActiveMatchMove.point;
        if (!CylinderProjectPoint(point, CylinderHomographyMultiply(sourceToScreen, screenToSuperlayer), &renderedPosition) ||
            !CylinderProjectPoint(point, CylinderHomographyMultiply(CylinderSourceBaselineToScreen, screenToSuperlayer), &stockPosition)) {
            return;
        }
        layer = CylinderActiveMatchMove.layer;
    } else {
        layer = flyingIconView.superview.layer;
        if (!layer) return;
        renderedPosition = layer.position;
        stockPosition = layer.position;
    }

    CylinderTakeLayer(layer);

    CylinderHomography baselineInverse;
    CylinderHomography screenToRendered;
    if (!CylinderHomographyInvert(CylinderBaselineToScreen, &baselineInverse) ||
        !CylinderHomographyInvert(CylinderLayerToScreenAtPosition(layer, renderedPosition), &screenToRendered)) {
        return;
    }
    CylinderHomography correction = CylinderHomographyMultiply(baselineInverse, iconToScreen);

    CGPoint anchor = CylinderAnchorInBounds(layer);
    CylinderHomography sublayer = CylinderHomographyFromTransform(CylinderSavedSublayerTransform);
    sublayer = CylinderHomographyMultiply(sublayer, CylinderHomographyTranslation(anchor.x, anchor.y));
    sublayer = CylinderHomographyMultiply(sublayer, CylinderLayerToScreenAtPosition(layer, stockPosition));
    sublayer = CylinderHomographyMultiply(sublayer, correction);
    sublayer = CylinderHomographyMultiply(sublayer, screenToRendered);
    sublayer = CylinderHomographyMultiply(sublayer, CylinderHomographyTranslation(-anchor.x, -anchor.y));

    CylinderFlightHidden = NO;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.sublayerTransform = CylinderTransformFromHomography(sublayer);
    layer.opacity = CylinderSavedOpacity * iconView.alpha * iconView.superview.alpha;
    [CATransaction commit];
}

void CylinderTransitionPagesRestored(void)
{
    CylinderReleaseSteering();
    CylinderBaselineIconView = nil;
    CylinderTransitionHideIfTargetIsGone();
}

void CylinderTransitionFinishFrame(CGFloat contentOffsetX, CGFloat pageWidth)
{
    CylinderContentOffsetX = contentOffsetX;
    CylinderPageWidth = pageWidth;
    CylinderTransitionHideIfTargetIsGone();
}

void CylinderTransitionHideIfTargetIsGone(void)
{
    SBIconView *flyingIconView = CylinderFlyingIconView;
    CylinderMatchMove match;
    if (!CylinderTransitionIcon || !flyingIconView || !CylinderFindMatchMove(flyingIconView.layer, nil, &match)) return;

    BOOL visible = NO;
    SBIconView *source = (SBIconView *)match.source.delegate;
    if ([source isKindOfClass:UIView.class] && [source respondsToSelector:@selector(icon)] && source.icon == CylinderTransitionIcon) {
        UIWindow *window = source.window;
        visible = window && CGRectIntersectsRect([source convertRect:source.bounds toView:nil], window.bounds);
    }

    if (!visible) {
        CylinderTakeLayer(match.layer);
        match.layer.opacity = 0;
        CylinderFlightHidden = YES;
    } else if (CylinderFlightHidden && CylinderSteeredLayer == match.layer) {
        match.layer.opacity = CylinderSavedOpacity;
        CylinderFlightHidden = NO;
    }
}
