-- Testler için WoW API'sinin eklentinin kullandığı kadarı. Gerçek istemcinin yerini tutmaz:
-- yalnızca çağrıların doğru sırada ve doğru biçimde yapıldığını sınar.
local mock = { chat = {}, frames = {}, instance = { nil, "none" }, combat = {} }

local function newObject(kind)
  local o = { _kind = kind, _scripts = {}, _events = {}, _shown = true, _text = "" }
  local methods = {}
  function methods:SetScript(name, fn) self._scripts[name] = fn end
  function methods:GetScript(name) return self._scripts[name] end
  function methods:RegisterEvent(e) self._events[e] = true end
  function methods:Show() self._shown = true end
  function methods:Hide() self._shown = false end
  function methods:IsShown() return self._shown end
  function methods:SetText(t) self._text = t or "" end
  function methods:GetText() return self._text end
  function methods:SetPoint(...) self._point = { ... } end
  function methods:GetPoint() local p = self._point or { "CENTER" }; return p[1], p[2], p[3] or p[1], p[4] or 0, p[5] or 0 end
  function methods:CreateFontString()
    local fs = newObject("FontString")
    mock.frames[#mock.frames + 1] = fs -- metni testte okunabilsin
    return fs
  end
  function methods:StartMoving() end
  function methods:StopMovingOrSizing() end
  return setmetatable(o, { __index = function(_, k)
    if methods[k] then return methods[k] end
    return function() end -- SetSize, SetBackdrop, SetJustifyH, ... : etkisiz
  end })
end

function mock.install()
  UIParent = newObject("Frame")
  BackdropTemplateMixin = {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) mock.chat[#mock.chat + 1] = msg end }
  SlashCmdList = {}
  CreateFrame = function(kind)
    local f = newObject(kind)
    mock.frames[#mock.frames + 1] = f
    return f
  end
  GetInstanceInfo = function() return unpack(mock.instance, 1, 8) end
  CombatLogGetCurrentEventInfo = function() return unpack(mock.combat, 1, 11) end
  local clock = 1000000
  time = function() return clock end
  mock.advance = function(s) clock = clock + s end
  debugprofilestop = function() return os.clock() * 1000 end
  unpack = unpack or table.unpack
end

function mock.fire(event, ...)
  for _, f in ipairs(mock.frames) do
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end

-- OnUpdate'i olan görünür çerçeveleri, işleri bitene kadar karelerle sürer.
function mock.runFrames(max)
  for _ = 1, max or 10000 do
    local any = false
    for _, f in ipairs(mock.frames) do
      if f._shown and f._scripts.OnUpdate then any = true; f._scripts.OnUpdate(f, 0.016) end
    end
    if not any then return end
  end
  error("çerçeveler durmadı")
end

function mock.slash(msg) SlashCmdList["ATLASSWEEP"](msg) end

function mock.kill(name, guid)
  mock.combat = { 0, "UNIT_DIED", false, "", "", 0, 0, guid, name, 0, 0 }
  mock.fire("COMBAT_LOG_EVENT_UNFILTERED")
end

function mock.lastChat(n)
  local r = {}
  for i = math.max(1, #mock.chat - (n or 1) + 1), #mock.chat do r[#r + 1] = mock.chat[i] end
  return table.concat(r, "\n")
end

function mock.chatHas(pattern)
  for _, m in ipairs(mock.chat) do if m:find(pattern) then return true end end
  return false
end

return mock
