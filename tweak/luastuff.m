#import "luastuff.h"
#include <libgen.h>
#import "../lua/lualib.h"
// #import "macros.h"
#import "lua_UIView.h"
#import "CylinderDebug.h"
#ifndef CYLINDER_SIMJECT
#import <libroot.h>
#endif

#define LOG_DIR @"/var/mobile/Library/Logs/Cylinder/"
#define LOG_PATH "errors.log"
#define PRINT_PATH "print.log"

static lua_State *L = NULL;

/// Registry references to each loaded script's function, read on every frame.
static int *_scripts = NULL;
static NSUInteger _scriptCount = 0;
static NSMutableArray *_scriptNames = nil;
BOOL _randomize;

static int l_loadfile_override(lua_State *L);
static int l_print(lua_State *L);
static int l_subviews(lua_State *L);
static int l_popup(lua_State *L);

static void write_error(const char *error);
static void write_file(const char *msg, const char *filename);

/// Scripts run inside SpringBoard, so they get no io or package library (which can load native code)
/// and none of these os functions.
static const char *OS_DANGER[] = {
    "exit",
    "setlocale",
    "remove",
    "tmpname",
    "rename",
    "execute",
    NULL
};

static void remove_script(NSUInteger index)
{
    luaL_unref(L, LUA_REGISTRYINDEX, _scripts[index]);
    memmove(&_scripts[index], &_scripts[index + 1], (_scriptCount - index - 1) * sizeof(int));
    _scriptCount--;
    [_scriptNames removeObjectAtIndex:index];
}

static NSDictionary *gen_error_dict(NSString *script, BOOL broken)
{
    NSArray *components = script.pathComponents;
    NSString *folder = [components objectAtIndex:0];
    NSString *name = [components objectAtIndex:1];
    NSNumber *nsbroken = [NSNumber numberWithBool:broken];
    return [NSDictionary dictionaryWithObjectsAndKeys:
        folder, PrefsEffectDirKey,
        name, PrefsEffectKey,
        nsbroken, @"broken",
        nil];
}

static void error_notification(NSArray *errors)
{
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:errors format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    if(data)
    {
        [data writeToFile:LOG_DIR".errornotify" atomically:true];
        CFNotificationCenterRef r = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterPostNotification(r, CFSTR("luaERROR"), NULL, NULL, true);
    }
}

void close_lua(void)
{
    if(L != NULL) lua_close(L);
    L = NULL;
    free(_scripts);
    _scripts = NULL;
    _scriptCount = 0;
    _scriptNames = nil;
}

static void create_state(void)
{
    //create state
    L = luaL_newstate();

    //load libraries
    luaL_openselectedlibs(L, ~(LUA_IOLIBK | LUA_LOADLIBK), 0);

    lua_getglobal(L, LUA_OSLIBNAME);
    for(const char **name = OS_DANGER; *name; name++)
    {
        lua_pushnil(L);
        lua_setfield(L, -2, *name);
    }
    lua_pop(L, 1);

    // Scripts allocate short-lived tables and handles on every frame and keep little else, which is
    // the pattern generational collection is built for. Lua 5.5 also runs its major collections
    // incrementally, so a full collection cannot stall one frame.
    lua_gc(L, LUA_GCGEN);

    #ifdef CYLINDER_SIMJECT
    // Deterministic randomness lets the simulator harness compare renders across builds.
    luaL_dostring(L, "math.randomseed(1)");
    #endif

    // LuaJIT and 64-bit OS X don't play well together http://luajit.org/install.html#embed
    // since we're embedding in SpringBoard we don't have the luxury of using linker flags
    // turning off the JIT fixes all the issues, unfortunately this mean C callbacks cannot be used
    //luaL_dostring(L, "if jit and jit.arch == 'arm64' then jit.off() end");

    //override certain functions
    lua_pushcfunction(L, l_print);
    lua_setglobal(L, "print");

    //set globals
    l_push_base_transform(L);
    lua_setglobal(L, "BASE_TRANSFORM");

    lua_pushcfunction(L, l_subviews);
    lua_setglobal(L, "subviews");

    lua_pushcfunction(L, l_popup);
    lua_setglobal(L, "popup");

    //set UIView metatable
    l_create_uiview_metatable(L);

    CylinderUpdateScreenMetrics();
    lua_pushnumber(L, CylinderPerspectiveDistance);
    lua_setglobal(L, "PERSPECTIVE_DISTANCE");

}

