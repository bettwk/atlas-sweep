-- Zindan içinde ilerleme takibi. WoW API'sine dokunmaz (oyun dışında test edilir);
-- ui/addon.lua ölüm olaylarını buraya iletir.
--
-- Classic istemcisi zindan içinde oyuncunun koordinatını vermez. Bu yüzden konum ölümlerden
-- çıkarılır:
--   * bir boss ölünce oyuncu o bossun odasındadır (boss adları tektir);
--   * planın sıradaki hedefi bir koridor temizliğiyse, o koridorun düşman adlarından gelen
--     ölümler sayılır; beklenen sayıya ulaşınca koridor temizlenmiş sayılır ve plan ilerler;
--   * planda birkaç bacak ilerideki boss ölürse aradaki bacaklar yapılmış sayılır.
-- Sıra dışı bir boss ölümü (oyuncu plandan saptı) yeniden planlama ister. Sayılar tutmazsa
-- (veri yaklaşık) oyuncu /as done ile hedefi elle tamamlar.
local _, ns = ...
local Sweep = ns.Sweep

local Tracker = {}
Tracker.__index = Tracker
Tracker.LOOKAHEAD = 2

function Tracker.new(M)
  local self = setmetatable({ M = M, state = Sweep.newState(M), leg = 1, kills = 0, seen = {} }, Tracker)
  return self
end

-- Planı mevcut durumdan yeniden kurar. yield verilirse planlama turlar arasında ona döner
-- (oyunda coroutine ile karelere bölmek için).
function Tracker:replan(yield)
  self.plan = Sweep.plan(self.M, self.state, { yield = yield })
  self.leg, self.kills = 1, 0
  return self.plan
end

function Tracker:currentLeg() return self.plan and self.plan.legs[self.leg] end

function Tracker:objective()
  local leg = self:currentLeg()
  return leg and leg.obj
end

function Tracker:finished()
  return self.plan ~= nil and self.leg > #self.plan.legs
end

-- Bacağı tamamla: yürüyüşleri ve hedefi duruma uygula.
function Tracker:completeLeg()
  local leg = self:currentLeg()
  if not leg then return end
  for _, w in ipairs(leg.walks) do Sweep.apply(self.M, self.M.arcs[w.arc], self.state) end
  if leg.obj then Sweep.apply(self.M, self.M.arcs[leg.obj.arc], self.state) end
  self.leg, self.kills = self.leg + 1, 0
end

-- Bir yaratık öldü. Döner: olay türü ("boss" | "cleared" | "kill" | "offplan") ve ayrıntı.
function Tracker:onKill(name, guid)
  if guid then
    if self.seen[guid] then return nil end
    self.seen[guid] = true
  end
  local M = self.M
  local boss = M.bosses[name]
  if boss then
    if self.state.dead[name] then return nil end
    -- Boss planda yakındaysa (en çok LOOKAHEAD bacak ileride) aradaki bacaklar yapılmış sayılır:
    -- düşman sayıları yaklaşık olduğu için koridor sayacı dolmadan boss ölebilir.
    local legs = self.plan and self.plan.legs or {}
    for j = self.leg, math.min(#legs, self.leg + Tracker.LOOKAHEAD) do
      local o = legs[j].obj
      if o and o.kind == "boss" and o.boss == name then
        while self.leg <= j do self:completeLeg() end
        return "boss", name
      end
    end
    -- Plandan sapma: boss başka bir sırada öldü. Oyuncu artık o odada.
    self.state.dead[name] = true
    if boss.task then self.state.covered[boss.task] = true end
    self.state.node = boss.at
    return "offplan", name
  end
  local obj = self:objective()
  if obj and obj.kind == "clear" and obj.mobs[name] then
    self.kills = self.kills + 1
    if self.kills >= obj.expect then
      self:completeLeg()
      return "cleared", obj.corridor
    end
    return "kill", name
  end
  return nil
end

-- Sıradaki hedefi elle tamamla (/as done).
function Tracker:done()
  local leg = self:currentLeg()
  if not leg then return false end
  self:completeLeg()
  return true
end

-- Sıradaki hedefi atla (/as skip): görev gereksiz sayılır, plan yeniden kurulur.
-- Hedefe giden yürüyüş yapılmış sayılır (oyuncu oradadır).
function Tracker:skip(yield)
  local leg = self:currentLeg()
  if not leg or not leg.obj then return nil end
  for _, w in ipairs(leg.walks) do Sweep.apply(self.M, self.M.arcs[w.arc], self.state) end
  local id = leg.obj.task
  if id and self.M.tasks[id] then self.M.tasks[id].required = false end
  self.state.node = leg.obj.from
  self:replan(yield)
  return id
end

-- Konumu elle düzelt (/as at <oda>).
function Tracker:setNode(node, yield)
  if not self.M.nodes[node] then return false end
  self.state.node = node
  self:replan(yield)
  return true
end

-- Gerekli görevlerden kaçı yapıldı.
function Tracker:progress()
  local done, total = 0, 0
  for _, id in ipairs(self.M.taskList) do
    local t = self.M.tasks[id]
    if t.required then
      total = total + 1
      if self.state.covered[id] then done = done + 1 end
    end
  end
  return done, total
end

-- Kalan süre: mevcut bacaktan sonuna.
function Tracker:remainingTime()
  if not self.plan then return 0 end
  local s = 0
  for i = self.leg, #self.plan.legs do s = s + self.plan.legs[i].time end
  return s
end

-- SavedVariables için.
function Tracker:serialize()
  local function keys(t) local r = {}; for k in pairs(t) do r[#r + 1] = k end; table.sort(r); return r end
  local skipped = {}
  for _, id in ipairs(self.M.taskList) do
    if not self.M.tasks[id].required then skipped[#skipped + 1] = id end
  end
  return { node = self.state.node, covered = keys(self.state.covered), cleared = keys(self.state.cleared),
           dead = keys(self.state.dead), skipped = skipped }
end

function Tracker.restore(M, data)
  local self = Tracker.new(M)
  if data then
    if data.node and M.nodes[data.node] then self.state.node = data.node end
    for _, k in ipairs(data.covered or {}) do self.state.covered[k] = true end
    for _, k in ipairs(data.cleared or {}) do self.state.cleared[k] = true end
    for _, k in ipairs(data.dead or {}) do self.state.dead[k] = true end
    for _, k in ipairs(data.skipped or {}) do if M.tasks[k] then M.tasks[k].required = false end end
  end
  return self
end

ns.Tracker = Tracker
