#import "tweak.h"
#import "luastuff.h"
#import "../Defines.h"
#import "UIView+Cylinder.h"

static BOOL _enabled;
static u_int32_t _randSeedForCurrentPage;

void reset_icon_layout(UIView *self)
{
    self.layer.transform = CATransform3DIdentity;
    [self.layer restorePosition];
    self.alpha = 1;
    self.wasModifiedByCylinder = false;
    for(UIView *v in self.subviews)
    {
        v.layer.transform = CATransform3DIdentity;
        [v.layer restorePosition];
        v.alpha = 1;
    }
}

void page_swipe(UIScrollView *scrollView, int page)
{
    CGRect eye = {scrollView.contentOffset, scrollView.frame.size};

    if (page == scrollView.subviews.count-1) {
        page--;
    }

    for (int i = page; i <= page + 1; i++) {
        UIView *view = scrollView.subviews[i];

        if (view.subviews.count < 1 || ![view.subviews[0] isMemberOfClass:%c(SBIconView)]) continue;

        if (view.wasModifiedByCylinder)
        {
            reset_icon_layout(view);
        }

        if(CGRectIntersectsRect(eye, view.frame))
        {
            const float offset = scrollView.contentOffset.x - view.frame.origin.x;

            _enabled = manipulate(view, offset, _randSeedForCurrentPage); //defined in luastuff.m
            view.wasModifiedByCylinder = true;

        }
    }
}


void end_scroll(UIScrollView *self)
{
    for(UIView *view in [self subviews]) {
        if([view isMemberOfClass:%c(SBIconListView)]) reset_icon_layout(view);
    }
}

@interface SBFolderView : UIView 
@property (assign,getter=isRotating,nonatomic) BOOL rotating;
@property (nonatomic,readonly) long long currentPageIndex;
-(id)scrollView;
@end 

%hook SBFolderView //SBIconController
-(void)scrollViewDidScroll:(UIScrollView *)scrollView
{   
    %orig;

    //these are for detecting if the scroll is actually just
    //a rotation. if its a rotation, then dont
    //cylinder-ize it.
    if(!_enabled || self.isRotating) return;

    page_swipe(scrollView, self.currentPageIndex - 99);
}

-(void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    %orig;

    if(_enabled) {
        end_scroll(scrollView);
        _randSeedForCurrentPage = arc4random();
    }
}

// For iOS 13. SpringBoard "optimizes" the icon visibility by only showing the bare
// minimum. I have no idea why this works, but it does. An interesting stack trace can
// be found by forcing a crash in -[SBRecycledViewsContainer addSubview:]. Probably best to decompile this function in IDA or something.
-(void)updateVisibleColumnRangeWithTotalLists:(unsigned long long)arg1 columnsPerList:(unsigned long long)arg2 iconVisibilityHandling:(long long)arg3
{
    return %orig(arg1, arg2, 0);
}

%end


static void loadPrefs()
{
    NSDictionary *settings = [NSDictionary dictionaryWithContentsOfFile:PREFS_PATH];

    if(settings && ![[settings valueForKey:PrefsEnabledKey] boolValue])
    {
        close_lua();
        _enabled = false;
    }
    else
    {
        BOOL random = [[settings valueForKey:PrefsRandomizedKey] boolValue];
        NSArray *effects = [settings valueForKey:PrefsEffectKey];
        _enabled = init_lua(effects, random);
    }
}


// the reason for this is create_state() in luastuff.m,
// which loadPrefs() calls, is called when SpringBoard loads.
// Unfortunately calling UIScreen.mainScreen.bounds.size
// causes a bootloop. so instead of setting that 
// global variable there, we set it when we know that
// everything in SpringBoard has already loaded
%hook SpringBoard
-(void)applicationDidFinishLaunching:(id)application 
{
    %orig;
	loadPrefs();
}
%end

%ctor{
    %init;

    //listen to notification center (for settings change)
    CFNotificationCenterRef r = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(r, NULL, (CFNotificationCallback)loadPrefs, (CFStringRef)kCylinderSettingsChanged, NULL, CFNotificationSuspensionBehaviorCoalesce);
}
