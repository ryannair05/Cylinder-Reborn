#import "../Defines.h"
#import "CLEffectsController.h"
#import "CylinderSettings.h"

#import "CLAlignedTableViewCell.h"

static CLEffectsController *sharedController = nil;

@interface PSViewController(Private)
-(void)viewWillAppear:(BOOL)animated;
@end

@implementation CLEffectsController
@synthesize effects = _effects, selectedEffects=_selectedEffects;

- (instancetype)init
{
	if (self = [super init])
    {
        _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height) style:UITableViewStyleGrouped];
        _tableView.dataSource = self;
        _tableView.delegate = self;
        // _tableView.editing = false;
        // _tableView.allowsSelection = true;

        // _tableView.allowsMultipleSelection = false;
        // _tableView.allowsSelectionDuringEditing = true;
        // _tableView.allowsMultipleSelectionDuringEditing = true;
    
		if ([self respondsToSelector:@selector(setView:)])
			[self performSelectorOnMainThread:@selector(setView:) withObject:_tableView waitUntilDone:YES];

        self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0,0,10,10)];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:17];
        self.titleLabel.text = @"Effects";
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.navigationItem.titleView = [UIView new];
        [self.navigationItem.titleView addSubview:self.titleLabel];

        [NSLayoutConstraint activateConstraints:@[
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.navigationItem.titleView.topAnchor],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.navigationItem.titleView.leadingAnchor],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.navigationItem.titleView.trailingAnchor],
            [self.titleLabel.bottomAnchor constraintEqualToAnchor:self.navigationItem.titleView.bottomAnchor],
        ]];

        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:LOCALIZE(@"RESET_EFFECTS", @"Clear") style:UIBarButtonItemStylePlain target:self action:@selector(clear:)];

	}
    sharedController = self;
	return self;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"WARNING: combining certain 3D effects may cause lag";
    }
    return nil;
}

- (void)addEffectsFromDirectory:(NSString *)directory
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray *directoryContents = [manager contentsOfDirectoryAtPath:directory error:nil];

    for (NSString *dirName in directoryContents)
    {
        NSString *path = [directory stringByAppendingPathComponent:dirName];

        BOOL isDir;
        if(![manager fileExistsAtPath:path isDirectory:&isDir] || !isDir) continue;

        NSArray *scripts = [manager contentsOfDirectoryAtPath:path error:nil];
        if(scripts.count == 0) continue;

        for(NSString *script in scripts)
        {
            CLEffect *effect = [[CLEffect alloc] initWithPath:[path stringByAppendingPathComponent:script]];
            if(effect)
                [self.effects addObject:effect];
        }
    }
    [self.effects sortUsingComparator:^NSComparisonResult(CLEffect *effect1, CLEffect *effect2)
    {
        return [effect1.name compare:effect2.name];
    }];
}

-(CLEffect *)effectWithName:(NSString *)name inDirectory:(NSString *)directory
{
    if(!name || !directory) return nil;

    for(CLEffect *effect in self.effects)
    {
        if([effect.name isEqualToString:name] && [effect.directory isEqualToString:directory])
        {
            return effect;
        }
    }
    return nil;
}

- (void)refreshList
{
    self.effects = [NSMutableArray array];
    CylinderSettingsListController *ctrl = (CylinderSettingsListController*)self.parentController;
    [self addEffectsFromDirectory:kEffectsDirectory];

    NSArray *effects = [ctrl.settings objectForKey:PrefsEffectKey];
    self.selectedEffects = [NSMutableArray array];

    for(NSDictionary *dict in effects)
    {
        NSString *name = [dict objectForKey:PrefsEffectKey];
        NSString *dir = [dict objectForKey:PrefsEffectDirKey];
        CLEffect *effect = [self effectWithName:name inDirectory:dir];
        effect.selected = true;
        if(effect)
            [self.selectedEffects addObject:effect];
    }
}

