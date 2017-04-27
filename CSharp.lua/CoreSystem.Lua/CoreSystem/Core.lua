--[[
Copyright 2016 YANG Huan (sy.yanghuan@gmail.com).
Copyright 2016 Redmoon Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
--]]

local setmetatable = setmetatable
local getmetatable = getmetatable
local type = type
local ipairs = ipairs
local assert = assert
local table = table
local tinsert = table.insert
local tremove = table.remove
local tconcat = table.concat
local floor = math.floor
local ceil = math.ceil
local error = error
local select = select
local pcall = pcall
local rawget = rawget
local rawset = rawset
local global = _G

local emptyFn = function() end
local falseFn = function() return false end
local identityFn = function(x) return x end
local equals = function(x, y) return x == y end
local modules = {}
local usings = {}
local Object = {}

local function new(cls, ...)
  local this = setmetatable({}, cls)
  cls.__ctor__(this, ...)
  return this
end

local function throw(e, lv)
  e:traceback(lv)
  error(e)
end

local function try(try, catch, finally)
  local ok, status, result = pcall(try)
  if not ok then
    if catch then
      if type(status) == "string" then
        status = System.Exception(status)
      end
      if finally then
        ok, status, result = pcall(catch, status)
      else
        ok, status, result = true, catch(status)
      end
      if ok then
        if status == 1 then
          ok = false
          status = result
        end
      end
    end
  end
  if finally then
    finally()
  end
  if not ok then
    throw(status)
  end
  return status, result
end

local function set(className, cls)
  local scope = global
  local starInx = 1
  while true do
    local pos = className:find("%.", starInx) or 0
    local name = className:sub(starInx, pos -1)
    if pos ~= 0 then
      local t = rawget(scope, name)
      if t == nil then
        t = {}
        rawset(scope, name, t)
      end
      scope = t
    else
      assert(rawget(scope, name) == nil, className)
      rawset(scope, name, cls)
      break
    end
    starInx = pos + 1
  end
  return cls
end

local function defaultValOfZero()
  return 0
end

local function genericKey(t, k, ...) 
  for i = 1, select("#", ...) do
    local tk = t[k]
    if tk == nil then
      tk = {}
      t[k] = tk
    end
    t = tk
    k = select(i, ...)
  end
  return t, k
end

local function genericName(name, ...)
  local t = {}
  tinsert(t, name)
  tinsert(t, "[")
  
  local hascomma
  for i = 1, select("#", ...) do
      local cls = select(i, ...)
      if hascomma then
        tinsert(t, ",")
      else
        hascomma = true
      end
      tinsert(t, cls.__name__)
  end
  tinsert(t, "]")
  return tconcat(t)
end

local enumMetatable = { __kind__ = "E", __default__ = defaultValOfZero, __index = false }
enumMetatable.__index = enumMetatable

local interfaceMetatable = { __kind__ = "I", __default__ = emptyFn, __index = false }
interfaceMetatable.__index = interfaceMetatable

local function setBase(cls)
  cls.__index = cls 
  cls.__call = new
  local extends = cls.__inherits__
  if extends ~= nil then
    if type(extends) == "function" then
      extends = extends(global)
    end           
    local base = extends[1]
    if base.__kind__ == "C" then
      cls.__base__ = base
      tremove(extends, 1)
      if #extends > 0 then
          cls.__interfaces__ = extends
      end 
      setmetatable(cls, base)
    else
      cls.__interfaces__ = extends
      setmetatable(cls, Object)
    end
    cls.__inherits__ = nil
  elseif cls ~= Object then
    setmetatable(cls, Object)
  end  
  local attributes = cls.__attributes__
  if attributes ~= nil then
    cls.__attributes__ = attributes(global)
  end
end

local function staticCtorSetBase(cls)
  setmetatable(cls, nil)
  setBase(cls)
  cls:__staticCtor__()
  cls.__staticCtor__ = nil
end

local staticCtorMetatable = {
  __index = function(cls, key)
    staticCtorSetBase(cls)
    return cls[key]
  end,
  __newindex = function(cls, key, value)
    staticCtorSetBase(cls)
    cls[key] = value
  end,
  __call = function(cls, ...)
    staticCtorSetBase(cls)
    return new(cls, ...)
  end,
}

