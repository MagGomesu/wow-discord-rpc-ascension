--[[
IPC Pixel Strip (WotLK 3.3.5 / Ascension)
-----------------------------------------
Purpose: Paint an OPAQUE, pixel-perfect strip at the very top of the screen
that encodes a text message in RGB triplets for an external reader (e.g. Python).

Key anti-bleed measures:
  1) Opaque black underlay spanning the whole strip (no scene/background shows through).
  2) All data pixels are painted OPAQUE (alpha=1).
  3) Frames scaled to land on physical pixels (counter UI scale / DPI resampling).
  4) Strip height = 2px for stability; reader should sample the top row.

Reads best if the decoder samples the CENTER column of each 3-px block:
  block width = 3  → sample x = block_left + 1

Slash commands:
  /ipc <text>   : Paint <text> immediately (debug/manual)
  /clean        : Clear the strip to opaque black
]]

---------------------------------------------
-- Configuration
---------------------------------------------
local BLOCK_WIDTH = 3       -- 3 px per block (R,G,B per block)
local STRIP_HEIGHT = 2      -- 2 px tall to reduce edge bleed
local UPDATE_INTERVAL = 2   -- seconds
local TOP_OFFSET_Y = 0      -- y offset from top edge (0 = very top)

---------------------------------------------
-- State
---------------------------------------------
local frame_count = 0
local frames = {}
local IPC_Backdrop = nil
local tickerFrame = nil
local sinceLastUpdate = 0

-- Message cache (not strictly required but useful for debugging)
local prevZone = ""
local prevSubZone = ""
local message = ""

---------------------------------------------
-- Simple localization / strings
---------------------------------------------
local UnknownZoneName = "Unknown"
local playerOnBattleGround = "Battleground"
local playerIsDead = " (Dead)"

---------------------------------------------
-- Helpers
---------------------------------------------

local function GetGroupSummary()
  local party = GetNumPartyMembers() or 0
  local raid = GetNumRaidMembers() or 0
  if raid > 0 then
    return string.format("In raid (%d)", raid)
  elseif party > 0 then
    return string.format("In party (%d)", party + 1) -- +1 includes player
  else
    return "Solo"
  end
end

local function IPC_ShowRange(blocks)
  local used = math.max(0, math.min(blocks, frame_count))
  -- Resize underlay to only cover the used area
  if IPC_Backdrop then
    IPC_Backdrop:SetWidth(used * BLOCK_WIDTH)
  end
  -- Show only the frames we need; hide the rest
  for i = 1, frame_count do
    if i <= used then
      frames[i]:Show()
    else
      frames[i]:Hide()
    end
  end
end


---------------------------------------------
-- Frame / Strip construction
---------------------------------------------
function IPC_CreateFrames()
  frame_count = math.floor(GetScreenWidth() / BLOCK_WIDTH)

  if not IPC_Backdrop then
    IPC_Backdrop = CreateFrame("Frame", "IPCBackdropFrame", UIParent)
    IPC_Backdrop:SetFrameStrata("FULLSCREEN_DIALOG")
    IPC_Backdrop:SetFrameLevel(0)
    IPC_Backdrop:SetScale(1 / UIParent:GetEffectiveScale())
    IPC_Backdrop:SetWidth(0)                      -- start hidden width
    IPC_Backdrop:SetHeight(STRIP_HEIGHT)
    IPC_Backdrop:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -TOP_OFFSET_Y)

    local bt = IPC_Backdrop:CreateTexture(nil, "BACKGROUND")
    bt:SetAllPoints(IPC_Backdrop)
    bt:SetTexture(0, 0, 0, 1)                     -- opaque black
    IPC_Backdrop.tex = bt
    IPC_Backdrop:Show()
  else
    IPC_Backdrop:SetScale(1 / UIParent:GetEffectiveScale())
    IPC_Backdrop:SetHeight(STRIP_HEIGHT)
    IPC_Backdrop:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -TOP_OFFSET_Y)
  end

  -- hide old frames
  if frames and #frames > 0 then
    for i = 1, #frames do
      if frames[i] then frames[i]:Hide() end
    end
  end
  frames = {}

  for i = 1, frame_count do
    local f = CreateFrame("Frame", nil, UIParent)
    frames[i] = f
    f:SetScale(1 / UIParent:GetEffectiveScale())
    f:SetFrameStrata(i % 2 == 0 and "TOOLTIP" or "FULLSCREEN_DIALOG")
    f:SetFrameLevel((IPC_Backdrop:GetFrameLevel() or 0) + 1)
    f:SetWidth(BLOCK_WIDTH)
    f:SetHeight(STRIP_HEIGHT)
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", (i - 1) * BLOCK_WIDTH, -TOP_OFFSET_Y)

    local t = f:CreateTexture(nil, "ARTWORK")
    t:SetAllPoints(f)
    if t.SetBlendMode then
      if not pcall(t.SetBlendMode, t, "ALPHAKEY") then
        pcall(t.SetBlendMode, t, "BLEND")
      end
    end
    t:SetTexture(0, 0, 0, 1)     -- opaque
    f.texture = t
    f:Hide()                     -- IMPORTANT: hidden by default
  end

  return frames
