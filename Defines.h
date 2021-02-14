#import <UIKit/UIKit.h>
#import <os/log.h>
#import <substrate.h>

#define CLLog(format, ...) os_log(OS_LOG_DEFAULT, "Cylinder: %@", [NSString stringWithFormat: format, ## __VA_ARGS__])
#define Log CLLog

#define SCREEN_SIZE UIScreen.mainScreen.bounds.size

#define PrefsEffectKey        @"effect"
#define PrefsEffectDirKey  @"effectFolder"
#define PrefsFormulaKey @"formula"
#define PrefsSelectedFormulaKey @"selectedFormula"
#define PrefsCarrierTextKey  @"carrierText"
#define PrefsUseTextKey      @"useText"
#define PrefsEnabledKey      @"enabled"
#define PrefsRandomizedKey      @"randomized"
#define PrefsOldMethodKey    @"useOldMethod"

#define PrefsPackKey         @"pack"
#define PrefsBrokenKey       @"brokenEffects"

#define DEFAULT_EFFECT @"Cube (inside)"
#define DEFAULT_DIRECTORY @"rweichler"

#ifndef MAIN_BUNDLE
#define MAIN_BUNDLE ([NSBundle bundleForClass:NSClassFromString(@"CylinderSettingsListController")])
#endif
#define LOCALIZE(KEY, DEFAULT) [MAIN_BUNDLE localizedStringForKey:KEY value:DEFAULT table:@"CylinderSettings"]
#define SYSTEM_LOCALIZE(KEY) [[NSBundle bundleWithIdentifier:@"com.apple.UIKit"] localizedStringForKey:KEY value:@"" table:nil]

#define IN_SPRINGBOARD()     ([[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"])
#define PREFS_PATH           @"/var/mobile/Library/Preferences/com.ryannair05.cylinder.plist"
#define RETINIZE(r)          [r stringByAppendingString:@"@2x"]

#define kCylinderSettingsChanged         @"com.ryannair05.cylinder/settingsChanged"
#define kCylinderSettingsRefreshSettings @"com.ryannair05.cylinder/refreshSettings"

#define BUNDLE_PATH @"/Library/PreferenceBundles/CylinderSettings.bundle/"

#define kEffectsDirectory     @"/Library/Cylinder"
#define kPacksDirectory      @"/Library/Cylinder/Packs"
#define DEFAULT_EFFECTS      [NSArray arrayWithObjects:[NSDictionary dictionaryWithObjectsAndKeys:DEFAULT_EFFECT, PrefsEffectKey, DEFAULT_DIRECTORY, PrefsEffectDirKey, nil], nil]
#define DEFAULT_FORMULAS    [NSDictionary dictionary]
#define DefaultPrefs         [NSMutableDictionary dictionaryWithObjectsAndKeys: DEFAULT_EFFECTS, PrefsEffectKey, DEFAULT_FORMULAS, PrefsFormulaKey, [NSNumber numberWithBool:YES], PrefsEnabledKey, [NSNumber numberWithBool:false], PrefsRandomizedKey, nil]

