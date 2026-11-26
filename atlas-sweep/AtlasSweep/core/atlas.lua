-- Atlas (Savaş Takan, github.com/savastakan/atlas) — Atlas.java'nın birebir Lua çevirisi.
--
-- Atlas bir grafın bütün kenarlarını tek bir yürüyüşle, az tekrarla dolaşmaya çalışır.
-- Yürüyüşün son kenarından başlayarak her turda:
--   1. erişilebilen kenarları DFS ardıl-sırasıyla (post-order) bir yığına koyar,
--   2. yığını ters sırayla açarak en uzun yol dinamik programlaması yapar: bir kenar
--      yürüyüşte yoksa 1, varsa 0 değerindedir,
--   3. en yüksek puanlı zinciri yürüyüşe ekler.
-- Hiçbir zincir yeni kenar getirmeyince durur. Kenar ağırlıkları kullanılmaz.
--
-- Java ile aynı çıktıyı vermek için:
--   * komşular Java HashSet sırasıyla gezilir (graph.lua),
--   * "erişildi" işareti Integer.MIN_VALUE'dur ve aritmetiği Java'daki gibidir,
--   * DFS özyinelemeli değil yığınlıdır (sonuç aynı; WoW'da derin özyineleme riskli),
--   * path.contains() bir sayaçla yapılır (sonuç aynı, daha hızlı).
-- Java'da hiçbir kenar gevşetilemezse cost[Integer.MIN_VALUE] okunur ve kod çöker; burada o
-- durumda yürüyüş biter. Java son turda yürüyüşün son kenarını çıkarıp öyle döner; bu davranış
-- korunmuştur, keepLast = true verilirse o kenar geri eklenir.
local _, ns = ...

local Atlas = {}
local MIN = -2147483648 -- Integer.MIN_VALUE

-- Atlas.dfs(): kenar üzerinden ardıl-sıralı DFS. Erişilen kenarlar cost[] içinde MIN olur.
local function dfs(g, start, cost)
  local stack = {}
  cost[start] = MIN
  local frames = { { e = start, i = 0, nbrs = g:outEdges(g.edges[start].dest) } }
  while #frames > 0 do
    local f = frames[#frames]
    local pushed = false
    while f.i < #f.nbrs do
      f.i = f.i + 1
      local n = f.nbrs[f.i]
      if cost[n] ~= MIN then
        cost[n] = MIN
        frames[#frames + 1] = { e = n, i = 0, nbrs = g:outEdges(g.edges[n].dest) }
        pushed = true
        break
      end
    end
    if not pushed then
      stack[#stack + 1] = f.e
      frames[#frames] = nil
    end
  end
  return stack
end

-- Atlas.longestPath(): yürüyüşü kenar etiketleri listesi olarak döner.
function Atlas.longestPath(g, start, keepLast)
  local path = { start }
  local onPath = { [start] = 1 }
  while true do
    local currentStart = path[#path] -- path.removeLast()
    path[#path] = nil
    onPath[currentStart] = onPath[currentStart] - 1

    local cost = {}
    for l = 0, g.m - 1 do cost[l] = 0 end
    local stack = dfs(g, currentStart, cost)
    local comeFrom = {}
    for l = 0, g.m - 1 do comeFrom[l] = cost[l] end -- cost.clone()
    cost[currentStart] = 0

    local visited = {}
    local currentCost, current = MIN, nil
    for s = #stack, 1, -1 do -- stack.pop()
      local e = stack[s]
      visited[e] = true
      local nbrs = g:outEdges(g.edges[e].dest)
      for k = 1, #nbrs do
        local n = nbrs[k]
        if not visited[n] then
          local newCost = cost[e] + (((onPath[n] or 0) > 0) and 0 or 1)
          if cost[n] < newCost then
            cost[n] = newCost
            comeFrom[n] = e
            if currentCost < cost[n] then
              currentCost = cost[n]
              current = n
            end
          end
        end
      end
    end

    if current == nil or cost[current] <= 0 then
      if keepLast then
        path[#path + 1] = currentStart
        onPath[currentStart] = onPath[currentStart] + 1
      end
      return path
    end

    -- path.add(current); sonra comeFrom geriye izlenip her kenar araya eklenir.
    local chain = { current }
    while comeFrom[current] >= 0 do
      current = comeFrom[current]
      chain[#chain + 1] = current
    end
    for i = #chain, 1, -1 do
      local e = chain[i]
      path[#path + 1] = e
      onPath[e] = (onPath[e] or 0) + 1
    end
  end
end

-- Atlas.getTestSuite(): yürüyüş boyunca girdilerin virgülle ayrılmış dizisi.
function Atlas.testSuite(g, path)
  local parts = {}
  for i, e in ipairs(path) do parts[i] = tostring(g.edges[e].input) end
  return table.concat(parts, ",")
end

-- Atlas.run()
function Atlas.run(g, keepLast)
  local path = Atlas.longestPath(g, g:firstStart(), keepLast)
  return Atlas.testSuite(g, path), path
end

-- Yürüyüşün kaç farklı kenarı kapsadığı.
function Atlas.coverage(g, path)
  local seen, n = {}, 0
  for _, e in ipairs(path) do
    if not seen[e] then seen[e] = true; n = n + 1 end
  end
  return n, g.m
end

ns.Atlas = Atlas