local function def(name, kind, cls, generic)
  if type(cls) == "function" then
    if generic then
      generic.__index = generic
      generic.__call = new
    end
    local mt = {}
    local fn = function(_, ...)
      local gt, gk = genericKey(mt, ...)
      local t = gt[gk]
      if t == nil then
        t = def(nil, kind, cls(...) or {}, genericName(name, ...))
        if generic then
          setmetatable(t, generic)
        end
        gt[gk] = t
      end
      return t
    end
    return set(name, setmetatable(generic or {}, { __call = fn, __index = Object }))
  end
  cls = cls or {}
  if name ~= nil then
    set(name, cls)
    cls.__name__ = name
  else
    cls.__name__ = generic
  end
  if kind == "C" or kind == "S" then
	cls.__kind__ = kind
    if cls.__staticCtor__ == nil then
      setBase(cls)
    else
      setmetatable(cls, staticCtorMetatable)
    end
  elseif kind == "I" then
    local extends = cls.__inherits__
    if extends then
      cls.__interfaces__ = extends
      cls.__inherits__ = nil
    end
    local attributes = cls.__attributes__
    if attributes ~= nil then
      cls.__attributes__ = attributes(global)
    end
    setmetatable(cls, interfaceMetatable)
  elseif kind == "E" then
    local attributes = cls.__attributes__
    if attributes ~= nil then
      cls.__attributes__ = attributes(global)
    end
    setmetatable(cls, enumMetatable)
  else
    assert(false, kind)
  end
  return cls
end

local function defCls(name, cls, genericSuper)
  return def(name, "C", cls, genericSuper) 
end

local function defInf(name, cls)
  return def(name, "I", cls)
end

local function defStc(name, cls, genericSuper)
  return def(name, "S", cls, genericSuper)
end

System = {
  emptyFn = emptyFn,
  falseFn = falseFn,
  identityFn = identityFn,
  equals = equals,
  try = try,
  throw = throw,
  define = defCls,
  defInf = defInf,
  defStc = defStc,
  global = global,
}

local System = System

local function trunc(num) 
  return num > 0 and floor(num) or ceil(num)
end

System.trunc = trunc

local _, _, version = _VERSION:find("^Lua (.*)$")
version = tonumber(version)
System.luaVersion = version

if version < 5.3 then
  local bit = require("bit")
  local band = bit.band
  local xor = bit.bxor

  System.bnot = bit.bnot
  System.band = band
  System.bor = bit.bor
  System.xor = xor
  System.sl = bit.lshift
  System.sr = bit.rshift

  function System.div(x, y) 
    if y == 0 then
      throw(System.DivideByZeroException(), 1)
    end
    return trunc(x / y)
  end    
    
  function System.mod(x, y) 
    if y == 0 then
      throw(System.DivideByZeroException(), 1)
    end
    return x % y;
  end

  function System.toUInt(v, max, mask, checked)
    if v >= 0 and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    return band(v, mask)
  end

  function System.toUIntOfD(v, max, mask, checked)
    v = trunc(v)
    if v >= 0 and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    if v < -2147483648 or v > 2147483647 then
      return 0
    end
    return band(v, mask)
  end

  local function toInt(v, mask, umask)
    v = band(v, mask)
    local uv = band(v, umask)
    if uv ~= v then
      return -xor(uv - 1, umask)
    end
    return v
  end

  function System.toInt(v, min, max, mask, umask, checked)
    if v >= min and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    return toInt(v, mask, umask)
  end

  function System.toIntOfD(v, min, max, mask, umask, checked)
    v = trunc(v)
    if v >= min and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    if v < -2147483648 or v > 2147483647 then
      return 0
    end
    return toInt(v, mask, umask)
  end

  local function toUInt32(v)
    v = band(v, 0xffffffff)
    local uv = band(v, 0x7fffffff)
    if uv ~= v then
      return uv + 0x80000000
    end
    return v
  end

  function System.toUInt32(v, checked)
    if v >= 0 and v <= 4294967295 then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    if v <= -2251799813685248 or v >= 2251799813685248 then  -- 2 ^ 51, Lua BitOp used 51 and 52
      throw(System.InvalidCastException()) 
    end
    return toUInt32(v)
  end

  function System.toUInt32OfD(v, checked)
    v = trunc(v)
    if v >= 0 and v <= 4294967295 then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    if v <= -4503599627370496 or v >= 4503599627370496 then -- 2 ^ 52
      return 0
    end
    if v <= -2251799813685248 or v >= 2251799813685248 then  -- 2 ^ 51, Lua BitOp used 51 and 52
      throw(System.InvalidCastException()) 
    end
    return toUInt32(v)
  end

  function System.toInt32(v, checked)
    if v >= -2147483648 and v <= 2147483647 then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    if v <= -2251799813685248 or v >= 2251799813685248 then  -- 2 ^ 51, Lua BitOp used 51 and 52
      throw(System.InvalidCastException()) 
    end
    return band(v, 0xffffffff)
  end

  if table.unpack == nil then
    table.unpack = unpack
  end

  if table.move == nil then
    table.move = function(a1, f, e, t, a2)
      if a2 == nil then a2 = a1 end
      t = e - f + t
      while e >= f do
        a2[t] = a1[e]
        t = t - 1
        e = e - 1
      end
    end
  end
