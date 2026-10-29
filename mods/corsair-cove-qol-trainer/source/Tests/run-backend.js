// Run the actual shipped Lua script in Lua 5.3 with a deterministic UE4SS test host.
const fs = require('fs');
const path = require('path');
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = require('../../Tools/LuaTests/node_modules/fengari');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
lua.lua_pushstring(L, to_luastring(fs.readFileSync(path.join(__dirname, '../Scripts/main.lua'), 'utf8')));
lua.lua_setglobal(L, to_luastring('trainerSource'));
lua.lua_pushstring(L, to_luastring(fs.readFileSync(path.join(__dirname, '../Scripts/WarehouseUI.lua'), 'utf8')));
lua.lua_setglobal(L, to_luastring('warehouseUiSource'));
const test = fs.readFileSync(path.join(__dirname, 'backend.spec.lua'), 'utf8') + '\n' + fs.readFileSync(path.join(__dirname, 'warehouse-ui.spec.lua'), 'utf8');
if (lauxlib.luaL_dostring(L, to_luastring(test)) !== lua.LUA_OK) {
  console.error(to_jsstring(lua.lua_tostring(L, -1)));
  process.exitCode = 1;
}
