-- 악귀 사냥꾼 : 쿼터뷰 액션 (LÖVE 11.x)
-- 조작 : WASD 이동, 마우스 조준, 좌클릭 베기(3연격), 우클릭 활, Space 구르기, E 회전베기, Q 물약
--        Esc 일시정지, F11 전체화면
-- 캐릭터·벽은 전부 블록(상자)을 코드로 그린다. 이미지 파일 없음.

local lg = love.graphics
local rnd = love.math.random
local Chars = require("chars")   -- 캐릭터 그림 (결투 방식)
local sin, cos, sqrt, floor, ceil, min, max, abs, pi = math.sin, math.cos, math.sqrt, math.floor, math.ceil, math.min, math.max, math.abs, math.pi
local atan2 = math.atan2

local W, H = 960, 540
local TW, TH, TZ = 64, 32, 36      -- 타일 가로/세로 픽셀, 높이 1 의 픽셀
local HW, HH = TW / 2, TH / 2
local ZOOM = 1.0                   -- 작을수록 카메라가 멀다
local MW, MH = 46, 46              -- 맵 크기 (타일)

local AUTO = nil                   -- 자동 테스트 모드 (--autotest)

-------------------------------------------------------------------------------
-- 기본 함수
-------------------------------------------------------------------------------
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function lerp(a, b, t) return a + (b - a) * t end
local function len(x, y) return sqrt(x * x + y * y) end
local function norm(x, y)
  local l = sqrt(x * x + y * y)
  if l < 1e-6 then return 0, 0 end
  return x / l, y / l
end
local function angDiff(a, b) return (a - b + pi) % (2 * pi) - pi end
local function turn(a, b, step)
  local d = angDiff(b, a)
  if abs(d) <= step then return b end
  return a + (d > 0 and step or -step)
end
-- 월드(x, y, 높이 z) → 쿼터뷰 화면 좌표
local function proj(x, y, z) return (x - y) * HW, (x + y) * HH - (z or 0) * TZ end
local R2 = 1.41421356

-------------------------------------------------------------------------------
-- 화면 / 폰트
-------------------------------------------------------------------------------
local view = { s = 1, x = 0, y = 0 }
local function updateView()
  local ww, wh = lg.getDimensions()
  view.s = math.min(ww / W, wh / H)
  view.x = math.floor((ww - W * view.s) / 2)
  view.y = math.floor((wh - H * view.s) / 2)
end
local function toGame(x, y) return (x - view.x) / view.s, (y - view.y) / view.s end

local fontData
local function loadFontData()
  if love.filesystem.getInfo("font.ttf") then return love.filesystem.read("font.ttf") end
  for _, p in ipairs({ "C:/Windows/Fonts/malgunbd.ttf", "C:/Windows/Fonts/malgun.ttf" }) do
    local fh = io.open(p, "rb")
    if fh then local s = fh:read("*a"); fh:close(); return s end
  end
end
local function mkFont(size)
  local dpi = math.max(1, view.s)
  if fontData then
    local ok, f = pcall(function()
      return lg.newFont(love.filesystem.newFileData(fontData, "korean.ttf"), size, "normal", dpi)
    end)
    if ok then return f end
  end
  return lg.newFont(size, "normal", dpi)
end
local fontS, fontM, fontL, fontXL
local function makeFonts()
  fontS, fontM, fontL, fontXL = mkFont(13), mkFont(18), mkFont(28), mkFont(52)
end

local function txt(s, x, y, font, align, w, a)
  lg.setFont(font)
  a = a or 1
  local r, g, b = lg.getColor()
  lg.setColor(0, 0, 0, .7 * a)
  if align then lg.printf(s, x + 2, y + 2, w, align) else lg.print(s, x + 2, y + 2) end
  lg.setColor(r, g, b, a)
  if align then lg.printf(s, x, y, w, align) else lg.print(s, x, y) end
end

-------------------------------------------------------------------------------
-- 소리 (코드로 합성)
-------------------------------------------------------------------------------
local sfx = {}
local function synth(dur, f)
  local rate = 44100
  local n = floor(dur * rate)
  local sd = love.sound.newSoundData(n, rate, 16, 1)
  local ph = 0
  for i = 0, n - 1 do
    local t = i / rate
    local v
    v, ph = f(t, t / dur, ph)
    sd:setSample(i, clamp(v, -1, 1))
  end
  return love.audio.newSource(sd, "static")
end
local function noise() return rnd() * 2 - 1 end
local function makeSounds()
  local rate = 44100
  sfx.swing = synth(.17, function(t, p, ph) return noise() * (1 - p) ^ 2 * sin(p * pi) * .35, ph end)
  sfx.hit = synth(.16, function(t, p, ph)
    ph = ph + 2 * pi * (170 - 110 * p) / rate
    return (sin(ph) * .75 + noise() * .35 * (1 - p)) * (1 - p) ^ 1.6 * .7, ph end)
  sfx.crit = synth(.22, function(t, p, ph)
    ph = ph + 2 * pi * (120 - 70 * p) / rate
    return (sin(ph) * .8 + noise() * .4 * (1 - p)) * (1 - p) ^ 1.3 * .8, ph end)
  sfx.shoot = synth(.12, function(t, p, ph)
    ph = ph + 2 * pi * (500 + 900 * p) / rate
    return (sin(ph) * .3 + noise() * .2) * (1 - p) ^ 2, ph end)
  sfx.hurt = synth(.25, function(t, p, ph)
    ph = ph + 2 * pi * (220 - 120 * p) / rate
    return ((ph % (2 * pi) < pi) and .35 or -.35) * (1 - p) ^ 1.5, ph end)
  sfx.pick = synth(.09, function(t, p, ph)
    ph = ph + 2 * pi * (900 + 600 * p) / rate
    return sin(ph) * .25 * (1 - p), ph end)
  sfx.die = synth(.35, function(t, p, ph)
    ph = ph + 2 * pi * (300 - 250 * p) / rate
    return (sin(ph) * .4 + noise() * .3) * (1 - p) ^ 2 * .7, ph end)
  sfx.roll = synth(.2, function(t, p, ph) return noise() * .18 * (1 - p) * sin(p * pi), ph end)
  sfx.level = synth(.6, function(t, p, ph)
    local notes = { 523, 659, 784, 1046 }
    local f = notes[min(4, floor(p * 4) + 1)]
    ph = ph + 2 * pi * f / rate
    return sin(ph) * .25 * (1 - (p * 4) % 1 * .6), ph end)
  sfx.slam = synth(.4, function(t, p, ph)
    ph = ph + 2 * pi * (80 - 50 * p) / rate
    return (sin(ph) * .9 + noise() * .5 * (1 - p)) * (1 - p) ^ 1.4 * .8, ph end)
  sfx.spawn = synth(.4, function(t, p, ph)
    ph = ph + 2 * pi * (90 + 60 * sin(p * 9)) / rate
    return sin(ph) * .18 * sin(p * pi), ph end)
end
local function play(name, pitchVar, vol)
  if AUTO then return end
  local s = sfx[name]
  if not s then return end
  local c = s:clone()
  c:setPitch(1 + (rnd() - .5) * (pitchVar or .2))
  c:setVolume(vol or 1)
  c:play()
end

-------------------------------------------------------------------------------
-- 맵
-------------------------------------------------------------------------------
local map, shade, lantern, reach
local lanterns = {}
local floorMesh

local function solid(tx, ty)
  if tx < 1 or ty < 1 or tx > MW or ty > MH then return true end
  return map[ty][tx] > 0
end
local function solidAt(x, y) return solid(floor(x), floor(y)) end

