-- Komut satırı demosu: bir zindanın planını yazdırır.
-- Kullanım: lua tools/plan.lua <rfc|wc|dm> [boss] [rares] [exit] [unit] [speed=7] [mob=10]
local root = arg[0]:match("^(.*)/tools/") or "."
local ns = dofile(root .. "/tools/load.lua")(root)
local S, D = ns.Sweep, ns.Dungeons

local d = D.find(nil, arg[1] or "dm")
assert(d, "zindan bulunamadı: " .. tostring(arg[1]) .. " (rfc, wc, dm)")
local opts = { mode = "full" }
local unit = false
for i = 2, #arg do
  local a = arg[i]
  if a == "boss" then opts.mode = "boss"
  elseif a == "rares" then opts.rares = true
  elseif a == "exit" then opts.exit = true
  elseif a == "unit" then unit = true
  elseif a:match("^speed=") then opts.speed = tonumber(a:sub(7))
  elseif a:match("^mob=") then opts.perMob = tonumber(a:sub(5)) end
end

local M = S.build(d, opts)
local t0 = os.clock()
local p = S.plan(M, nil, { unit = unit })
local ms = (os.clock() - t0) * 1000

print(("%s — %s%s%s%s"):format(d.name, opts.mode == "full" and "tam temizlik" or "boss koşusu",
  opts.rares and ", nadirler" or "", opts.exit and ", girişe dönüş" or "",
  unit and ", Atlas.java kuralı (birim ağırlık)" or ""))
for i, leg in ipairs(p.legs) do
  print(("%2d. %-9s %s"):format(i, S.fmtTime(leg.time), S.legText(M, leg)))
end
local st, lb = p.stats, p.lower
print(("\ntoplam %s = yürüme %s + temizlik %s + boss %s   (kural: %s, %d yay, %.0f ms)"):format(
  S.fmtTime(st.total), S.fmtTime(st.walk), S.fmtTime(st.clear), S.fmtTime(st.fight),
  ({ ratio = "oran", chain = "zincir", pilot = "pilot" })[p.rule], st.arcs, ms))
if opts.mode == "full" then
  print(("alt sınır %s; yürüme / gerekli koridorların yürüme süresi = %.3f"):format(
    S.fmtTime(lb.total), st.walk / lb.walk))
end
if #p.unreachable > 0 then print("ulaşılamayan: " .. table.concat(p.unreachable, ", ")) end
