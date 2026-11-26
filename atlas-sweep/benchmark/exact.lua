-- Ölçüt için kesin çözüm (eklentinin parçası değildir): durum = (oda, kapsanan görevler kümesi),
-- Dijkstra ile en küçük toplam planlama maliyeti. Yalnızca tam temizlik kipi içindir; orada
-- gerekli koridorların temizliği ve boss dövüşleri sabittir, maliyet = yürüme (+ gerekli olmayan
-- düşmanlı koridorların temizliği). Durum sayısı 2^görev × oda kadar büyüyebildiği için
-- küçük zindanlarda kullanılır (limit aşılırsa nil döner).
-- Bit işlemleri aritmetikle yapılır; LuaJIT ve Lua 5.4'te aynı çalışır.
return function(ns)
  local S = ns.Sweep

  local function exact(M, limit)
    limit = limit or 3000000
    local tasks, bit = {}, {}
    for _, id in ipairs(M.taskList) do
      if M.tasks[id].required then
        tasks[#tasks + 1] = id
        bit[id] = 2 ^ (#tasks - 1)
      end
    end
    local full = 2 ^ #tasks - 1
    local function has(mask, b) return (mask % (2 * b)) >= b end

    -- Durumun "dead/cleared/covered" görünümü: maskeden kurulur.
    local function stateOf(node, mask)
      local st = { node = node, covered = {}, cleared = {}, dead = {}, unreachable = {} }
      for _, id in ipairs(tasks) do
        if has(mask, bit[id]) then
          st.covered[id] = true
          local t = M.tasks[id]
          if t.kind == "boss" then st.dead[t.boss] = true end
          if t.kind == "corridor" then st.cleared[t.corridor] = true end
        end
      end
      return st
    end

    -- İkili yığın
    local heap, hn = {}, 0
    local function push(d, k)
      hn = hn + 1; heap[hn] = { d, k }
      local i = hn
      while i > 1 do
        local p = math.floor(i / 2)
        if heap[p][1] <= heap[i][1] then break end
        heap[p], heap[i] = heap[i], heap[p]; i = p
      end
    end
    local function pop()
      local top = heap[1]
      heap[1] = heap[hn]; heap[hn] = nil; hn = hn - 1
      local i = 1
      while true do
        local l, r, s = 2 * i, 2 * i + 1, i
        if l <= hn and heap[l][1] < heap[s][1] then s = l end
        if r <= hn and heap[r][1] < heap[s][1] then s = r end
        if s == i then break end
        heap[s], heap[i] = heap[i], heap[s]; i = s
      end
      return top
    end

    local nodeIndex, nodes = {}, {}
    for i, n in ipairs(M.nodeList) do nodeIndex[n.id] = i - 1; nodes[i - 1] = n.id end
    local NN = #M.nodeList
    local function key(node, mask) return mask * NN + nodeIndex[node] end

    local dist, count = {}, 0
    local k0 = key(M.d.entrance, 0)
    dist[k0] = 0
    push(0, k0)
    while hn > 0 do
      local top = pop()
      local d, k = top[1], top[2]
      if dist[k] == d then
        local mask = math.floor(k / NN)
        local node = nodes[k % NN]
        if mask == full then return d, count end
        count = count + 1
        if count > limit then return nil, count end
        local st = stateOf(node, mask)
        for _, l in ipairs(M.out[node]) do
          local a = M.arcs[l]
          if S.available(M, a, st) then
            local c = S.planCost(M, a, st)
            local nm = mask
            if a.task and bit[a.task] and not has(mask, bit[a.task]) and S.prereqsMet(M, M.tasks[a.task], st) then
              nm = mask + bit[a.task]
            end
            if nm ~= mask or a.kind == "move" then
              local nk = key(a.dest, nm)
              local nd = d + c
              if dist[nk] == nil or nd < dist[nk] - 1e-9 then
                dist[nk] = nd
                push(nd, nk)
              end
            end
          end
        end
      end
    end
    return nil, count -- ulaşılamaz
  end

  return exact
end
