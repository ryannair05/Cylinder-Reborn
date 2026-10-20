#import "../lua/lua.h"
#import "../lua/lauxlib.h"
#import "CylinderPageContext.h"
#import "../Defines.h"

/// Installs the metatable shared by every light userdata value, which Cylinder only uses for handles.
void l_create_uiview_metatable(lua_State *L);
int l_push_base_transform(lua_State *L);

static inline void l_push_handle(lua_State *L, CylinderHandle *handle)
{
    lua_pushlightuserdata(L, handle);
}