else  
  load[[
  local System = System
  local throw = System.throw
  local trunc = System.trunc
  
  function System.bnot(x) return ~v end 
  function System.band(x, y) return x & y end
  function System.bor(x, y) return x | y end
  function System.xor(x, y) return x ~ y end
  function System.sl(x, y) return x << y end
  function System.sr(x, y) return x >> y end
  function System.div (x, y) return x // y end
  function System.mod(x, y) return x % y end
  
  local function toUInt (v, max, mask, checked)  
    if v >= 0 and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 2) 
    end
    return v & mask
  end
  System.toUInt = toUInt

  function System.toUIntOfD(v, max, mask, checked)
    v = trunc(v)
    if v >= 0 and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 2) 
    end
    if v < -2147483648 or v > 2147483647 then
      return 0
    end
    return v & mask
  end
  
  local function toSingedInt(v, mask, umask)
    v = v & mask
    local uv = v & umask
    if uv ~= v then
      return -((uv - 1) ~ umask)
    end
    return v
  end
  
  local function toInt(v, min, max, mask, umask, checked)
    if v >= min and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 2) 
    end
    return toSingedInt(v, mask, umask)
  end
  System.toInt = toInt
  
  function System.toIntOfD(v, min, max, mask, umask, checked)
    v = trunc(v)
    if v >= min and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    if v < -2147483648 or v > 2147483647 then
      return 0
    end
    return toSingedInt(v, mask, umask)
  end

  function System.toUInt32(v, checked)
    return toUInt(v, 4294967295, 0xffffffff, checked)
  end
  
  function System.toUInt32OfD(v, checked)
    v = trunc(v)
    if v >= 0 and v <= 4294967295 then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    if v <= -4503599627370496 or v >= 4503599627370496 then -- 2 ^ 52
      return 0
    end
    return v & 0xffffffff
  end
  
  function System.toInt32(v, checked)
    return toInt(v, -2147483648, 2147483647, 0xffffffff, 0x7fffffff, checked)
  end
  
  ]]()
end

function System.toInt32OfD(v, checked)
  v = trunc(v)
  if v >= -2147483648 and v <= 2147483647 then
    return v
  end
  if checked then
    throw(System.OverflowException(), 1) 
  end
  return -2147483648
end

function System.using(t, f)
  local dispose = t and t.Dispose
  if dispose ~= nil then
    local ok, status, ret = pcall(f, t)   
    dispose(t)
    if not ok then
      throw(status)
    end
    return status, ret
  else
    return f(t)    
  end
end

