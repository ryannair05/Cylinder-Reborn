
#import <UIKit/UIKit.h>

void write_error(const char *error);

#define CHECK_NAN(NUM, STR)\
    if(isnan(NUM))\
        return luaL_error(L, STR" is NaN. It is either too large or is imaginary")

@interface SBIcon : NSObject
@property (nonatomic,copy,readonly) NSString * displayName; 
@end 


@interface SBIconImageView : UIView
@end 

@interface SBIconImageCrossfadeView : UIView
@end 

@interface SBIconView : UIView {
    SBIconImageView* _iconImageView;
    SBIconImageCrossfadeView* _crossfadeView;
}

@property (nonatomic,retain) SBIcon *icon;
@end 

NS_CLASS_AVAILABLE_IOS(4_0) @interface SBIconListView : UIView
@property(readonly, nonatomic) NSUInteger maximumIconCount API_AVAILABLE(ios(13.0));
@property(readonly, nonatomic) NSUInteger maxIcons API_DEPRECATED_WITH_REPLACEMENT("maximumIconCount", ios(4.0, 13.0));
@property(readonly, nonatomic) NSUInteger iconColumnsForCurrentOrientation;
@property(readonly, nonatomic) NSUInteger iconRowsForCurrentOrientation;

-(NSArray *)icons;
-(void)layoutIconsNow;
- (void)setIconsNeedLayout;

- (void)setAlphaForAllIcons:(CGFloat)alpha;
- (void)enumerateIconViewsUsingBlock:(void(^)())block;

@end

@interface SBIconScrollView : UIScrollView
@end 

@interface SBFolder : NSObject
@property (nonatomic, assign, readonly) NSUInteger listCount;
@end

@interface SBRootFolder : SBFolder
@end

@interface SBIconController : UIViewController
+ (id)sharedInstance;
@property (nonatomic, assign, readonly) SBRootFolder *rootFolder;
@end

@interface SBFolderView : UIView 
@property (assign,getter=isRotating,nonatomic) BOOL rotating;

- (void)enumerateIconListViewsUsingBlock:(void(^)())block;
@end 
