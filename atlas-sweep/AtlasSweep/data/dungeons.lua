-- Zindan grafları (şematik). Düğümler oda/kavşaktır; x, y yaklaşık yarda cinsindendir ve
-- koridor uzunluğu verilmezse iki uç arasındaki uzaklık × bend olarak hesaplanır.
-- Koridor alanları:
--   packs  { {"Düşman adı", adet}, ... }   (oyundaki İngilizce ad: ölüm takibi buna bakar)
--   gate   bu boss ölmeden geçilemez (kapı)
--   oneway yalnızca a'dan b'ye (aşağı atlama)
-- Boss alanları: at (oda), fight (tahmini dövüş süresi, sn), rare (nadir, isteğe bağlı),
--   requires (önce ölmesi gereken bosslar).
--
-- UYARI: Yerleşim, düşman sayıları ve süreler oyun dosyalarından okunmadı. Bilinen boss
-- odaları ve sırası esas alınarak elle, yaklaşık kuruldu; oyunda ya da haritalarla
-- doğrulanmalıdır. Algoritma bu sayılara bağlı değildir, yalnızca örnek sonuçlar bağlıdır.
local _, ns = ...

local D = {}

D.rfc = {
  id = "rfc", name = "Ragefire Chasm", instanceID = 389, levels = "13-18", faction = "Horde",
  names = { "Ragefire Chasm" },
  entrance = "entrance", bend = 1.2,
  nodes = {
    { id = "entrance",   name = "Giriş",               x = 0,   y = 0 },
    { id = "ramp",       name = "İniş tüneli",         x = 30,  y = 50 },
    { id = "trogg_camp", name = "Trogg kampı",         x = 60,  y = 100 },
    { id = "pools",      name = "Lav gölleri",         x = 40,  y = 170 },
    { id = "lava_hall",  name = "Büyük lav mağarası",  x = 130, y = 140 },
    { id = "cult_ramp",  name = "Tarikat yokuşu",      x = 200, y = 100 },
    { id = "jergosh",    name = "Jergosh'un odası",    x = 250, y = 50 },
    { id = "bazzalan",   name = "Bazzalan'ın odası",   x = 290, y = 120 },
    { id = "taragaman",  name = "Taragaman'ın odası",  x = 210, y = 200 },
  },
  corridors = {
    { id = "r1",  a = "entrance",   b = "ramp",       packs = { { "Ragefire Trogg", 2 } } },
    { id = "r2",  a = "ramp",       b = "trogg_camp", packs = { { "Ragefire Trogg", 3 }, { "Ragefire Shaman", 1 } } },
    { id = "r3",  a = "trogg_camp", b = "lava_hall",  packs = { { "Earthborer", 2 }, { "Molten Elemental", 1 } } },
    { id = "r4",  a = "trogg_camp", b = "pools",      packs = { { "Ragefire Trogg", 2 }, { "Ragefire Shaman", 2 } } },
    { id = "r5",  a = "pools",      b = "lava_hall",  packs = { { "Molten Elemental", 3 } } },
    { id = "r6",  a = "lava_hall",  b = "cult_ramp",  packs = { { "Searing Blade Cultist", 3 } } },
    { id = "r7",  a = "cult_ramp",  b = "jergosh",    packs = { { "Searing Blade Warlock", 2 }, { "Searing Blade Cultist", 2 } } },
    { id = "r8",  a = "jergosh",    b = "bazzalan",   packs = { { "Searing Blade Enforcer", 2 } } },
    { id = "r9",  a = "cult_ramp",  b = "bazzalan",   packs = { { "Searing Blade Enforcer", 1 }, { "Searing Blade Cultist", 2 } } },
    { id = "r10", a = "lava_hall",  b = "taragaman",  packs = { { "Searing Blade Cultist", 2 }, { "Searing Blade Enforcer", 2 } } },
  },
  bosses = {
    { name = "Oggleflint",            at = "trogg_camp", fight = 40 },
    { name = "Taragaman the Hungerer", at = "taragaman", fight = 70 },
    { name = "Jergosh the Invoker",   at = "jergosh",    fight = 60 },
    { name = "Bazzalan",              at = "bazzalan",   fight = 50 },
  },
}

