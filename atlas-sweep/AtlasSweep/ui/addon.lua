-- Oyun içi kabuk: olaylar, komutlar, kayıtlı ayarlar. Planlamanın kendisi core/ içindedir ve
-- oyunun dışında da aynen çalışır (tools/, tests/).
--
--   /as                       yardım
--   /as start [rfc|wc|dm]     koşu başlat (zindandaysanız kendiliğinden başlar)
--   /as plan                  bütün planı sohbete yaz        /as next   sıradaki 3 bacak
--   /as done                  sıradaki hedefi elle tamamla    /as skip   hedefi atla, yeniden planla
--   /as at <oda>              bulunduğunuz odayı düzeltin     /as rooms  odaları listele
--   /as mode full|boss        tam temizlik ya da boss koşusu
--   /as rares on|off          nadir bossları da plana kat     /as exit on|off  sonda girişe dön
--   /as speed <yd/sn>         yürüme hızı (7 = yaya)          /as mob <sn>     düşman başı temizlik süresi
--   /as compare               Atlas.java kuralı, eklenti ve alt sınırı karşılaştır
--   /as show | hide | reset | list
local addonName, ns = ...
local Sweep, Tracker, Dungeons, UI = ns.Sweep, ns.Tracker, ns.Dungeons, ns.UI

local DEFAULTS = { mode = "full", rares = false, exit = false, speed = 7, perMob = 10, shown = true }
local RUN_TTL = 2 * 3600 -- kayıtlı koşu bu kadar saniye sonra eski sayılır

local db
local run -- { dungeon, M, tracker, mode, planning, version, pending }
local inDungeon = false -- ölümler yalnızca zindan içinde sayılır (Westfall'daki Defias'lar sayılmasın)

