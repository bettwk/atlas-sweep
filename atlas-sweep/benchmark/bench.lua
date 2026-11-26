-- Ölçüm: Atlas kuralları ve kesin çözüm, tam temizlik kipinde. Eklentinin parçası değildir.
-- Kullanım: lua benchmark/bench.lua [deneme sayısı=40]
-- Ölçülen: kaçınılabilir süre (yürüme) — temizlik ve boss süreleri her planda aynıdır.
local root = arg[0]:match("^(.*)/benchmark/") or "."
local ns = dofile(root .. "/tools/load.lua")(root)
local S, D = ns.Sweep, ns.Dungeons
local exact = dofile(root .. "/benchmark/exact.lua")(ns)
local trials = tonumber(arg[1]) or 40

local function overhead(M, p)
  local st = S.copyState(S.newState(M))
  local c = 0
  for _, l in ipairs(p.walk) do
    local a = M.arcs[l]
    c = c + S.planCost(M, a, st)
    -- apply: Sweep.steps ile aynı etkiler
    if a.task then st.covered[a.task] = true end
    if a.kind == "move" then st.cleared[a.corridor] = true end
    if a.kind == "boss" then st.dead[a.boss] = true end
    st.node = a.dest
  end
  return c
end

local RULES = {
  { key = "unit",   label = "Atlas.java kuralı", opts = { unit = true } },
  { key = "chain",  label = "zincir",            opts = { rule = "zincir" } },
  { key = "ratio",  label = "oran",              opts = { rule = "oran" } },
  { key = "pilot",  label = "pilot",             opts = { rule = "pilot" } },
  { key = "best",   label = "eklenti (en iyi)",  opts = {} },
}

local function runAll(M)
  local r = {}
  for _, R in ipairs(RULES) do
    local t0 = os.clock()
    local p = S.plan(M, nil, R.opts)
    r[R.key] = { cost = overhead(M, p), miss = #p.unreachable, ms = (os.clock() - t0) * 1000 }
  end
  local t0 = os.clock()
  local opt, states = exact(M)
  r.exact = { cost = opt, states = states, ms = (os.clock() - t0) * 1000 }
  return r
end

-- Gerçek zindanlar -----------------------------------------------------------------------------
print("Gerçek zindanlar (şematik veri), tam temizlik; yürüme süresi (sn), parantezde / optimum")
print(("%-26s %8s %8s %8s %8s %8s %8s"):format("", "Java", "zincir", "oran", "pilot", "eklenti", "optimum"))
for _, id in ipairs(D.order) do
  for _, extra in ipairs({ {}, { rares = true, exit = true } }) do
    local o = { mode = "full", rares = extra.rares, exit = extra.exit }
    local M = S.build(D[id], o)
    local r = runAll(M)
    local name = D[id].name .. (extra.exit and " +nadir+çıkış" or "")
    local function cell(x)
      if not r.exact.cost then return ("%8.0f"):format(x.cost) end
      return ("%5.0f(%.2f)"):format(x.cost, x.cost / r.exact.cost)
    end
    print(("%-26s %s %s %s %s %s %8s"):format(name, cell(r.unit), cell(r.chain), cell(r.ratio),
      cell(r.pilot), cell(r.best), r.exact.cost and ("%.0f"):format(r.exact.cost) or "çok büyük"))
  end
end

-- Rastgele zindanlar ---------------------------------------------------------------------------
local x = 20261122
local function rnd(n) x = (x * 1103515245 + 12345) % 2147483648; return math.floor(x / 65536) % n end

local function randomDungeon(seed)
  x = seed
  local n = 8 + rnd(4)
  local nodes, corridors, bosses = {}, {}, {}
  for i = 1, n do nodes[i] = { id = "n" .. i, name = "Oda " .. i, x = rnd(300), y = rnd(300) } end
  nodes[1].x, nodes[1].y = 0, 0
  local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
  local parent, depth = {}, { [1] = 0 }
  local cid = 0
  local function addCorr(a, b)
    cid = cid + 1
    local packs = rnd(4) > 0 and { { "Mob", 1 + rnd(4) } } or nil
    corridors[#corridors + 1] = { id = "k" .. cid, a = nodes[a].id, b = nodes[b].id, packs = packs }
    return corridors[#corridors]
  end
  local treeEdge = {}
  for i = 2, n do -- en yakın önceki düğüme bağla (ağaç)
    local best, bd = 1, math.huge
    for j = 1, i - 1 do local dd = dist(nodes[i], nodes[j]); if dd < bd then best, bd = j, dd end end
    parent[i], depth[i] = best, depth[best] + 1
    treeEdge[i] = addCorr(best, i)
  end
  for _ = 1, 1 + rnd(3) do -- birkaç halka
    local a, b = 1 + rnd(n), 1 + rnd(n)
    if a ~= b and parent[a] ~= b and parent[b] ~= a then addCorr(a, b) end
  end
  local used = {}
  for k = 1, 3 + rnd(2) do
    local at = 2 + rnd(n - 1)
    if not used[at] then
      used[at] = true
      bosses[#bosses + 1] = { name = "Boss" .. k, at = nodes[at].id, fight = 30 + rnd(40) }
    end
  end
  -- bir kapı: ilk bossun odasından derine giden ağaç kenarı
  local b1 = bosses[1]
  for i = 2, n do
    if nodes[parent[i]].id == b1.at then treeEdge[i].gate = b1.name; break end
  end
  return { id = "rnd" .. seed, name = "Rastgele", entrance = "n1", bend = 1.2,
           nodes = nodes, corridors = corridors, bosses = bosses, names = {} }
end

local sums, worst, count, skipped = {}, {}, 0, 0
local keys = { "unit", "chain", "ratio", "pilot", "best" }
for _, k in ipairs(keys) do sums[k] = 0; worst[k] = 0 end
local hits = 0
for t = 1, trials do
  local d = randomDungeon(1000 + t)
  local M = S.build(d, { mode = "full" })
  local r = runAll(M)
  if r.exact.cost and r.exact.cost > 0 and r.best.miss == 0 then
    count = count + 1
    for _, k in ipairs(keys) do
      local q = r[k].cost / r.exact.cost
      sums[k] = sums[k] + q
      if q > worst[k] then worst[k] = q end
    end
    if math.abs(r.best.cost - r.exact.cost) < 1e-6 then hits = hits + 1 end
  else
    skipped = skipped + 1
  end
end
print(("\nRastgele zindanlar (8–11 oda, halkalı, kapılı), %d deneme, yürüme / optimum:"):format(count))
for _, k in ipairs(keys) do
  local label
  for _, R in ipairs(RULES) do if R.key == k then label = R.label end end
  print(("  %-18s ortalama %.3f   en kötü %.3f"):format(label, sums[k] / count, worst[k]))
end
print(("  eklenti optimumu bulduğu deneme: %d / %d%s"):format(hits, count,
  skipped > 0 and ("  (" .. skipped .. " deneme atlandı)") or ""))
