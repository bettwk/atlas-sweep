-- Eklenti testleri. Kullanım: lua tests/run.lua   (Lua 5.4 ya da LuaJIT/Lua 5.1)
local root = arg[0]:match("^(.*)/tests/") or "."
local load = dofile(root .. "/tools/load.lua")
local ns = load(root)
local S, D, Tracker, Atlas, Graph = ns.Sweep, ns.Dungeons, ns.Tracker, ns.Atlas, ns.Graph

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print("ok    " .. name)
  else failed = failed + 1; print("HATA  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, msg) if a ~= b then error((msg or "") .. ": beklenen " .. tostring(b) .. ", gelen " .. tostring(a), 2) end end
local function truthy(v, msg) if not v then error(msg or "doğru olmalıydı", 2) end end
local function read(p) local f = assert(io.open(p)); local s = f:read("*a"); f:close(); return s end

local FIX = root .. "/tests/fixtures/"
local fixtures = {}
for _, f in ipairs({ "bbtas", "r_4_3_1", "r_10_3_2", "r_10_8_3", "r_25_4_4", "r_40_4_5", "r_50_10_6",
                     "r_100_10_7", "r_200_4_8", "s_30_5_11", "s_60_6_12", "s_150_8_13" }) do
  fixtures[#fixtures + 1] = f
end

-- Atlas çevirisi -----------------------------------------------------------------------------
test("Lua Atlas, Atlas.java ile aynı test dizisini üretir (12 FSM)", function()
  for _, f in ipairs(fixtures) do
    local g = Graph.parseFSM(read(FIX .. f .. ".fsm"))
    truthy(g.exactJavaOrder, f .. ": Java sırası taklit edilemedi")
    eq(Atlas.run(g), (read(FIX .. f .. ".java.txt"):gsub("%s+$", "")), f)
  end
end)

test("Atlas yürüyüşü kesintisizdir; keepLast ile güçlü bağlı FSM'lerin her kenarı kapsanır", function()
  for _, f in ipairs(fixtures) do
    local g = Graph.parseFSM(read(FIX .. f .. ".fsm"))
    local _, p = Atlas.run(g, true)
    for i = 2, #p do eq(g.edges[p[i - 1]].dest, g.edges[p[i]].source, f .. " adım " .. i) end
    if f:match("^s_") or f == "bbtas" then
      local n, m = Atlas.coverage(g, p)
      eq(n, m, f .. " kapsama")
    end
  end
end)

test("Java HashSet sırası: kova = etiket mod kapasite, kova içinde ekleme sırası", function()
  local g = Graph.new()
  local order = g:javaOrder({ 1, 16, 17, 33, 2 })
  eq(table.concat(order, ","), "16,1,17,33,2")
  local big = {}
  for i = 1, 13 do big[i] = (i - 1) * 3 end -- 13 eleman: kapasite 32
  eq(g:javaOrder(big)[2], 33 % 32 == 1 and 33 or g:javaOrder(big)[2], "kapasite")
  eq(g:javaOrder(big)[1], 0)
end)

-- Veri ---------------------------------------------------------------------------------------
test("zindan verisi tutarlı: uçlar, boss odaları, kapılar, önkoşullar, erişilebilirlik", function()
  for _, id in ipairs(D.order) do
    local d = D[id]
    local nodes, bosses, ids = {}, {}, {}
    for _, n in ipairs(d.nodes) do truthy(not nodes[n.id], id .. " yinelenen oda " .. n.id); nodes[n.id] = n end
    for _, b in ipairs(d.bosses) do truthy(nodes[b.at], id .. " boss odası " .. b.name); bosses[b.name] = b end
    for _, b in ipairs(d.bosses) do
      for _, r in ipairs(b.requires or {}) do truthy(bosses[r], id .. " önkoşul " .. r) end
    end
    local adj = {}
    for _, c in ipairs(d.corridors) do
      truthy(not ids[c.id], id .. " yinelenen koridor " .. c.id); ids[c.id] = true
      truthy(nodes[c.a] and nodes[c.b], id .. " koridor ucu " .. c.id)
      if c.gate then truthy(bosses[c.gate], id .. " kapı bossu " .. c.gate) end
      for _, p in ipairs(c.packs or {}) do truthy(type(p[1]) == "string" and p[2] > 0, id .. " grup " .. c.id) end
      adj[c.a] = adj[c.a] or {}; table.insert(adj[c.a], c.b)
      if not c.oneway then adj[c.b] = adj[c.b] or {}; table.insert(adj[c.b], c.a) end
    end
    local seen, q = { [d.entrance] = true }, { d.entrance }
    while #q > 0 do
      local n = table.remove(q)
      for _, m in ipairs(adj[n] or {}) do if not seen[m] then seen[m] = true; q[#q + 1] = m end end
    end
    for _, n in ipairs(d.nodes) do truthy(seen[n.id], id .. " erişilemeyen oda " .. n.id) end
    truthy(D.find(d.instanceID) == d, id .. " instanceID ile bulunur")
    truthy(D.find(nil, d.names[1]) == d, id .. " adıyla bulunur")
  end
end)

-- Planlar ------------------------------------------------------------------------------------
local function checkPlan(d, opts, p, M)
  local tag = d.id .. " " .. (opts.mode or "full") .. (opts.rares and "+nadir" or "") .. (opts.exit and "+çıkış" or "")
  eq(#p.unreachable, 0, tag .. " ulaşılamayan")
  local st = S.newState(M)
  local node = d.entrance
  for i, l in ipairs(p.walk) do
    local a = M.arcs[l]
    eq(a.source, node, tag .. " kesintisiz yürüyüş, adım " .. i)
    truthy(S.available(M, a, st), tag .. " kapalı kapı ya da önkoşul, adım " .. i .. " (" .. tostring(a.boss or a.corridor) .. ")")
    S.apply(M, a, st)
    node = a.dest
  end
  for _, id in ipairs(M.taskList) do
    if M.tasks[id].required then truthy(st.covered[id], tag .. " kapsanmayan görev " .. id) end
  end
  if opts.exit then
    eq(M.arcs[p.walk[#p.walk]].kind, "exit", tag .. " son adım girişe dönüş")
    eq(node, d.entrance, tag .. " girişte biter")
  end
  local s = p.stats
  truthy(math.abs(s.total - (s.walk + s.clear + s.fight)) < 1e-6, tag .. " süre toplamı")
  if (opts.mode or "full") == "full" then truthy(s.total >= p.lower.total - 1e-6, tag .. " alt sınır") end
  local legTime = 0
  for _, leg in ipairs(p.legs) do legTime = legTime + leg.time end
  truthy(math.abs(legTime - s.total) < 1e-6, tag .. " bacak süreleri")
end

test("her zindan, her kipte: kesintisiz, kapılara ve önkoşullara uyan, bütün görevleri kapsayan plan", function()
  for _, id in ipairs(D.order) do
    for _, o in ipairs({ { mode = "full" }, { mode = "full", rares = true, exit = true },
                         { mode = "boss" }, { mode = "boss", rares = true, exit = true } }) do
      local M = S.build(D[id], o)
      checkPlan(D[id], o, S.plan(M), M)
    end
  end
end)

test("Mutanus dört Fanglord'dan sonra; Deadmines kapıları boss ölmeden açılmaz", function()
  local M = S.build(D.wc, { mode = "full" })
  local p = S.plan(M)
  local dead = {}
  for _, l in ipairs(p.walk) do
    local a = M.arcs[l]
    if a.boss == "Mutanus the Devourer" then
      for _, b in ipairs({ "Lady Anacondra", "Lord Cobrahn", "Lord Pythas", "Lord Serpentis" }) do
        truthy(dead[b], "Mutanus'tan önce " .. b)
      end
    end
    if a.boss then dead[a.boss] = true end
  end
  M = S.build(D.dm, { mode = "boss" })
  p = S.plan(M)
  dead = {}
  for _, l in ipairs(p.walk) do
    local a = M.arcs[l]
    if a.gate then truthy(dead[a.gate], "kapı " .. a.corridor .. " / " .. a.gate) end
    if a.boss then dead[a.boss] = true end
  end
end)

test("eklenti planı tek tek kuralların en iyisidir; aynı girdiyle aynı plan çıkar", function()
  for _, id in ipairs(D.order) do
    local M = S.build(D[id], { mode = "full" })
    local best = S.plan(M)
    for _, r in ipairs({ "pilot", "oran", "zincir" }) do
      local p = S.plan(S.build(D[id], { mode = "full" }), nil, { rule = r })
      truthy(best.stats.total <= p.stats.total + 1e-6, id .. " " .. r)
    end
    local again = S.plan(S.build(D[id], { mode = "full" }))
    eq(table.concat(again.walk, ","), table.concat(best.walk, ","), id .. " belirlenimci")
  end
end)

test("boss koşusu: görevler yalnızca bosslar; geçilen düşmanlı koridorun temizliği süreye eklenir", function()
  local M = S.build(D.dm, { mode = "boss" })
  for _, id in ipairs(M.taskList) do eq(M.tasks[id].kind, "boss", id) end
  local p = S.plan(M)
  truthy(p.stats.clear > 0, "temizlik süresi")
  local full = S.plan(S.build(D.dm, { mode = "full" }))
  truthy(p.stats.total < full.stats.total, "boss koşusu tam temizlikten kısa")
end)

test("küçük graf: plan kesin çözümle aynı; ulaşılamayan görev bildirilir", function()
  local d = { id = "t", name = "Deneme", entrance = "e", names = {}, bend = 1,
    nodes = { { id = "e", name = "E", x = 0, y = 0 }, { id = "a", name = "A", x = 10, y = 0 },
              { id = "b", name = "B", x = 20, y = 0 }, { id = "c", name = "C", x = 10, y = 10 } },
    corridors = { { id = "1", a = "e", b = "a", packs = { { "X", 1 } } },
                  { id = "2", a = "a", b = "b", packs = { { "X", 1 } } },
                  { id = "3", a = "a", b = "c", packs = { { "X", 1 } } } },
    bosses = { { name = "Bo", at = "b", fight = 10 } } }
  local M = S.build(d, { mode = "full", speed = 1 })
  local p = S.plan(M)
  local exact = dofile(root .. "/benchmark/exact.lua")(ns)
  local opt = exact(M)
  eq(math.floor(p.stats.walk + 0.5), math.floor(opt + 0.5), "yürüme = optimum")
  eq(math.floor(opt + 0.5), 40, "optimum: e-a, a-c, c-a, a-b") -- 10+10+10+10
  -- C'ye giden koridor nadir bir bossun kapısının arkasında, nadirler kapalı: ulaşılamaz
  d.corridors[3].gate = "Nadir"
  d.bosses[2] = { name = "Nadir", at = "b", fight = 5, rare = true }
  M = S.build(d, { mode = "full", speed = 1 })
  p = S.plan(M)
  eq(#p.unreachable, 1, "ulaşılamayan sayısı")
  eq(p.unreachable[1], "c:3")
end)

-- Takip --------------------------------------------------------------------------------------
local guid = 0
local function nextGuid() guid = guid + 1; return "Creature-0-0-0-0-" .. guid end

-- Planı izleyerek bütün ölümleri sırayla bildirir.
local function followPlan(tr)
  local events = {}
  local safety = 0
  while not tr:finished() do
    safety = safety + 1
    assert(safety < 500, "takip ilerlemiyor")
    local obj = tr:objective()
    if not obj then tr:done()
    elseif obj.kind == "clear" then
      for name, n in pairs(obj.mobs) do
        for _ = 1, n do
          local ev = tr:onKill(name, nextGuid())
          if ev then events[#events + 1] = ev end
          if tr:objective() ~= obj then break end
        end
        if tr:objective() ~= obj then break end
      end
    elseif obj.kind == "boss" then
      events[#events + 1] = tr:onKill(obj.boss, nextGuid())
    else
      tr:done()
    end
  end
  return events
end

test("takip: planı izleyen ölümler bütün bacakları tamamlar, ilerleme %100 olur", function()
  for _, id in ipairs(D.order) do
    local M = S.build(D[id], { mode = "full", exit = true })
    local tr = Tracker.new(M)
    tr:replan()
    local ev = followPlan(tr)
    local done, total = tr:progress()
    eq(done, total, id .. " ilerleme")
    for _, e in ipairs(ev) do truthy(e ~= "offplan", id .. " plan dışı olay") end
    eq(tr:remainingTime(), 0, id .. " kalan süre")
  end
end)

test("takip: aynı GUID iki kez sayılmaz, başka koridorun düşmanı sayılmaz", function()
  local M = S.build(D.dm, { mode = "full" })
  local tr = Tracker.new(M)
  tr:replan()
  local obj = tr:objective()
  eq(obj.kind, "clear")
  local name = next(obj.mobs)
  local g = nextGuid()
  eq(tr:onKill(name, g), "kill")
  eq(tr:onKill(name, g), nil, "yinelenen GUID")
  eq(tr.kills, 1)
  eq(tr:onKill("Defias Squallshaper", nextGuid()), nil, "uzak koridorun düşmanı")
  eq(tr.kills, 1)
end)

test("takip: sıra dışı boss ölümü konumu düzeltir, yeni plan o bossu içermez", function()
  local M = S.build(D.wc, { mode = "boss" })
  local tr = Tracker.new(M)
  tr:replan()
  local near = false
  for j = 1, math.min(#tr.plan.legs, 1 + Tracker.LOOKAHEAD) do
    local o = tr.plan.legs[j].obj
    if o and o.boss == "Lord Pythas" then near = true end
  end
  truthy(not near, "deneme için Pythas planda uzak olmalı")
  eq(tr:onKill("Lord Pythas", nextGuid()), "offplan")
  eq(tr.state.node, "pythas")
  tr:replan()
  for _, l in ipairs(tr.plan.walk) do truthy(M.arcs[l].boss ~= "Lord Pythas", "Pythas yeniden planda") end
  eq(M.arcs[tr.plan.walk[1]].source, "pythas", "yeni plan Pythas'ın odasından başlar")
end)

test("takip: atla, konum düzelt, kaydet ve geri yükle", function()
  local M = S.build(D.rfc, { mode = "full" })
  local tr = Tracker.new(M)
  tr:replan()
  local first = tr:objective().task
  local skipped = tr:skip()
  eq(skipped, first)
  truthy(not M.tasks[first].required, "atlanan görev gereksiz")
  tr:done(); tr:done()
  local data = tr:serialize()
  local M2 = S.build(D.rfc, { mode = "full" })
  local tr2 = Tracker.restore(M2, data)
  eq(tr2.state.node, tr.state.node, "konum")
  local d1, t1 = tr:progress()
  local d2, t2 = tr2:progress()
  eq(d2, d1, "yapılan"); eq(t2, t1, "toplam")
  truthy(tr2:setNode("jergosh"), "oda")
  eq(M2.arcs[tr2.plan.walk[1]].source, "jergosh")
end)

-- Oyun içi kabuk, WoW API taklidiyle -----------------------------------------------------------
test("eklenti: zindana girince plan, ölümlerle ilerleme, komutlar, kayıtlı koşunun sürdürülmesi", function()
  local mock = dofile(root .. "/tests/wowmock.lua")
  mock.install()
  AtlasSweepDB = nil
  local ns2 = load(root, true)
  mock.fire("ADDON_LOADED", "AtlasSweep")
  truthy(AtlasSweepDB and AtlasSweepDB.mode == "full", "varsayılan ayarlar")
  mock.instance = { "The Deadmines", "party", 1, "Normal", 5, 0, false, 36 }
  mock.fire("PLAYER_ENTERING_WORLD")
  mock.runFrames()
  truthy(mock.chatHas("plan hazır"), "plan duyurusu: " .. mock.lastChat(2))
  local run = ns2.getRun()
  truthy(run and run.tracker.plan, "koşu")
  -- planlama sürerken gelen ölüm kaybolmaz: bekletilir, plan bitince işlenir
  mock.slash("at entrance") -- yeniden planlamayı başlatır
  truthy(run.planning, "planlama sürüyor")
  mock.kill("Defias Miner", nextGuid())
  eq(#run.pending, 1, "bekletilen ölüm")
  mock.runFrames()
  eq(#run.pending, 0, "bekletilen ölüm işlendi")
  eq(run.tracker.kills, 1, "bekletilen ölüm sayıldı")
  -- ilk koridorun düşmanları
  local obj = run.tracker:objective()
  for name, n in pairs(obj.mobs) do for _ = 1, n do mock.kill(name, nextGuid()) end end
  truthy(mock.chatHas("koridor temizlendi"), "temizlik duyurusu")
  eq(run.tracker.leg, 2, "ikinci bacak")
  -- Rhahk'Zor, ikinci koridorun sayacı dolmadan: aradaki bacak yapılmış sayılır
  mock.slash("next")
  local before = run.tracker.leg
  mock.kill("Rhahk'Zor", nextGuid())
  truthy(mock.chatHas("Rhahk'Zor|r öldü"), "boss duyurusu: " .. mock.lastChat(2))
  eq(run.tracker.leg, before + 2, "koridor + boss bacakları tamam")
  truthy(not run.planning, "yeniden planlama gerekmez")
  mock.slash("plan")
  mock.slash("done")
  mock.slash("at kereste")
  mock.runFrames()
  eq(run.tracker.state.node, "mill", "konum düzeltme")
  mock.slash("mode boss")
  mock.runFrames()
  eq(ns2.getRun().mode, "boss")
  truthy(ns2.getRun().tracker.state.dead["Rhahk'Zor"], "kip değişince ilerleme korunur")
  mock.slash("compare")
  truthy(mock.chatHas("Atlas.java kuralı"), "karşılaştırma")
  mock.slash("rooms"); mock.slash("list"); mock.slash("bilinmeyen")
  mock.slash("speed 300"); truthy(mock.chatHas("kullanım: /as speed"), "aralık denetimi")
  -- çık ve yeniden yükle: kayıtlı koşu sürdürülür
  mock.fire("PLAYER_LOGOUT")
  local saved = AtlasSweepDB.runs.dm
  truthy(saved and saved.data.dead[1], "kayıt")
  mock.frames, mock.chat = {}, {}
  local ns3 = load(root, true)
  mock.fire("ADDON_LOADED", "AtlasSweep")
  mock.fire("PLAYER_ENTERING_WORLD")
  mock.runFrames()
  truthy(mock.chatHas("sürdürülüyor"), "sürdürme: " .. mock.lastChat(3))
  truthy(ns3.getRun().tracker.state.dead["Rhahk'Zor"], "ölü boss hatırlanır")
  -- pencere metni: başlık, ilerleme ve sıradaki bacak
  ns3.UI.update(ns3.getRun())
  local texts = {}
  for _, f in ipairs(mock.frames) do texts[#texts + 1] = f._text end
  local all = table.concat(texts, "\n")
  truthy(all:find("AtlasSweep — The Deadmines", 1, true), "pencere başlığı")
  truthy(all:find("İlerleme %d+/%d+"), "pencere ilerleme satırı")
  truthy(all:find("> ", 1, true), "pencerede sıradaki bacak")
  mock.slash("reset")
  mock.runFrames()
  truthy(not ns3.getRun().tracker.state.dead["Rhahk'Zor"], "sıfırlama")
  -- zindan dışında aynı adlı düşmanlar sayılmaz
  mock.instance = { "Westfall", "none" }
  mock.fire("ZONE_CHANGED_NEW_AREA")
  local k0, leg0 = ns3.getRun().tracker.kills, ns3.getRun().tracker.leg
  mock.kill("Defias Miner", nextGuid()); mock.kill("Defias Miner", nextGuid()); mock.kill("Defias Miner", nextGuid())
  eq(ns3.getRun().tracker.kills, k0, "zindan dışı ölüm"); eq(ns3.getRun().tracker.leg, leg0, "zindan dışı bacak")
end)

-- Lua 5.1 uyumu (WoW) ----------------------------------------------------------------------------
test("eklenti dosyaları Lua 5.1'de olmayan sözdizimi ve kütüphane kullanmaz", function()
  local toc = read(root .. "/AtlasSweep/AtlasSweep.toc")
  for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^%s*#") and line:match("%S") then
      local rel = line:gsub("\\", "/"):gsub("%s+$", "")
      local src = read(root .. "/AtlasSweep/" .. rel)
      -- yorumları ve dizgileri çıkar
      local code = src:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
      code = code:gsub('"[^"\n]*"', '""'):gsub("'[^'\n]*'", "''")
      for _, pat in ipairs({ "%f[%w]goto%f[%W]", "//", "&", "<<", ">>", "%f[%w]utf8%.", "table%.unpack",
                             "math%.type", "string%.pack", "table%.move", "%f[%w]_ENV%f[%W]" }) do
        truthy(not code:find(pat), rel .. " içinde Lua 5.1 dışı: " .. pat)
      end
      -- tek başına ~ (xor/not) ama ~= değil
      truthy(not code:find("~[^=]"), rel .. " içinde ~ işleci")
    end
  end
end)

print(("\n%d geçti, %d hata"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