static void changedofile(const char *folder, const char *func)
{
    //(), {}
    lua_getupvalue(L, -2, 1);
    lua_pushstring(L, func);
    //(), {}, _ENV, func""
    lua_gettable(L, -2);
    lua_pushstring(L, folder);
    //(), {}, _ENV{}, func(), folder""
    lua_pushcclosure(L, l_loadfile_override, 2);
    //(), {}, _ENV{}, newfunc()
    lua_pushstring(L, func);
    lua_pushvalue(L, -2);
    //(), {}, _ENV{}, newfunc(), func"", newfunc()
    lua_settable(L, -5);
    //(), {}, _ENV{}, newfunc()
    lua_pop(L, 2);
    //(), {}
}

static void set_environment(const char *script)
{
    const char *folder = dirname((char *)script);
    //()
    lua_newtable(L);
    lua_newtable(L);
    lua_pushstring(L, "__index");
    lua_getupvalue(L, -4, 1);
    //(), {}, {}, "__index", _ENV{}
    lua_settable(L, -3);
    //(), {}, {"__index":_ENV{}}
    lua_setmetatable(L, -2);
    //(), {}
    changedofile(folder, "dofile");
    changedofile(folder, "loadfile");
    lua_setupvalue(L, -2, 1);
}

/// Writes the path of a file under /Library/Cylinder, given as a format and its arguments, into `out`, which
/// holds PATH_MAX bytes. libroot resolves the jailbreak root on rootful, rootless and roothide; simulator
/// builds read the copy in the simulator's data directory.
static const char *script_path(char *out, const char *format, ...)
{
    char relative[PATH_MAX];
    int length = snprintf(relative, sizeof(relative), "/Library/Cylinder/");
    va_list args;
    va_start(args, format);
    vsnprintf(relative + length, sizeof(relative) - length, format, args);
    va_end(args);

    #ifdef CYLINDER_SIMJECT
    snprintf(out, PATH_MAX, "%s%s", NSHomeDirectory().fileSystemRepresentation, relative);
    return out;
    #else
    return libroot_dyn_jbrootpath(relative, out);
    #endif
}

static int open_script(const char *script)
{
    char buffer[PATH_MAX];
    const char *path = script_path(buffer, "%s.lua", script);

    #ifdef CYLINDER_SIMJECT
    NSLog(@"[CylinderSimject] loading Lua script %s (exists: %@)", path,
          access(path, F_OK) == 0 ? @"YES" : @"NO");
    #endif

    //load our file and save the function we want to call
    BOOL loaded = luaL_loadfile(L, path) == 0;
    if(loaded)
    {
        set_environment(script);
        loaded = lua_pcall(L, 0, 1, 0) == 0;

        if(loaded && lua_isfunction(L, -1))
        {
            return luaL_ref(L, LUA_REGISTRYINDEX);
        }
        else if(!loaded)
        {
            write_error([NSString stringWithFormat:@"error opening %s: %s", script, lua_tostring(L, -1)].UTF8String);
        }
        else
        {
            write_error([NSString stringWithFormat:@"error opening %s: result must be a function", script].UTF8String);
        }
    }
    else 
    {
        #ifdef CYLINDER_SIMJECT
        NSLog(@"[CylinderSimject] Lua load failed for %s: %s", path, lua_tostring(L, -1));
        #endif
        write_error(lua_tostring(L, -1));
    }

    lua_pop(L, 1);

    return -1;
}

