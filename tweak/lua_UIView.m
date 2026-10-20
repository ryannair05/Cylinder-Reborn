#import "lua_UIView.h"
#import "tweak.h"

/// Every view or layer a script touches is a CylinderHandle passed as light userdata. Lua gives all
/// light userdata one shared metatable, so it is installed once and pushing a handle is a single store.

static inline CylinderHandle *l_check_handle(lua_State *L, int index)
{
    CylinderHandle *handle = (CylinderHandle *)lua_touserdata(L, index);
    if (!handle) luaL_error(L, "first argument must be a view");
    return handle;
}

static inline BOOL l_is_page(CylinderEntry *entry)
{
    return entry == &entry->context->_page;
}

#define CHECK_PAGE(L, ENTRY) \
    if (!l_is_page(ENTRY)) return luaL_error(L, "trying to get icon from object that is not a list")

static const char *ERR_MALFORMED = "malformed transformation matrix";

#define CALL_TRANSFORM_MACRO(F, ...) \
    F(m11, ##__VA_ARGS__); \
    F(m12, ##__VA_ARGS__); \
    F(m13, ##__VA_ARGS__); \
    F(m14, ##__VA_ARGS__); \
    F(m21, ##__VA_ARGS__); \
    F(m22, ##__VA_ARGS__); \
    F(m23, ##__VA_ARGS__); \
    F(m24, ##__VA_ARGS__); \
    F(m31, ##__VA_ARGS__); \
    F(m32, ##__VA_ARGS__); \
    F(m33, ##__VA_ARGS__); \
    F(m34, ##__VA_ARGS__); \
    F(m41, ##__VA_ARGS__); \
    F(m42, ##__VA_ARGS__); \
    F(m43, ##__VA_ARGS__); \
    F(m44, ##__VA_ARGS__);

#define PUSH_TRANSFORM_STEP(M, LUASTATE, I, TRANSFORM) \
    lua_pushnumber(LUASTATE, TRANSFORM.M); \
    lua_rawseti(LUASTATE, -2, ++I);

static int l_push_transform(lua_State *L, CATransform3D transform)
{
    lua_createtable(L, 16, 0);
    int i = 0;
    CALL_TRANSFORM_MACRO(PUSH_TRANSFORM_STEP, L, i, transform);
    return 1;
}

int l_push_base_transform(lua_State *L)
{
    return l_push_transform(L, CATransform3DIdentity);
}

#define FILL_TRANSFORM(M, LUASTATE, I, TRANSFORM) \
    if (lua_rawgeti(LUASTATE, VALUE, ++I) != LUA_TNUMBER) \
        return luaL_error(LUASTATE, ERR_MALFORMED); \
    TRANSFORM.M = lua_tonumber(LUASTATE, -1); \
    lua_pop(LUASTATE, 1); \
    CHECK_NAN(TRANSFORM.M, "the "#M" of the transform");

static int l_set_transform(lua_State *L, CylinderEntry *entry)
{
    const int VALUE = 3;
    if (!lua_istable(L, VALUE))
        return luaL_error(L, "transform must be a table");
    if (luaL_len(L, VALUE) != 16)
        return luaL_error(L, ERR_MALFORMED);

    CATransform3D transform;
    int i = 0;
    CALL_TRANSFORM_MACRO(FILL_TRANSFORM, L, i, transform);
    CylinderEntrySetTransform(entry, transform);
    return 0;
}

#pragma mark - Transform methods

static int l_transform_rotate(lua_State *L)
{
    CylinderEntry *entry = l_check_handle(L, 1)->entry;

    lua_Number angle = lua_tonumber(L, 2);
    // `rotate(angle)` spins around z. Once an axis is given, its missing components are 0, as in the original
    // Cylinder, so `rotate(angle, 0, 1)` turns around y rather than around (0, 1, 1).
    lua_Number pitch = 0, yaw = 0, roll = 1;
    if (lua_isnumber(L, 3)) {
        pitch = lua_tonumber(L, 3);
        yaw = luaL_optnumber(L, 4, 0);
        roll = luaL_optnumber(L, 5, 0);
    }

    CHECK_NAN(pitch, "the pitch of the rotation");
    CHECK_NAN(yaw, "the yaw of the rotation");
    CHECK_NAN(roll, "the roll of the rotation");

    CATransform3D transform = CylinderEntryTransform(entry);
    if (fabs(pitch) > 0.01 || fabs(yaw) > 0.01)
        transform.m34 = -1 / CylinderPerspectiveDistance;

    CylinderEntrySetTransform(entry, CATransform3DRotate(transform, angle, pitch, yaw, roll));
    return 0;
}

static int l_transform_translate(lua_State *L)
{
    CylinderEntry *entry = l_check_handle(L, 1)->entry;

    lua_Number x = lua_tonumber(L, 2), y = lua_tonumber(L, 3), z = lua_tonumber(L, 4);

    CHECK_NAN(x, "the x value for the translation");
    CHECK_NAN(y, "the y value for the translation");
    CHECK_NAN(z, "the z value for the translation");

    CATransform3D transform = CylinderEntryTransform(entry);
    CGFloat oldm34 = transform.m34;
    if (fabs(z) > 0.01)
        transform.m34 = -1 / CylinderPerspectiveDistance;
    transform = CATransform3DTranslate(transform, x, y, z);
    transform.m34 = oldm34;

    CylinderEntrySetTransform(entry, transform);
    return 0;
}

static int l_transform_scale(lua_State *L)
{
    CylinderEntry *entry = l_check_handle(L, 1)->entry;

    lua_Number x = lua_tonumber(L, 2);
    lua_Number y = lua_isnumber(L, 3) ? lua_tonumber(L, 3) : x;
    lua_Number z = lua_isnumber(L, 4) ? lua_tonumber(L, 4) : 1;

    CHECK_NAN(x, "the x value for the scale");
    CHECK_NAN(y, "the y value for the scale");
    CHECK_NAN(z, "the z value for the scale");

    CATransform3D transform = CylinderEntryTransform(entry);
    CGFloat oldm34 = transform.m34;
    transform.m34 = -1 / CylinderPerspectiveDistance;
    transform = CATransform3DScale(transform, x, y, z);
    transform.m34 = oldm34;

    CylinderEntrySetTransform(entry, transform);
    return 0;
}

#pragma mark - Indexing

/// `page[i]` and `#page` follow SpringBoard's icon order. UIKit's subview order is an artifact of
/// view recycling, so scripts indexing icons by position need the reading order the grid shows.
static int l_page_subscript(lua_State *L, CylinderEntry *entry)
{
    CHECK_PAGE(L, entry);
    int isInteger;
    lua_Integer index = lua_tointegerx(L, 2, &isInteger) - 1;
    if (!isInteger || index < 0) return 0;

    NSUInteger count;
    CylinderEntry **icons = [entry->context iconEntriesWithCount:&count];
    if ((NSUInteger)index >= count) return 0;

    l_push_handle(L, &icons[index]->viewHandle);
    return 1;
}

static int l_page_icons(lua_State *L, CylinderEntry *entry)
{
    CHECK_PAGE(L, entry);
    NSUInteger count;
    CylinderEntry **icons = [entry->context iconEntriesWithCount:&count];

    lua_createtable(L, (int)count, 0);
    for (NSUInteger index = 0; index < count; index++) {
        l_push_handle(L, &icons[index]->viewHandle);
        lua_rawseti(L, -2, (lua_Integer)index + 1);
    }
    return 1;
}

static inline int l_push_number(lua_State *L, lua_Number number)
{
    lua_pushnumber(L, number);
    return 1;
}

/// Grid values are whole numbers, so scripts get Lua integers they can use as table keys directly.
static inline int l_push_integer(lua_State *L, NSInteger integer)
{
    lua_pushinteger(L, (lua_Integer)integer);
    return 1;
}

/// `view:center()` returns `view.x + view.width/2, view.y + view.height/2` in one call.
static int l_view_center(lua_State *L)
{
    CylinderHandle *handle = l_check_handle(L, 1);
    if (handle->kind != CylinderHandleKindView) return luaL_error(L, "center needs a view");

    CylinderEntry *entry = handle->entry;
    CGRect frame = CylinderEntryFrame(entry);
    CGSize size = CylinderEntrySize(entry);
    lua_pushnumber(L, CGRectGetMinX(frame) + size.width / 2);
    lua_pushnumber(L, CGRectGetMinY(frame) + size.height / 2);
    return 2;
}

/// Keys are dispatched on length and first byte, which keeps every lookup to a single short compare.
static int l_view_index(lua_State *L, CylinderEntry *entry, const char *key, size_t length)
{
    switch (length) {
        case 1:
            if (key[0] == 'x') return l_push_number(L, CGRectGetMinX(CylinderEntryFrame(entry)));
            if (key[0] == 'y') return l_push_number(L, CGRectGetMinY(CylinderEntryFrame(entry)));
            break;
        case 3:
            if (!strcmp(key, "row")) {
                CylinderEntryLoadGridCoordinate(entry);
                return l_push_integer(L, entry->row);
            }
            break;
        case 5:
            if (!strcmp(key, "alpha")) return l_push_number(L, CylinderEntryAlpha(entry));
            if (!strcmp(key, "width")) return l_push_number(L, CylinderEntrySize(entry).width);
            if (!strcmp(key, "scale")) {
                lua_pushcfunction(L, l_transform_scale);
                return 1;
            }
            if (!strcmp(key, "layer")) {
                l_push_handle(L, &entry->layerHandle);
                return 1;
            }
            break;
        case 6:
            if (!strcmp(key, "height")) return l_push_number(L, CylinderEntrySize(entry).height);
            if (!strcmp(key, "center")) {
                lua_pushcfunction(L, l_view_center);
                return 1;
            }
            if (!strcmp(key, "column")) {
                CylinderEntryLoadGridCoordinate(entry);
                return l_push_integer(L, entry->column);
            }
            if (!strcmp(key, "rotate")) {
                lua_pushcfunction(L, l_transform_rotate);
                return 1;
            }
            break;
        case 8:
            if (!strcmp(key, "subviews")) return l_page_icons(L, entry);
            if (!strcmp(key, "max_rows")) {
                CHECK_PAGE(L, entry);
                return l_push_integer(L, (NSInteger)entry->context.maximumRowCount);
            }
            break;
        case 9:
            if (!strcmp(key, "translate")) {
                lua_pushcfunction(L, l_transform_translate);
                return 1;
            }
            if (!strcmp(key, "max_icons")) {
                CHECK_PAGE(L, entry);
                return l_push_integer(L, (NSInteger)entry->context.maximumIconCount);
            }
            break;
        case 11:
            if (!strcmp(key, "max_columns")) {
                CHECK_PAGE(L, entry);
                return l_push_integer(L, (NSInteger)entry->context.maximumColumnCount);
            }
            break;
    }
    return 0;
}

static int l_layer_index(lua_State *L, CylinderEntry *entry, const char *key, size_t length)
{
    switch (length) {
        case 1:
            if (key[0] == 'x') return l_push_number(L, CylinderEntryPosition(entry).x);
            if (key[0] == 'y') return l_push_number(L, CylinderEntryPosition(entry).y);
            break;
        case 5:
            if (!strcmp(key, "width")) return l_push_number(L, entry->layer.bounds.size.width);
            break;
        case 6:
            if (!strcmp(key, "height")) return l_push_number(L, entry->layer.bounds.size.height);
            break;
        case 9:
            if (!strcmp(key, "transform")) return l_push_transform(L, CylinderEntryTransform(entry));
            break;
    }
    return 0;
}

static int l_handle_index(lua_State *L)
{
    CylinderHandle *handle = l_check_handle(L, 1);
    CylinderEntry *entry = handle->entry;

    switch (lua_type(L, 2)) {
        case LUA_TNUMBER:
            if (handle->kind == CylinderHandleKindView) return l_page_subscript(L, entry);
            return 0;
        case LUA_TSTRING: {
            size_t length;
            const char *key = lua_tolstring(L, 2, &length);
            return handle->kind == CylinderHandleKindView
                ? l_view_index(L, entry, key, length)
                : l_layer_index(L, entry, key, length);
        }
    }
    return 0;
}

#pragma mark - Assignment

static int l_handle_newindex(lua_State *L)
{
    CylinderHandle *handle = l_check_handle(L, 1);
    CylinderEntry *entry = handle->entry;
    if (lua_type(L, 2) != LUA_TSTRING) return 0;

    size_t length;
    const char *key = lua_tolstring(L, 2, &length);

    if (handle->kind == CylinderHandleKindView) {
        if (length == 5 && !strcmp(key, "alpha")) {
            if (!lua_isnumber(L, 3))
                return luaL_error(L, "'alpha' must be a number");
            lua_Number alpha = lua_tonumber(L, 3);
            CHECK_NAN(alpha, "'alpha'");
            CylinderEntrySetAlpha(entry, alpha);
        }
        return 0;
    }

    if (length == 1 && (key[0] == 'x' || key[0] == 'y')) {
        if (!lua_isnumber(L, 3))
            return luaL_error(L, key[0] == 'x' ? "'x' must be a number" : "'y' must be a number");
        lua_Number value = lua_tonumber(L, 3);
        CHECK_NAN(value, key[0] == 'x' ? "'x'" : "'y'");

        CGPoint position = CylinderEntryPosition(entry);
        if (key[0] == 'x') position.x = value;
        else position.y = value;
        CylinderEntrySetPosition(entry, position);
    } else if (length == 9 && !strcmp(key, "transform")) {
        return l_set_transform(L, entry);
    }
    return 0;
}

static int l_handle_len(lua_State *L)
{
    CylinderHandle *handle = l_check_handle(L, 1);
    if (handle->kind != CylinderHandleKindView) return 0;

    CylinderEntry *entry = handle->entry;
    NSUInteger count = 0;
    if (l_is_page(entry)) [entry->context iconEntriesWithCount:&count];
    else count = entry->view.subviews.count;
    lua_pushinteger(L, (lua_Integer)count);
    return 1;
}

void l_create_uiview_metatable(lua_State *L)
{
    lua_pushlightuserdata(L, NULL);
    lua_createtable(L, 0, 3);

    lua_pushcfunction(L, l_handle_index);
    lua_setfield(L, -2, "__index");

    lua_pushcfunction(L, l_handle_newindex);
    lua_setfield(L, -2, "__newindex");

    lua_pushcfunction(L, l_handle_len);
    lua_setfield(L, -2, "__len");

    lua_setmetatable(L, -2);
    lua_pop(L, 1);
}
