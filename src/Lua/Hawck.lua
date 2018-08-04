--[====================================================================================[
   Hawck main library.
   
   Copyright (C) 2018 Jonas Møller (no) <jonasmo441@gmail.com>
   All rights reserved.
   
   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions are met:
   
   1. Redistributions of source code must retain the above copyright notice, this
      list of conditions and the following disclaimer.
   2. Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.
   
   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
   ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
   WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
   DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
   FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
   DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
   SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
   CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
   OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
   OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--]====================================================================================]

require "Keymap"
require "utils"
require "match"
require "app"
kbd = require "kbd"

FALLTHROUGH = 0x3141592654

-- Keeps track of keys that are requested by the script.
__keys = {}

-- Root match scope
__match = MatchScope.new()
match = __match
_G["__match"] = __match

cont = ConcatF.new(function ()
    return FALLTHROUGH
end)

any = Cond.new(function ()
    return true
end)
always = any
all = any

none = Cond.new(function ()
    return false
end)
never = none

key = function (key_name)
  __keys[key_name] = true
  return LazyCondF.new(function (key_name)
      return kbd:hadKey(key_name)
  end)(key_name)
end

press = LazyF.new(function (key)
    kbd:press(key)
end)

function getEntryFunction(sym)
  local succ, code

  succ, code = pcall(u.curry(getKeysym, sym))
  if succ then
    return press(code)
  end

  succ, code = pcall(u.curry(getCombo, sym))
  if succ then
    return function ()
      kbd:pressMod(unpack(code))
    end
  end

  error(("No such symbol: %s"):format(sym))
end

insert = LazyF.new(function (str)
    getEntryFunction(str)()
end)

echo = ConcatF.new(function ()
    kbd:echo()
end)

held = LazyCondF.new(function (key_name)
    return kbd:keyIsDown(key_name)
end)

down = Cond.new(function ()
    return kbd:hadKeyDown()
end)

up = Cond.new(function ()
    return kbd:hadKeyUp()
end)

modkeys = {
  shift_r = "rightshift",
  shift_l = "leftshift",
  ctrl_l = "leftctrl",
  ctrl_r = "rightctrl",
  alt_r = "rightalt",
  alt_l = "leftalt",
}

for key, sys_key in pairs(modkeys) do
  _G[key] = held(sys_key)
end

ctrl = ctrl_l / ctrl_r
alt = alt_l / alt_r
shift = shift_l / shift_r

fn_keys = {}
for i = 1, 24 do
  table.insert(fn_keys, "f" .. tostring(i))
end

fn_keycodes = {}
for i, key in pairs(fn_keys) do
  fn_keycodes[getKeysym(key)] = true
end

prepare = Cond.new(function ()
    kbd:prepare()

    -- Don't act on Ctrl+Alt+F(n) keys
    if (ctrl + alt)() and fn_keycodes[kbd.event_code] then
      return true
    end

    return false
end)

notify = LazyF.new(function (title, message)
    io.popen(("zenity --notification --title='%s' --text='%s'"):format(title, message))
end)

say = LazyF.new(function (message)
    notify("Hawck:", message)()
end)

function mode(name, cond)
  local state = false
  local messages = {
    [true] = "%s was enabled.",
    [false] = "%s was disabled."
  }
  return Cond.new(function ()
      if cond() then
        state = not state
        notify("Hawck:", messages[state]:format(name))()
      end
      return state
  end)
end

__match[prepare] = echo
ProtectedMeta = {
  -- __newindex = function(t, name, val)
  --   if name:sub(1, 2) == "__" then
  --     error("Names starting with '__' are not allowed.")
  --   end
  --   rawset(t, name, val)
  -- end,

  __index = function (t, name)
    if not rawget(t, name) then
      error(("Undefined variable: %s"):format(name))
    end
    return rawget(t, name)
  end
}

setKeymap("./keymaps/qwerty/no.map")

local OMNIPRESENT = {"control_r",
                     "control_l",
                     "control",
                     "shift_l",
                     "shift_r",
                     "altgr",
                     "shift"}

for idx, name in ipairs(OMNIPRESENT) do
  __keys[name] = true
end

-- Called after loading a hwk script, requests keys from the daemon
-- depending on which keys are checked for using the key() function.
function __setup()
  -- Request keys from the keyboard-listening daemon, if we are currently
  -- in the daemon. If not then we are inside the Lua executor and have
  -- already requested keys in the other process.
  if KBDDaemon then
    for name, _ in pairs(__keys) do
      local succ, key = pcall(function ()
          return getKeysym(name)
      end)
      if succ then
        KBDDaemon:requestKey(key)
        print(("Requested key: %s"):format(name))
      else
        print(("Unable to request key: %s"):format(name))
      end
    end
  end
end

-- setmetatable(_G, ProtectedMeta)