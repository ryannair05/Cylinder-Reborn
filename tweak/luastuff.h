#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import "../lua/lua.h"
#import "CylinderPageContext.h"

void close_lua(void);
BOOL init_lua(NSArray *scripts, BOOL random);
/// Runs the selected scripts against the page. Returns NO once every script has failed.
BOOL manipulate(CylinderPageContext *context, CGFloat offset, u_int32_t rand);