- (void)clear:(id)sender
{
    for(CLEffect *effect in self.selectedEffects)
    {
        effect.selected = false;
        [self setCellIcon:effect.cell effect:effect];
    }

    self.selectedEffects = [NSMutableArray array];
    [_tableView reloadData];

    [self updateSettings];
}

- (void)viewWillAppear:(BOOL)animated
{
    if(!_initialized)
    {
        [self refreshList];
        _initialized = true;
    }
    [super viewWillAppear:animated];

}

- (void)dealloc
{
    sharedController = nil;
}

- (id)view
{
    return _tableView;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.effects.count;

}

-(void)setCellIcon:(UITableViewCell *)cell effect:(CLEffect *)effect
{
    if(effect.broken)
        cell.imageView.image = [UIImage imageWithContentsOfFile:BUNDLE_PATH "error.png"];
}

-(id)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    CLAlignedTableViewCell *cell = (CLAlignedTableViewCell*)[tableView dequeueReusableCellWithIdentifier:@"EffectCell"];
    if (!cell)
    {
        cell = [CLAlignedTableViewCell.alloc initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"EffectCell"];
        cell.textLabel.adjustsFontSizeToFitWidth = true;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    CLEffect *effect = [self.effects objectAtIndex:indexPath.row];
    effect.cell = cell;

    cell.textLabel.text = effect.name;
    cell.detailTextLabel.text = effect.directory;
    [self setCellIcon:cell effect:effect];

    cell.numberLabel.text = effect.selected ? [NSString stringWithFormat:@"%lu", ([self.selectedEffects indexOfObject:effect] + 1)] : @"";

    return cell;
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!tableView.isEditing)
    {
        // deselect old one
        [tableView deselectRowAtIndexPath:indexPath animated:true];

        CLEffect *effect = [self.effects objectAtIndex:indexPath.row];
        effect.selected = !effect.selected;

        if(effect.selected)
        {
            [self.selectedEffects addObject:effect];
            CLEffect *e = [self.selectedEffects objectAtIndex: self.selectedEffects.count-1];
            CLAlignedTableViewCell *cell = (CLAlignedTableViewCell *)e.cell;
            cell.numberLabel.text = [NSString stringWithFormat:@"%lu",  self.selectedEffects.count];
        }
        else
        {
            effect.cell.numberLabel.text = @"";
            [self.selectedEffects removeObject:effect];
        }

        [self updateSettings];
    }
}

-(void)updateSettings
{
    // make the title changes
    CylinderSettingsListController *ctrl = (CylinderSettingsListController*)self.parentController;
    ctrl.selectedEffects = self.selectedEffects;
}

@end

#define ERROR_DIR @"/var/mobile/Library/Logs/Cylinder/.errornotify"

static void luaErrorNotification()
{
    CLEffectsController *self = sharedController;
    if(!self) return;
    BOOL isDir;
    if(![NSFileManager.defaultManager fileExistsAtPath:ERROR_DIR isDirectory:&isDir] || isDir) return;

    BOOL changed = false;
    NSArray *errors = [NSArray arrayWithContentsOfFile:ERROR_DIR];
    for(NSDictionary *effectDict in errors)
    {
        NSString *name = [effectDict valueForKey:PrefsEffectKey];
        NSString *folder = [effectDict valueForKey:PrefsEffectDirKey];
        CLEffect *effect = [self effectWithName:name inDirectory:folder];
        BOOL broken = [[effectDict valueForKey:@"broken"] boolValue];

        if(broken && !effect.broken) changed = true;

        effect.broken = broken;

        [self setCellIcon:effect.cell effect:effect];
    }
    if(changed) [[self view] reloadData];
}

static __attribute__((constructor)) void __wbsInit() {

    CFNotificationCenterRef r = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(r, NULL, (CFNotificationCallback)luaErrorNotification, (CFStringRef)@"luaERROR", NULL, CFNotificationSuspensionBehaviorCoalesce);
}
