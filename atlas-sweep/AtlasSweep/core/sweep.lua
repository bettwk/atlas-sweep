-- Zindan tam temizlik planı, Atlas ile.
--
-- Zindan bir graftır: kavşaklar/odalar düğüm, koridorlar iki yönlü kenar (iki yay). İçinde
-- düşman grubu olan koridorun ilk geçişi, temizleme süresi kadar ek tutar. Bosslar
-- bulundukları odada kendi üzerine dönen bir yaydır (ağırlığı dövüş süresi). Bazı koridorlar
-- bir boss ölünce açılır (kapı), bazıları tek yönlüdür (aşağı atlama).
--
-- Yapılması gereken her şey bir GÖREVdir; bir görev yaylarından biri geçilince kapsanır:
--   full  (tam temizlik)  düşmanlı her koridor + her boss
--   boss  (boss koşusu)   yalnızca bosslar; yoldaki düşmanlar yine temizlenir ve süre tutar
--   isteğe bağlı          nadir (rare) bosslar, sonda girişe dönüş
-- Plan böylece Atlas'ın kendi problemi olur: bütün gerekli yayları kapsayan tek yürüyüş.
-- Atlas.java'dan farkı: orada her kenar 1 adımdır; koridorların iki yayı vardır ama görev
-- birdir, yani herhangi bir yönden geçmek yeter (yönsüz kırsal postacı problemine yakındır).
--
-- Her tur Atlas'ın turudur (atlas.lua):
--   1. yürüyüşün son yayından erişilen (kapısı açık) yayları DFS ardıl-sırasıyla dizer,
--   2. bu sıra üzerinde en uzun yol DP'si:  puan(n) = puan(e) + yeni(n)·λ − maliyet(n),
--      maliyet = kaçınılabilir süre (yürüme + gerekmeyen temizlik; bkz. planCost),
--   3. bir zinciri yürüyüşe ekler; gerekli görev kalmayana kadar sürer.
-- Oyuna göre eklenenler:
--   * Birden çok DFS sırası. DP yalnızca DFS sırasında ileri giden yayları izler; komşular
--     farklı sıralarla (veri sırası, önce yakın, önce uzak, sabit tohumlu karıştırmalar)
--     gezilerek aynı tur birkaç kez çalıştırılır.
--   * λ taraması. λ = BÜYÜK, Atlas'ın kuralıdır (önce çok yeni görev, eşitlikte kısa süre).
--     Daha küçük λ'lar daha kısa, yakın zincirler üretir. Her DP'nin her görev-yayında biten
--     zinciri bir aday olur.
--   * Üç seçim kuralı; her biri baştan sona plan kurar, en kısası tutulur:
--       "oran"   adaylar içinden  maliyet / yeni görev  oranı en küçük zincir,
--       "zincir" Atlas'ın kendi seçimi: λ = BÜYÜK ile en yüksek puanlı zincir,
--       "pilot"  en iyi birkaç "oran" adayının her biri için planın geri kalanı hızlı bir
--                Atlas koşusuyla tamamlanır, toplamı en küçük aday seçilir (pilot yöntemi;
--                açgözlü seçimin "koridoru geride bırakıp sonra geri dönme" hatasını azaltır).
--   * Kapılar ve önkoşullar (ör. Mutanus için dört Fanglord) her turun başında güncellenir;
--     kapısı kapalı yay o turun DFS'ine girmez.
--   * Bir zincirdeki gerçek kazanç ve süre zincir eklenirken yeniden hesaplanır (DP aynı
--     koridorun iki yayını iki kez sayabilir; plan istatistikleri bu yüzden kesindir).
local _, ns = ...

local Sweep = {}
local NEG = -math.huge
local BIG = 1e7

-- Biçim yardımcıları -------------------------------------------------------------------------
function Sweep.fmtTime(s)
  s = math.floor(s + 0.5)
  if s >= 3600 then return ("%d sa %02d dk"):format(math.floor(s / 3600), math.floor(s % 3600 / 60)) end
  if s >= 60 then return ("%d dk %02d sn"):format(math.floor(s / 60), s % 60) end
  return ("%d sn"):format(s)