function System.usingX(f, ...)
  local ok, status, ret = pcall(f, ...)
  for i = 1, select("#", ...) do
    local t = select(i, ...)
    if t ~= nil then
      local dispose = t.Dispose
      if dispose ~= nil then
        dispose(t)
      end
    end
  end
  if not ok then
    throw(status)
  end
  return status, ret
end

function System.create(t, f)
  f(t)
  return t
end

function System.default(T)
  return T.__default__()
end

function System.property(name)
  local function get(this)
    return this[name]
  end
  local function set(this, v)
    this[name] = v
  end
  return get, set
end

function System.event(name)
  local function add(this, v)
    this[name] = System.combine(this[name], v)
  end
  local function remove(this, v)
    this[name] = System.remove(this[name], v)
  end
  return add, remove
end

function System.new(cls)
  local ctor = cls.__ctor__
  if type(ctor) == "table" then
    ctor = ctor[1]
  end
  local this = setmetatable({}, cls)
  ctor(this)
  return this
end

function System.CreateInstance(type, ...)
  return type.c(...)
end

function System.getClass(className)
  local scope = global
  local starInx = 1
  while true do
    local pos = className:find("%.", starInx) or 0
    local name = className:sub(starInx, pos -1)
    if pos ~= 0 then
      local t = rawget(scope, name)
      if t == nil then
        return nil
      end
      scope = t
    else
      return rawget(scope, name)
    end
    starInx = pos + 1
  end
end

function System.usingDeclare(f)
  tinsert(usings, f)
end

function System.init(namelist, conf)
  for _, name in ipairs(namelist) do
    assert(modules[name], name)()
  end
  for _, f in ipairs(usings) do
    f(global)
  end
  if conf ~= nil then
    System.entryPoint = conf.Main
  end
  modules = nil
  usings = nil
end

local function multiNew(cls, inx, ...) 
  local this = setmetatable({}, cls)
  cls.__ctor__[inx](this, ...)
  return this
end

Object.__call = new
Object.__default__ = emptyFn
Object.__ctor__ = emptyFn
Object.__kind__ = "C"
Object.new = multiNew
Object.EqualsObj = equals
Object.ReferenceEquals = equals
Object.GetHashCode = identityFn

function Object.EqualsStatic(x, y)
  if x == y then
    return true
  end
  if x == nil or y == nil then
    return false
  end
  return x:EqualsObj(y)
end

function Object.ToString(this)
  return this.__name__
end

defCls("System.Object", Object)

local anonymousType = {}
defCls("System.AnonymousType", anonymousType)

function System.anonymousType(t)
  return setmetatable(t, anonymousType)
end

local tuple = {}
defCls("System.Tuple", tuple)

function System.tuple(...)
  return setmetatable({...}, tuple)
end

debug.setmetatable(nil, {
  __concat = function(a, b)
    if a == nil then
      if b == nil then
        return ""
      else
        return b
      end
    else
      return a
    end
  end,
  __add = emptyFn,
  __sub = emptyFn,
  __mul = emptyFn,
  __div = emptyFn,
  __mod = emptyFn,
  __unm = emptyFn,
  __lt = falseFn,
  __le = falseFn,
})

function System.toString(t)
  if t == nil then return "" end
  return t:ToString()
end

local namespace = {}
local curName

local function namespaceDef(kind, name, f)
  if #curName > 0 then
    name = curName .. "." .. name
  end
  assert(modules[name] == nil, name)
  local prevName = curName
  curName = name
  local t = f(namespace)
  curName = prevName
  modules[name] = function()
    def(name, kind, t)
  end
end

function namespace.class(name, f)
  namespaceDef("C", name, f) 
end

function namespace.struct(name, f)
  namespaceDef("S", name, f) 
end

function namespace.interface(name, f)
  namespaceDef("I", name, f) 
end

function namespace.enum(name, f)
  namespaceDef("E", name, f)
end

function namespace.namespace(name, f)
  name = curName .. "." .. name
  local prevName = curName
  curName = name
  f(namespace)
  curName = prevName
end

function System.namespace(name, f)
  curName = name
  f(namespace)
  curName = nil
end

local function config(conf) 
  if conf ~= nil then
    System.time = conf.time
  end
end

return config
