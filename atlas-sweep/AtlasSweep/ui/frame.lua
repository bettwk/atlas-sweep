-- Sürüklenebilir küçük pencere: zindan, ilerleme, kalan süre ve sıradaki bacaklar.
local _, ns = ...
local Sweep = ns.Sweep

local UI = {}
local frame, title, status, lines
local LINES = 6
local WIDTH = 360

local KIND_COLOR = { clear = "|cffff8040", boss = "|cffff3030", exit = "|cff40ff40", walk = "|cffffffff" }

local function create(db)
  frame = CreateFrame("Frame", "AtlasSweepFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  frame:SetSize(WIDTH, 40 + LINES * 16)
  local p = db.framePoint
  if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -220) end
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    db.framePoint = { point, rel, x, y }
  end)
  if frame.SetBackdrop then
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                        tile = true, tileSize = 16, edgeSize = 16,
                        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    frame:SetBackdropColor(0, 0, 0, 0.75)
  end

  title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetWidth(WIDTH - 20)
  title:SetJustifyH("LEFT")

  status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
  status:SetWidth(WIDTH - 20)
  status:SetJustifyH("LEFT")

  lines = {}
  for i = 1, LINES do
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", i == 1 and status or lines[i - 1], "BOTTOMLEFT", 0, i == 1 and -6 or -3)
    fs:SetWidth(WIDTH - 20)
    fs:SetJustifyH("LEFT")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    lines[i] = fs
  end
  frame:Hide()
end

function UI.init(db) if not frame then create(db) end end

function UI.show() if frame then frame:Show() end end
function UI.hide() if frame then frame:Hide() end end
function UI.shown() return frame ~= nil and frame:IsShown() end

-- run = { dungeon, tracker, mode, planning }
function UI.update(run)
  if not frame then return end
  if not run then
    title:SetText("AtlasSweep")
    status:SetText("Bir zindana girin ya da /as start <rfc|wc|dm>")
    for i = 1, LINES do lines[i]:SetText("") end
    return
  end
  local tr = run.tracker
  local modeText = run.mode == "boss" and "boss koşusu" or "tam temizlik"
  title:SetText(("AtlasSweep — %s (%s)"):format(run.dungeon.name, modeText))
  if run.planning or not tr.plan then
    status:SetText("Atlas planlıyor…")
    for i = 1, LINES do lines[i]:SetText("") end
    return
  end
  local done, total = tr:progress()
  local extra = ""
  if #tr.plan.unreachable > 0 then extra = ("  |cffff4040%d ulaşılamaz|r"):format(#tr.plan.unreachable) end
  status:SetText(("İlerleme %d/%d · kalan ~%s%s"):format(done, total, Sweep.fmtTime(tr:remainingTime()), extra))
  for i = 1, LINES do
    local leg = tr.plan.legs[tr.leg + i - 1]
    if leg then
      local kind = leg.obj and leg.obj.kind or "walk"
      local text = Sweep.legText(tr.M, leg)
      if i == 1 and kind == "clear" then
        text = text .. (" [%d/%d]"):format(tr.kills, leg.obj.expect)
      end
      lines[i]:SetText((i == 1 and "> " or "  ") .. (KIND_COLOR[kind] or "") .. text .. "|r")
    elseif i == 1 then
      lines[i]:SetText("|cff40ff40Plan tamamlandı.|r")
    else
      lines[i]:SetText("")
    end
  end
end

ns.UI = UI