D.wc = {
  id = "wc", name = "Wailing Caverns", instanceID = 43, levels = "15-25",
  names = { "Wailing Caverns" },
  entrance = "entrance", bend = 1.25,
  nodes = {
    { id = "entrance",       name = "Giriş (Disciple of Naralex)", x = 0,   y = 0 },
    { id = "mouth",          name = "Ağız mağarası",               x = 50,  y = 40 },
    { id = "waterfall",      name = "Şelale arkası",               x = 20,  y = 120 },
    { id = "hub",            name = "Ana mağara",                  x = 110, y = 80 },
    { id = "anacondra",      name = "Anacondra'nın çıkıntısı",     x = 90,  y = 160 },
    { id = "cobrahn_den",    name = "Cobrahn'ın ini",              x = 170, y = 170 },
    { id = "pythas_tunnel",  name = "Pythas tüneli",               x = 200, y = 60 },
    { id = "pythas",         name = "Pythas'ın gözetleme yeri",    x = 270, y = 30 },
    { id = "naralex",        name = "Naralex'in odası",            x = 330, y = 70 },
    { id = "pools",          name = "Sığ havuzlar",                x = 160, y = 250 },
    { id = "kresh_lake",     name = "Kresh gölü",                  x = 240, y = 290 },
    { id = "skum",           name = "Skum'un mağarası",            x = 320, y = 320 },
    { id = "serpentis_ramp", name = "Serpentis yokuşu",            x = 260, y = 190 },
    { id = "serpentis",      name = "Serpentis'in terası",         x = 330, y = 180 },
    { id = "verdan",         name = "Verdan'ın havuzu",            x = 390, y = 250 },
  },
  corridors = {
    { id = "w1",  a = "entrance",      b = "mouth",          packs = { { "Deviate Raptor", 1 }, { "Deviate Viper", 1 } } },
    { id = "w2",  a = "mouth",         b = "hub",            packs = { { "Druid of the Fang", 1 }, { "Deviate Raptor", 2 } } },
    { id = "w3",  a = "mouth",         b = "waterfall",      packs = { { "Deviate Viper", 2 } } },
    { id = "w4",  a = "hub",           b = "anacondra",      packs = { { "Druid of the Fang", 2 }, { "Deviate Adder", 1 } } },
    { id = "w5",  a = "anacondra",     b = "cobrahn_den",    packs = { { "Deviate Ravager", 2 } } },
    { id = "w6",  a = "hub",           b = "cobrahn_den",    packs = { { "Druid of the Fang", 2 }, { "Deviate Viper", 1 } } },
    { id = "w7",  a = "hub",           b = "pythas_tunnel",  packs = { { "Deviate Ravager", 1 }, { "Druid of the Fang", 1 } } },
    { id = "w8",  a = "pythas_tunnel", b = "pythas",         packs = { { "Druid of the Fang", 2 }, { "Deviate Adder", 2 } } },
    { id = "w9",  a = "pythas",        b = "naralex",        packs = { { "Druid of the Fang", 2 } } },
    { id = "w10", a = "cobrahn_den",   b = "pools",          packs = { { "Deviate Guardian", 2 } } },
    { id = "w11", a = "pools",         b = "kresh_lake",     packs = { { "Deviate Lurker", 3 } } },
    { id = "w12", a = "kresh_lake",    b = "skum",           packs = { { "Deviate Lurker", 2 }, { "Deviate Moccasin", 2 } } },
    { id = "w13", a = "pools",         b = "serpentis_ramp", packs = { { "Druid of the Fang", 2 }, { "Deviate Dreadfang", 1 } } },
    { id = "w14", a = "serpentis_ramp", b = "serpentis",     packs = { { "Druid of the Fang", 2 } } },
    { id = "w15", a = "serpentis",     b = "verdan",         packs = { { "Deviate Shambler", 2 }, { "Evolving Ectoplasm", 2 } } },
    { id = "w16", a = "verdan",        b = "kresh_lake",     oneway = true, len = 40, name = "Aşağı atlama" },
    { id = "w17", a = "pythas_tunnel", b = "serpentis_ramp", packs = { { "Deviate Ravager", 2 } } },
  },
  bosses = {
    { name = "Lady Anacondra",        at = "anacondra",      fight = 60 },
    { name = "Lord Cobrahn",          at = "cobrahn_den",    fight = 60 },
    { name = "Lord Pythas",           at = "pythas",         fight = 60 },
    { name = "Lord Serpentis",        at = "serpentis",      fight = 60 },
    { name = "Kresh",                 at = "kresh_lake",     fight = 45 },
    { name = "Skum",                  at = "skum",           fight = 50 },
    { name = "Verdan the Everliving", at = "verdan",         fight = 75 },
    { name = "Mutanus the Devourer",  at = "naralex",        fight = 70,
      requires = { "Lady Anacondra", "Lord Cobrahn", "Lord Pythas", "Lord Serpentis" } },
    { name = "Mad Magglish",          at = "waterfall",      fight = 30, rare = true },
    { name = "Deviate Faerie Dragon", at = "serpentis_ramp", fight = 40, rare = true },
  },
}