local function out(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AtlasSweep|r " .. msg) end
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

-- Planlamayı karelere bölen çalıştırıcı (coroutine; karede en çok ~8 ms) -------------------
local runner = CreateFrame("Frame")
runner:Hide()
local job
runner:SetScript("OnUpdate", function(self)
  if not job then self:Hide(); return end
  local t0 = debugprofilestop()
  repeat
    local ok, err = coroutine.resume(job.co)
    if not ok then
      out("|cffff4040planlama hatası:|r " .. tostring(err))
      job = nil; self:Hide(); return
    end
    if coroutine.status(job.co) == "dead" then
      local j = job
      job = nil; self:Hide()
      j.done()
      return
    end
  until debugprofilestop() - t0 > 8
end)

local function runAsync(fn, done)
  job = { co = coroutine.create(function() fn(coroutine.yield) end), done = done }
  runner:Show()
end
ns.runAsync = runAsync

-- Koşu yönetimi ----------------------------------------------------------------------------
local function options()
  return { mode = db.mode, rares = db.rares, exit = db.exit, speed = db.speed, perMob = db.perMob }
end

local function save()
  if not run then return end
  db.runs[run.dungeon.id] = { at = time(), mode = run.mode, data = run.tracker:serialize() }
end

local function legLine(i, leg)
  return ("%d. %s — %s"):format(i, Sweep.fmtTime(leg.time), Sweep.legText(run.M, leg))
end

local function announceNext()
  local leg = run.tracker:currentLeg()
  if leg then out("sıradaki: " .. Sweep.legText(run.M, leg))
  else out("|cff40ff40plan tamamlandı.|r") end
end

local onKill

local function replan(quiet)
  if not run then return end
  run.planning = true
  run.pending = run.pending or {}
  UI.update(run)
  local version = run.version
  runAsync(function(yield) run.tracker:replan(yield) end, function()
    if run.version ~= version then return replan(quiet) end -- planlarken durum değişti
    run.planning = false
    local p = run.tracker.plan
    -- planlarken gelen ölümleri şimdi işle
    local pending = run.pending
    run.pending = {}
    for _, k in ipairs(pending) do onKill(k[1], k[2]) end
    if not quiet then
      out(("%s — plan hazır: %d bacak, ~%s (yürüme %s). /as plan"):format(run.dungeon.name,
        #p.legs, Sweep.fmtTime(p.stats.total), Sweep.fmtTime(p.stats.walk)))
      if #p.unreachable > 0 then out("|cffff4040ulaşılamayan:|r " .. table.concat(p.unreachable, ", ")) end
    end
    save()
    UI.update(run)
  end)
end

local function startRun(d, resume)
  local M = Sweep.build(d, options())
  local saved = resume and db.runs[d.id]
  local tracker
  if saved and saved.mode == db.mode and saved.at and time() - saved.at < RUN_TTL then
    tracker = Tracker.restore(M, saved.data)
    out(d.name .. ": kayıtlı koşu sürdürülüyor (/as reset ile sıfırlayın).")
  else
    tracker = Tracker.new(M)
  end
  run = { dungeon = d, M = M, tracker = tracker, mode = db.mode, planning = false, version = 0 }
  if db.shown then UI.show() end
  replan()
end

-- Ayar değişince modeli yeniden kur, ilerlemeyi koru.
local function rebuild()
  if not run then return end
  local data = run.tracker:serialize()
  data.skipped = nil -- atlananlar yeni kipte yeniden seçilir
  run.M = Sweep.build(run.dungeon, options())
  run.tracker = Tracker.restore(run.M, data)
  run.mode = db.mode
  run.version = run.version + 1
  replan()
end

local function detectInstance()
  local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
  inDungeon = instanceType == "party"
  if instanceType ~= "party" then
    if run then
      -- Zindandan çıkıldı: sıradaki hedef "girişe dön" ise tamamlanmış sayılır.
      local obj = run.tracker:objective()
      if obj and obj.kind == "exit" and not run.planning then
        run.tracker:done(); out("|cff40ff40zindandan çıkıldı, plan tamamlandı.|r"); UI.update(run)
      end
      save()
    end
    return
  end
  local d = Dungeons.find(instanceID, name)
  if not d then return end
  if run and run.dungeon.id == d.id then return end
  startRun(d, true)
end

-- Ölüm takibi ------------------------------------------------------------------------------
function onKill(destName, destGUID)
  if run.planning then
    run.pending[#run.pending + 1] = { destName, destGUID }
    return
  end
  local ev, what = run.tracker:onKill(destName, destGUID)
  if not ev then return end
  run.version = run.version + 1
  if ev == "boss" then
    out(("|cffff3030%s|r öldü."):format(what)); announceNext(); save()
  elseif ev == "cleared" then
    out("koridor temizlendi."); announceNext(); save()
  elseif ev == "offplan" then
    out(("%s plan dışı öldü; yeniden planlanıyor."):format(what))
    replan(true)
    return
  end
  UI.update(run)
end

local function onCombatLog()
  if not run or not inDungeon then return end
  local _, sub, _, _, _, _, _, destGUID, destName = CombatLogGetCurrentEventInfo()
  if sub ~= "UNIT_DIED" or not destGUID or not destName then return end
  if not destGUID:match("^Creature") then return end
  onKill(destName, destGUID)
end

-- Komutlar ---------------------------------------------------------------------------------
local function findRoom(text)
  text = trim(text or ""):lower()
  if text == "" or not run then return nil end
  local hit
  for _, n in ipairs(run.dungeon.nodes) do
    if n.id == text or n.name:lower() == text then return n end
    if n.name:lower():find(text, 1, true) or n.id:find(text, 1, true) then
      if hit then return nil, "birden çok oda eşleşti" end
      hit = n
    end
  end
  return hit
end

local function onOff(v) if v == "on" then return true elseif v == "off" then return false end end

local function help()
  out("komutlar: start [rfc|wc|dm], plan, next, done, skip, at <oda>, rooms, mode full|boss, " ..
      "rares on|off, exit on|off, speed <yd/sn>, mob <sn>, compare, show, hide, reset, list")
end

local commands = {}

function commands.start(rest)
  local d = rest ~= "" and Dungeons.find(nil, rest)
  if not d then
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    d = Dungeons.find(instanceID, name)
  end
  if not d then out("zindan bulunamadı. /as list"); return end
  startRun(d, false)
end

function commands.list()
  for _, id in ipairs(Dungeons.order) do
    local d = Dungeons[id]
    out(("%s — %s (seviye %s, %d oda, %d koridor, %d boss)"):format(id, d.name, d.levels,
      #d.nodes, #d.corridors, #d.bosses))
  end
end

local function needRun()
  if not run then out("etkin koşu yok. /as start <rfc|wc|dm>"); return false end
  if run.planning then out("plan hesaplanıyor, bir an…"); return false end
  return true
end

function commands.plan()
  if not needRun() then return end
  local p = run.tracker.plan
  for i = run.tracker.leg, #p.legs do out(legLine(i, p.legs[i])) end
  out(("kalan ~%s"):format(Sweep.fmtTime(run.tracker:remainingTime())))
end

function commands.next()
  if not needRun() then return end
  local p = run.tracker.plan
  for i = run.tracker.leg, math.min(#p.legs, run.tracker.leg + 2) do out(legLine(i, p.legs[i])) end
end

function commands.done()
  if not needRun() then return end
  if run.tracker:done() then run.version = run.version + 1; announceNext(); save(); UI.update(run) end
end

function commands.skip()
  if not needRun() then return end
  local id = run.tracker:skip()
  if id then out("atlandı: " .. id) end
  run.version = run.version + 1
  replan()
end

function commands.at(rest)
  if not needRun() then return end
  local n, err = findRoom(rest)
  if not n then out(err or "oda bulunamadı. /as rooms"); return end
  run.tracker.state.node = n.id
  run.version = run.version + 1
  out("konum: " .. n.name)
  replan()
end

function commands.rooms()
  if not run then out("etkin koşu yok."); return end
  local names = {}
  for _, n in ipairs(run.dungeon.nodes) do names[#names + 1] = n.name .. " (" .. n.id .. ")" end
  out(table.concat(names, ", "))
end

function commands.mode(rest)
  if rest ~= "full" and rest ~= "boss" then out("kullanım: /as mode full|boss"); return end
  db.mode = rest
  out("kip: " .. (rest == "full" and "tam temizlik" or "boss koşusu"))
  rebuild()
end

local function toggle(key, label)
  return function(rest)
    local v = onOff(rest)
    if v == nil then out("kullanım: /as " .. key .. " on|off"); return end
    db[key] = v
    out(label .. ": " .. (v and "açık" or "kapalı"))
    rebuild()
  end
end
commands.rares = toggle("rares", "nadir bosslar")
commands.exit = toggle("exit", "girişe dönüş")

local function number(key, label, lo, hi, cmd)
  return function(rest)
    local v = tonumber(rest)
    if not v or v < lo or v > hi then out(("kullanım: /as %s <%g-%g>"):format(cmd or key, lo, hi)); return end
    db[key] = v
    out(label .. ": " .. v)
    rebuild()
  end
end
commands.speed = number("speed", "yürüme hızı", 1, 30)
commands.mob = number("perMob", "düşman başı süre", 1, 120, "mob")

function commands.compare()
  if not needRun() then return end
  local d = run.dungeon
  local o = options()
  local function walkOf(opts)
    local M = Sweep.build(d, o)
    local p = Sweep.plan(M, nil, opts)
    return p.stats.walk, p.stats.total
  end
  local jw, jt = walkOf({ unit = true })
  local ew, et = walkOf({})
  local lb = Sweep.lowerBound(Sweep.build(d, o))
  out(("%s, baştan: Atlas.java kuralı yürüme %s (toplam %s) · eklenti yürüme %s (toplam %s)"):format(
    d.name, Sweep.fmtTime(jw), Sweep.fmtTime(jt), Sweep.fmtTime(ew), Sweep.fmtTime(et)))
  if db.mode == "full" then out("alt sınır (her gerekli koridor bir kez): yürüme " .. Sweep.fmtTime(lb.walk)) end
end

function commands.show() db.shown = true; UI.show(); UI.update(run) end
function commands.hide() db.shown = false; UI.hide() end

function commands.reset()
  if run then
    db.runs[run.dungeon.id] = nil
    local d = run.dungeon
    startRun(d, false)
    out("koşu sıfırlandı.")
  else
    db.runs = {}
    out("kayıtlı koşular silindi.")
  end
end

SLASH_ATLASSWEEP1 = "/as"
SLASH_ATLASSWEEP2 = "/atlassweep"
SlashCmdList["ATLASSWEEP"] = function(msg)
  msg = trim(msg or "")
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower()
  local f = cmd and commands[cmd]
  if f then f(trim(rest or "")) else help() end
end

-- Olaylar ----------------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    AtlasSweepDB = AtlasSweepDB or {}
    db = AtlasSweepDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    db.runs = db.runs or {}
    UI.init(db)
  elseif not db then
    return
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    onCombatLog()
  elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    detectInstance()
  elseif event == "PLAYER_LOGOUT" then
    save()
  end
end)

-- Testler için
ns.commands = commands
ns.getRun = function() return run end
