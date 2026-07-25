#if !defined LUA_VERSION_NUM
/* Lua 5.0 */

#define luaL_addchar(B,c) \
  ((void)((B)->p < ((B)->buffer+LUAL_BUFFERSIZE) || luaL_prepbuffer(B)), \
   (*(B)->p++ = (char)(c)))
#endif

#if LUA_VERSION_NUM==501
/* Lua 5.1 */
#define lua_rawlen lua_objlen
#endif

#ifdef __cplusplus
extern "C" {
#endif    
#include "lua.h"
#include "lauxlib.h"
/* luaL_reg 는 Lua 5.0 시절 이름이고 5.1 부터는 luaL_Reg 다. Lua 5.1 은 하위호환 별칭으로
   luaL_reg 를 남겨 뒀지만 LuaJIT 2.1 은 제거했으므로, 5.0 에서만 별칭을 만든다. */
#if !defined LUA_VERSION_NUM
#define luaL_Reg luaL_reg
#endif
extern void luaL_setfuncs(lua_State *L, const luaL_Reg *l, int nup);
#ifdef __cplusplus
}
#endif    

