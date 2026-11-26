-- Kenar etiketli yönlü graf: Atlas.java'nın Graph/Edge yapısının Lua karşılığı.
-- Ayrıca Atlas'ın okuduğu KISS2 benzeri ".fsm" satırlarının okuyucusu:
--     durum -- girdi / çıktı -> sonraki_durum
--
-- Atlas'ın sonucu, bir düğümün çıkan kenarlarının hangi sırayla gezildiğine bağlıdır.
-- Java'da bu küme HashSet<Integer>'dır ve sırası ekleme sırası değil, kova sırasıdır:
--   kova = hash(etiket) mod kapasite   (hash = h xor (h >>> 16), kapasite 16'dan başlar,
--   eleman sayısı kapasitenin 0,75'ini geçince iki katına çıkar; kova içinde ekleme sırası).
-- javaOrder() bu sırayı üretir; böylece Lua çevirisi Java ile kenar kenar karşılaştırılabilir.
-- (Bir kovada 8'den çok eleman olursa Java kovayı ağaca çevirir ya da tabloyu büyütür; bu
-- durumda sıra tam taklit edilemez, graph.exactJavaOrder = false olur. Test graflarında olmaz.)
local _, ns = ...

local Graph = {}
Graph.__index = Graph

function Graph.new()
  return setmetatable({ edges = {}, out = {}, m = 0, starts = {}, exactJavaOrder = true }, Graph)
end

-- Etiketler Java'daki gibi 0'dan başlar. Kaynağı 0 olan kenarlar başlangıç kenarıdır
-- (Util.toGraph: "if (state_ == 0) graph.addStart(label)").
function Graph:addEdge(source, dest, input, output, weight)
  local label = self.m
  self.m = label + 1
  self.edges[label] = { label = label, source = source, dest = dest,
                        input = input, output = output, weight = weight or 1 }
  if not self.out[source] then self.out[source] = {} end
  if not self.out[dest] then self.out[dest] = {} end
  local list = self.out[source]
  list[#list + 1] = label
  if source == 0 then self.starts[#self.starts + 1] = label end
  self._order = nil
  return label
end

-- Bit kütüphanesi olmadan (WoW Lua 5.1 ve Lua 5.4'te aynı çalışsın diye) xor.
local function xor(a, b)
  local r, bitv = 0, 1
  while a > 0 or b > 0 do
    local x, y = a % 2, b % 2
    if x ~= y then r = r + bitv end
    a = (a - x) / 2; b = (b - y) / 2; bitv = bitv * 2
  end
  return r
end

local function javaHash(h)
  if h < 65536 then return h end -- h >>> 16 = 0
  return xor(h, math.floor(h / 65536))
end

local function javaCapacity(n)
  local cap = 16
  while n > cap * 0.75 do cap = cap * 2 end
  return cap
end

-- Etiket listesini java.util.HashSet<Integer> dolaşma sırasına dizer.
-- Etiketler artan sırayla eklendiği için kova içi sıra = etiket sırası.
function Graph:javaOrder(list)
  local cap = javaCapacity(#list)
  local sorted, count = {}, {}
  for i = 1, #list do
    sorted[i] = list[i]
    local b = javaHash(list[i]) % cap
    count[b] = (count[b] or 0) + 1
    if count[b] > 8 then self.exactJavaOrder = false end
  end
  table.sort(sorted, function(a, b)
    local ba, bb = javaHash(a) % cap, javaHash(b) % cap
    if ba ~= bb then return ba < bb end
    return a < b
  end)
  return sorted
end

-- Graph.edgeLabels(node) karşılığı, Java sırasıyla (önbellekli).
function Graph:outEdges(node)
  if not self._order then self._order = {} end
  local o = self._order[node]
  if not o then
    o = self:javaOrder(self.out[node] or {})
    self._order[node] = o
  end
  return o
end

-- graph.getStarts().iterator().next()
function Graph:firstStart()
  return self:javaOrder(self.starts)[1]
end

function Graph.parseFSM(text)
  local g = Graph.new()
  for line in text:gmatch("[^\r\n]+") do
    local s, i, o, d = line:match("^(%d+)%s%-%-%s(%d+)%s/%s(%d+)%s%->%s(%d+)")
    if s then g:addEdge(tonumber(s), tonumber(d), tonumber(i), tonumber(o), 1) end
  end
  return g
end

ns.Graph = Graph
