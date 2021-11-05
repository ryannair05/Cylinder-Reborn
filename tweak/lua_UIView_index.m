#import "lua_UIView.h"
#import "lua_UIView_index.h"
#import "UIView+Cylinder.h"
#import "tweak.h"
#import "luastuff.h"

static int _viewIndexTable;

static int l_transform_rotate(lua_State *L);
static int l_transform_translate(lua_State *L);
static int l_transform_scale(lua_State *L);

int l_uiview_index(lua_State *L)
{
    UIView *self = (__bridge UIView *)lua_touserdata(L, 1);
    if(lua_isnumber(L, 2)) //if it's a number, return the subview
    {
        if(![self isKindOfClass:objc_getClass("SBIconListView")]) {
            return luaL_error(L, "trying to get icon from object that is not a list");
        }
        int index = lua_tonumber(L, 2) - 1;
        if(index >= 0 && index < self.subviews.count)
        {
            UIView *view = self.subviews[index];
            if (![view isKindOfClass:objc_getClass("SBFTouchPassThroughView")]) {
                return l_push_view(L, view);
            }
        }
    }
    else if(lua_isstring(L, 2))
    {
        lua_rawgeti(L, LUA_REGISTRYINDEX, _viewIndexTable);
        int lastStackTop = lua_gettop(L);
        lua_pushvalue(L, 2);
        lua_gettable(L, -2);
        lua_pushvalue(L, 1);
        lua_call(L, 1, LUA_MULTRET);
        int diff = lua_gettop(L) - lastStackTop;
        return diff;
    }

    return 0;
}


static int l_uiview_index_subviews(lua_State *L)
{
    SBIconListView *self = (__bridge SBIconListView *)lua_touserdata(L, 1);
    if(![self isKindOfClass:objc_getClass("SBIconListView")]) {
        return luaL_error(L, "trying to get icon from object that is not a list");
    }
    lua_newtable(L);

    [self enumerateIconViewsUsingBlock:^(SBIconView *view, NSUInteger idx)  {
        lua_pushnumber(L, idx+1);
        l_push_view(L, view);
        lua_settable(L, -3);
    }];
    return 1;
}

static int l_uiview_index_alpha(lua_State *L)
{
    UIView *self = (__bridge UIView *)lua_touserdata(L, 1);
    lua_pushnumber(L, self.alpha);
    return 1;
}

static int l_uiview_index_rotate(lua_State *L)
{
    lua_pushcfunction(L, l_transform_rotate);
    return 1;
}

static int l_uiview_index_translate(lua_State *L)
{
    lua_pushcfunction(L, l_transform_translate);
    return 1;
}

static int l_uiview_index_scale(lua_State *L)
{
    lua_pushcfunction(L, l_transform_scale);
    return 1;
}

static int l_uiview_index_x(lua_State *L)
{
    UIView *self = (__bridge UIView *)lua_touserdata(L, 1);
    lua_pushnumber(L, self.frame.origin.x);
    return 1;
}

static int l_uiview_index_y(lua_State *L)
{
    UIView *self = (__bridge UIView *)lua_touserdata(L, 1);
    lua_pushnumber(L, self.frame.origin.y);
    return 1;
}

static int l_uiview_index_width(lua_State *L)
{
    UIView *self = (__bridge UIView *)lua_touserdata(L, 1);
    lua_pushnumber(L, self.frame.size.width/self.layer.transform.m11);
    return 1;
}

static int l_uiview_index_height(lua_State *L)
{
    UIView *self = (__bridge UIView *)lua_touserdata(L, 1);
    lua_pushnumber(L, self.frame.size.height/self.layer.transform.m22);
    return 1;
}

static int l_uiview_index_max_icons(lua_State *L)
{
    
    SBIconListView *self = (__bridge SBIconListView *)lua_touserdata(L, 1);

    if (@available(iOS 13, *)) {
        lua_pushnumber(L, self.maximumIconCount);
    } 
    else {
        lua_pushnumber(L, self.maxIcons);
    }

    return 1;
}

static int l_uiview_index_max_columns(lua_State *L)
{
    SBIconListView *self = (__bridge SBIconListView *)lua_touserdata(L, 1);

    lua_pushnumber(L, self.iconColumnsForCurrentOrientation);

    return 1;
}

