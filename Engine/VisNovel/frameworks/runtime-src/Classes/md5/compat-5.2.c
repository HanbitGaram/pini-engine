#include "compat-5.2.h"
#ifdef __cplusplus
extern "C" {
#endif

#include "lua.h"
#include "lauxlib.h"

/* LuaJIT 2.1 은 Lua 5.2 에서 온 luaL_setfuncs 를 자체적으로 제공한다. 그대로 두면
   링크 시 duplicate symbol '_luaL_setfuncs' 가 난다.
   (LuaJIT 2.0 / 순정 Lua 5.1 에는 없으므로 그때는 아래 구현을 쓴다.) */
#if defined(__has_include)
#  if __has_include("luajit.h")
#    include "luajit.h"
#  endif
#endif

#if (!defined LUA_VERSION_NUM || LUA_VERSION_NUM==501) \
    && !(defined LUAJIT_VERSION_NUM && LUAJIT_VERSION_NUM >= 20100)
/*
** Adapted from Lua 5.2.0
*/
void luaL_setfuncs (lua_State *L, const luaL_Reg *l, int nup) {
  luaL_checkstack(L, nup+1, "too many upvalues");
  for (; l->name != NULL; l++) {  /* fill the table with given functions */
    int i;
    lua_pushstring(L, l->name);
    for (i = 0; i < nup; i++)  /* copy upvalues to the top */
      lua_pushvalue(L, -(nup + 1));
    lua_pushcclosure(L, l->func, nup);  /* closure with those upvalues */
    lua_settable(L, -(nup + 3)); /* table must be below the upvalues, the name and the closure */
  }
  lua_pop(L, nup);  /* remove upvalues */
}
#endif

#ifdef __cplusplus
}
#endif