end

local function copySet(t)
  local c = {}
  if t then for k, v in pairs(t) do c[k] = v end end
  return c
end

-- Model ------------------------------------------------------------------------------------
-- d: data/dungeons.lua içindeki bir zindan. opts:
--   mode   "full" | "boss"        rares  nadir bossları da görev say
--   exit   sonda girişe dön       speed  yürüme hızı yd/sn (7 = yaya)
--   perMob bir düşmanın ortalama temizleme süresi (sn)
--   skip   { [görevKimliği] = true }  atlanacak görevler
function Sweep.build(d, opts)
  opts = opts or {}
  local speed = opts.speed or 7
  local perMob = opts.perMob or 10
  local mode = opts.mode or "full"
  local skip = opts.skip or {}

  local M = { d = d, opts = opts, nodes = {}, nodeList = {}, arcs = {}, m = 0, out = {},
              tasks = {}, taskList = {}, corridors = {}, bosses = {}, bossList = {} }

  for _, n in ipairs(d.nodes) do
    M.nodes[n.id] = n
    M.nodeList[#M.nodeList + 1] = n
    M.out[n.id] = {}
  end

  local function addArc(a)
    M.m = M.m + 1
    a.label = M.m
    M.arcs[a.label] = a
    local o = M.out[a.source]
    assert(o, "bilinmeyen düğüm: " .. tostring(a.source))
    assert(M.out[a.dest], "bilinmeyen düğüm: " .. tostring(a.dest))
    o[#o + 1] = a.label
    return a.label
  end

  local function addTask(t)
    t.required = not skip[t.id]
    M.tasks[t.id] = t
    M.taskList[#M.taskList + 1] = t.id
    return t
  end

  -- Koridorlar
  for _, c in ipairs(d.corridors) do
    local A, B = M.nodes[c.a], M.nodes[c.b]
    assert(A and B, "koridor " .. c.id .. ": bilinmeyen uç")
    local len = c.len
    if not len then
      local dx, dy = A.x - B.x, A.y - B.y
      len = math.sqrt(dx * dx + dy * dy) * (d.bend or 1.2)
    end
    local mobs, expect = {}, 0
    for _, p in ipairs(c.packs or {}) do
      mobs[p[1]] = (mobs[p[1]] or 0) + p[2]
      expect = expect + p[2]
    end
    local cor = { id = c.id, a = c.a, b = c.b, len = len, walk = len / speed,
                  clear = expect * perMob, mobs = mobs, expect = expect, gate = c.gate,
                  oneway = c.oneway, name = c.name }
    M.corridors[c.id] = cor
    local task
    if mode == "full" and expect > 0 then
      task = addTask({ id = "c:" .. c.id, kind = "corridor", corridor = c.id, arcs = {},
                       name = c.name or (A.name .. " — " .. B.name) })
    end
    local fwd = addArc({ source = c.a, dest = c.b, walk = cor.walk, corridor = c.id,
                         kind = "move", gate = c.gate, task = task and task.id })
    cor.arcs = { fwd }
    if task then task.arcs[#task.arcs + 1] = fwd end
    if not c.oneway then
      local back = addArc({ source = c.b, dest = c.a, walk = cor.walk, corridor = c.id,
                            kind = "move", gate = c.gate, task = task and task.id })
      cor.arcs[2] = back
      if task then task.arcs[#task.arcs + 1] = back end
    end
  end

  -- Bosslar
  for _, b in ipairs(d.bosses) do
    assert(M.nodes[b.at], "boss " .. b.name .. ": bilinmeyen oda " .. tostring(b.at))
    local boss = { name = b.name, at = b.at, fight = b.fight or 60, rare = b.rare,
                   requires = b.requires or {}, alias = b.alias }
    M.bosses[b.name] = boss
    M.bossList[#M.bossList + 1] = boss
    if not b.rare or opts.rares then
      local t = addTask({ id = "b:" .. b.name, kind = "boss", boss = b.name, arcs = {},
                          name = b.name, requires = boss.requires })
      local l = addArc({ source = b.at, dest = b.at, walk = 0, kind = "boss",
                         boss = b.name, task = t.id })
      t.arcs[1] = l
      boss.task = t.id
    end
  end

  -- Girişe dönüş: bütün diğer gerekli görevlerden sonra
  if opts.exit then
    local t = addTask({ id = "exit", kind = "exit", arcs = {}, name = "Girişe dön",
                        afterAll = true })
    t.arcs[1] = addArc({ source = d.entrance, dest = d.entrance, walk = 0, kind = "exit",
                         task = t.id })
  end

  -- Ortalama yay süresi (λ taraması için)
  local sum, n = 0, 0
  for _, a in ipairs(M.arcs) do
    if a.kind == "move" then sum = sum + a.walk; n = n + 1 end
  end
  M.meanArc = n > 0 and sum / n or 1

  -- DFS keşif sıraları
  M.orders = Sweep.makeOrders(M, opts.orders or 6)
  return M
end

-- Komşu listelerinin farklı sıraları. Her sıra: düğüm -> yay etiketleri.
function Sweep.makeOrders(M, count)
  local function base(l)
    local a = M.arcs[l]
    if a.kind == "move" then return a.walk + M.corridors[a.corridor].clear end
    return 0
  end
  local orders = {}
  orders[1] = M.out -- veri sırası
  local near, far = {}, {}
  for id, list in pairs(M.out) do
    local s1, s2 = {}, {}
    for i, l in ipairs(list) do s1[i] = l; s2[i] = l end
    table.sort(s1, function(x, y) if base(x) ~= base(y) then return base(x) < base(y) end return x < y end)
    table.sort(s2, function(x, y) if base(x) ~= base(y) then return base(x) > base(y) end return x < y end)
    near[id], far[id] = s1, s2
  end
  orders[2], orders[3] = near, far
  local x = 12345
  local function rnd(n) x = (x * 1103515245 + 12345) % 2147483648; return math.floor(x / 65536) % n end
  for k = 4, count do
    local o = {}
    for _, node in ipairs(M.nodeList) do -- düğüm sırası sabit: sonuç tekrarlanabilir
      local list = M.out[node.id]
      local s = {}
      for i, l in ipairs(list) do s[i] = l end
      for i = #s, 2, -1 do local j = rnd(i) + 1; s[i], s[j] = s[j], s[i] end
      o[node.id] = s
    end
    orders[k] = o
  end
  local out = {}
  for k = 1, math.min(count, #orders) do out[k] = orders[k] end
  return out
end

-- Durum ------------------------------------------------------------------------------------
-- state = { node, covered = {görev=true}, cleared = {koridor=true}, dead = {boss=true} }
function Sweep.newState(M, node)
  return { node = node or M.d.entrance, covered = {}, cleared = {}, dead = {} }
end

function Sweep.copyState(s)
  return { node = s.node, covered = copySet(s.covered), cleared = copySet(s.cleared),
           dead = copySet(s.dead) }
end

local function prereqsMet(M, t, state)
  if t.afterAll then
    local un = state.unreachable or {}
    for _, id in ipairs(M.taskList) do
      local o = M.tasks[id]
      if o.required and id ~= t.id and not state.covered[id] and not un[id] then
        return false
      end
    end
    return true
  end
  for _, b in ipairs(t.requires or {}) do
    if not state.dead[b] then return false end
  end
  return true
end
Sweep.prereqsMet = prereqsMet

-- Yay bu durumda kullanılabilir mi?
local function available(M, a, state)
  if a.kind == "start" then return false end
  if a.gate and not state.dead[a.gate] then return false end
  if a.kind == "boss" or a.kind == "exit" then
    local t = M.tasks[a.task]
    if state.covered[t.id] or (a.boss and state.dead[a.boss]) then return false end
    return prereqsMet(M, t, state)
  end
  return true
end
Sweep.available = available

-- Yayın bu durumdaki süresi.
local function arcTime(M, a, state)
  if a.kind == "move" then
    local c = M.corridors[a.corridor]
    if state.cleared[c.id] then return a.walk end
    return a.walk + c.clear
  elseif a.kind == "boss" then
    return M.bosses[a.boss].fight
  end
  return 0
end
Sweep.arcTime = arcTime

-- Planlama maliyeti: yalnızca kaçınılabilir süre. Gerekli koridorların temizliği ve boss
-- dövüşleri her planda aynıdır, sıralamayı etkilememeli (yoksa planlayıcı bir bossun odasından
-- geçip "pahalı" dövüşü sonraya bırakır). Kaçınılabilir olan: yürüme ve gerekli olmayan bir
-- koridorun (boss koşusunda ya da atlanan görevde) temizliği.
local function planCost(M, a, state)
  if a.kind ~= "move" then return 0 end
  local c = M.corridors[a.corridor]
  if state.cleared[c.id] or c.expect == 0 then return a.walk end
  local t = a.task and M.tasks[a.task]
  if t and t.required then return a.walk end
  return a.walk + c.clear
end
Sweep.planCost = planCost

-- Yay yeni bir gerekli görev kapsıyor mu?
local function gain(M, a, state)
  local id = a.task
  if not id then return 0 end
  local t = M.tasks[id]
  if not t.required or state.covered[id] then return 0 end
  if not prereqsMet(M, t, state) then return 0 end
  return 1
end

-- Yayı yürüyüşe uygula: kesin süre ve kazanç.
local function apply(M, a, state)
  local dt = arcTime(M, a, state)
  local g = gain(M, a, state)
  if a.task then state.covered[a.task] = true end
  if a.kind == "move" then state.cleared[a.corridor] = true end
  if a.kind == "boss" then state.dead[a.boss] = true end
  state.node = a.dest
  return dt, g
end
Sweep.apply = apply

-- Kalan gerekli görev sayısı (kapsanmamış, ulaşılamaz olarak işaretlenmemiş).
local function remaining(M, state)
  local n = 0
  for _, id in ipairs(M.taskList) do
    local t = M.tasks[id]
    if t.required and not state.covered[id] and not state.unreachable[id] then n = n + 1 end
  end
  return n
end

-- Bir Atlas turu: DFS ardıl-sırası + en uzun yol DP'si. -------------------------------------
-- unit = true ise süreler 1 sayılır (Atlas.java kuralı, karşılaştırma için).
local function atlasRound(M, state, startArc, order, lambda, unit)
  -- 1. DFS ardıl-sırası (yığınlı), yalnızca kullanılabilir yaylar
  local mark, stack = {}, {}
  mark[startArc] = true
  local function nbrs(l) return order[M.arcs[l].dest] or {} end
  local frames = { { e = startArc, i = 0, n = nbrs(startArc) } }
  while #frames > 0 do
    local f = frames[#frames]
    local pushed = false
    while f.i < #f.n do
      f.i = f.i + 1
      local x = f.n[f.i]
      if not mark[x] and available(M, M.arcs[x], state) then
        mark[x] = true
        frames[#frames + 1] = { e = x, i = 0, n = nbrs(x) }
        pushed = true
        break
      end
    end
    if not pushed then
      stack[#stack + 1] = f.e
      frames[#frames] = nil
    end
  end

  -- 2. En uzun yol DP'si, yığın ters sırayla
  local score, cnt, tim, from = {}, {}, {}, {}
  score[startArc], cnt[startArc], tim[startArc] = 0, 0, 0
  local visited = {}
  for s = #stack, 1, -1 do
    local e = stack[s]
    visited[e] = true
    if score[e] and score[e] > NEG then
      for _, x in ipairs(nbrs(e)) do
        if not visited[x] and mark[x] then
          local a = M.arcs[x]
          local g = gain(M, a, state)
          local t = unit and 1 or planCost(M, a, state)
          local ns_ = score[e] + g * lambda - t
          if score[x] == nil or score[x] < ns_ then
            score[x], cnt[x], tim[x], from[x] = ns_, cnt[e] + g, tim[e] + t, e
          end
        end
      end
    end
  end
  return score, cnt, tim, from
end

local function chainOf(from, startArc, last)
  local chain = { last }
  local cur = last
  while from[cur] and from[cur] ~= startArc do
    cur = from[cur]
    chain[#chain + 1] = cur
  end
  local r = {}
  for i = #chain, 1, -1 do r[#r + 1] = chain[i] end
  return r
end

-- Zinciri bir durum kopyasında yürüterek kesin planlama maliyeti ve kazanç.
local function evalChain(M, state, chain)
  local s = Sweep.copyState(state)
  s.unreachable = state.unreachable
  local t, g = 0, 0
  for _, l in ipairs(chain) do
    local a = M.arcs[l]
    t = t + planCost(M, a, s)
    local _, dg = apply(M, a, s)
    g = g + dg
  end
  return t, g
end

-- Bir turun aday zincirleri, iyiden kötüye. cfg = { orders, lambdas }, keep = en çok kaç aday.
--   "chain": her DP'nin en yüksek puanlı yayında biten zincir (Atlas'ın seçimi);
--            anahtar: önce çok yeni görev, sonra az maliyet.
--   "ratio": her DP'nin her görev-yayında biten zincir; anahtar: maliyet / yeni görev.
local function candidates(M, state, startArc, rule, unit, cfg, keep)
  local list, seen = {}, {}
  local function offer(chain)
    local key = table.concat(chain, ",")
    if seen[key] then return end
    seen[key] = true
    local t, g = evalChain(M, state, chain)
    if g <= 0 then return end
    local k1, k2
    if rule == "chain" then k1, k2 = -g, t else k1, k2 = t / g, -g end
    list[#list + 1] = { chain = chain, k1 = k1, k2 = k2, cost = t, gain = g }
  end
  for _, order in ipairs(cfg.orders) do
    for _, lambda in ipairs(cfg.lambdas) do
      local score, cnt, _, from = atlasRound(M, state, startArc, order, lambda, unit)
      if rule == "chain" then
        local top, topScore
        for x = 1, M.m do
          local sc = score[x]
          if sc and x ~= startArc and cnt[x] > 0 and (topScore == nil or sc > topScore) then
            top, topScore = x, sc
          end
        end
        if top then offer(chainOf(from, startArc, top)) end
      else
        for x = 1, M.m do
          local c = cnt[x]
          if c and x ~= startArc and c > 0 and gain(M, M.arcs[x], state) > 0 then
            offer(chainOf(from, startArc, x))
          end
        end
      end
    end
  end
  table.sort(list, function(a, b)
    if math.abs(a.k1 - b.k1) > 1e-9 then return a.k1 < b.k1 end
    if a.k2 ~= b.k2 then return a.k2 < b.k2 end
    if #a.chain ~= #b.chain then return #a.chain < #b.chain end
    return table.concat(a.chain, ",") < table.concat(b.chain, ",")
  end)
  while #list > (keep or 1) do list[#list] = nil end
  return list
end

-- Yürüyüşün başlangıç yayı: düğümde kendi üzerine dönen, kullanılamayan sanal yay.
local function startArcAt(M, node)
  M.startArcs = M.startArcs or {}
  if not M.startArcs[node] then
    M.m = M.m + 1
    local a = { label = M.m, source = node, dest = node, walk = 0, kind = "start" }
    M.arcs[a.label] = a
    M.startArcs[node] = a.label -- out[] listesine eklenmez
  end
  return M.startArcs[node]
end

local function configs(M)
  if not M.cfg then
    local m = M.meanArc
    M.cfg = {
      full  = { orders = M.orders, lambdas = { BIG, m * 8, m * 3, m } },
      chain = { orders = M.orders, lambdas = { BIG } },
      fast  = { orders = { M.orders[1], M.orders[2], M.orders[3] }, lambdas = { BIG, m * 3 } },
    }
  end
  return M.cfg
end

local planWith

-- Pilot kuralı: en iyi birkaç "oran" adayının her biri için plan hızlı bir Atlas koşusuyla
-- (az sıra, iki λ) sona kadar tamamlanır; toplam maliyeti en küçük olan aday seçilir.
local function pilotPick(M, state, startArc, unit, yield)
  local cfg = configs(M)
  local list = candidates(M, state, startArc, "ratio", unit, cfg.full, M.opts.pilot or 4)
  if #list <= 1 then return list[1] and list[1].chain end
  local best, bestTotal
  for _, c in ipairs(list) do
    local s = Sweep.copyState(state)
    s.unreachable = copySet(state.unreachable)
    for _, l in ipairs(c.chain) do apply(M, M.arcs[l], s) end
    local _, final, cost = planWith(M, s, "ratio", unit, nil, M.opts.rollout == "full" and cfg.full or cfg.fast)
    local miss = 0
    for _ in pairs(final.unreachable) do miss = miss + 1 end
    local total = c.cost + cost + miss * BIG
    if best == nil or total < bestTotal - 1e-9 then best, bestTotal = c.chain, total end
    if yield then yield() end
  end
  return best
end

local function pick(M, state, startArc, rule, unit, cfg, yield)
  if rule == "pilot" then return pilotPick(M, state, startArc, unit, yield) end
  local c = candidates(M, state, startArc, rule, unit, cfg, 1)[1]
  return c and c.chain
end

-- Tek bir kuralla baştan sona plan. Döner: yürüyüş, son durum, toplam planlama maliyeti.
function planWith(M, state0, rule, unit, yield, cfg)
  local C = configs(M)
  cfg = cfg or (rule == "chain" and C.chain or C.full)
  local state = Sweep.copyState(state0)
  state.unreachable = copySet(state0.unreachable)
  local walk, cost = {}, 0
  local last = startArcAt(M, state.node)
  local rounds = 0
  local function take(chain)
    for _, l in ipairs(chain) do
      local a = M.arcs[l]
      walk[#walk + 1] = l
      cost = cost + planCost(M, a, state)
      apply(M, a, state)
    end
    last = chain[#chain]
  end
  while remaining(M, state) > 0 do
    rounds = rounds + 1
    local chain = pick(M, state, last, rule, unit, cfg, yield)
    if not chain then
      -- Kalan görevlerin hiçbirine ulaşılamıyor: bildir. Girişe dönüş yine de mümkünse yap.
      for _, id in ipairs(M.taskList) do
        local t = M.tasks[id]
        if t.required and not state.covered[id] and not t.afterAll then state.unreachable[id] = true end
      end
      if remaining(M, state) > 0 then
        local c2 = pick(M, state, last, rule, unit, cfg, yield)
        if c2 then take(c2) else
          for _, id in ipairs(M.taskList) do
            if M.tasks[id].required and not state.covered[id] then state.unreachable[id] = true end
          end
        end
      end
      break
    end
    take(chain)
    if yield then yield() end
    if rounds > 4 * #M.taskList + 10 then break end -- güvenlik
  end
  return walk, state, cost
end

-- Yürüyüşü adımlara çevirir ve istatistik çıkarır.
function Sweep.steps(M, state0, walk)
  local state = Sweep.copyState(state0)
  state.unreachable = {}
  local steps = {}
  local st = { walk = 0, clear = 0, fight = 0, total = 0, arcs = #walk }
  for _, l in ipairs(walk) do
    local a = M.arcs[l]
    local kind = a.kind
    local c = a.corridor and M.corridors[a.corridor]
    if kind == "move" then
      kind = (c.expect > 0 and not state.cleared[c.id]) and "clear" or "walk"
    end
    local newTask = (a.task and not state.covered[a.task]) and a.task or nil
    local dt = apply(M, a, state)
    if a.kind == "move" then
      st.walk = st.walk + a.walk
      if kind == "clear" then st.clear = st.clear + c.clear end
    elseif a.kind == "boss" then
      st.fight = st.fight + dt
    end
    st.total = st.total + dt
    steps[#steps + 1] = { arc = l, kind = kind, from = a.source, to = a.dest,
                          corridor = a.corridor, boss = a.boss, time = dt, task = newTask,
                          mobs = c and c.mobs, expect = c and c.expect }
  end
  return steps, st
end

-- Alt sınır: her gerekli koridor bir kez yürünür ve temizlenir, her boss bir kez dövülür.
function Sweep.lowerBound(M)
  local lb = { walk = 0, work = 0 }
  for _, id in ipairs(M.taskList) do
    local t = M.tasks[id]
    if t.required then
      if t.kind == "corridor" then
        local c = M.corridors[t.corridor]
        lb.walk = lb.walk + c.walk
        lb.work = lb.work + c.clear
      elseif t.kind == "boss" then
        lb.work = lb.work + M.bosses[t.boss].fight
      end
    end
  end
  lb.total = lb.walk + lb.work
  return lb
end

-- Ana giriş: planı kurar. opts.rule = "pilot" | "oran" | "zincir"; verilmezse üçü de denenir.
-- opts.unit = true: Atlas.java kuralı (her yay 1 adım), yalnızca karşılaştırma için.
function Sweep.plan(M, state0, opts)
  opts = opts or {}
  state0 = state0 or Sweep.newState(M)
  local rules
  if opts.rule == "oran" then rules = { "ratio" }
  elseif opts.rule == "zincir" or opts.unit then rules = { "chain" }
  elseif opts.rule == "pilot" then rules = { "pilot" }
  else rules = { "pilot", "ratio", "chain" } end
  local best
  for _, r in ipairs(rules) do
    local walk, final = planWith(M, state0, r, opts.unit, opts.yield)
    local steps, st = Sweep.steps(M, state0, walk)
    local unreachable = {}
    for _, id in ipairs(M.taskList) do
      if final.unreachable[id] then unreachable[#unreachable + 1] = id end
    end
    local p = { walk = walk, steps = steps, stats = st, rule = r, unreachable = unreachable,
                start = state0.node }
    if best == nil or #p.unreachable < #best.unreachable or
        (#p.unreachable == #best.unreachable and p.stats.total < best.stats.total) then
      best = p
    end
  end
  best.legs = Sweep.legs(best.steps)
  best.lower = Sweep.lowerBound(M)
  return best
end

-- Adımları "bacaklara" böler: art arda yürüyüşler + bir hedef (temizlik, boss ya da çıkış).
function Sweep.legs(steps)
  local legs, cur = {}, { walks = {}, time = 0 }
  for _, s in ipairs(steps) do
    cur.time = cur.time + s.time
    if s.kind == "walk" then
      cur.walks[#cur.walks + 1] = s
    else
      cur.obj = s
      legs[#legs + 1] = cur
      cur = { walks = {}, time = 0 }
    end
  end
  if #cur.walks > 0 then legs[#legs + 1] = cur end
  return legs
end

-- Bir bacağın tek satırlık anlatımı.
function Sweep.legText(M, leg)
  local parts = {}
  local function nodeName(id) return M.nodes[id] and M.nodes[id].name or id end
  local path = {}
  for _, w in ipairs(leg.walks) do path[#path + 1] = nodeName(w.to) end
  if #path > 0 then parts[#parts + 1] = "yürü: " .. table.concat(path, " > ") end
  local o = leg.obj
  if o then
    if o.kind == "clear" then
      local c = M.corridors[o.corridor]
      local mobs = {}
      for name, n in pairs(o.mobs) do mobs[#mobs + 1] = n .. " " .. name end
      table.sort(mobs)
      parts[#parts + 1] = ("temizle: %s > %s (%s)"):format(nodeName(o.from), nodeName(o.to),
        table.concat(mobs, ", "))
    elseif o.kind == "boss" then
      parts[#parts + 1] = "boss: " .. o.boss .. " (" .. nodeName(o.to) .. ")"
    elseif o.kind == "exit" then
      parts[#parts + 1] = "girişe dön"
    end
  end
  return table.concat(parts, "; ")
end

ns.Sweep = Sweep