static int l_uiview_index_max_rows(lua_State *L)
{
    SBIconListView *self = (__bridge SBIconListView *)lua_touserdata(L, 1);

    lua_pushnumber(L, self.iconRowsForCurrentOrientation);

    return 1;
}

static int l_uiview_index_layer(lua_State *L)
{
    UIView *self = (__bridge UIView *)lua_touserdata(L, 1);
    return l_push_view(L, self.layer);
}

#define PUSH_FUNC(X)                            \
    lua_pushstring(L, #X);                      \
    lua_pushcfunction(L, l_uiview_index_##X);   \
    lua_settable(L, -3);

void l_create_viewindextable(lua_State *L)
{
    lua_newtable(L);
    PUSH_FUNC(subviews);
    PUSH_FUNC(alpha);
    PUSH_FUNC(rotate);
    PUSH_FUNC(translate);
    PUSH_FUNC(scale);
    PUSH_FUNC(x);
    PUSH_FUNC(y);
    PUSH_FUNC(width);
    PUSH_FUNC(height);
    PUSH_FUNC(max_icons);
    PUSH_FUNC(max_columns);
    PUSH_FUNC(max_rows);
    PUSH_FUNC(layer);
    _viewIndexTable = luaL_ref(L, LUA_REGISTRYINDEX);
}

static int l_transform_rotate(lua_State *L)
{
    // CHECK_UIVIEW(L, 1);

    UIView *self = (__bridge UIView *)lua_touserdata(L, 1);

    if ([self isKindOfClass:objc_getClass("MTMaterialView")]) {
        return 0;
    }

    CATransform3D transform = self.layer.transform;
    float pitch = 0, yaw = 0, roll = 0;
    if(!lua_isnumber(L, 3))
        roll = 1;
    else
    {
        pitch = lua_tonumber(L, 3);
        yaw = lua_tonumber(L, 4);
        roll = lua_tonumber(L, 5);
    }

    CHECK_NAN(pitch, "the pitch of the rotation");
    CHECK_NAN(yaw, "the yaw of the rotation");
    CHECK_NAN(roll, "the roll of the rotation");

    if(fabs(pitch) > 0.01 || fabs(yaw) > 0.01)
        transform.m34 = -1/PERSPECTIVE_DISTANCE;

    transform = CATransform3DRotate(transform, lua_tonumber(L, 2), pitch, yaw, roll);

    self.layer.transform = transform;

    return 0;
}

static int l_transform_translate(lua_State *L)
{

    UIView *self = (__bridge UIView *)lua_touserdata(L, 1);

    if ([self isKindOfClass:objc_getClass("MTMaterialView")]) {
        return 0;
    }

    CATransform3D transform = self.layer.transform;
    float x = lua_tonumber(L, 2), y = lua_tonumber(L, 3), z = lua_tonumber(L, 4);

    CHECK_NAN(x, "the x value for the translation");
    CHECK_NAN(y, "the y value for the translation");
    CHECK_NAN(z, "the z value for the translation");

    float oldm34 = transform.m34;
    if(fabs(z) > 0.01)
        transform.m34 = -1/PERSPECTIVE_DISTANCE;
    transform = CATransform3DTranslate(transform, x, y, z);
    transform.m34 = oldm34;

    self.layer.transform = transform;

    return 0;
}

static int l_transform_scale(lua_State *L)
{
    UIView *self = (__bridge UIView *)lua_touserdata(L, 1);

    if ([self isKindOfClass:objc_getClass("MTMaterialView")]) {
        return 0;
    }

    CATransform3D transform = self.layer.transform;
    float x = lua_tonumber(L, 2);
    float y = lua_isnumber(L, 3) ? lua_tonumber(L, 3) : x;
    float z = lua_isnumber(L, 4) ? lua_tonumber(L, 4) : 1;

    CHECK_NAN(x, "the x value for the scale");
    CHECK_NAN(y, "the y value for the scale");
    CHECK_NAN(z, "the z value for the scale");

    float oldm34 = transform.m34;
    transform.m34 = -1/PERSPECTIVE_DISTANCE;
    transform = CATransform3DScale(transform, x, y, z);
    transform.m34 = oldm34;

    self.layer.transform = transform;

    return 0;
}
