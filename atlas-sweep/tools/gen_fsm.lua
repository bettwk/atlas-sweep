-- Rastgele, tam tanımlı FSM üretir (her durumda her girdi için bir geçiş), KISS2 benzeri biçimde.
-- Atlas'ın Util.createFSMFile'ı tools/fsm-gen-fsm aracını çağırır; o araç depoda olmadığı için
-- bunun yerine yazıldı. "strong" verilirse her durum 0'dan erişilebilir olacak şekilde bir halka eklenir.
-- Kullanım: lua tools/gen_fsm.lua <durum> <girdi> <çıktı> <tohum> [strong] > dosya.fsm
local states, inputs, outputs, seed = tonumber(arg[1]), tonumber(arg[2]), tonumber(arg[3]), tonumber(arg[4])
local strong = arg[5] == "strong"
assert(states and inputs and outputs and seed, "kullanım: gen_fsm.lua <durum> <girdi> <çıktı> <tohum> [strong]")

-- Lua sürümünden bağımsız, tekrarlanabilir rastgele sayı (doğrusal eşlik üreteci).
local x = seed
local function rnd(n)
  x = (x * 1103515245 + 12345) % 2147483648
  return math.floor(x / 65536) % n
end

for s = 0, states - 1 do
  for i = 0, inputs - 1 do
    local d = rnd(states)
    if strong and i == 0 then d = (s + 1) % states end
    io.write(("%d -- %d / %d -> %d\n"):format(s, i, rnd(outputs), d))
  end
end