BOOL init_lua(NSArray *scripts, BOOL random)
{
    if(scripts.count == 0) return false;

    _randomize = random;
    close_lua();
    create_state();

    _scripts = calloc(scripts.count, sizeof(int));
    _scriptNames = [NSMutableArray arrayWithCapacity:scripts.count];

    NSMutableArray *errors = [NSMutableArray arrayWithCapacity:scripts.count];
    for(NSDictionary *scriptDict in scripts)
    {
        NSString *script = [NSString stringWithFormat:@"%@/%@", [scriptDict valueForKey:PrefsEffectDirKey], [scriptDict valueForKey:PrefsEffectKey]];

        int func = open_script(script.UTF8String);

        NSMutableDictionary *errorDict = scriptDict.mutableCopy;
        [errorDict setValue:[NSNumber numberWithBool:(func == -1)] forKey:@"broken"];
        [errors addObject:errorDict];

        if(func != -1)
        {
            _scripts[_scriptCount++] = func;
            [_scriptNames addObject:script];
        }
    }

    error_notification(errors);

    if(_scriptCount == 0 || L == NULL)
    {
        close_lua();
        return false;
    }
    return true;
}

static int l_loadfile_override(lua_State *L)
{
    const char *file = lua_tostring(L, 1);
    const char *subfolder = lua_tostring(L, lua_upvalueindex(2));

    char buffer[PATH_MAX];
    if(file != NULL)
        file = script_path(buffer, "%s/%s", subfolder, file);

    int top = lua_gettop(L);
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_insert(L, 1);

    if(file != NULL)
    {
        lua_pushstring(L, file);
        lua_remove(L, 2);
        lua_insert(L, 2);
    }
    const BOOL success = lua_pcall(L, top, 1, 0) == 0;
    if(!success)
    {
        return luaL_error(L, lua_tostring(L, -1));
    }
    return 1;
}

//stolen from lua's print function
static int l_concat_args(lua_State *L, const char *func_name, const char *separator)
{
    const int n = lua_gettop(L);  /* number of arguments */
    int i;
    NSMutableString *result = [NSMutableString string];
    lua_getglobal(L, "tostring");
    for (i=1; i<=n; i++) {
        const char *s;
        lua_pushvalue(L, -1);  /* function to be called */
        lua_pushvalue(L, i);   /* value to print */
        lua_call(L, 1, 1);
        s = lua_tolstring(L, -1, NULL);  /* get result */
        if (s == NULL)
            return luaL_error(L,
                    [NSString stringWithFormat:@"'tostring' must return a string to '%s'", func_name].UTF8String);
        if (i>1) [result appendFormat:@"%s", separator];//luai_writestring("\t", 1);
        [result appendFormat:@"%s", s];//luai_writestring(s, l);
        lua_pop(L, 1);  /* pop result */
    }
    lua_pop(L, 1); //pop tostring()
    lua_pushstring(L, result.UTF8String);
    return 1;
}

static int l_print(lua_State *L)
{
    l_concat_args(L, "print", "\t");

    write_file(lua_tostring(L, -1), "print.log");
    return 0;
}

inline int l_popup(lua_State *L)
{
    l_concat_args(L, "popup", "\n");

    // [[UIAlertView.alloc initWithTitle:@"Cylinder" message:[NSString stringWithUTF8String:lua_tostring(L, -1)] delegate:nil cancelButtonTitle:@"Close" otherButtonTitles:nil] show];

    return 0;
}

//this is literally the same code as ipairs
static int l_subviewsaux(lua_State *L)
{
    const lua_Integer i = luaL_checkinteger(L, 2) + 1;
    lua_pushinteger(L, i);
    lua_pushvalue(L, -1);
    lua_gettable(L, 1);
    return (lua_isnil(L, -1)) ? 1 : 2;
}

