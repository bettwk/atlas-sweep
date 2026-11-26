-- Zindan grafını ve planı SVG olarak çizer (rapor için).
-- Kullanım: lua tools/draw.lua <rfc|wc|dm> [boss] [rares] [exit] [unit] > rota.svg
-- Koridor üzerindeki sayılar, planın o koridordan kaçıncı bacakta geçtiğidir.
local root = arg[0]:match("^(.*)/tools/") or "."
local ns = dofile(root .. "/tools/load.lua")(root)
local S, D = ns.Sweep, ns.Dungeons

local d = D.find(nil, arg[1] or "dm")
assert(d, "zindan bulunamadı")
local opts, unit = { mode = "full" }, false
for i = 2, #arg do
  if arg[i] == "boss" then opts.mode = "boss" elseif arg[i] == "rares" then opts.rares = true
  elseif arg[i] == "exit" then opts.exit = true elseif arg[i] == "unit" then unit = true end
end
local M = S.build(d, opts)
local p = S.plan(M, nil, { unit = unit })

local minx, miny, maxx, maxy = math.huge, math.huge, -math.huge, -math.huge
for _, n in ipairs(d.nodes) do
  minx, miny = math.min(minx, n.x), math.min(miny, n.y)
  maxx, maxy = math.max(maxx, n.x), math.max(maxy, n.y)
end
local PAD, SC = 70, 1.6
local W, H = (maxx - minx) * SC + 2 * PAD + 150, (maxy - miny) * SC + 2 * PAD + 70
local function X(v) return (v - minx) * SC + PAD end
local function Y(v) return (v - miny) * SC + PAD + 40 end
local function esc(s) return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end

-- hangi bacakta hangi koridordan geçildi
local passes = {}
for i, leg in ipairs(p.legs) do
  local steps = {}
  for _, w in ipairs(leg.walks) do steps[#steps + 1] = w end
  if leg.obj then steps[#steps + 1] = leg.obj end
  for _, s in ipairs(steps) do
    if s.corridor then
      passes[s.corridor] = passes[s.corridor] or {}
      table.insert(passes[s.corridor], i)
    end
  end
end
local bossLeg = {}
for i, leg in ipairs(p.legs) do if leg.obj and leg.obj.boss then bossLeg[leg.obj.boss] = i end end

local o = {}
local function w(s) o[#o + 1] = s end
w(('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" font-family="Georgia, serif">')
  :format(W, H, W, H))
w('<defs><marker id="ar" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="#5b4a3a"/></marker></defs>')
w(('<rect width="%d" height="%d" fill="#f4ecd8"/>'):format(W, H))
local st = p.stats
w(('<text x="%d" y="30" font-size="20" fill="#3a2c1e">%s — %s%s</text>'):format(PAD, esc(d.name),
  opts.mode == "full" and "tam temizlik" or "boss koşusu", unit and " (Atlas.java kuralı)" or ""))
w(('<text x="%d" y="52" font-size="13" fill="#5b4a3a">%d bacak · toplam %s · yürüme %s · temizlik %s · boss %s</text>')
  :format(PAD, #p.legs, S.fmtTime(st.total), S.fmtTime(st.walk), S.fmtTime(st.clear), S.fmtTime(st.fight)))

for _, c in ipairs(d.corridors) do
  local A, B = M.nodes[c.a], M.nodes[c.b]
  local cor = M.corridors[c.id]
  local col = cor.expect > 0 and "#a33b2b" or "#8a7a66"
  local dash = c.gate and ' stroke-dasharray="7,5"' or ""
  local mk = c.oneway and ' marker-end="url(#ar)"' or ""
  w(('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="%d"%s%s stroke-linecap="round"/>')
    :format(X(A.x), Y(A.y), X(B.x), Y(B.y), col, cor.expect > 0 and 4 or 2, dash, mk))
  local mx, my = (X(A.x) + X(B.x)) / 2, (Y(A.y) + Y(B.y)) / 2
  local label = passes[c.id] and table.concat(passes[c.id], ",") or "—"
  w(('<rect x="%.1f" y="%.1f" width="%d" height="16" rx="8" fill="#fffaf0" stroke="%s"/>')
    :format(mx - (#label * 4 + 6), my - 8, #label * 8 + 12, col))
  w(('<text x="%.1f" y="%.1f" font-size="11" text-anchor="middle" fill="#3a2c1e">%s</text>'):format(mx, my + 4, label))
end

for _, n in ipairs(d.nodes) do
  local entrance = n.id == d.entrance
  w(('<circle cx="%.1f" cy="%.1f" r="%d" fill="%s" stroke="#3a2c1e" stroke-width="1.5"/>')
    :format(X(n.x), Y(n.y), entrance and 9 or 6, entrance and "#d9b44a" or "#fffaf0"))
  w(('<text x="%.1f" y="%.1f" font-size="12" fill="#3a2c1e">%s</text>'):format(X(n.x) + 10, Y(n.y) - 8, esc(n.name)))
end

local stack = {}
for _, b in ipairs(d.bosses) do
  local n = M.nodes[b.at]
  stack[b.at] = (stack[b.at] or 0) + 1
  local yy = Y(n.y) + 8 + stack[b.at] * 14
  local leg = bossLeg[b.name]
  local col = b.rare and "#7a5aa0" or "#a33b2b"
  w(('<text x="%.1f" y="%.1f" font-size="11" fill="%s">◆ %s%s</text>'):format(X(n.x) + 10, yy, col,
    esc(b.name), leg and (" · " .. leg) or (b.rare and " · nadir, planda yok" or "")))
end

w(('<text x="%d" y="%d" font-size="11" fill="#5b4a3a">kırmızı: düşmanlı koridor · kesikli: kapı (boss ölünce açılır) · ok: tek yön · sayılar: bacak sırası · ◆ boss</text>')
  :format(PAD, H - 16))
w("</svg>")
io.write(table.concat(o, "\n"), "\n")