local function genMap()
  map, shade, lantern, reach = {}, {}, {}, {}
  lanterns = {}
  for y = 1, MH do
    map[y], shade[y], lantern[y], reach[y] = {}, {}, {}, {}
    for x = 1, MW do
      local h = 0
      if x <= 2 or y <= 2 then h = 2.2                 -- 뒤쪽 외벽은 높게
      elseif x >= MW - 1 or y >= MH - 1 then h = .5 end -- 앞쪽 외벽은 낮게 (가리지 않게)
      map[y][x] = h
      shade[y][x] = rnd()
    end
  end
  local cx, cy = MW / 2, MH / 2
  -- 무너진 담장 덩어리
  for _ = 1, 30 do
    local w, h = rnd(2, 5), rnd(1, 2)
    if rnd() < .5 then w, h = h, w end
    local x, y = rnd(4, MW - 4 - w), rnd(4, MH - 4 - h)
    if abs(x + w / 2 - cx) > 4 or abs(y + h / 2 - cy) > 4 then
      for yy = y, y + h - 1 do
        for xx = x, x + w - 1 do
          if rnd() < .85 then map[yy][xx] = 1 end
        end
      end
    end
  end
  -- 높은 기둥
  for _ = 1, 16 do
    local x, y = rnd(4, MW - 3), rnd(4, MH - 3)
    if abs(x - cx) > 3 or abs(y - cy) > 3 then map[y][x] = 2 end
  end
  -- 석등
  for _ = 1, 14 do
    local x, y = rnd(4, MW - 3), rnd(4, MH - 3)
    if map[y][x] == 0 and (abs(x - cx) > 2 or abs(y - cy) > 2) then
      map[y][x] = .9
      lantern[y][x] = true
      lanterns[#lanterns + 1] = { x = x + .5, y = y + .5, ph = rnd() * 10 }
    end
  end
  -- 시작점(가운데) 근처는 비운다
  for y = floor(cy) - 2, floor(cy) + 2 do
    for x = floor(cx) - 2, floor(cx) + 2 do
      if not lantern[y][x] then map[y][x] = 0 end
    end
  end
  -- 가운데에서 갈 수 있는 바닥 표시 (막힌 구석에는 적을 안 만든다)
  local qx, qy, head = { floor(cx) }, { floor(cy) }, 1
  reach[floor(cy)][floor(cx)] = true
  while head <= #qx do
    local x, y = qx[head], qy[head]; head = head + 1
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = x + d[1], y + d[2]
      if not solid(nx, ny) and not reach[ny][nx] then
        reach[ny][nx] = true
        qx[#qx + 1], qy[#qy + 1] = nx, ny
      end
    end
  end
  -- 갇힌 바닥은 담장으로 메운다
  for y = 1, MH do
    for x = 1, MW do
      if map[y][x] == 0 and not reach[y][x] then map[y][x] = 1 end
    end
  end
end

local function buildFloorMesh()
  local v = {}
  local function quad(x0, y0, x1, y1, r, g, b)
    local ax, ay = proj(x0, y0)
    local bx, by = proj(x1, y0)
    local cx, cy = proj(x1, y1)
    local dx, dy = proj(x0, y1)
    v[#v + 1] = { ax, ay, 0, 0, r, g, b, 1 }
    v[#v + 1] = { bx, by, 0, 0, r, g, b, 1 }
    v[#v + 1] = { cx, cy, 0, 0, r, g, b, 1 }
    v[#v + 1] = { ax, ay, 0, 0, r, g, b, 1 }
    v[#v + 1] = { cx, cy, 0, 0, r, g, b, 1 }
    v[#v + 1] = { dx, dy, 0, 0, r, g, b, 1 }
  end
  for y = 1, MH do
    for x = 1, MW do
      if map[y][x] == 0 then
        local s = shade[y][x]
        -- 벽 옆 바닥은 어둡게 (그림자 느낌)
        local ao = 0
        for dy = -1, 1 do
          for dx = -1, 1 do
            if (dx ~= 0 or dy ~= 0) and solid(x + dx, y + dy) then
              ao = ao + ((dx == 0 or dy == 0) and .11 or .05)
            end
          end
        end
        local k = 1 - min(.4, ao)
        local base = .33 + s * .07
        local r, g, b = base * .93, base * .95, base * 1.1
        if s > .86 then r, g, b = r * .8, g * 1.12, b * .8 end -- 이끼
        if s < .06 then r, g, b = r * 1.1, g * .95, b * .85 end -- 흙
        quad(x, y, x + 1, y + 1, r * .62 * k, g * .62 * k, b * .62 * k)
        quad(x + .05, y + .05, x + .95, y + .95, r * k, g * k, b * k)
      end
    end
  end
  floorMesh = lg.newMesh(v, "triangles", "static")
end

-- 흐름장 : 플레이어 칸까지의 거리. 적은 이걸 따라 벽을 돌아온다
local flow, flowTx, flowTy
local function buildFlow(tx, ty)
  flow = {}
  for y = 1, MH do flow[y] = {} end
  if solid(tx, ty) then return end
  local qx, qy, head = { tx }, { ty }, 1
  flow[ty][tx] = 0
  while head <= #qx do
    local x, y = qx[head], qy[head]; head = head + 1
    local d = flow[y][x] + 1
    for i = 1, 4 do
      local nx, ny = x, y
      if i == 1 then nx = x + 1 elseif i == 2 then nx = x - 1 elseif i == 3 then ny = y + 1 else ny = y - 1 end
      if not solid(nx, ny) and not flow[ny][nx] then
        flow[ny][nx] = d
        qx[#qx + 1], qy[#qy + 1] = nx, ny
      end
    end
  end
end

local function los(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  local n = ceil(len(dx, dy) / .25)
  for i = 1, n - 1 do
    local t = i / n
    if solidAt(x1 + dx * t, y1 + dy * t) then return false end
  end
  return true
end

-- 원(캐릭터) 과 벽 칸 충돌을 밀어낸다
local function collide(e)
  local r = e.r
  for ty = floor(e.y - r), floor(e.y + r) do
    for tx = floor(e.x - r), floor(e.x + r) do
      if solid(tx, ty) then
        local cx, cy = clamp(e.x, tx, tx + 1), clamp(e.y, ty, ty + 1)
        local dx, dy = e.x - cx, e.y - cy
        local d2 = dx * dx + dy * dy
        if d2 < r * r then
          local d = sqrt(d2)
          if d > 1e-5 then
            e.x, e.y = e.x + dx / d * (r - d), e.y + dy / d * (r - d)
          else
            local l, rr, u, b = e.x - tx, tx + 1 - e.x, e.y - ty, ty + 1 - e.y
            local m = min(l, rr, u, b)
            if m == l then e.x = tx - r elseif m == rr then e.x = tx + 1 + r
            elseif m == u then e.y = ty - r else e.y = ty + 1 + r end
          end
        end
      end
    end
  end
end

-------------------------------------------------------------------------------
-- 블록 그리기
-------------------------------------------------------------------------------
local bx, by = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
-- 회전한 상자 하나. (cx,cy) 바닥 중심, z0 바닥 높이, w 폭(옆), d 깊이(앞), h 높이, ang 바라보는 방향
local function drawBox(cx, cy, z0, w, d, h, ang, col, alpha, flash, glow)
  alpha, flash = alpha or 1, flash or 0
  local ux, uy = cos(ang), sin(ang)
  local vx, vy = -uy, ux
  local hd, hw = d * .5, w * .5
  bx[1], by[1] = cx + ux * hd + vx * hw, cy + uy * hd + vy * hw
  bx[2], by[2] = cx + ux * hd - vx * hw, cy + uy * hd - vy * hw
  bx[3], by[3] = cx - ux * hd - vx * hw, cy - uy * hd - vy * hw
  bx[4], by[4] = cx - ux * hd + vx * hw, cy - uy * hd + vy * hw
  local r, g, b = col[1], col[2], col[3]
  if flash > 0 then r, g, b = lerp(r, 1, flash), lerp(g, 1, flash), lerp(b, 1, flash) end
  local z1 = z0 + h
  for i = 1, 4 do
    local nx, ny
    if i == 1 then nx, ny = ux, uy elseif i == 2 then nx, ny = -vx, -vy
    elseif i == 3 then nx, ny = -ux, -uy else nx, ny = vx, vy end
    if nx + ny > .001 then
      local j = i % 4 + 1
      local s = glow and 1 or (.68 + .16 * (ny - nx))
      local ax, ay = proj(bx[i], by[i], z0)
      local bbx, bby = proj(bx[j], by[j], z0)
      local ccx, ccy = proj(bx[j], by[j], z1)
      local ddx, ddy = proj(bx[i], by[i], z1)
      lg.setColor(r * s, g * s, b * s, alpha)
      lg.polygon("fill", ax, ay, bbx, bby, ccx, ccy, ddx, ddy)
      if not glow then
        lg.setColor(r * .3, g * .3, b * .3, alpha * .7)
        lg.polygon("line", ax, ay, bbx, bby, ccx, ccy, ddx, ddy)
      end
    end
  end
  local ax, ay = proj(bx[1], by[1], z1)
  local bbx, bby = proj(bx[2], by[2], z1)
  local ccx, ccy = proj(bx[3], by[3], z1)
  local ddx, ddy = proj(bx[4], by[4], z1)
  local s = glow and 1 or 1.06
  lg.setColor(min(1, r * s), min(1, g * s), min(1, b * s), alpha)
  lg.polygon("fill", ax, ay, bbx, bby, ccx, ccy, ddx, ddy)
  if not glow then
    lg.setColor(r * .3, g * .3, b * .3, alpha * .7)
    lg.polygon("line", ax, ay, bbx, bby, ccx, ccy, ddx, ddy)
  end
end

-- 캐릭터 부품을 모아서 앞뒤 순서로 그린다
local cp, cpn = {}, 0
local cpList = {}
local function cpart(x, y, z, w, d, h, ang, col, glow)
  cpn = cpn + 1
  local t = cp[cpn]
  if not t then t = {}; cp[cpn] = t end
  t.x, t.y, t.z, t.w, t.d, t.h, t.ang, t.col, t.glow = x, y, z, w, d, h, ang, col, glow
  t.k = x + y + z * .02
end
local function sortK(a, b) return a.k < b.k end
local function flushParts(alpha, flash)
  for i = 1, cpn do cpList[i] = cp[i] end
  for i = cpn + 1, #cpList do cpList[i] = nil end
  table.sort(cpList, sortK)
  for i = 1, cpn do
    local t = cpList[i]
    drawBox(t.x, t.y, t.z, t.w, t.d, t.h, t.ang, t.col, alpha, t.glow and 0 or flash, t.glow)
  end
  cpn = 0
end

-------------------------------------------------------------------------------
-- 게임 상태
-------------------------------------------------------------------------------
local state = "title"
local player, enemies, projs, drops, pts, texts, effects, spawns
local cam = { x = 0, y = 0, sx = 0, sy = 0 }
local shake, freeze, slowTimer = 0, 0, 0
-- 타격 경직(히트스톱, 결투에서 가져옴): frames 프레임(60fps 기준) 동안 싸우는 쪽이 전부 멈춘다. 이미 더 길게 멈춰 있으면 그대로
local function hitStop(frames) freeze = math.max(freeze, frames / 60) end
local wave, waveQueue, spawnT, breakT, kills, pendingLv
local banner = { text = "", t = 0 }
local lvChoices = {}
local gameTime = 0
local lightCanvas, glowImg, vignette

local TYPES = {
  grunt = { name = "악귀", hp = 34, speed = 2.3, r = .3, dmg = 10, range = 1.05, windup = .45, cd = 1.1, exp = 2,
    stagger = .25, mass = 1, s = 1, sc = .48, weapon = { style = "claw", len = 0, width = 0 },
    skin = { .42, .56, .36 }, cloth = { .32, .22, .34 }, leg = { .22, .18, .24 }, eye = { 1, .25, .15 },
    horns = { .85, .8, .66 }, mouth = { .15, .08, .08 } },
  archer = { name = "원귀", hp = 22, speed = 2.1, r = .28, dmg = 9, range = 7, windup = .6, cd = 2.1, exp = 3,
    stagger = .3, mass = .8, s = .95, sc = .55,
    skin = { .84, .86, .94 }, cloth = { .62, .68, .84 }, leg = { .5, .56, .74 }, eye = { .35, .95, 1 } },
  brute = { name = "거귀", hp = 150, speed = 1.5, r = .5, dmg = 22, range = 1.5, windup = .8, cd = 2.4, exp = 10,
    stagger = 0, mass = 3.5, s = 1.55, sc = .78, weapon = { style = "bigclub", len = 84, width = 10 },
    skin = { .62, .27, .24 }, cloth = { .24, .17, .14 }, leg = { .18, .13, .11 }, eye = { 1, .82, .2 },
    horns = { .92, .88, .74 }, mouth = { .2, .06, .05 } },
}

local UPGRADES = {
  { name = "날카로운 칼날", desc = "근접 공격력 +20%", apply = function(p) p.dmg = p.dmg * 1.2 end },
  { name = "강인한 육체", desc = "최대 체력 +25\n체력 40 회복", apply = function(p) p.maxhp = p.maxhp + 25; p.hp = min(p.maxhp, p.hp + 40) end },
  { name = "질풍 걸음", desc = "이동 속도 +10%", apply = function(p) p.speed = p.speed * 1.1 end },
  { name = "연격", desc = "공격 속도 +15%", apply = function(p) p.atkSpeed = p.atkSpeed * 1.15 end },
  { name = "급소 노리기", desc = "치명타 확률 +8%", apply = function(p) p.crit = p.crit + .08 end },
  { name = "선풍", desc = "회전베기 쿨타임 -20%\n범위 +15%", apply = function(p) p.spinMax = p.spinMax * .8; p.spinR = p.spinR * 1.15 end },
  { name = "파마 화살", desc = "화살 +15\n화살 피해 +30%", apply = function(p) p.arrows = p.arrows + 15; p.arrowDmg = p.arrowDmg * 1.3 end },
  { name = "흡혼", desc = "적 처치 시\n체력 2 회복", apply = function(p) p.lifesteal = p.lifesteal + 2 end },
  { name = "약초 주머니", desc = "물약 쿨타임 -25%", apply = function(p) p.potionMax = p.potionMax * .75 end },
}

local function newPlayer()
  return {
    x = MW / 2 + .5, y = MH / 2 + .5, r = .3, face = .8,
    hp = 100, maxhp = 100, speed = 4.3, dmg = 12, atkSpeed = 1, crit = .08, lifesteal = 0,
    arrowDmg = 1, arrows = 30,
    atkCd = 0, combo = 0, comboT = 0, swingT = 0, swingDur = .2, swingDir = 0, swingSide = 1, swingHeavy = false,
    roll = 0, rollDur = .32, rollCd = 0, rollDx = 0, rollDy = 0, inv = 0, dir = 1,
    potionCd = 0, potionMax = 15, spin = 0, spinCd = 0, spinMax = 8, spinR = 2.3, spinA = 0, shootCd = 0,
    level = 1, exp = 0, nextExp = 8, walk = 0, moving = false, flash = 0, kx = 0, ky = 0, aimT = 0,
  }
end

local function addText(x, y, s, col, big)
  texts[#texts + 1] = { x = x, y = y, z = 1.4, s = s, col = col, t = 0, life = big and 1 or .75, big = big,
    vx = (rnd() - .5) * .6 }
end
local function burst(x, y, z, n, col, spd, size, life)
  for _ = 1, n do
    local a = rnd() * pi * 2
    local v = (spd or 3) * (.4 + rnd() * .8)
    pts[#pts + 1] = { x = x, y = y, z = z or .5, vx = cos(a) * v, vy = sin(a) * v, vz = rnd() * 4 + 1,
      life = (life or .5) * (.6 + rnd() * .6), t = 0, size = (size or 3) * (.6 + rnd() * .7), col = col, grav = 12 }
  end
end
local function addShake(v) shake = max(shake, v) end

local function startWave(n)
  wave = n
  waveQueue = {}
  local g = 4 + n * 2
  local a = n >= 2 and floor(n / 2) + 1 or 0
  local b = floor(n / 3)
  for _ = 1, g do waveQueue[#waveQueue + 1] = "grunt" end
  for _ = 1, a do waveQueue[#waveQueue + 1] = "archer" end
  for _ = 1, b do waveQueue[#waveQueue + 1] = "brute" end
  for i = #waveQueue, 2, -1 do
    local j = rnd(1, i)
    waveQueue[i], waveQueue[j] = waveQueue[j], waveQueue[i]
  end
  spawnT = 1
  banner.text = "웨이브 " .. n
  banner.sub = (b > 0) and "거귀가 섞여 있다!" or "악귀들이 몰려온다"
  banner.t = 2.6
end

local function newGame()
  genMap()
  buildFloorMesh()
  player = newPlayer()
  enemies, projs, drops, pts, texts, effects, spawns = {}, {}, {}, {}, {}, {}, {}
  wave, kills, pendingLv = 0, 0, 0
  waveQueue, spawnT, breakT = {}, 0, 3
  banner.text, banner.sub, banner.t = "악귀들이 냄새를 맡았다...", "곧 몰려온다", 3
  cam.x, cam.y = player.x, player.y
  flowTx, flowTy = nil, nil
  shake, freeze, slowTimer, gameTime = 0, 0, 0, 0
end

-------------------------------------------------------------------------------
-- 입력 (자동 테스트 때는 가짜 입력)
-------------------------------------------------------------------------------
local function keyDown(...)
  if AUTO then
    for _, k in ipairs({ ... }) do if AUTO.keys[k] then return true end end
    return false
  end
  return love.keyboard.isDown(...)
end
local function mouseDown(b)
  if AUTO then return AUTO.mouse[b] end
  return love.mouse.isDown(b)
end
local function screenToWorld(gx, gy, zPlane)
  local sx = (gx - W / 2) / ZOOM + cam.sx
  local sy = (gy - H / 2) / ZOOM + cam.sy + (zPlane or 0) * TZ
  local a, b = sx / HW, sy / HH
  return (a + b) / 2, (b - a) / 2
end
local function mouseWorld()
  if AUTO then return AUTO.ax, AUTO.ay end
  local gx, gy = toGame(love.mouse.getPosition())
  return screenToWorld(gx, gy, .6) -- 캐릭터 몸통 높이를 겨냥
end
local function worldToGame(x, y, z)
  local sx, sy = proj(x, y, z)
  return W / 2 + (sx - cam.sx) * ZOOM, H / 2 + (sy - cam.sy) * ZOOM
end

-------------------------------------------------------------------------------
-- 전투
-------------------------------------------------------------------------------
-- stop: 히트스톱 프레임 (몬스터 공격 7, 내려찍기·돌진 10)
local function hurtPlayer(amount, dx, dy, kb, stop)
  local p = player
  if p.inv > 0 or p.roll > 0 or state ~= "play" then return end
  p.hp = p.hp - amount
  p.inv, p.flash = .6, .2
  p.kx, p.ky = p.kx + dx * kb, p.ky + dy * kb
  addShake(.45)
  hitStop(stop or 7)
  addText(p.x, p.y, tostring(floor(amount)), { 1, .35, .3 })
  burst(p.x, p.y, .8, 8, { .8, .1, .1 }, 3, 3)
  play("hurt")
  if p.hp <= 0 then
    p.hp = 0
    state = "dead"
    burst(p.x, p.y, .8, 30, { .7, .1, .1 }, 5, 4, .9)
  end
end

local function killEnemy(e)
  e.dead = true
  kills = kills + 1
  local T = e.T
  burst(e.x, e.y, .8 * T.s, 18, T.skin, 4, 4, .7)
  burst(e.x, e.y, .8 * T.s, 8, { .15, .08, .2 }, 2, 6, .9)
  for _ = 1, T.exp do
    local a = rnd() * pi * 2
    drops[#drops + 1] = { kind = "exp", x = e.x, y = e.y, z = .5, vx = cos(a) * 2.5, vy = sin(a) * 2.5, vz = 4, t = 0, v = 1 }
  end
  local r = rnd()
  if r < .09 then
    drops[#drops + 1] = { kind = "hp", x = e.x, y = e.y, z = .5, vx = 0, vy = 0, vz = 5, t = 0 }
  elseif r < .2 then
    drops[#drops + 1] = { kind = "arrow", x = e.x, y = e.y, z = .5, vx = 0, vy = 0, vz = 5, t = 0 }
  end
  if player.lifesteal > 0 then player.hp = min(player.maxhp, player.hp + player.lifesteal) end
  play("die")
  -- 웨이브 마지막 적 = 결정타: 크게 멈췄다가 느린 화면으로 (결투와 같은 16프레임 + 1.6초)
  local last = #waveQueue == 0 and #spawns == 0
  if last then
    for _, o in ipairs(enemies) do if not o.dead then last = false; break end end
  end
  if last and wave > 0 then
    hitStop(16)
    slowTimer = 1.6
    addShake(.6)
    addText(e.x, e.y, "결정타!", { 1, .85, .3 }, true)
  end
end

-- stop: 히트스톱 프레임 (결투 기준: 일반 7, 강공격 11, 치명타는 카운터처럼 13)
local function damageEnemy(e, amount, dx, dy, kb, crit, stop)
  if e.dead then return end
  e.hp = e.hp - amount
  e.flash, e.hpShow = .12, 2.5
  local T = e.T
  e.kx, e.ky = e.kx + dx * kb / T.mass, e.ky + dy * kb / T.mass
  if T.stagger > 0 then
    e.stun = max(e.stun, T.stagger)
    if e.state == "windup" then e.state = "chase"; e.cd = max(e.cd, .4) end
  end
  addText(e.x, e.y, tostring(floor(amount)) .. (crit and "!" or ""), crit and { 1, .85, .2 } or { 1, 1, 1 }, crit)
  burst(e.x, e.y, .7 * T.s, crit and 10 or 5, { 1, .9, .6 }, 4, 2.5, .3)
  hitStop(crit and 13 or (stop or 7))
  addShake(crit and .3 or .15)
  play(crit and "crit" or "hit")
  if e.hp <= 0 then killEnemy(e) end
end

local function rollDamage(base)
  local crit = rnd() < player.crit
  return base * (crit and 2 or 1) * (.9 + rnd() * .2), crit
end

local function doSwing(aim)
  local p = player
  p.combo = (p.comboT > 0) and (p.combo % 3 + 1) or 1
  p.comboT = .8
  local heavy = p.combo == 3
  p.face, p.aimT = aim, .35
  p.swingT, p.swingDur, p.swingDir = heavy and .26 or .2, heavy and .26 or .2, aim
  p.swingSide = (p.combo == 2) and -1 or 1
  p.swingHeavy = heavy
  p.atkCd = (heavy and .55 or .3) / p.atkSpeed
  p.kx, p.ky = p.kx + cos(aim) * (heavy and 7 or 4), p.ky + sin(aim) * (heavy and 7 or 4)
  local range, half = heavy and 1.95 or 1.6, heavy and 1.35 or 1.05
  effects[#effects + 1] = { kind = "arc", x = p.x, y = p.y, ang = aim, range = range, half = half, side = p.swingSide,
    t = 0, dur = heavy and .26 or .2, heavy = heavy }
  play("swing", .25, heavy and 1 or .8)
  for _, e in ipairs(enemies) do
    if not e.dead then
      local dx, dy = e.x - p.x, e.y - p.y
      local d = len(dx, dy)
      if d < range + e.r and (d < .5 or abs(angDiff(atan2(dy, dx), aim)) < half) then
        local dmg, crit = rollDamage(p.dmg * (heavy and 1.8 or 1))
        local nx, ny = norm(dx, dy)
        damageEnemy(e, dmg, nx, ny, heavy and 11 or 6, crit, heavy and 11 or 7)
      end
    end
  end
end

local function doShoot(aim)
  local p = player
  if p.arrows <= 0 then
    p.shootCd = .3
    if gameTime - (p.noArrowT or -9) > 1.2 then
      p.noArrowT = gameTime
      addText(p.x, p.y, "화살 없음", { .8, .8, .8 })
    end
    return
  end
  p.arrows = p.arrows - 1
  p.shootCd = .38 / p.atkSpeed
  p.face, p.aimT, p.shootT = aim, .3, .22
  projs[#projs + 1] = { owner = "player", x = p.x + cos(aim) * .4, y = p.y + sin(aim) * .4, z = .65,
    vx = cos(aim) * 15, vy = sin(aim) * 15, r = .16, dmg = p.dmg * .85 * p.arrowDmg, life = 1.4, pierce = 2, hit = {}, ang = aim }
  play("shoot")
end

local function doRoll()
  local p = player
  if p.rollCd > 0 or p.roll > 0 or state ~= "play" then return end
  local dx, dy = p.mvx or 0, p.mvy or 0
  if dx == 0 and dy == 0 then dx, dy = cos(p.face), sin(p.face) end
  p.rollDx, p.rollDy = dx, dy
  p.roll, p.inv, p.rollCd = .32, .38, .75
  p.rollDur = p.roll
  p.face = atan2(dy, dx)
  burst(p.x, p.y, .1, 6, { .5, .48, .5 }, 2, 3, .4)
  play("roll")
end

local function doSpin()
  local p = player
  if p.spinCd > 0 or p.roll > 0 or state ~= "play" then return end
  p.spin, p.spinCd, p.spinA = .45, p.spinMax, p.face
  effects[#effects + 1] = { kind = "ring", x = p.x, y = p.y, r = p.spinR, t = 0, dur = .4 }
  addShake(.3)
  play("slam", .1, .7)
  for _, e in ipairs(enemies) do
    if not e.dead then
      local dx, dy = e.x - p.x, e.y - p.y
      if len(dx, dy) < p.spinR + e.r then
        local dmg, crit = rollDamage(p.dmg * 1.6)
        local nx, ny = norm(dx, dy)
        damageEnemy(e, dmg, nx, ny, 13, crit, 11)
      end
    end
  end
end

local function doPotion()
  local p = player
  if p.potionCd > 0 or state ~= "play" then return end
  local heal = floor(p.maxhp * .4)
  p.hp = min(p.maxhp, p.hp + heal)
  p.potionCd = p.potionMax
  addText(p.x, p.y, "+" .. heal, { .4, 1, .5 }, true)
  burst(p.x, p.y, .6, 14, { .3, 1, .5 }, 2.5, 3, .7)
  play("pick", .1)
end

-------------------------------------------------------------------------------
-- 업데이트
-------------------------------------------------------------------------------
local function updatePlayer(dt)
  local p = player
  p.atkCd = p.atkCd - dt
  p.comboT = p.comboT - dt
  p.swingT = max(0, p.swingT - dt)
  p.rollCd = p.rollCd - dt
  p.inv = p.inv - dt
  p.potionCd = max(0, p.potionCd - dt)
  p.spinCd = max(0, p.spinCd - dt)
  p.shootCd = p.shootCd - dt
  p.flash = max(0, p.flash - dt)
  p.aimT = p.aimT - dt
  p.shootT = (p.shootT or 0) - dt

  local ix, iy = 0, 0
  if keyDown("a", "left") then ix = ix - 1 end
  if keyDown("d", "right") then ix = ix + 1 end
  if keyDown("w", "up") then iy = iy - 1 end
  if keyDown("s", "down") then iy = iy + 1 end
  -- 화면 기준 방향을 월드 방향으로 (화면 위 = 월드 (-1,-1))
  local dx, dy = norm(ix + iy, iy - ix)
  p.mvx, p.mvy = dx, dy
  local mx, my = mouseWorld()
  local aim = atan2(my - p.y, mx - p.x)

  if p.roll > 0 then
    p.roll = p.roll - dt
    p.x, p.y = p.x + p.rollDx * 9.6 * dt, p.y + p.rollDy * 9.6 * dt   -- 거리는 예전과 같게 (0.32초)
    p.moving = false
  else
    local spd = p.speed
    if p.swingT > 0 then spd = spd * .45 end
    if p.spin > 0 then spd = spd * .75 end
    p.x, p.y = p.x + dx * spd * dt, p.y + dy * spd * dt
    p.moving = dx ~= 0 or dy ~= 0
    if p.moving then
      p.walk = p.walk + dt * 11
      if p.aimT <= 0 and p.spin <= 0 then p.face = turn(p.face, atan2(dy, dx), dt * 16) end
    end
  end
  if p.spin > 0 then p.spin = p.spin - dt; p.spinA = p.spinA + dt * 26 end
  p.x, p.y = p.x + p.kx * dt, p.y + p.ky * dt
  local k = max(0, 1 - dt * 10)
  p.kx, p.ky = p.kx * k, p.ky * k
  collide(p)

  if p.roll <= 0 and p.spin <= 0 then
    if mouseDown(1) and p.atkCd <= 0 then doSwing(aim)
    elseif mouseDown(2) and p.shootCd <= 0 and p.swingT <= 0 then doShoot(aim) end
  end
end

local function chaseDir(e, d)
  local tx, ty = floor(e.x), floor(e.y)
  local own = flow[ty] and flow[ty][tx]
  if (own and own <= 1) or d < 1.5 or not own then return norm(player.x - e.x, player.y - e.y) end
  local best, bxx, byy = own, nil, nil
  for dy = -1, 1 do
    for dx = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        local v = flow[ty + dy] and flow[ty + dy][tx + dx]
        if v and v < best and (dx == 0 or dy == 0 or (not solid(tx + dx, ty) and not solid(tx, ty + dy))) then
          best, bxx, byy = v, tx + dx, ty + dy
        end
      end
    end
  end
  if bxx then return norm(bxx + .5 - e.x, byy + .5 - e.y) end
  return norm(player.x - e.x, player.y - e.y)
end

local function updateEnemy(e, dt)
  local T, p = e.T, player
  e.flash = max(0, e.flash - dt)
  e.hpShow = max(0, (e.hpShow or 0) - dt)
  e.cd, e.cd2 = e.cd - dt, e.cd2 - dt
  local dx, dy = p.x - e.x, p.y - e.y
  local d = len(dx, dy)
  local toP = atan2(dy, dx)
  local mvx, mvy, spd = 0, 0, 0

  if e.stun > 0 then
    e.stun = e.stun - dt
  elseif e.state == "chase" then
    if e.kind == "grunt" then
      if d > T.range * .8 then mvx, mvy = chaseDir(e, d); spd = T.speed
      elseif e.cd <= 0 then e.state, e.t, e.aim = "windup", T.windup, toP end
      e.face = turn(e.face, (spd > 0) and atan2(mvy, mvx) or toP, dt * 9)
    elseif e.kind == "archer" then
      local see = d < 9 and los(e.x, e.y, p.x, p.y)
      if not see or d > 6.5 then mvx, mvy = chaseDir(e, d); spd = T.speed
      elseif d < 3.5 then mvx, mvy = norm(-dx, -dy); spd = T.speed * .9
      else mvx, mvy = norm(-dy * e.strafe, dx * e.strafe); spd = T.speed * .45 end
      if see and d < 7.5 and e.cd <= 0 then e.state, e.t, e.aim = "windup", T.windup, toP end
      e.face = turn(e.face, toP, dt * 8)
    else -- brute
      if d < T.range + .3 and e.cd2 <= 0 then
        e.state, e.t, e.cd2 = "slam", .75, 3
      elseif d < 6.5 and d > 2.2 and e.cd <= 0 and los(e.x, e.y, p.x, p.y) then
        e.state, e.t, e.aim = "windup", T.windup, toP
      else
        mvx, mvy = chaseDir(e, d); spd = T.speed
      end
      e.face = turn(e.face, toP, dt * 5)
    end
  elseif e.state == "windup" then
    e.t = e.t - dt
    if e.kind == "grunt" then e.aim = turn(e.aim, toP, dt * 2) end
    if e.kind == "archer" then e.aim = turn(e.aim, toP, dt * 3) end
    e.face = e.aim
    if e.t <= 0 then
      if e.kind == "grunt" then
        if d < T.range + p.r + .15 and abs(angDiff(toP, e.aim)) < 1.0 then
          hurtPlayer(T.dmg, cos(e.aim), sin(e.aim), 7)
        end
        effects[#effects + 1] = { kind = "arc", x = e.x, y = e.y, ang = e.aim, range = T.range + .2, half = 1.0, side = 1,
          t = 0, dur = .16, enemy = true }
        e.kx, e.ky = e.kx + cos(e.aim) * 3, e.ky + sin(e.aim) * 3
        e.state, e.t, e.cd = "recover", .4, T.cd
      elseif e.kind == "archer" then
        projs[#projs + 1] = { owner = "enemy", x = e.x + cos(e.aim) * .4, y = e.y + sin(e.aim) * .4, z = .8,
          vx = cos(e.aim) * 6.5, vy = sin(e.aim) * 6.5, r = .2, dmg = T.dmg, life = 3 }
        play("shoot", .2, .5)
        e.state, e.t, e.cd = "recover", .35, T.cd * (.8 + rnd() * .4)
      else
        e.state, e.t, e.hitDone = "dash", .55, false
        play("roll", .1, 1)
      end
    end
  elseif e.state == "dash" then
    e.t = e.t - dt
    mvx, mvy, spd = cos(e.aim), sin(e.aim), 10
    if rnd() < .5 then burst(e.x, e.y, .1, 1, { .45, .42, .45 }, 1.5, 4, .5) end
    if not e.hitDone and d < e.r + p.r + .2 then
      hurtPlayer(T.dmg, mvx, mvy, 13, 10)
      e.hitDone = true
    end
    if e.t <= 0 then e.state, e.t, e.cd = "recover", .6, T.cd end
  elseif e.state == "slam" then
    e.t = e.t - dt
    if e.t <= 0 then
      if d < 2.1 then hurtPlayer(T.dmg, dx / max(d, .01), dy / max(d, .01), 10, 10) end
      effects[#effects + 1] = { kind = "ring", x = e.x, y = e.y, r = 2.1, t = 0, dur = .35, enemy = true }
      burst(e.x, e.y, .1, 20, { .45, .4, .4 }, 5, 4, .6)
      addShake(.4)
      play("slam")
      e.state, e.t = "recover", .7
    end
  elseif e.state == "recover" then
    e.t = e.t - dt
    if e.t <= 0 then e.state = "chase" end
  end

  local ox, oy = e.x, e.y
  e.x, e.y = e.x + (mvx * spd + e.kx) * dt, e.y + (mvy * spd + e.ky) * dt
  local k = max(0, 1 - dt * 8)
  e.kx, e.ky = e.kx * k, e.ky * k
  e.moving = spd > 0
  if spd > 0 then e.walk = e.walk + dt * spd * 3.4 end
  collide(e)
  -- 돌진하다 벽에 박으면 잠깐 기절
  if e.state == "dash" and len(e.x - ox, e.y - oy) < spd * dt * .3 then
    e.state, e.t, e.cd = "recover", 1.0, T.cd
    addShake(.35)
    burst(e.x, e.y, .8, 12, { .6, .58, .6 }, 3, 4, .5)
    play("slam", .2, .6)
  end
end

local function separate()
  local n = #enemies
  for i = 1, n do
    local a = enemies[i]
    for j = i + 1, n do
      local b = enemies[j]
      local dx, dy = b.x - a.x, b.y - a.y
      local rr = a.r + b.r
      local d2 = dx * dx + dy * dy
      if d2 < rr * rr and d2 > 1e-6 then
        local d = sqrt(d2)
        local push = (rr - d)
        local wa = b.T.mass / (a.T.mass + b.T.mass)
        local nx, ny = dx / d, dy / d
        a.x, a.y = a.x - nx * push * wa, a.y - ny * push * wa
        b.x, b.y = b.x + nx * push * (1 - wa), b.y + ny * push * (1 - wa)
      end
    end
    -- 플레이어와 겹치지 않게 (적이 주로 밀려남)
    local p = player
    local dx, dy = a.x - p.x, a.y - p.y
    local rr = a.r + p.r
    local d2 = dx * dx + dy * dy
    if d2 < rr * rr and d2 > 1e-6 and p.roll <= 0 then
      local d = sqrt(d2)
      local push = rr - d
      a.x, a.y = a.x + dx / d * push * .8, a.y + dy / d * push * .8
      p.x, p.y = p.x - dx / d * push * .2, p.y - dy / d * push * .2
    end
  end
end

local function findSpawnPoint()
  for _ = 1, 60 do
    local x, y = rnd(3, MW - 2), rnd(3, MH - 2)
    if reach[y][x] and not solid(x, y) then
      local d = len(x + .5 - player.x, y + .5 - player.y)
      if d > 8 and d < 15 then return x + .5, y + .5 end
    end
  end
  for _ = 1, 200 do
    local x, y = rnd(3, MW - 2), rnd(3, MH - 2)
    if reach[y][x] and not solid(x, y) and len(x + .5 - player.x, y + .5 - player.y) > 5 then return x + .5, y + .5 end
  end
  return nil
end

local function newEnemy(kind, x, y)
  local T = TYPES[kind]
  local hpMul = 1 + (wave - 1) * .12
  enemies[#enemies + 1] = {
    kind = kind, T = T, x = x, y = y, r = T.r, hp = T.hp * hpMul, maxhp = T.hp * hpMul,
    face = atan2(player.y - y, player.x - x), state = "chase", t = 0, cd = .5 + rnd() * T.cd, cd2 = 1,
    stun = 0, flash = 0, kx = 0, ky = 0, walk = rnd() * 6, aim = 0, hpShow = 0, moving = false,
    strafe = rnd() < .5 and 1 or -1, ph = rnd() * 10,
    -- 마리마다 다른 생김새 (결투 오크처럼: 피부 톤, 송곳니, 배, 머리, 흉터, 목걸이)
    look = {
      skin = { T.skin[1] * (.88 + rnd() * .24), T.skin[2] * (.88 + rnd() * .24), T.skin[3] * (.88 + rnd() * .24) },
      cloth = T.cloth, eye = T.eye, horns = (kind == "brute" or rnd() < .3) and T.horns or nil,
      tusk = .7 + rnd() * .7, belly = rnd(0, 6), hair = rnd(0, 2), scar = rnd() < .3, necklace = rnd() < .25,
    },
  }
  burst(x, y, .5, 14, { .35, .1, .45 }, 3, 4, .6)
end

local function openLevelUp()
  state = "levelup"
  lvChoices = {}
  local pool = {}
  for i = 1, #UPGRADES do pool[i] = i end
  for i = 1, 3 do
    local j = rnd(i, #pool)
    pool[i], pool[j] = pool[j], pool[i]
    lvChoices[i] = UPGRADES[pool[i]]
  end
  play("level")
end

local function chooseUpgrade(i)
  local u = lvChoices[i]
  if not u then return end
  u.apply(player)
  pendingLv = pendingLv - 1
  addText(player.x, player.y, u.name, { 1, .9, .4 }, true)
  if pendingLv > 0 then openLevelUp() else state = "play" end
end

-- 투사체 : 히트스톱과 상관없이 계속 날아간다
local function updateProjs(dt)
  for i = #projs, 1, -1 do
    local b = projs[i]
    b.life = b.life - dt
    b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
    local dead = b.life <= 0
    if solidAt(b.x, b.y) then
      dead = true
      burst(b.x, b.y, b.z, 5, b.owner == "player" and { .8, .7, .5 } or { .7, .3, 1 }, 2, 3, .3)
    end
    if not dead then
      if b.owner == "player" then
        for _, e in ipairs(enemies) do
          if not e.dead and not b.hit[e] and len(e.x - b.x, e.y - b.y) < e.r + b.r then
            b.hit[e] = true
            local dmg, crit = rollDamage(b.dmg)
            local nx, ny = norm(b.vx, b.vy)
            damageEnemy(e, dmg, nx, ny, 4, crit, 5)
            b.pierce = b.pierce - 1
            if b.pierce <= 0 then dead = true; break end
          end
        end
      else
        local p = player
        if len(p.x - b.x, p.y - b.y) < p.r + b.r and p.roll <= 0 and p.inv <= 0 then
          local nx, ny = norm(b.vx, b.vy)
          hurtPlayer(b.dmg, nx, ny, 5)
          dead = true
        end
      end
    end
    if dead then table.remove(projs, i) end
  end
end

local function updateWorld(dt)
  -- 떨어진 물건
  local p = player
  for i = #drops, 1, -1 do
    local o = drops[i]
    o.t = o.t + dt
    o.vz = o.vz - 20 * dt
    o.z = o.z + o.vz * dt
    if o.z < .15 then o.z, o.vz = .15, -o.vz * .35 end
    local dx, dy = p.x - o.x, p.y - o.y
    local d = len(dx, dy)
    local mag = o.kind == "exp" and 3.5 or 1.8
    if o.t > .45 and (d < mag or (o.kind == "exp" and o.t > 9)) then
      local sp = 9 + o.t * 2
      o.vx, o.vy = dx / max(d, .01) * sp, dy / max(d, .01) * sp
    else
      local k = max(0, 1 - dt * 4)
      o.vx, o.vy = o.vx * k, o.vy * k
    end
    o.x, o.y = o.x + o.vx * dt, o.y + o.vy * dt
    if o.t > .3 and d < .45 then
      if o.kind == "exp" then
        p.exp = p.exp + o.v
        play("pick", .3, .45)
        while p.exp >= p.nextExp do
          p.exp = p.exp - p.nextExp
          p.level = p.level + 1
          p.nextExp = floor(p.nextExp * 1.35 + 3)
          pendingLv = pendingLv + 1
        end
      elseif o.kind == "hp" then
        p.hp = min(p.maxhp, p.hp + 25)
        addText(p.x, p.y, "+25", { .4, 1, .5 })
        play("pick", .1)
      else
        p.arrows = p.arrows + 6
        addText(p.x, p.y, "화살 +6", { .9, .85, .6 })
        play("pick", .1)
      end
      table.remove(drops, i)
    end
  end
  -- 소환 예고
  for i = #spawns, 1, -1 do
    local s = spawns[i]
    s.t = s.t - dt
    if s.t <= 0 then
      newEnemy(s.kind, s.x, s.y)
      table.remove(spawns, i)
    end
  end
  -- 웨이브
  if #waveQueue > 0 then
    spawnT = spawnT - dt
    if spawnT <= 0 and #enemies < 40 then
      local n = min(#waveQueue, rnd(1, 3))
      local sx, sy = findSpawnPoint()
      if sx then
        for _ = 1, n do
          local kind = table.remove(waveQueue)
          local ox, oy = (rnd() - .5) * 1.4, (rnd() - .5) * 1.4
          local x, y = sx + ox, sy + oy
          if solidAt(x, y) then x, y = sx, sy end
          spawns[#spawns + 1] = { kind = kind, x = x, y = y, t = 1.1, dur = 1.1 }
        end
        play("spawn", .2, .6)
      end
      spawnT = max(.55, 2.3 - wave * .12)
    end
  elseif #enemies == 0 and #spawns == 0 then
    breakT = breakT - dt
    if breakT <= 0 then
      startWave(wave + 1)
      breakT = 4
    end
  end
end

-- 글자·배너 (히트스톱 중에도 움직인다)
local function updateTexts(dt)
  for i = #texts, 1, -1 do
    local t = texts[i]
    t.t = t.t + dt
    t.z = t.z + dt * 1.6
    t.x = t.x + t.vx * dt
    if t.t >= t.life then table.remove(texts, i) end
  end
  if banner.t > 0 then banner.t = banner.t - dt end
end

-- 파편·칼 궤적 (히트스톱 중엔 그 자리에 멈춘다)
local function updateFx(dt)
  for i = #pts, 1, -1 do
    local q = pts[i]
    q.t = q.t + dt
    q.vz = q.vz - q.grav * dt
    q.x, q.y, q.z = q.x + q.vx * dt, q.y + q.vy * dt, q.z + q.vz * dt
    if q.z < 0 then q.z, q.vz = 0, -q.vz * .3; q.vx, q.vy = q.vx * .6, q.vy * .6 end
    if q.t >= q.life then table.remove(pts, i) end
  end
  for i = #effects, 1, -1 do
    local f = effects[i]
    f.t = f.t + dt
    if f.t >= f.dur then table.remove(effects, i) end
  end
end

local function updateCamera(dt)
  local p = player
  local tx, ty = p.x, p.y
  if state == "play" and not AUTO then
    local mx, my = mouseWorld()
    local lx, ly = mx - p.x, my - p.y
    local l = len(lx, ly)
    if l > 4 then lx, ly = lx / l * 4, ly / l * 4 end
    tx, ty = tx + lx * .18, ty + ly * .18
  end
  local k = 1 - math.exp(-dt * 7)
  cam.x, cam.y = lerp(cam.x, tx, k), lerp(cam.y, ty, k)
  cam.sx, cam.sy = proj(cam.x, cam.y, 0)
  shake = max(0, shake - dt * 1.6)
end

local function updatePlay(dt)
  local rawDt = dt   -- 히트스톱은 느린 화면과 상관없이 정해진 프레임만큼만 멈춘다
  if freeze <= 0 and slowTimer > 0 then slowTimer = slowTimer - dt; dt = dt * 0.3
  elseif slowTimer > 0 then dt = dt * 0.3 end
  gameTime = gameTime + dt
  updateTexts(dt)
  updateProjs(dt)   -- 화살·원귀 탄은 히트스톱 중에도 날아간다

  if freeze > 0 then
    -- 히트스톱: 나, 적, 파편, 칼 궤적이 그 자리에 멈춘다 (투사체 제외)
    freeze = freeze - rawDt
    if freeze < 1e-6 then freeze = 0 end
  else
    local ptx, pty = floor(player.x), floor(player.y)
    if ptx ~= flowTx or pty ~= flowTy then
      buildFlow(ptx, pty)
      flowTx, flowTy = ptx, pty
    end
    updatePlayer(dt)
    for _, e in ipairs(enemies) do updateEnemy(e, dt) end
    separate()
    for i = #enemies, 1, -1 do if enemies[i].dead then table.remove(enemies, i) end end
    updateWorld(dt)
    updateFx(dt)
  end
  if pendingLv > 0 and state == "play" and freeze <= 0 then openLevelUp() end
end

-------------------------------------------------------------------------------
-- 그리기
-------------------------------------------------------------------------------
local items = {}
local function addItem(k, kind, o)
  items[#items + 1] = { k = k, kind = kind, o = o }
end

local function groundEllipse(mode, x, y, r)
  local sx, sy = proj(x, y, 0)
  lg.ellipse(mode, sx, sy, r * HW * R2, r * HH * R2, 32)
end

-- 바닥에 그리는 부채꼴 (조각 사각형으로 나눠 그림)
local function groundSector(x, y, r0, r1, a0, a1, z)
  local n = max(4, floor(abs(a1 - a0) * 10))
  for i = 0, n - 1 do
    local t0, t1 = a0 + (a1 - a0) * i / n, a0 + (a1 - a0) * (i + 1) / n
    local ax, ay = proj(x + cos(t0) * r0, y + sin(t0) * r0, z)
    local bbx, bby = proj(x + cos(t0) * r1, y + sin(t0) * r1, z)
    local ccx, ccy = proj(x + cos(t1) * r1, y + sin(t1) * r1, z)
    local ddx, ddy = proj(x + cos(t1) * r0, y + sin(t1) * r0, z)
    lg.polygon("fill", ax, ay, bbx, bby, ccx, ccy, ddx, ddy)
  end
end

local STONE = {}
local function drawWall(o)
  local a = o.fade and .3 or 1
  local s = shade[o.y][o.x]
  local base = .46 + s * .1
  if o.lan then
    local cx, cy = o.x + .5, o.y + .5
    drawBox(cx, cy, 0, .42, .42, .5, 0, { .5, .49, .52 }, a)
    drawBox(cx, cy, .5, .32, .32, .24, 0, { 1, .7, .3 }, a, 0, true)
    drawBox(cx, cy, .74, .6, .6, .1, 0, { .44, .43, .47 }, a)
    drawBox(cx, cy, .84, .2, .2, .1, 0, { .44, .43, .47 }, a)
    return
  end
  STONE[1], STONE[2], STONE[3] = base * .92, base * .92, base * 1.05
  if o.h >= 2 and o.x > 2 and o.y > 2 then
    -- 기둥 : 몸통 + 머리장식
    drawBox(o.x + .5, o.y + .5, 0, .8, .8, o.h - .2, 0, STONE, a)
    drawBox(o.x + .5, o.y + .5, o.h - .2, 1, 1, .2, 0, { base * .8, base * .78, base * .9 }, a)
  else
    drawBox(o.x + .5, o.y + .5, 0, 1, 1, o.h, 0, STONE, a)
    if s > .8 and o.h <= 1 then
      -- 이끼 낀 윗면
      drawBox(o.x + .5, o.y + .5, o.h, .7, .6, .04, 0, { .3, .45, .25 }, a)
    end
  end
end

-- 캐릭터는 결투 디자인을 8방향으로 (chars.lua 의 3D 뼈대). 몸은 8방향으로 끊어서 돈다
local CHAR_SC = .52   -- 결투 그림 크기 → 월드 픽셀
local function snap8(a) return floor(a / (pi / 4) + .5) * (pi / 4) end

local heroO = {}
local function drawPlayer(p)
  local o = heroO
  o.tm, o.fl = love.timer.getTime(), p.flash > 0
  o.face, o.walk, o.moving, o.idle = snap8(p.face), p.walk, p.moving, not p.moving
  o.crouch, o.stride, o.lean, o.mode, o.t, o.side, o.tuck, o.windGlow = 0, 0, 0, "idle", 0, 1, false, false
  if p.moving then o.stride = sin(p.walk) * .9; o.lean = .12 end
  if p.swingT > 0 then
    o.mode = p.swingHeavy and "heavy" or "slash"
    o.t, o.side, o.lean, o.crouch = 1 - p.swingT / p.swingDur, p.swingSide, .2, 4
  elseif p.spin > 0 then
    o.mode, o.face, o.crouch = "spin", p.spinA, 6     -- 회전베기는 끊지 않고 계속 돈다
  elseif (p.shootT or 0) > 0 then
    o.mode = "shoot"
  end
  local rollK
  if p.roll > 0 then
    rollK = 1 - p.roll / p.rollDur
    o.mode, o.crouch, o.stride, o.tuck = "roll", 20, 0, true
  end
  local sx, sy = proj(p.x, p.y, 0)
  local blink = p.inv > 0 and p.roll <= 0 and (floor(gameTime * 20) % 2 == 0)
  lg.push()
  lg.translate(sx, sy)
  lg.scale(CHAR_SC, CHAR_SC)
  if rollK then
    -- 덤블링: 몸을 웅크려 구르는 방향으로 한 바퀴 (살짝 떠오른다)
    local sgn = (cos(p.face) - sin(p.face)) >= 0 and 1 or -1
    local cy = -48
    lg.translate(0, cy - sin(rollK * pi) * 22)
    lg.rotate(rollK * pi * 2 * sgn)
    lg.translate(0, -cy)
  end
  Chars.withAlpha(blink and .35 or 1, Chars.hero, o)
  lg.pop()
end

local enemyO = {}
local function drawEnemy(e)
  local T = e.T
  local o = enemyO
  o.tm, o.fl = love.timer.getTime(), e.flash > 0
  o.face, o.walk, o.moving = snap8(e.face), e.walk, e.moving
  o.L, o.w = e.look, T.weapon
  o.crouch, o.stride, o.lean, o.mode, o.k, o.trailA, o.glow, o.charge = 0, 0, 0, "idle", 0, 0, false, 0
  if e.moving then o.stride = sin(e.walk) * .9; o.lean = .1 end
  local st = e.state
  if e.stun > 0 then
    o.mode, o.lean = "stun", -.25
  elseif st == "windup" then
    local k = clamp(1 - e.t / T.windup, 0, 1)
    if e.kind == "grunt" then
      o.mode, o.k, o.crouch, o.glow = "raise", min(1, k * 2), 6, true
    elseif e.kind == "brute" then
      o.mode, o.crouch, o.lean, o.glow = "forward", 12, .45, true   -- 돌진 준비: 낮게 숙인다
    else
      o.charge = k
    end
  elseif st == "slam" then
    local k = clamp(1 - e.t / .75, 0, 1)
    o.mode, o.k, o.crouch, o.glow = "raise", min(1, k * 1.6), 4 + k * 6, true
  elseif st == "dash" then
    o.mode, o.lean, o.stride = "forward", .45, sin(gameTime * 30) * 1.1
  elseif st == "recover" and e.kind ~= "archer" then
    -- 막 내리친 직후: 팔을 앞으로 뻗은 채 궤적이 사라진다
    o.mode, o.lean = "strike", .22
    o.trailA = e.t > .2 and (e.t - .2) / .2 or 0
  end
  local sx, sy = proj(e.x, e.y, 0)
  lg.push()
  if e.kind == "archer" then
    lg.translate(sx, sy - 10 - sin(gameTime * 3 + e.ph) * 4)   -- 떠다닌다
    lg.scale(T.sc, T.sc)
    Chars.withAlpha(.88, Chars.caster, o)
  else
    lg.translate(sx, sy)
    lg.scale(T.sc, T.sc)
    Chars.orc(o)
  end
  lg.pop()
end

local function drawDrop(o)
  local sx, sy = proj(o.x, o.y, o.z + sin(o.t * 5) * .05)
  if o.kind == "exp" then
    lg.setColor(.4, 1, .85, 1)
    local r = 4
    lg.polygon("fill", sx, sy - r * 1.4, sx + r, sy, sx, sy + r * 1.4, sx - r, sy)
    lg.setColor(1, 1, 1, .9)
    lg.polygon("fill", sx, sy - r * .7, sx + r * .4, sy, sx, sy + r * .7, sx - r * .4, sy)
  elseif o.kind == "hp" then
    -- 고기 덩이 (결투의 음식처럼)
    lg.setColor(.75, .3, .25); lg.circle("fill", sx, sy, 6)
    lg.setColor(.95, .55, .45); lg.circle("fill", sx - 2, sy - 2, 2.5)
    lg.setColor(.92, .88, .8); lg.setLineWidth(3); lg.line(sx + 4, sy + 3, sx + 10, sy + 7)
    lg.setLineWidth(1)
  else
    -- 화살 묶음
    lg.setLineWidth(1.6)
    for k = -1, 1 do
      lg.setColor(.6, .45, .25); lg.line(sx - 9, sy + 3 + k * 2, sx + 9, sy - 3 + k * 2)
      lg.setColor(.95, .95, .95); lg.line(sx - 9, sy + 3 + k * 2, sx - 5, sy + 1 + k * 2)
    end
    lg.setColor(.4, .25, .15); lg.setLineWidth(2.5); lg.line(sx, sy - 3, sx, sy + 3)
    lg.setLineWidth(1)
  end
end

local function drawProj(b)
  if b.owner == "player" then
    cpart(b.x, b.y, b.z, .05, .55, .05, b.ang, { .82, .7, .5 })
    cpart(b.x - cos(b.ang) * .25, b.y - sin(b.ang) * .25, b.z - .02, .14, .1, .09, b.ang, { .95, .95, .95 })
    flushParts(1, 0)
  else
    local sx, sy = proj(b.x, b.y, b.z)
    lg.setColor(.55, .2, .85, 1)
    lg.circle("fill", sx, sy, 6)
    lg.setColor(1, .8, 1, 1)
    lg.circle("fill", sx, sy, 3)
  end
end

local function drawParticle(q)
  local sx, sy = proj(q.x, q.y, q.z)
  local k = 1 - q.t / q.life
  lg.setColor(q.col[1], q.col[2], q.col[3], k)
  local s = q.size * (.5 + k * .5)
  lg.rectangle("fill", sx - s / 2, sy - s / 2, s, s)
end

local function drawSpawn(s)
  local k = 1 - s.t / s.dur
  lg.setColor(.25, .05, .35, .55 * k + .1)
  groundEllipse("fill", s.x, s.y, .2 + .5 * k)
  lg.setColor(.7, .3, 1, .6)
  local sx, sy = proj(s.x, s.y, 0)
  for i = 0, 5 do
    local a = gameTime * 5 + i * pi / 3
    local r = .6 * (1 - k) + .15
    local ax, ay = proj(s.x + cos(a) * r, s.y + sin(a) * r, k * .6)
    lg.rectangle("fill", ax - 2, ay - 2, 4, 4)
  end
end

local function drawWorld()
  -- 바닥
  lg.setColor(1, 1, 1, 1)
  lg.draw(floorMesh)

  -- 화면에 보이는 범위
  local vw, vh = W / ZOOM / 2 + 90, H / ZOOM / 2 + 140
  local function visible(sx, sy) return abs(sx - cam.sx) < vw and abs(sy - cam.sy) < vh end

  -- 그림자 / 소환 예고
  lg.setColor(0, 0, 0, .35)
  if state ~= "dead" then groundEllipse("fill", player.x, player.y, player.r * 1.1) end
  for _, e in ipairs(enemies) do
    lg.setColor(0, 0, 0, .35)
    groundEllipse("fill", e.x, e.y, e.r * 1.15)
  end
  for _, o in ipairs(drops) do lg.setColor(0, 0, 0, .25); groundEllipse("fill", o.x, o.y, .12) end
  for _, s in ipairs(spawns) do drawSpawn(s) end

  -- 앞뒤 정렬해서 그리는 것들
  for i = #items, 1, -1 do items[i] = nil end
  local pk = player.x + player.y
  for y = 1, MH do
    for x = 1, MW do
      local h = map[y][x]
      if h > 0 then
        local sx, sy = proj(x + .5, y + .5, 0)
        if visible(sx, sy) then
          local k = x + y + 1
          local fade = k > pk + .3 and len(x + .5 - player.x, y + .5 - player.y) < 2.6 and h >= .9
          addItem(k, "wall", { x = x, y = y, h = h, lan = lantern[y][x], fade = fade })
        end
      end
    end
  end
  if state ~= "dead" then addItem(pk, "player", player) end
  for _, e in ipairs(enemies) do addItem(e.x + e.y, "enemy", e) end
  for _, o in ipairs(drops) do addItem(o.x + o.y, "drop", o) end
  for _, b in ipairs(projs) do addItem(b.x + b.y, "proj", b) end
  for _, q in ipairs(pts) do addItem(q.x + q.y, "pt", q) end
  table.sort(items, sortK)
  for _, it in ipairs(items) do
    local kd = it.kind
    if kd == "wall" then drawWall(it.o)
    elseif kd == "player" then drawPlayer(it.o)
    elseif kd == "enemy" then drawEnemy(it.o)
    elseif kd == "drop" then drawDrop(it.o)
    elseif kd == "proj" then drawProj(it.o)
    else drawParticle(it.o) end
  end
end

-- 빛 지도 : 어두운 바탕에 빛을 더해서, 화면에 곱한다
local function renderLights()
  lg.push()
  lg.origin()
  lg.setCanvas(lightCanvas)
  lg.clear(.38, .36, .5, 1)
  lg.setBlendMode("add")
  local function light(x, y, z, r, cr, cg, cb)
    local gx, gy = worldToGame(x, y, z)
    local s = r * ZOOM / 64
    lg.setColor(cr, cg, cb, 1)
    lg.draw(glowImg, gx, gy, 0, s, s * .62, 64, 64)
  end
  if state ~= "dead" then light(player.x, player.y, .3, 300, .75, .66, .5) end
  for _, l in ipairs(lanterns) do
    local f = .85 + sin(gameTime * 7 + l.ph) * .06 + sin(gameTime * 13 + l.ph) * .04
    light(l.x, l.y, .6, 230, .8 * f, .5 * f, .2 * f)
  end
  for _, b in ipairs(projs) do
    if b.owner == "enemy" then light(b.x, b.y, b.z, 80, .5, .15, .7) end
  end
  for _, s in ipairs(spawns) do light(s.x, s.y, 0, 90, .35, .1, .5) end
  for _, e in ipairs(enemies) do
    if e.kind == "archer" then light(e.x, e.y, .8, 70, .15, .3, .4) end
  end
  for _, f in ipairs(effects) do
    if f.kind == "ring" and not f.enemy then light(f.x, f.y, .3, 200 * (1 - f.t / f.dur), .6, .6, .7) end
  end
  lg.setBlendMode("alpha")
  lg.setCanvas()
  lg.pop()
end

local function drawTelegraphs()
  for _, e in ipairs(enemies) do
    local T = e.T
    if e.state == "windup" then
      local k = clamp(1 - e.t / T.windup, 0, 1)
      if e.kind == "grunt" then
        lg.setColor(1, .15, .1, .18)
        groundSector(e.x, e.y, 0, T.range + .2, e.aim - 1.0, e.aim + 1.0, .02)
        lg.setColor(1, .2, .1, .35)
        groundSector(e.x, e.y, 0, (T.range + .2) * k, e.aim - 1.0, e.aim + 1.0, .02)
      elseif e.kind == "archer" then
        lg.setColor(.8, .3, 1, .25 + k * .3)
        lg.setLineWidth(2 / ZOOM)
        local ax, ay = proj(e.x, e.y, .05)
        local bbx, bby = proj(e.x + cos(e.aim) * 7, e.y + sin(e.aim) * 7, .05)
        lg.line(ax, ay, bbx, bby)
        lg.setLineWidth(1)
      else
        local L = 5.5
        local ux, uy = cos(e.aim), sin(e.aim)
        local vx, vy = -uy * e.r, ux * e.r
        local function q(t, a)
          local ax, ay = proj(e.x + vx, e.y + vy, .02)
          local bbx, bby = proj(e.x - vx, e.y - vy, .02)
          local ccx, ccy = proj(e.x - vx + ux * L * t, e.y - vy + uy * L * t, .02)
          local ddx, ddy = proj(e.x + vx + ux * L * t, e.y + vy + uy * L * t, .02)
          lg.setColor(1, .15, .1, a)
          lg.polygon("fill", ax, ay, bbx, bby, ccx, ccy, ddx, ddy)
        end
        q(1, .16)
        q(k, .32)
      end
    elseif e.state == "slam" then
      local k = clamp(1 - e.t / .75, 0, 1)
      lg.setColor(1, .15, .1, .16)
      groundEllipse("fill", e.x, e.y, 2.1)
      lg.setColor(1, .2, .1, .3)
      groundEllipse("fill", e.x, e.y, 2.1 * k)
    end
  end
end

local function drawEffects()
  lg.setBlendMode("add")
  for _, f in ipairs(effects) do
    local k = f.t / f.dur
    if f.kind == "arc" then
      local t = 1 - (1 - k) ^ 2
      local a0 = f.ang - f.side * f.half
      local a1 = f.ang + f.side * f.half * (-1 + 2 * t)
      if f.enemy then lg.setColor(1, .3, .2, .5 * (1 - k))
      else lg.setColor(1, f.heavy and .85 or 1, f.heavy and .55 or .9, .65 * (1 - k)) end
      local lo, hi = min(a0, a1), max(a0, a1)
      groundSector(f.x, f.y, f.range * .45, f.range, lo, hi, .5)
    elseif f.kind == "ring" then
      if f.enemy then lg.setColor(1, .45, .3, .6 * (1 - k)) else lg.setColor(.75, .85, 1, .7 * (1 - k)) end
      local r = f.r * (.3 + .7 * k)
      groundSector(f.x, f.y, r * .82, r, 0, pi * 2, .3)
    end
  end
  -- 빛나는 것들
  for _, l in ipairs(lanterns) do
    local gx, gy = proj(l.x, l.y, .62)
    lg.setColor(1, .6, .25, .35)
    lg.draw(glowImg, gx, gy, 0, .45, .45, 64, 64)
  end
  for _, b in ipairs(projs) do
    if b.owner == "enemy" then
      local gx, gy = proj(b.x, b.y, b.z)
      lg.setColor(.7, .3, 1, .6)
      lg.draw(glowImg, gx, gy, 0, .3, .3, 64, 64)
    end
  end
  for _, o in ipairs(drops) do
    if o.kind == "exp" then
      local gx, gy = proj(o.x, o.y, o.z)
      lg.setColor(.3, 1, .8, .35)
      lg.draw(glowImg, gx, gy, 0, .2, .2, 64, 64)
    end
  end
  lg.setBlendMode("alpha")
end

local function drawOverlayTexts()
  -- 적 체력바
  for _, e in ipairs(enemies) do
    if e.hpShow > 0 or e.kind == "brute" then
      local gx, gy = worldToGame(e.x, e.y, (e.kind == "archer" and 115 or 140) * e.T.sc / TZ)
      local w = e.kind == "brute" and 46 or 30
      lg.setColor(0, 0, 0, .6)
      lg.rectangle("fill", gx - w / 2 - 1, gy - 1, w + 2, 6)
      lg.setColor(.9, .2, .2, 1)
      lg.rectangle("fill", gx - w / 2, gy, w * max(0, e.hp / e.maxhp), 4)
    end
  end
  for _, t in ipairs(texts) do
    local gx, gy = worldToGame(t.x, t.y, t.z)
    local a = 1 - (t.t / t.life) ^ 2
    lg.setColor(t.col[1], t.col[2], t.col[3])
    local f = t.big and fontM or fontS
    txt(t.s, gx - 60, gy, f, "center", 120, a)
  end
end

local function skillIcon(x, y, key, label, cdFrac, sub)
  lg.setColor(0, 0, 0, .6)
  lg.rectangle("fill", x, y, 50, 50, 6)
  lg.setColor(1, 1, 1, cdFrac > 0 and .3 or .85)
  lg.setLineWidth(2)
  lg.rectangle("line", x, y, 50, 50, 6)
  lg.setLineWidth(1)
  lg.setColor(1, 1, 1, cdFrac > 0 and .5 or 1)
  txt(label, x, y + 15, fontS, "center", 50)
  if cdFrac > 0 then
    lg.setColor(0, 0, 0, .55)
    lg.rectangle("fill", x, y + 50 * (1 - cdFrac), 50, 50 * cdFrac, 6)
  end
  lg.setColor(1, .9, .5, 1)
  txt(key, x + 3, y + 1, fontS)
  if sub then lg.setColor(1, 1, 1, 1); txt(sub, x, y + 33, fontS, "right", 46) end
end

local function drawHUD()
  local p = player
  -- 체력
  local bw, bx0, by0 = 300, W / 2 - 150, H - 92
  lg.setColor(0, 0, 0, .6)
  lg.rectangle("fill", bx0 - 3, by0 - 3, bw + 6, 22, 4)
  local hk = p.hp / p.maxhp
  lg.setColor(.75 - hk * .1, .15 + hk * .15, .18, 1)
  lg.rectangle("fill", bx0, by0, bw * hk, 16, 3)
  lg.setColor(1, 1, 1, 1)
  txt(floor(p.hp) .. " / " .. floor(p.maxhp), bx0, by0, fontS, "center", bw)
  -- 스킬
  local sx = W / 2 - 112
  skillIcon(sx, H - 64, "Spc", "구르기", max(0, p.rollCd) / .75)
  skillIcon(sx + 58, H - 64, "E", "회전", p.spinCd / p.spinMax)
  skillIcon(sx + 116, H - 64, "Q", "물약", p.potionCd / p.potionMax)
  skillIcon(sx + 174, H - 64, "우", "화살", 0, tostring(p.arrows))
  -- 경험치
  lg.setColor(0, 0, 0, .6)
  lg.rectangle("fill", 0, H - 7, W, 7)
  lg.setColor(.35, 1, .8, 1)
  lg.rectangle("fill", 0, H - 6, W * p.exp / p.nextExp, 5)
  lg.setColor(.6, 1, .9, 1)
  txt("Lv " .. p.level, W / 2 - 160, H - 117, fontM)
  -- 웨이브
  lg.setColor(1, 1, 1, 1)
  local left = #enemies + #spawns + #waveQueue
  local ws = wave > 0 and ("웨이브 " .. wave .. "   남은 악귀 " .. left) or "준비"
  txt(ws, 0, 12, fontM, "center", W)
  lg.setColor(.85, .85, .9, 1)
  txt("처치 " .. kills, 14, 12, fontS)
  -- 배너
  if banner.t > 0 then
    local a = clamp(banner.t, 0, 1) * clamp((2.6 - banner.t) * 3 + .3, 0, 1)
    lg.setColor(1, .85, .55, 1)
    txt(banner.text, 0, H * .3, fontL, "center", W, a)
    if banner.sub then lg.setColor(.9, .8, .8, 1); txt(banner.sub, 0, H * .3 + 42, fontM, "center", W, a) end
  end
  -- 피 적을 때 붉은 테두리
  if hk < .35 then
    local a = (.35 - hk) * 1.6 * (.6 + sin(gameTime * 6) * .4)
    lg.setColor(.8, 0, 0, a)
    lg.setLineWidth(18)
    lg.rectangle("line", 0, 0, W, H)
    lg.setLineWidth(1)
  end
end

local function cardRect(i)
  local cw, ch = 220, 150
  local x = W / 2 - cw * 1.5 - 20 + (i - 1) * (cw + 20)
  return x, H / 2 - ch / 2 + 20, cw, ch
end

local function drawLevelUp()
  lg.setColor(0, 0, 0, .6)
  lg.rectangle("fill", 0, 0, W, H)
  lg.setColor(1, .9, .5, 1)
  txt("레벨 업! 강화를 고르세요", 0, H / 2 - 120, fontL, "center", W)
  local gx, gy = toGame(love.mouse.getPosition())
  for i, u in ipairs(lvChoices) do
    local x, y, w, h = cardRect(i)
    local hov = gx >= x and gx <= x + w and gy >= y and gy <= y + h
    lg.setColor(.12, .1, .16, .95)
    lg.rectangle("fill", x, y, w, h, 8)
    lg.setColor(hov and 1 or .6, hov and .85 or .55, hov and .4 or .45, 1)
    lg.setLineWidth(hov and 3 or 2)
    lg.rectangle("line", x, y, w, h, 8)
    lg.setLineWidth(1)
    lg.setColor(1, .9, .6, 1)
    txt(u.name, x, y + 18, fontM, "center", w)
    lg.setColor(.9, .9, .95, 1)
    txt(u.desc, x + 10, y + 56, fontS, "center", w - 20)
    lg.setColor(.7, .7, .75, 1)
    txt("[" .. i .. "]", x, y + h - 26, fontS, "center", w)
  end
end

local function drawCenterPanel(title, lines)
  lg.setColor(0, 0, 0, .55)
  lg.rectangle("fill", 0, 0, W, H)
  lg.setColor(1, .85, .5, 1)
  txt(title, 0, H * .26, fontXL, "center", W)
  lg.setColor(.92, .92, .95, 1)
  for i, l in ipairs(lines) do txt(l, 0, H * .26 + 70 + i * 26, fontM, "center", W) end
end

-------------------------------------------------------------------------------
-- LÖVE 콜백
-------------------------------------------------------------------------------
function love.load(args)
  for _, a in ipairs(args or {}) do
    if a == "--autotest" then AUTO = { t = 0, keys = {}, mouse = {}, ax = 0, ay = 0, dirT = 0, dead = 0, lv = 0 } end
  end
  io.stdout:setvbuf("no")
  lg.setDefaultFilter("linear", "linear")
  lg.setLineJoin("bevel")
  updateView()
  fontData = loadFontData()
  makeFonts()
  makeSounds()
  lightCanvas = lg.newCanvas(W, H)
  do
    local s = 128
    local id = love.image.newImageData(s, s)
    id:mapPixel(function(x, y)
      local d = len(x - s / 2 + .5, y - s / 2 + .5) / (s / 2)
      local v = clamp(1 - d, 0, 1)
      v = v * v * (3 - 2 * v)
      return v, v, v, 1
    end)
    glowImg = lg.newImage(id)
    local vd = love.image.newImageData(W / 4, H / 4)
    vd:mapPixel(function(x, y)
      local dx, dy = (x / (W / 4) - .5) * 2, (y / (H / 4) - .5) * 2
      local d = clamp(len(dx * .9, dy) - .55, 0, 1)
      return 0, 0, 0, d * d * .75
    end)
    vignette = lg.newImage(vd)
  end
  newGame()
  if AUTO then state = "play"; breakT = .5; wave = 2 end
end

function love.resize()
  updateView()
  makeFonts()
end

-- 자동 테스트 : 가짜 입력으로 몇 웨이브 돌려 보고 끝낸다
local function autoStep(dt)
  local A = AUTO
  A.t = A.t + dt
  A.dirT = A.dirT - dt
  if A.dirT <= 0 then
    A.dirT = .6 + rnd()
    A.keys = {}
    local ks = { "w", "a", "s", "d" }
    if rnd() < .8 then A.keys[ks[rnd(1, 4)]] = true end
    if rnd() < .4 then A.keys[ks[rnd(1, 4)]] = true end
  end
  local best, bd = nil, 1e9
  for _, e in ipairs(enemies) do
    local d = len(e.x - player.x, e.y - player.y)
    if d < bd then best, bd = e, d end
  end
  if best then A.ax, A.ay = best.x, best.y else A.ax, A.ay = player.x + 1, player.y end
  A.mouse[1] = bd < 2.2
  A.mouse[2] = bd >= 2.2 and bd < 8
  if rnd() < .01 then doRoll() end
  if rnd() < .01 then doSpin() end
  if player.hp < 50 then doPotion() end
  if state == "levelup" then A.lv = A.lv + 1; chooseUpgrade(rnd(1, 3)) end
  if state == "dead" then
    A.dead = A.dead + 1
    print(string.format("[자동테스트] 사망: 웨이브 %d 처치 %d 레벨 %d", wave, kills, player.level))
    newGame(); state = "play"; breakT = .5; wave = 2
  end
  if floor(A.t / 10) ~= floor((A.t - dt) / 10) then
    print(string.format("[자동테스트] %.0f초 웨이브 %d 적 %d 처치 %d 레벨 %d HP %d 투사체 %d 파티클 %d",
      A.t, wave, #enemies, kills, player.level, player.hp, #projs, #pts))
  end
  for _, st in ipairs({ 22, 66, 135 }) do
    if A.t >= st and A.t - dt < st then lg.captureScreenshot("auto_" .. st .. ".png") end
  end
  if A.t > 150 then
    print(string.format("[자동테스트] 완료: 사망 %d회 레벨업 %d회 최종 웨이브 %d", A.dead, A.lv, wave))
    print(string.format("[자동테스트] 히트스톱 %d번, 멈춘 중에 움직인 프레임 %d, 결정타 느린화면 %d번",
      A.stops or 0, A.stopMoved or 0, A.slows or 0))
    love.event.quit()
  end
end

function love.update(dt)
  dt = min(dt, 1 / 30)
  if AUTO then
    for _ = 1, 8 do
      local sdt = 1 / 60
      autoStep(sdt)
      if state == "play" then
        -- 히트스톱 점검: 멈춘 동안 나와 적이 정말 안 움직이는지, 몇 번 멈췄는지
        local was, px, py = freeze > 0, player.x, player.y
        local e1 = enemies[1]
        local ex, ey = e1 and e1.x, e1 and e1.y
        if not was and freeze <= 0 then AUTO.prevFree = true end
        updatePlay(sdt)
        if was and (player.x ~= px or player.y ~= py or (e1 and (e1.x ~= ex or e1.y ~= ey))) then
          AUTO.stopMoved = (AUTO.stopMoved or 0) + 1
        end
        if freeze > 0 and AUTO.prevFree then AUTO.stops = (AUTO.stops or 0) + 1; AUTO.prevFree = false end
        if slowTimer > 0 and not AUTO.inSlow then AUTO.slows = (AUTO.slows or 0) + 1 end
        AUTO.inSlow = slowTimer > 0
      end
      updateCamera(sdt)
    end
    return
  end
  if state == "play" then
    updatePlay(dt)
  elseif state == "title" then
    gameTime = gameTime + dt
    player.face = player.face + dt * .6
  elseif state == "dead" then
    updateFx(dt)
    updateTexts(dt)
  end
  updateCamera(dt)
end

function love.draw()
  renderLights()
  lg.clear(.05, .04, .07, 1)
  lg.push()
  lg.translate(view.x, view.y)
  lg.scale(view.s)
  lg.setScissor(view.x, view.y, W * view.s, H * view.s)

  -- 월드
  lg.push()
  local shx, shy = 0, 0
  if shake > 0 then shx, shy = (rnd() - .5) * shake * 16, (rnd() - .5) * shake * 16 end
  lg.translate(W / 2 + shx, H / 2 + shy)
  lg.scale(ZOOM)
  lg.translate(-cam.sx, -cam.sy)
  lg.setLineWidth(1 / ZOOM)
  drawWorld()
  lg.pop()

  -- 빛 곱하기
  lg.setBlendMode("multiply", "premultiplied")
  lg.setColor(1, 1, 1, 1)
  lg.draw(lightCanvas, 0, 0)
  lg.setBlendMode("alpha")

  -- 빛 위에 올라가는 것들
  lg.push()
  lg.translate(W / 2 + shx, H / 2 + shy)
  lg.scale(ZOOM)
  lg.translate(-cam.sx, -cam.sy)
  drawTelegraphs()
  drawEffects()
  lg.pop()

  lg.setColor(1, 1, 1, 1)
  lg.draw(vignette, 0, 0, 0, 4, 4)
  drawOverlayTexts()

  if state == "title" then
    drawCenterPanel("악귀 사냥꾼", {
      "WASD 이동   ·   마우스 조준   ·   좌클릭 베기 (3연격)",
      "우클릭 활   ·   Space 구르기   ·   E 회전베기   ·   Q 물약",
      "",
      "클릭하거나 Enter 를 눌러 시작",
    })
  else
    drawHUD()
    if state == "levelup" then drawLevelUp()
    elseif state == "pause" then drawCenterPanel("일시정지", { "Esc 계속하기", "R 처음부터" })
    elseif state == "dead" then
      drawCenterPanel("쓰러졌다", {
        "웨이브 " .. wave .. "   ·   처치 " .. kills .. "   ·   레벨 " .. player.level,
        "",
        "R 또는 클릭으로 다시 시작",
      })
    end
  end

  lg.setScissor()
  lg.pop()
end

function love.keypressed(k)
  if k == "f11" then
    love.window.setFullscreen(not love.window.getFullscreen(), "desktop")
    updateView(); makeFonts()
    return
  end
  if state == "title" then
    if k == "return" or k == "space" then state = "play" end
  elseif state == "play" then
    if k == "space" then doRoll()
    elseif k == "e" then doSpin()
    elseif k == "q" then doPotion()
    elseif k == "escape" then state = "pause" end
  elseif state == "pause" then
    if k == "escape" then state = "play"
    elseif k == "r" then newGame(); state = "play" end
  elseif state == "levelup" then
    local n = tonumber(k)
    if n and n >= 1 and n <= 3 then chooseUpgrade(n) end
  elseif state == "dead" then
    if k == "r" or k == "return" then newGame(); state = "play" end
  end
end

function love.mousepressed(x, y, b)
  local gx, gy = toGame(x, y)
  if state == "title" then
    state = "play"
    player.atkCd = .3
  elseif state == "levelup" then
    for i = 1, #lvChoices do
      local cx, cy, cw, ch = cardRect(i)
      if gx >= cx and gx <= cx + cw and gy >= cy and gy <= cy + ch then chooseUpgrade(i); player.atkCd = .25; return end
    end
  elseif state == "dead" then
    newGame(); state = "play"; player.atkCd = .3
  end
end