/// Steps through a page's icons directly instead of indexing the page through its metamethod.
static int l_page_subviewsaux(lua_State *L)
{
    CylinderHandle *handle = (CylinderHandle *)lua_touserdata(L, 1);
    const lua_Integer i = luaL_checkinteger(L, 2);
    if(!handle) return 0;

    NSUInteger count;
    CylinderEntry **icons = [handle->entry->context iconEntriesWithCount:&count];
    if(i < 0 || (NSUInteger)i >= count)
    {
        lua_pushnil(L);
        return 1;
    }
    lua_pushinteger(L, i + 1);
    l_push_handle(L, &icons[i]->viewHandle);
    return 2;
}

static BOOL l_is_page_handle(lua_State *L, int index)
{
    if(lua_type(L, index) != LUA_TLIGHTUSERDATA) return NO;
    CylinderHandle *handle = (CylinderHandle *)lua_touserdata(L, index);
    if(!handle) return NO;
    CylinderEntry *entry = handle->entry;
    return handle->kind == CylinderHandleKindView && entry == &entry->context->_page;
}

static int l_subviews(lua_State *L)
{
    lua_pushcfunction(L, l_is_page_handle(L, 1) ? l_page_subviewsaux : l_subviewsaux);
    lua_pushvalue(L, 1);
    lua_pushinteger(L, 0);
    return 3;
}


inline void write_error(const char *error)
{
    write_file(error, LOG_PATH);
}

static void write_file(const char *msg, const char *filename)
{
    Log(@"wrote to file %s: %s", filename, msg);
    CylinderDebugLog(@"[lua %s] %s", filename, msg);

    NSString *path = [LOG_DIR stringByAppendingPathComponent:[NSString stringWithUTF8String:filename]];

    if(![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:nil])
    {
        if(![NSFileManager.defaultManager fileExistsAtPath:LOG_DIR isDirectory:nil])
            [NSFileManager.defaultManager createDirectoryAtPath:LOG_DIR withIntermediateDirectories:false attributes:nil error:nil];
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    }
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    [fileHandle seekToEndOfFile];

    static NSDateFormatter *dateFormatter;
    if(!dateFormatter)
    {
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"[yyyy-MM-dd HH:mm:ss] "];
    }
    NSString *dateStr = [dateFormatter stringFromDate:NSDate.date];

    [fileHandle writeData:[dateStr dataUsingEncoding:NSUTF8StringEncoding]];
    [fileHandle writeData:[NSData dataWithBytes:msg length:strlen(msg)]];
    [fileHandle writeData:[NSData dataWithBytes:"\n" length:1]];
    [fileHandle closeFile];
}

/// Runs one script on the page. A failing script is removed and reported so later frames skip it.
static BOOL manipulate_step(CylinderPageContext *context, CGFloat offset, NSUInteger funcIndex)
{
    lua_rawgeti(L, LUA_REGISTRYINDEX, _scripts[funcIndex]);

    l_push_handle(L, &context->_page.viewHandle);
    lua_pushnumber(L, offset);
    lua_pushnumber(L, CylinderScreenSize.width);
    lua_pushnumber(L, CylinderScreenSize.height);

    if (lua_pcall(L, 4, 0, 0) == LUA_OK) return YES;

    write_error(lua_tostring(L, -1));
    lua_pop(L, 1);
    NSDictionary *error = gen_error_dict([_scriptNames objectAtIndex:funcIndex], true);
    error_notification([NSArray arrayWithObject:error]);
    remove_script(funcIndex);
    return NO;
}

BOOL manipulate(CylinderPageContext *context, CGFloat offset, u_int32_t rand)
{
    if(_randomize)
    {
        while(_scriptCount > 0 && !manipulate_step(context, offset, rand % _scriptCount));
    }
    else
    {
        for(NSUInteger i = 0; i < _scriptCount;)
        {
            // A failed script is removed, which shifts the next script into index i.
            if(manipulate_step(context, offset, i)) i++;
        }
    }
    return _scriptCount > 0;
}