end


local function IPC_PaintFrame(frame, r, g, b)
  -- normalize 0..255 → 0..1 and paint OPAQUE
  r = ((r or 0) / 255)
  g = ((g or 0) / 255)
  b = ((b or 0) / 255)
  frame.texture:SetTexture(r, g, b, 1) -- OPAQUE
end

function IPC_CleanFrames()
  if IPC_Backdrop then
    IPC_Backdrop:SetWidth(0)         -- nothing visible past sentinel
  end
  for i = 1, frame_count do
    if frames[i] then frames[i]:Hide() end
  end
end


---------------------------------------------
-- Encoding & Painting
---------------------------------------------
function IPC_PaintSomething(text)
  if not frames or #frames == 0 then
    IPC_CreateFrames()
  end

  -- Hide all first (no long black bar)
  IPC_CleanFrames()

  if not text or text == "" then
    return
  end

  -- How many 3-byte blocks do we need?
  local payload_blocks = math.ceil(#text / 3)
  -- +1 for the white sentinel
  local total_blocks = math.min(payload_blocks + 1, frame_count)

  -- Only show what we actually use (payload + sentinel)
  IPC_ShowRange(total_blocks)

  -- Paint payload blocks
  local idx = 0
  for trio in text:gmatch(".?.?.?") do
    idx = idx + 1
    if idx > payload_blocks or idx > frame_count then break end

    local r = 0
    local g = 0
    local b = 0
    local len = #trio
    if len >= 1 then r = string.byte(trio, 1) or 0 end
    if len >= 2 then g = string.byte(trio, 2) or 0 end
    if len >= 3 then b = string.byte(trio, 3) or 0 end

    IPC_PaintFrame(frames[idx], r, g, b)   -- opaque color
  end

  -- Paint the white sentinel immediately after the payload
  local sentinel_index = math.min(payload_blocks + 1, frame_count)
  IPC_PaintFrame(frames[sentinel_index], 255, 255, 255)

  -- All frames after `total_blocks` remain hidden (no trailing blacks)
end


function IPC_EncodeMessage()
  -- Helper: keep delimiters safe
  local function sanitizeField(s)
    s = tostring(s or "")
    s = s:gsub("|", "/"):gsub("%$", "S")
    return s
  end

  local zoneName = GetRealZoneText()
  if not zoneName or zoneName == "" then
    zoneName = UnknownZoneName
  end

  local subZone = GetMinimapZoneText() or ""
  if subZone ~= "" then
    zoneName = zoneName .. ", " .. subZone
  end

  -- Player identity
  local guid = UnitGUID("player")
  local locClass, engClass, locRace, _, _, playerName = "", "", "", "", "", "Player"
  if guid then
    locClass, engClass, locRace, _, _, playerName = GetPlayerInfoByGUID(guid)
  else
    playerName = UnitName("player") or "Player"
    engClass = select(2, UnitClass("player")) or "WARRIOR"
    locRace = select(2, UnitRace("player")) or "Human"
    locClass = select(1, UnitClass("player")) or "Warrior"
  end

  -- Realm / server name (works on 3.3.5/WotLK/Classic)
  local realmName = (GetRealmName and GetRealmName()) or GetCVar and GetCVar("realmName") or "Realm"

  -- Context adjustments
  local _, instanceType, _, difficultyName = GetInstanceInfo()
  if instanceType == "party" or instanceType == "raid" then
    if difficultyName and difficultyName ~= "" then
      zoneName = string.format("%s(%s)", zoneName, difficultyName)
    end
  elseif instanceType == "pvp" then
    zoneName = playerOnBattleGround
  else
    if UnitIsDeadOrGhost("player") and not UnitIsDead("player") then
      playerName = playerName .. playerIsDead
    end
  end

  -- Details: solo (XP/Gold) vs group summary
  local playerLevel = UnitLevel("player") or 0
  local details
  local party = GetNumPartyMembers() or 0
  local raid  = GetNumRaidMembers() or 0
  if (party + raid) == 0 then
    local maxXP = UnitXPMax("player") or 0
    local XP = UnitXP("player") or 0
    if maxXP > 0 then
      local function fmtK(n)
        if n >= 1000 then
          return string.format("%.01fk", n / 1000)
        end
        return tostring(n)
      end
      details = fmtK(XP) .. "/" .. fmtK(maxXP) .. " XP"
    else
      local money = GetMoney() or 0
      details = string.format(
        "%dg %ds %dc",
        math.floor(money / (100 * 100)),
        math.floor((money / 100) % 100),
        money % 100
      )
    end
  else
    details = GetGroupSummary()
  end

  -- Classic/WotLK map id (requires map to be set elsewhere if needed)
  local mapID = GetCurrentMapAreaID and GetCurrentMapAreaID() or 0

  local playerInfo = (locRace or "Human") .. ", " .. (locClass or "Warrior")

  -- Build message: add realmName as a NEW field after playerName
  local fields = {
    sanitizeField(zoneName),
    tostring(playerLevel or 0),
    sanitizeField(playerName),
    sanitizeField(realmName),              -- << NEW FIELD
    sanitizeField(playerInfo),
    sanitizeField(engClass or "WARRIOR"),
    sanitizeField(details or ""),
    tostring(mapID or 0),
  }

  message = "$$$" .. table.concat(fields, "|") .. "$$$"

  prevZone = zoneName
  prevSubZone = subZone

  return message
end


---------------------------------------------
-- Update loop (every UPDATE_INTERVAL seconds)
---------------------------------------------
local function StartLoop()
  if tickerFrame then return end

  tickerFrame = CreateFrame("Frame", "IPCUpdateTicker", UIParent)
  tickerFrame:SetScript("OnUpdate", function(self, elapsed)
    sinceLastUpdate = sinceLastUpdate + (elapsed or 0)
    if sinceLastUpdate >= UPDATE_INTERVAL then
      sinceLastUpdate = 0
      local encoded = IPC_EncodeMessage()
      if encoded and encoded ~= "" then
        IPC_PaintSomething(encoded)
      end
    end
  end)
end

---------------------------------------------
-- Events / Init
---------------------------------------------
local IPCFrame = CreateFrame("Frame", "IPCFrame", UIParent)

local function IPC_OnEvent(self, event, ...)
  if event == "PLAYER_LOGIN" then
    IPC_CreateFrames()
    StartLoop()
  end
end

IPCFrame:RegisterEvent("PLAYER_LOGIN")
IPCFrame:SetScript("OnEvent", IPC_OnEvent)

function IPC_OnLoad()
    IPCFrame:RegisterEvent("PLAYER_LOGIN")
    SlashCmdList["IPC"] = IPC_PaintSomething
    SLASH_IPC1 = "/ipc"
    SlashCmdList["CLEAN"] = IPC_CleanFrames
    SLASH_CLEAN1 = "/clean"
end


