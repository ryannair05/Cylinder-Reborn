#import "CylinderSettings.h"
#import "../Defines.h"
#import "CLEffect.h"

@interface CylinderSettingsListController()
{
    NSString *_defaultFooterText;
}
@property (nonatomic, retain, readwrite) NSMutableDictionary *settings;
@end

@implementation CylinderSettingsListController
@synthesize settings = _settings;

- (instancetype)init { 
    self = [super init];

    if (self) {
        self.settings = ([NSMutableDictionary dictionaryWithContentsOfFile:PREFS_PATH] ?: DefaultPrefs);
        if(![[_settings valueForKey:PrefsEffectKey] isKindOfClass:NSArray.class]) [_settings setValue:nil forKey:PrefsEffectKey];
        _defaultFooterText = [[NSDictionary dictionaryWithContentsOfFile:@"/Library/PreferenceBundles/CylinderSettings.bundle/en.lproj/CylinderSettings.strings"] objectForKey:@"FOOTER_TEXT"];
    }
    return self;
}

- (NSArray *)specifiers {
	if (_specifiers == nil) {
		_specifiers = [self loadSpecifiersFromPlistName:@"CylinderSettings" target:self];
	}
	return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {

    [_settings setValue:value forKey:specifier.properties[@"key"]];

    [self writeSettings];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return ([_settings objectForKey:specifier.properties[@"key"]]) ?: specifier.properties[@"default"];
}

- (void)visitWebsite:(id)sender {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://r333d.com"] options:@{} completionHandler:nil];
}

-(void)visitBarrel:(id)sender
{
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"cydia://package/com.aaronash.barrel"] options:@{} completionHandler:nil];
}

- (void)visitTwitter:(id)sender {
    NSString* user = @"rweichler";
    NSURL* url = [NSURL URLWithString: [@"https://twitter.com/" stringByAppendingString:user]];

    if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"tweetbot://"]]) {
        url = [NSURL URLWithString: [@"tweetbot:///user_profile/" stringByAppendingString:user]];
    } else if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"twitterrific://"]]) {
        url = [NSURL URLWithString: [@"twitterrific:///profile?screen_name=" stringByAppendingString:user]];
    } else if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"tweetings://"]]) {
        url = [NSURL URLWithString: [@"tweetings:///user?screen_name=" stringByAppendingString:user]];
    } else if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"twitter://"]]) {
        url = [NSURL URLWithString: [@"twitter://user?screen_name=" stringByAppendingString:user]];
    }

    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
}

- (void)visitGithub:(id)sender {
	[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://github.com/ryannair05/Cylinder-Reborn"] options:@{} completionHandler:nil];
}

- (void)visitReddit:(id)sender {
    if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"apollo://"]]) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"apollo://reddit.com/r/cylinder"] options:@{} completionHandler:nil];
    }
    else {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://reddit.com/r/cylinder"] options:@{} completionHandler:nil];
    }
}

- (void)writeSettings {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:self.settings format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];

	if (!data)
		return;
	[data writeToFile:PREFS_PATH atomically:NO];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (CFStringRef) kCylinderSettingsChanged, NULL, NULL, YES);
}

-(void)setSelectedEffects:(NSArray *)effects
{
    NSMutableString *text = [NSMutableString string];
    NSMutableArray *toWrite = [NSMutableArray arrayWithCapacity:effects.count];
    for(CLEffect *effect in effects)
    {
        if(!effect.name || !effect.directory) continue;

        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:effect.name, PrefsEffectKey, effect.directory, PrefsEffectDirKey, nil];
        [toWrite addObject:dict];

        [text appendString:effect.name];
        if(effect != effects.lastObject)
        {
            [text appendString:@", "];
        }
    }

    UITableViewCell *cell = [self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    cell.detailTextLabel.text = text;

    [_settings setObject:toWrite forKey:PrefsEffectKey];
    self.selectedFormula = nil;
    [self writeSettings];
}

-(void)setFormulas:(NSDictionary *)formulas
{
    [_settings setObject:formulas forKey:PrefsFormulaKey];
}

-(void)setSelectedFormula:(NSString *)formula
{
    if(!formula)
    {
        [_settings removeObjectForKey:PrefsSelectedFormulaKey];
        return;
    }

    [_settings setObject:formula forKey:PrefsSelectedFormulaKey];

    NSDictionary *formulas = [_settings objectForKey:PrefsFormulaKey];
    NSArray *effects = [formulas objectForKey:formula];

    if(effects)
        [_settings setObject:effects forKey:PrefsEffectKey];

}

-(NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
    if(section == 1)
        return LOCALIZE(@"FOOTER_TEXT", _defaultFooterText);
    else
        return [super tableView:tableView titleForFooterInSection:section];
}

@end
