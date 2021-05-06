#import "tweak.h"
#import "luastuff.h"
#import "../Defines.h"
#import "UIView+Cylinder.h"

static BOOL _enabled;
static u_int32_t _randSeedForCurrentPage;
__weak static SBIconView *neededView;
static NSMutableArray *frameArray;

void reset_icon_layout(__unsafe_unretained SBIconListView *self)
{
    self.layer.transform = CATransform3DIdentity;
    [self.layer restorePosition];
    self.alpha = 1;
    
    [self enumerateIconViewsUsingBlock:^(SBIconView *v)  {
        v.layer.transform = CATransform3DIdentity;
        [v.layer restorePosition];
    }];

    [self setAlphaForAllIcons:1];
}

void page_swipe(SBFolderView *self, SBIconScrollView *scrollView)
{
    CGRect eye = {scrollView.contentOffset, scrollView.frame.size};

    if (neededView) {
        for (int i = 0; i < scrollView.subviews.count; i++)
        {
            if ([frameArray[i] isKindOfClass:%c(__NSFrozenDictionaryM)]) {
                continue;
            }

            __unsafe_unretained UIView *view = scrollView.subviews[i];
            if (view.subviews.count < 1 || ![view.subviews[0] isMemberOfClass:%c(SBIconView)]) continue;
            
            // make a dictionary of the frames of all the icons
            NSMutableDictionary *frames = [[NSMutableDictionary alloc] init];

            for (SBIconView* iconview in view.subviews) {
                [frames setObject:NSStringFromCGRect([iconview frame]) forKey:[iconview.icon displayName]];
            }
            [frameArray replaceObjectAtIndex:i withObject:frames.copy];
        }
    }

    for (int i = 0; i < scrollView.subviews.count; i++) {
        __unsafe_unretained SBIconListView *view = scrollView.subviews[i];
        // make sure it is an SBIconListView and actually has icons
        if (view.subviews.count < 1 || ![view.subviews[0] isMemberOfClass:%c(SBIconView)]) continue;

        if (view.wasModifiedByCylinder)
        {
            reset_icon_layout(view);
        }
        else if (neededView && [frameArray[i] isKindOfClass:%c(__NSFrozenDictionaryM)] && [frameArray[i] objectForKey:[neededView.icon displayName]]) {
            neededView.frame = CGRectFromString([frameArray[i] valueForKey:[neededView.icon displayName]]);
            neededView.layer.transform = CATransform3DIdentity;
            [view addSubview:neededView];
        }

        if(CGRectIntersectsRect(eye, view.frame))
        {
            const float offset = scrollView.contentOffset.x - view.frame.origin.x;

            _enabled = manipulate((UIView *) view, offset, _randSeedForCurrentPage); //defined in luastuff.m
            view.wasModifiedByCylinder = true;
        }
    }
}


void end_scroll(__unsafe_unretained SBFolderView *self)
{
    [self enumerateIconListViewsUsingBlock:^(SBIconListView *view)  {
         reset_icon_layout(view);
         view.wasModifiedByCylinder = false;
         [view setIconsNeedLayout];
    }];
}

%hook SBFolderView //SBIconController
-(void)scrollViewDidScroll:(SBIconScrollView *)scrollView
{   
    %orig;

    //if its a rotation, then dont
    //cylinder-ize it.
    if(!_enabled || self.isRotating) return;

    page_swipe(self, scrollView);
}

-(void)scrollViewDidEndDecelerating:(SBIconScrollView *)scrollView
{
    %orig;

    if(_enabled) {
        end_scroll(self);
        _randSeedForCurrentPage = arc4random();
    }
}

// For iOS 13, SpringBoard "optimizes" the icon visibility by only showing the bare
// minimum. I have no idea why this works, but it does. An interesting stack trace can
// be found by forcing a crash in -[SBRecycledViewsContainer addSubview:]. Probably best to decompile this function in IDA or something.
-(void)updateVisibleColumnRangeWithTotalLists:(NSUInteger)arg1 columnsPerList:(NSUInteger)arg2 iconVisibilityHandling:(NSInteger)arg3
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

    if (@available(iOS 14, *)) {
        const int count = [[[%c(SBIconController) sharedInstance] rootFolder] listCount] + 2; // get number of icon pages
        frameArray = [NSMutableArray arrayWithCapacity:count]; 

        for (int i = 0; i < count; i++) {
            [frameArray insertObject:[NSNumber numberWithInt:i] atIndex:i];
        }
    }
}
%end

%group animationHack

%hook SBIconView
- (void)prepareToCrossfadeImageWithView:(UIView *)arg1 anchorPoint:(CGPoint)arg2 options:(NSUInteger)arg3{
    if (arg3 == 3) { // If arg3 equals 2, then it is a folder which we don't want to modify
        neededView = self;
    }
    return %orig;
}
%end

%hook SBIconImageCrossfadeView
-(void)cleanup {
    if (neededView) {
        [neededView removeFromSuperview];
        neededView = nil;
    }
    return %orig;
}
%end
%end


%ctor{
    %init;

    if (@available(iOS 14, *)) { // Only works on iOS 14, support for older versions is needed
        %init(animationHack);
        // This is nowhere close to a proper fix, but it's the best solution I could come up with
    }

    //listen to notification center (for settings change)
    CFNotificationCenterRef r = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(r, NULL, (CFNotificationCallback)loadPrefs, (CFStringRef)kCylinderSettingsChanged, NULL, CFNotificationSuspensionBehaviorCoalesce);
}