D.dm = {
  id = "dm", name = "The Deadmines", instanceID = 36, levels = "17-26",
  names = { "The Deadmines", "Deadmines" },
  entrance = "entrance", bend = 1.2,
  nodes = {
    { id = "entrance",     name = "Giriş",                  x = 0,   y = 0 },
    { id = "mine1",        name = "Maden tüneli",           x = 60,  y = 30 },
    { id = "rhahk",        name = "Rhahk'Zor'un mağarası",  x = 120, y = 60 },
    { id = "lower_mine",   name = "Alt maden",              x = 180, y = 110 },
    { id = "johnson",      name = "Çıkmaz tünel",           x = 130, y = 170 },
    { id = "upper_tunnel", name = "Üst tünel",              x = 250, y = 70 },
    { id = "mill",         name = "Kereste atölyesi",       x = 290, y = 140 },
    { id = "foundry",      name = "Dökümhane",              x = 360, y = 110 },
    { id = "cannon",       name = "Top geçidi",             x = 420, y = 170 },
    { id = "dock",         name = "Ironclad Koyu iskelesi", x = 480, y = 230 },
    { id = "ship_deck",    name = "Gemi güvertesi",         x = 540, y = 260 },
    { id = "ship_galley",  name = "Gemi mutfağı",           x = 520, y = 310 },
    { id = "ship_top",     name = "Üst güverte",            x = 580, y = 300 },
  },
  corridors = {
    { id = "d1",  a = "entrance",     b = "mine1",        packs = { { "Defias Miner", 2 } } },
    { id = "d2",  a = "mine1",        b = "rhahk",        packs = { { "Defias Miner", 2 }, { "Defias Overseer", 1 } } },
    { id = "d3",  a = "rhahk",        b = "lower_mine",   gate = "Rhahk'Zor", packs = { { "Defias Miner", 2 }, { "Defias Evoker", 1 } } },
    { id = "d4",  a = "lower_mine",   b = "johnson",      packs = { { "Defias Miner", 2 } } },
    { id = "d5",  a = "lower_mine",   b = "mill",         packs = { { "Defias Taskmaster", 1 }, { "Defias Wizard", 1 }, { "Defias Miner", 2 } } },
    { id = "d6",  a = "lower_mine",   b = "upper_tunnel", packs = { { "Defias Wizard", 2 }, { "Defias Taskmaster", 1 } } },
    { id = "d7",  a = "upper_tunnel", b = "mill",         packs = { { "Goblin Woodcarver", 2 }, { "Defias Henchman", 1 } } },
    { id = "d8",  a = "mill",         b = "foundry",      gate = "Sneed", packs = { { "Goblin Craftsman", 2 }, { "Goblin Engineer", 1 }, { "Defias Henchman", 2 } } },
    { id = "d9",  a = "foundry",      b = "cannon",       gate = "Gilnid", packs = { { "Defias Henchman", 2 } } },
    { id = "d10", a = "cannon",       b = "dock",         packs = { { "Defias Pirate", 2 }, { "Defias Squallshaper", 1 } } },
    { id = "d11", a = "dock",         b = "ship_deck",    packs = { { "Defias Pirate", 3 }, { "Defias Squallshaper", 1 } } },
    { id = "d12", a = "ship_deck",    b = "ship_galley",  packs = { { "Defias Pirate", 2 } } },
    { id = "d13", a = "ship_deck",    b = "ship_top",     packs = { { "Defias Pirate", 2 }, { "Defias Squallshaper", 1 } } },
  },
  bosses = {
    { name = "Rhahk'Zor",         at = "rhahk",       fight = 45 },
    { name = "Miner Johnson",     at = "johnson",     fight = 35, rare = true },
    { name = "Sneed",             at = "mill",        fight = 70, alias = "Sneed's Shredder" },
    { name = "Gilnid",            at = "foundry",     fight = 50 },
    { name = "Mr. Smite",         at = "dock",        fight = 60 },
    { name = "Captain Greenskin", at = "ship_deck",   fight = 50 },
    { name = "Cookie",            at = "ship_galley", fight = 40 },
    { name = "Edwin VanCleef",    at = "ship_top",    fight = 80 },
  },
}

D.order = { "rfc", "wc", "dm" }

-- Oyundaki instanceID ya da ada göre zindan bulur.
function D.find(instanceID, name)
  for _, id in ipairs(D.order) do
    local d = D[id]
    if instanceID and d.instanceID == instanceID then return d end
  end
  if name then
    local low = name:lower()
    for _, id in ipairs(D.order) do
      local d = D[id]
      if d.id == low then return d end
      for _, n in ipairs(d.names) do
        if n:lower() == low then return d end
      end
    end
  end
  return nil
end

ns.Dungeons = D
