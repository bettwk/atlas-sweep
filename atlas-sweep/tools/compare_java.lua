-- Lua çevirisi ile Atlas'ın özgün Java kodunu aynı .fsm dosyalarında çalıştırıp çıktıları karşılaştırır.
-- Kullanım: lua tools/compare_java.lua <java-sınıf-klasörü> a.fsm [b.fsm ...]
-- --save verilirse Java çıktısı dosya.java.txt olarak yanına yazılır (testler bunları kullanır).
local root = arg[0]:match("^(.*)/tools/") or "."
local ns = dofile(root .. "/tools/load.lua")(root)
local classes, save = arg[1], false
local same, diff, inexact = 0, 0, 0
for i = 2, #arg do
  local f = arg[i]
  if f == "--save" then save = true else
    local g = ns.Graph.parseFSM(assert(io.open(f)):read("*a"))
    local suite = ns.Atlas.run(g)
    if not g.exactJavaOrder then inexact = inexact + 1 end
    local p = io.popen("java -Xss64m -cp '" .. classes .. "' AtlasCli '" .. f .. "' 2>/dev/null")
    local java = p:read("*a"):gsub("%s+$", "")
    p:close()
    if save then
      local o = assert(io.open((f:gsub("%.fsm$", "") .. ".java.txt"), "w")); o:write(java, "\n"); o:close()
    end
    if java == suite then same = same + 1 else
      diff = diff + 1
      print("FARKLI " .. f)
      print("  java: " .. java:sub(1, 160))
      print("  lua : " .. suite:sub(1, 160))
    end
  end
end
print(("aynı: %d  farklı: %d  (Java sırası tam taklit edilemeyen: %d)"):format(same, diff, inexact))
os.exit(diff == 0 and 0 or 1)
