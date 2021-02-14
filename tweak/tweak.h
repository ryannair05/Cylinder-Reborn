
#import <UIKit/UIKit.h>

void write_error(const char *error);

#define CHECK_NAN(NUM, STR)\
    if(isnan(NUM))\
        return luaL_error(L, STR" is NaN. It is either too large or is imaginary")
