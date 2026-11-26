-- Eklenti dosyalarını oyunun dışında, oyundaki gibi yükler: her dosya (eklentiAdı, ns) ile
-- çağrılır. Varsayılan olarak yalnızca core/ ve data/ yüklenir; withUI = true ise .toc'taki
-- bütün dosyalar (ui/ için WoW API taklidi önceden kurulmuş olmalı, bkz. tests/wowmock.lua).
return function(root, withUI)
  local ns = {}
  local toc = assert(io.open(root .. "/AtlasSweep/AtlasSweep.toc")):read("*a")
  for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^%s*#") and line:match("%S") then
      local rel = line:gsub("\\", "/"):gsub("%s+$", "")
      if withUI or not rel:match("^ui/") then
        local f = assert(loadfile(root .. "/AtlasSweep/" .. rel))
        f("AtlasSweep", ns)
      end
    end
  end
  return ns
end
