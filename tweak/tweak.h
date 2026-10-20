
#import <UIKit/UIKit.h>

void write_error(const char *error);

#define CHECK_NAN(NUM, STR)\
    if(isnan(NUM))\
        return luaL_error(L, STR" is NaN. It is either too large or is imaginary")

typedef NS_OPTIONS(NSUInteger, SBIconViewCrossfadeOptions) {
    SBIconViewCrossfadeOptionMasksCorners = 1 << 0,
    SBIconViewCrossfadeOptionPerformsTrueCrossfade = 1 << 1,
    SBIconViewCrossfadeOptionUsesDoubleSidedView = 1 << 2,
    SBIconViewCrossfadeOptionUsesAlternateStyle = 1 << 3,
};

typedef NS_CLOSED_ENUM(NSInteger, SBIconVisibilityHandling) {
    SBIconVisibilityHandlingNone = 0,
    SBIconVisibilityHandlingDefault = 1,
    SBIconVisibilityHandlingLibraryPod = 2,
};

typedef struct SBIconCoordinate {
    NSUInteger first;
    NSUInteger second;
} SBIconCoordinate;

@interface SBIcon : NSObject
@property (nonatomic,copy,readonly) NSString * displayName; 
@end

@interface SBIconView : UIView
@property (nonatomic,retain) SBIcon *icon;
- (void)prepareToCrossfadeImageWithView:(UIView *)view
                            anchorPoint:(CGPoint)anchorPoint
                                options:(SBIconViewCrossfadeOptions)options API_AVAILABLE(ios(14.0));
- (void)cleanupAfterCrossfade API_AVAILABLE(ios(10.0));
@end 

NS_CLASS_AVAILABLE_IOS(4_0) @interface SBIconListView : UIView
@property(readonly, nonatomic) NSUInteger maximumIconCount API_AVAILABLE(ios(13.0));
@property(readonly, nonatomic) NSUInteger maxIcons API_DEPRECATED_WITH_REPLACEMENT("maximumIconCount", ios(4.0, 13.0));
@property(readonly, nonatomic) NSUInteger iconColumnsForCurrentOrientation;
@property(readonly, nonatomic) NSUInteger iconRowsForCurrentOrientation;
- (SBIconView *)displayedIconViewForIcon:(SBIcon *)icon API_AVAILABLE(ios(13.0));
- (SBIconCoordinate)coordinateForIcon:(SBIcon *)icon API_AVAILABLE(ios(7.0));
- (CGPoint)originForIconAtCoordinate:(SBIconCoordinate)coordinate API_AVAILABLE(ios(7.0));
- (void)setIconsNeedLayout;

- (void)enumerateIconViewsUsingBlock:(void (^)(SBIconView *iconView, NSUInteger index, BOOL *stop))block;

@end

@interface SBIconScrollView : UIScrollView
@end 

@interface SBFluidSwitcherViewController : UIViewController
- (void)_temporarilyHideMatchMovedZoomDownAnimationViewAnimated:(BOOL)animated API_AVAILABLE(ios(13.0));
@end

NS_CLASS_AVAILABLE_IOS(4_0) @interface SBFolderView : UIView
- (void)getLeadingVisiblePageIndex:(NSInteger *)leadingPageIndex
         trailingVisiblePageIndex:(NSInteger *)trailingPageIndex API_AVAILABLE(ios(14.0));
- (SBIconListView *)iconListViewForPageIndex:(NSInteger)pageIndex API_AVAILABLE(ios(14.0));
- (CGPoint)_scrollOffsetForPageAtIndex:(NSInteger)pageIndex API_AVAILABLE(ios(7.0));
- (BOOL)isScrolling API_AVAILABLE(ios(5.0));
- (void)_addScrollingCompletionBlock:(dispatch_block_t)completion API_AVAILABLE(ios(11.0));
- (SBIconVisibilityHandling)iconVisibilityHandling API_AVAILABLE(ios(13.0));
- (void)performWhenScrollingEndsUsingBlock:(dispatch_block_t)completion API_AVAILABLE(ios(11.0));
@end
