-- 쿼터뷰 액션 : 전투 테스트 (LÖVE 11.x)
-- 기준 문서: 「캐릭터 컨트롤과 장르」 — 복잡한 성장 대신 캐릭터 컨트롤과 직관적인 실시간 전투
-- 전투 스타일 6가지 (문서의 액션 조작법 예 12~18) + 공통 벽 넘기(16)
--   1 검사   : 공격 시 전진, 전방 공격, 공격하면서 방향 조절, 전방 자동 조준
--   2 방패병 : 실시간 막기 (데미지 감소, 약간 밀쳐짐, 막으며 방향 조절)
--   3 궁수   : 누르고 있으면 게이지, 떼면 모은 만큼 발사, 이동하며 모으기
--   4 마법사 : 스킬 사용 후 범위 지정 (움직여서 지정, 캐릭터는 제자리, 사용 후 이동)
--   5 척탄병 : 벽 뒤 공격, 범위 공격으로 튕겨냄
--   6 거너   : 시전 시간, 이속 느려짐, 쏘며 방향 조절, 맞으며 방향 조절
-- 공통: WASD 이동, 마우스 조준, Space 대쉬 (낮은 벽 앞이면 넘는다), Tab 스타일 다시 고르기, Esc 일시정지

local lg = love.graphics
local rnd = love.math.random
local sin, cos, sqrt, floor, ceil, min, max, abs, pi = math.sin, math.cos, math.sqrt, math.floor, math.ceil, math.min, math.max, math.abs, math.pi
local atan2 = math.atan2
local Rig = require("rig")

local W, H = 960, 540
local S = 40                  -- 1m = 40 픽셀
local KY, KZ = .77, .64       -- 카메라가 내려다보는 각도 (바닥 세로 압축, 높이 압축)
local MAPW, MAPH = 40, 28
local LOW = .9                -- 이 높이 이하 벽은 넘을 수 있다
local SHX, SHY = -.42, .3     -- 그림자 방향 (높이 1m 당)
Rig.setup(KY, KZ, S / 100)

local AUTO = nil              -- 자동 테스트 (--autotest)

-------------------------------------------------------------------------------
-- 기본
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
local function snap8(a) return floor(a / (pi / 4) + .5) * (pi / 4) end
local function proj(x, y, z) return x * S, (y * KY - (z or 0) * KZ) * S end

-------------------------------------------------------------------------------
-- 화면 / 폰트 / 소리
-------------------------------------------------------------------------------
local view = { s = 1, x = 0, y = 0 }
local function updateView()
  local ww, wh = lg.getDimensions()
  view.s = min(ww / W, wh / H)
  view.x = floor((ww - W * view.s) / 2)
  view.y = floor((wh - H * view.s) / 2)
end
local function toGame(x, y) return (x - view.x) / view.s, (y - view.y) / view.s end

local fontData
local function loadFontData()
  for _, p in ipairs({ "C:/Windows/Fonts/malgunbd.ttf", "C:/Windows/Fonts/malgun.ttf" }) do
    local fh = io.open(p, "rb")
    if fh then local s = fh:read("*a"); fh:close(); return s end
  end
end
local function mkFont(size)
  local dpi = max(1, view.s)
  if fontData then
    local ok, f = pcall(function() return lg.newFont(love.filesystem.newFileData(fontData, "k.ttf"), size, "normal", dpi) end)
    if ok then return f end
  end
  return lg.newFont(size, "normal", dpi)
end
local fontS, fontM, fontL, fontXL
local function makeFonts() fontS, fontM, fontL, fontXL = mkFont(12), mkFont(16), mkFont(24), mkFont(44) end
local function txt(s, x, y, font, align, w, a)
  lg.setFont(font)
  a = a or 1
  local r, g, b = lg.getColor()
  lg.setColor(0, 0, 0, .65 * a)
  if align then lg.printf(s, x + 1.5, y + 1.5, w, align) else lg.print(s, x + 1.5, y + 1.5) end
  lg.setColor(r, g, b, a)
  if align then lg.printf(s, x, y, w, align) else lg.print(s, x, y) end
end

local sfx = {}
local function synth(dur, f)
  local rate = 44100
  local n = floor(dur * rate)
  local sd = love.sound.newSoundData(n, rate, 16, 1)
  local ph = 0
  for i = 0, n - 1 do
    local v
    v, ph = f(i / rate, i / n, ph)
    sd:setSample(i, clamp(v, -1, 1))
  end
  return love.audio.newSource(sd, "static")
end
local function noise() return rnd() * 2 - 1 end
local function makeSounds()
  local R = 44100
  sfx.swing = synth(.16, function(t, p, ph) return noise() * (1 - p) ^ 2 * sin(p * pi) * .35, ph end)
  sfx.hit = synth(.15, function(t, p, ph) ph = ph + 2 * pi * (170 - 110 * p) / R
    return (sin(ph) * .75 + noise() * .35 * (1 - p)) * (1 - p) ^ 1.6 * .7, ph end)
  sfx.heavy = synth(.22, function(t, p, ph) ph = ph + 2 * pi * (120 - 70 * p) / R
    return (sin(ph) * .8 + noise() * .4 * (1 - p)) * (1 - p) ^ 1.3 * .8, ph end)
  sfx.block = synth(.18, function(t, p, ph) ph = ph + 2 * pi * 900 / R
    return (sin(ph) * .4 + sin(ph * 2.7) * .25 + noise() * .2) * (1 - p) ^ 3, ph end)
  sfx.bow = synth(.14, function(t, p, ph) ph = ph + 2 * pi * (300 + 500 * p) / R
    return (sin(ph) * .25 + noise() * .25 * (1 - p)) * (1 - p) ^ 2, ph end)
  sfx.shot = synth(.12, function(t, p, ph) return noise() * (1 - p) ^ 4 * .6, ph end)
  sfx.boom = synth(.5, function(t, p, ph) ph = ph + 2 * pi * (70 - 40 * p) / R
    return (sin(ph) * .7 + noise() * .7 * (1 - p)) * (1 - p) ^ 1.5 * .9, ph end)
  sfx.zap = synth(.3, function(t, p, ph) return (noise() * .5 + (((t * 1800) % 1) - .5) * .4) * (1 - p) ^ 1.5, ph end)
  sfx.hurt = synth(.22, function(t, p, ph) ph = ph + 2 * pi * (220 - 120 * p) / R
    return ((ph % (2 * pi) < pi) and .3 or -.3) * (1 - p) ^ 1.5, ph end)
  sfx.die = synth(.3, function(t, p, ph) ph = ph + 2 * pi * (260 - 200 * p) / R
    return (sin(ph) * .4 + noise() * .3) * (1 - p) ^ 2 * .7, ph end)
  sfx.dash = synth(.18, function(t, p, ph) return noise() * .2 * (1 - p) * sin(p * pi), ph end)
  sfx.pick = synth(.1, function(t, p, ph) ph = ph + 2 * pi * (800 + 700 * p) / R return sin(ph) * .22 * (1 - p), ph end)
  sfx.spawn = synth(.4, function(t, p, ph) ph = ph + 2 * pi * (90 + 60 * sin(p * 9)) / R return sin(ph) * .15 * sin(p * pi), ph end)
  sfx.beam = synth(.5, function(t, p, ph) ph = ph + 2 * pi * 140 / R
    return (sin(ph) * .25 + sin(ph * 3.01) * .12 + noise() * .1), ph end)
  sfx.beam:setLooping(true)
end
local function play(name, var, vol)
  if AUTO then return end
  local s = sfx[name]
  if not s then return end
  local c = s:clone()
  c:setPitch(1 + (rnd() - .5) * (var or .2))
  c:setVolume(vol or 1)
  c:play()
end

-------------------------------------------------------------------------------
-- 맵 : 제한된 쿼터뷰 레벨 (영상처럼 상자 벽, 긴 벽, 넘을 수 있는 낮은 벽)
-------------------------------------------------------------------------------
local map = {}
local blots = {}
local function rect(x, y, w, h, ht)
  for yy = y, y + h - 1 do for xx = x, x + w - 1 do map[yy][xx] = ht end end
end
local function buildMap()
  for y = 1, MAPH do
    map[y] = {}
    for x = 1, MAPW do map[y][x] = 0 end
  end
  rect(1, 1, MAPW, 1, 2.4); rect(1, 1, 1, MAPH, 2.4); rect(MAPW, 1, 1, MAPH, 2.4)
  rect(1, MAPH, MAPW, 1, .5)                        -- 앞쪽 외벽은 낮게 (가리지 않게)
  -- 큰 상자
  rect(7, 6, 3, 3, 1.8); rect(32, 6, 3, 3, 1.8); rect(7, 20, 3, 3, 1.8); rect(32, 20, 3, 3, 1.8)
  -- 긴 벽 (가운데가 뚫림)
  rect(13, 9, 6, 1, 1.6); rect(23, 9, 6, 1, 1.6); rect(13, 19, 6, 1, 1.6); rect(23, 19, 6, 1, 1.6)
  -- 넘을 수 있는 낮은 벽
  rect(11, 12, 1, 5, .7); rect(30, 12, 1, 5, .7); rect(18, 14, 6, 1, .7)
  rect(3, 14, 4, 1, .7); rect(35, 14, 4, 1, .7); rect(19, 4, 4, 1, .7); rect(19, 24, 4, 1, .7)
  -- 기둥
  rect(16, 5, 1, 1, 2.2); rect(25, 5, 1, 1, 2.2); rect(16, 23, 1, 1, 2.2); rect(25, 23, 1, 1, 2.2)
  -- 바닥 얼룩
  blots = {}
  for _ = 1, 70 do
    blots[#blots + 1] = { x = 2 + rnd() * (MAPW - 2), y = 2 + rnd() * (MAPH - 2), r = .6 + rnd() * 2.2, a = .03 + rnd() * .05 }
  end
end
local function cellH(x, y)
  local tx, ty = floor(x), floor(y)
  if tx < 1 or ty < 1 or tx > MAPW or ty > MAPH then return 99 end
  return map[ty][tx]
end
local function tileH(tx, ty)
  if tx < 1 or ty < 1 or tx > MAPW or ty > MAPH then return 99 end
  return map[ty][tx]
end

-- 원(캐릭터)을 벽에서 밀어낸다. z 보다 높은 벽만 막는다
local function collide(e, z)
  z = z or 0
  local r = e.r
  local hitWall = false
  for ty = floor(e.y - r), floor(e.y + r) do
    for tx = floor(e.x - r), floor(e.x + r) do
      if tileH(tx, ty) > z + .05 then
        local cx, cy = clamp(e.x, tx, tx + 1), clamp(e.y, ty, ty + 1)
        local dx, dy = e.x - cx, e.y - cy
        local d2 = dx * dx + dy * dy
        if d2 < r * r then
          hitWall = true
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
  return hitWall
end
local function freeCircle(x, y, r)
  for ty = floor(y - r), floor(y + r) do
    for tx = floor(x - r), floor(x + r) do
      if tileH(tx, ty) > 0 then
        local cx, cy = clamp(x, tx, tx + 1), clamp(y, ty, ty + 1)
        if len(x - cx, y - cy) < r then return false end
      end
    end
  end
  return true
end
-- z 높이로 지나가는 선이 막히는지
local function los(x1, y1, x2, y2, z)
  local dx, dy = x2 - x1, y2 - y1
  local n = ceil(len(dx, dy) / .2)
  for i = 1, n - 1 do
    local t = i / n
    if cellH(x1 + dx * t, y1 + dy * t) > (z or 1) then return false end
  end
  return true
end

-- 흐름장 : 적이 벽을 돌아서 온다 (적은 낮은 벽을 못 넘는다)
local flow, flowTx, flowTy
local function buildFlow(tx, ty)
  flow = {}
  for y = 1, MAPH do flow[y] = {} end
  if tileH(tx, ty) > 0 then return end
  local qx, qy, head = { tx }, { ty }, 1
  flow[ty][tx] = 0
  while head <= #qx do
    local x, y = qx[head], qy[head]; head = head + 1
    local d = flow[y][x] + 1
    for i = 1, 4 do
      local nx, ny = x, y
      if i == 1 then nx = x + 1 elseif i == 2 then nx = x - 1 elseif i == 3 then ny = y + 1 else ny = y - 1 end
      if tileH(nx, ny) == 0 and not flow[ny][nx] then
        flow[ny][nx] = d
        qx[#qx + 1], qy[#qy + 1] = nx, ny
      end
    end
  end
end

-------------------------------------------------------------------------------
-- 상태
-------------------------------------------------------------------------------
local state = "select"
local player, enemies, projs, corpses, pts, texts, fx, zones, spawns, pickups
local cam = { x = 20, y = 14 }
local shake, freeze, slowT = 0, 0, 0
local wave, waveQueue, spawnT, breakT, kills
local banner = { text = "", sub = "", t = 0 }
local gameTime, realTime = 0, 0
local styleIdx = 1
local shadowCanvas
local beamSrc
local mouseMovedT = 0

-- 히트스톱: frames 프레임(60fps) 동안 캐릭터가 멈춘다 (투사체는 계속 날아간다)
local function hitStop(frames) freeze = max(freeze, frames / 60) end
local function addShake(v) shake = max(shake, v) end

local PCOL = { .9, .88, .84 }
local PCOL2 = { .5, .5, .52 }
local VISOR = { .15, .75, .95 }
local CS = 1.2                -- 캐릭터 크기 배율 (무기·팔이 잘 보이게)
-- 스타일마다 견갑·가슴 표식 색 (실루엣으로 구분)
local ACCENT = {
  fist = { .85, .28, .22 }, blade = { .28, .52, .9 }, guard = { .6, .66, .76 }, archer = { .36, .62, .28 },
  mage = { .58, .38, .88 }, bomber = { .9, .58, .2 }, gunner = { .3, .3, .36 },
}

local TYPES = {
  sword = { name = "칼잡이", hp = 40, speed = 3.1, r = .35, size = 1, col = { .78, .2, .17 }, weapon = "esword",
    range = 1.55, windup = .5, cd = 1.3, dmg = 10, mass = 1, stagger = .3 },
  gun = { name = "총잡이", hp = 28, speed = 2.7, r = .35, size = .95, col = { .72, .26, .2 }, weapon = "rifle",
    range = 9, windup = .8, cd = 2.3, dmg = 9, mass = .9, stagger = .35 },
  brute = { name = "돌격병", hp = 140, speed = 2.2, r = .5, size = 1.35, col = { .5, .13, .12 }, weapon = "club",
    range = 1.9, windup = .85, cd = 2.6, dmg = 22, mass = 3, stagger = 0 },
}

local STYLES
local function newPlayer(idx)
  local st = STYLES[idx]
  return {
    style = st, x = MAPW / 2 + .5, y = 12, z = 0, r = .35, face = pi / 2, aim = pi / 2,
    hp = st.hp, maxhp = st.hp, speed = st.speed,
    inv = 0, stagger = 0, kx = 0, ky = 0, flash = 0, walk = 0, moving = false,
    dash = nil, dashCd = 0, vault = nil, cdR = 0, atkCd = 0,
    -- 스타일별
    sw = nil, combo = 0, comboT = 0, dashSlash = nil,
    pu = nil, focus = nil, focusN = 0, focusT = -9,
    blocking = false, blockStart = -9, blockFlash = 0, bash = nil,
    charging = false, charge = 0, recoil = 0,
    targeting = false, tx = 0, ty = 0, castT = 0, boltT = 0,
    holdThrow = false, throwT = 0, kickT = 0,
    gcast = 0, beaming = false, beamDir = 0, heat = 0, overT = 0, buttT = 0,
  }
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
local function screenToWorld(gx, gy, z)
  return (gx - W / 2) / S + cam.x, ((gy - H / 2) / S + (z or 0) * KZ) / KY + cam.y
end
local function mouseWorld(z)
  if AUTO then return AUTO.ax, AUTO.ay end
  local gx, gy = toGame(love.mouse.getPosition())
  return screenToWorld(gx, gy, z or 1)
end
local function worldToGame(x, y, z)
  local sx, sy = proj(x, y, z)
  return sx - cam.x * S + W / 2, sy - cam.y * KY * S + H / 2
end

-------------------------------------------------------------------------------
-- 효과
-------------------------------------------------------------------------------
local function addText(x, y, s, col, big)
  texts[#texts + 1] = { x = x, y = y, z = 2, s = s, col = col, t = 0, life = big and .9 or .7, big = big, vx = (rnd() - .5) * .8 }
end
local function burst(x, y, z, n, col, spd, size, life, grav)
  for _ = 1, n do
    local a = rnd() * pi * 2
    local v = (spd or 3) * (.4 + rnd() * .8)
    pts[#pts + 1] = { x = x, y = y, z = z or 1, vx = cos(a) * v, vy = sin(a) * v, vz = rnd() * 4 + 1,
      t = 0, life = (life or .5) * (.6 + rnd() * .6), size = (size or 3) * (.6 + rnd() * .7), col = col, grav = grav or 14 }
  end
end
local function sparks(x, y, z, dx, dy, n, col)
  for _ = 1, n do
    local a = atan2(dy, dx) + (rnd() - .5) * 1.6
    local v = 4 + rnd() * 6
    pts[#pts + 1] = { x = x, y = y, z = z, vx = cos(a) * v, vy = sin(a) * v, vz = rnd() * 3,
      t = 0, life = .15 + rnd() * .2, size = 2 + rnd() * 2, col = col or { 1, .9, .5 }, grav = 8, glow = true }
  end
end

-------------------------------------------------------------------------------
-- 전투 공통
-------------------------------------------------------------------------------
local killEnemy

-- 적이 플레이어를 때린다. 방패로 막으면 줄고, 반환값 "block"/"perfect"/true
local function hurtPlayer(dmg, sx, sy, kb, attacker, isProj)
  local p = player
  if state ~= "play" or p.hp <= 0 then return false end
  if p.inv > 0 or p.dash or p.vault then return false end
  local dx, dy = norm(p.x - sx, p.y - sy)
  -- 방패병: 앞쪽에서 오는 공격은 막는다
  if p.blocking then
    local toSrc = atan2(sy - p.y, sx - p.x)
    if abs(angDiff(toSrc, p.face)) < 1.2 then
      local perfect = gameTime - p.blockStart < .22 and not p.style.noPerfect
      p.blockFlash = .25
      sparks(p.x + cos(p.face) * .5, p.y + sin(p.face) * .5, 1, -dx, -dy, perfect and 14 or 8, perfect and { 1, 1, .6 } or nil)
      play("block", .15)
      if perfect then
        addText(p.x, p.y, "완벽한 막기!", { 1, .95, .5 }, true)
        if attacker and not isProj then attacker.stun = 1.1; attacker.state = "chase"; attacker.kx, attacker.ky = -dx * 6, -dy * 6 end
        hitStop(9)
        return "perfect"
      end
      local d = dmg * (p.style.blockChip or .2)        -- 방패 20%, 칼 30%
      p.hp = p.hp - d
      p.kx, p.ky = p.kx + dx * kb * .35, p.ky + dy * kb * .35     -- 약간씩 밀쳐짐
      addText(p.x, p.y, tostring(floor(d + .5)), { .8, .85, 1 })
      hitStop(5)
      addShake(.12)
      if p.hp <= 0 then p.hp = 0; state = "dead" end
      return "block"
    end
  end
  p.hp = p.hp - dmg
  p.inv, p.flash, p.stagger = .5, .15, .18
  p.kx, p.ky = p.kx + dx * kb, p.ky + dy * kb                      -- 피격 시 밀쳐짐
  addText(p.x, p.y, tostring(floor(dmg)), { 1, .35, .3 })
  burst(p.x, p.y, 1, 8, { .9, .2, .2 }, 3, 3)
  addShake(.4)
  hitStop(7)
  play("hurt")
  -- 거너는 맞아도 쏘기가 끊기지 않는다 (맞으며 방향 조절)
  if p.style.id ~= "gunner" then p.sw, p.charging, p.holdThrow, p.kk, p.pu = nil, false, false, nil, nil end
  if p.hp <= 0 then
    p.hp = 0
    state = "dead"
    burst(p.x, p.y, 1, 30, { .9, .2, .2 }, 5, 4, .9)
  end
  return true
end

-- 플레이어가 적을 때린다
local HIT_FLINCH = .2                  -- 맞았을 때 상체 움찔 시간 (초)
local function hitEnemy(e, dmg, dx, dy, kb, stop, crit)
  if e.dead then return end
  dmg = dmg * (.9 + rnd() * .2)
  e.hp = e.hp - dmg
  e.flash, e.hpShow = .1, 2.5
  e.hitT = HIT_FLINCH                  -- 맞을 때마다 상체가 움찔 (다시 맞으면 처음부터 다시)
  local T = e.T
  e.kx, e.ky = e.kx + dx * kb / T.mass, e.ky + dy * kb / T.mass
  e.lastDx, e.lastDy, e.lastKb = dx, dy, kb
  if T.stagger > 0 and e.state ~= "dash" then
    e.stun = max(e.stun, T.stagger)
    if e.state == "windup" then e.state = "chase"; e.cd = max(e.cd, .5) end
  end
  addText(e.x, e.y, tostring(floor(dmg + .5)) .. (crit and "!" or ""), crit and { 1, .85, .2 } or { 1, 1, 1 }, crit)
  burst(e.x, e.y, 1, 4, { 1, .85, .6 }, 4, 2.5, .25)
  if stop and stop > 0 then hitStop(stop) end
  addShake(crit and .25 or .12)
  play(crit and "heavy" or "hit")
  if e.hp <= 0 then killEnemy(e) end
end

-- 부채꼴 근접 판정
local function meleeArc(x, y, dir, range, half, dmg, kb, stop, crit, hitSet)
  local n = 0
  for _, e in ipairs(enemies) do
    if not e.dead and not (hitSet and hitSet[e]) then
      local dx, dy = e.x - x, e.y - y
      local d = len(dx, dy)
      if d < range + e.r and (d < .5 or abs(angDiff(atan2(dy, dx), dir)) < half) then
        local nx, ny = norm(dx, dy)
        hitEnemy(e, dmg, nx, ny, kb, stop, crit)
        if hitSet then hitSet[e] = true end
        n = n + 1
      end
    end
  end
  return n
end

-- 원형 범위: 바깥으로 튕겨낸다
local function blast(x, y, r, dmg, kb, stop)
  for _, e in ipairs(enemies) do
    if not e.dead then
      local dx, dy = e.x - x, e.y - y
      local d = len(dx, dy)
      if d < r + e.r then
        local nx, ny = norm(dx, dy)
        if d < .05 then nx, ny = cos(rnd() * 6.28), sin(rnd() * 6.28) end
        local k = 1 - d / (r + e.r) * .5
        hitEnemy(e, dmg * k, nx, ny, kb * k, stop)
      end
    end
  end
end

-------------------------------------------------------------------------------
-- 전투 스타일 6가지
-------------------------------------------------------------------------------
local function canAct(p) return not p.dash and not p.vault and p.stagger <= 0 and p.hp > 0 end

-- 전방 자동 조준: 앞쪽 부채꼴 안의 가장 가까운 적 쪽으로
local function autoTarget(p, dir, range, half)
  local best, bd = nil, 1e9
  for _, e in ipairs(enemies) do
    if not e.dead then
      local dx, dy = e.x - p.x, e.y - p.y
      local d = len(dx, dy)
      if d < range and abs(angDiff(atan2(dy, dx), dir)) < half and d < bd then best, bd = e, d end
    end
  end
  if best then return atan2(best.y - p.y, best.x - p.x), best end
  return dir
end

local function fireArrow(p, c)
  local power = c >= 1
  local spd = 15 + 13 * c
  local a = p.aim
  projs[#projs + 1] = { kind = "arrow", owner = "p", x = p.x + cos(a) * .5, y = p.y + sin(a) * .5, z = 1.25,
    vx = cos(a) * spd, vy = sin(a) * spd, dmg = 8 + 26 * c, kb = 3 + 9 * c, pierce = power and 6 or 1,
    hit = {}, life = 1.6, power = power, trail = {} }
  p.face = a
  p.recoil = .18
  play("bow", .1, .6 + c * .4)
  if power then addShake(.15) end
end

local function castBolt(p)
  local a = p.aim
  projs[#projs + 1] = { kind = "bolt", owner = "p", x = p.x + cos(a) * .5, y = p.y + sin(a) * .5, z = 1.4,
    vx = cos(a) * 13, vy = sin(a) * 13, dmg = 10, kb = 4, pierce = 1, hit = {}, life = 1.3, trail = {} }
  p.face, p.boltT, p.atkCd = a, .2, .32
  play("zap", .2, .4)
end

local function throwGrenade(p)
  local mx, my = mouseWorld(0)
  local dx, dy = mx - p.x, my - p.y
  local d = len(dx, dy)
  if d > 9 then dx, dy, d = dx / d * 9, dy / d * 9, 9 end
  local T = .55 + d * .035
  local g = 24
  projs[#projs + 1] = { kind = "grenade", owner = "p", x = p.x, y = p.y, z = 1.6,
    vx = dx / T, vy = dy / T, vz = (g * T * T / 2 - 1.6) / T, g = g, life = T + .5, spin = 0 }
  p.face, p.throwT, p.atkCd = atan2(dy, dx), .22, .8
  play("swing", .2, .6)
end

-- 맨손: 잽·잽·스트레이트. 스트레이트에 맞은 적은 날아가서 다른 적과 부딪힌다 (launchEnemy)
-- 주먹: 앞쪽 좁은 부채꼴 안의 적을 모두 친다. 같은 적을 계속 때리면 그 적에게 연타가 쌓여 세진다
local launchEnemy
local SUPER_SPEED = 15                  -- 슈퍼맨 펀치 돌진 속도 (m/s, 약 4m 날아간다)
local SPIN_R = 2.1                      -- 검사 3타 회전베기 반경 (m)
local BLADE_BLOCK_CHIP = .3             -- 칼로 막기: 막아도 받는 피해 비율 (30%)
local function inPunchReach(p, e, dir, range, half)
  if e.dead or e.fly then return false end
  local dx, dy = e.x - p.x, e.y - p.y
  local d = len(dx, dy)
  return d < range + e.r and (d < .5 or abs(angDiff(atan2(dy, dx), dir)) < half), d
end
local function punchTarget(p, dir, range, half)
  -- 때리던 놈이 아직 닿으면 그놈을 계속
  local f = p.focus
  if f and gameTime - p.focusT < 1.2 and inPunchReach(p, f, dir, range + .3, half + .4) then return f end
  local best, bd = nil, 1e9
  for _, e in ipairs(enemies) do
    local ok, d = inPunchReach(p, e, dir, range, half)
    if ok and d < bd then best, bd = e, d end
  end
  return best
end
-- 주먹 범위: 칼(사거리 1.75, 반각 1.05 = 약 120도)보다 짧고 좁은 앞쪽 부채꼴. 그 안의 적은 모두 맞는다
local PUNCH_R, PUNCH_HALF = 1.3, .5          -- 잽: 사거리 1.3m, 반각 .5 (약 57도)
local STRAIGHT_R, STRAIGHT_HALF = 1.5, .55   -- 스트레이트: 1.5m, 반각 .55 (약 63도)
local function punchHit(p, s)
  local straight = s.n == 3
  local R, HALF = straight and STRAIGHT_R or PUNCH_R, straight and STRAIGHT_HALF or PUNCH_HALF
  -- 연타는 '주로 때리는 놈'(때리던 놈 또는 가장 가까운 놈) 기준으로 쌓인다
  local main = punchTarget(p, s.dir, R, HALF)
  if not main then return end
  if p.focus == main and gameTime - p.focusT < 1.2 then p.focusN = min(8, p.focusN + 1) else p.focus, p.focusN = main, 1 end
  p.focusT = gameTime
  local mul = 1 + (p.focusN - 1) * .1
  local victims = { main }
  for _, e in ipairs(enemies) do
    if e ~= main and inPunchReach(p, e, s.dir, R, HALF) then victims[#victims + 1] = e end
  end
  for _, e in ipairs(victims) do
    local m = (e == main) and mul or 1                -- 연타 보너스는 주로 때리는 놈만
    local dx, dy = e.x - p.x, e.y - p.y
    local d = len(dx, dy)
    local nx, ny = norm(dx * .4 + cos(s.dir) * d * .6, dy * .4 + sin(s.dir) * d * .6)   -- 주먹 방향 쪽으로
    if straight then
      e.lastKb = 13
      hitEnemy(e, 18 * m, nx, ny, 0, 11, e == main and p.focusN >= 4)
      launchEnemy(e, nx, ny, 10.5 + ((e == main) and p.focusN * .6 or 0))
    else
      hitEnemy(e, 8 * m, nx, ny, 2, 0)                  -- 잽은 히트스톱 없음 (예전 5프레임)
      if not e.dead then e.stun = max(e.stun, .32) end -- 잽은 짧게 묶어 둔다
    end
    fx[#fx + 1] = { kind = "pow", x = e.x - nx * e.r, y = e.y - ny * e.r, z = 1.3, t = 0, dur = straight and .16 or .1, big = straight }
  end
  if p.focusN >= 3 then addText(main.x, main.y + .1, p.focusN .. "연타", { 1, .8, .4 }) end
  if straight then p.focus = nil; addShake(.3) end
end

STYLES = {
  -- 1 맨손 -----------------------------------------------------------------
  {
    id = "fist", name = "맨손", tag = "권법 · 기본기", hp = 110, speed = 5.4,
    desc = { "좌클릭  잽 · 잽 · 스트레이트 — 앞쪽 좁은 범위", "같은 적을 계속 때리면 연타가 쌓여 세진다", "스트레이트로 날린 적이 다른 적과 부딪히고 벽에 박힌다", "우클릭  슈퍼맨 펀치 — 앞으로 쭉 날아가며 주먹을 꽂는다" },
    update = function(p, dt)
      -- 슈퍼맨 펀치: 앞으로 쭉 뛰어들며 주먹을 내지른다. 처음 닿는 한 놈에게 꽂고 그놈을 날린다
      if p.kk then
        local k = p.kk
        k.t = k.t + dt
        local q = min(1, k.t / k.dur)
        local sp = SUPER_SPEED * (1 - q * .4)                  -- 끝까지 거의 같은 속도로 뚫고 나간다
        p.x, p.y = p.x + cos(k.dir) * sp * dt, p.y + sin(k.dir) * sp * dt
        p.z = .45 + sin(q * pi) * .3                           -- 떠서 날아간다
        p.face = k.dir
        if rnd() < .8 then burst(p.x, p.y, .4, 1, { .9, .9, .85 }, 1, 2.5, .25, 0) end
        -- 뚫고 나가는 펀치: 지나가는 길의 적을 모두 한 번씩 치고, 양옆으로 튕겨낸다 (멈추지 않음)
        local dx0, dy0 = cos(k.dir), sin(k.dir)
        for _, e in ipairs(enemies) do
          if not e.dead and not e.fly and not k.hits[e] then
            local ex, ey = e.x - p.x, e.y - p.y
            local along = ex * dx0 + ey * dy0
            local side = ex * -dy0 + ey * dx0
            if along > -.3 and along < 1.0 + e.r and abs(side) < e.r + .45 then
              k.hits[e] = true
              local sgn = side >= 0 and 1 or -1
              local nx, ny = norm(dx0 * .65 - dy0 * sgn * .75, dy0 * .65 + dx0 * sgn * .75)
              e.lastKb = 12
              hitEnemy(e, 20, nx, ny, 0, 6, true)
              launchEnemy(e, nx, ny, 11)
              fx[#fx + 1] = { kind = "pow", x = e.x - nx * e.r, y = e.y - ny * e.r, z = 1.1, t = 0, dur = .16, big = true }
              addShake(.25)
            end
          end
        end
        if k.t >= k.dur then p.kk = nil; p.z = 0 end
      end
      if p.pu then
        local s = p.pu
        s.t = s.t + dt
        s.dir = turn(s.dir, p.aim, dt * 4)
        p.face = s.dir
        -- 스트레이트는 주먹을 한 번 뒤로 당겼다가(텀) 나간다
        if s.pre > 0 and not s.went and s.t >= s.pre then
          s.went = true
          p.kx, p.ky = p.kx + cos(s.dir) * 7, p.ky + sin(s.dir) * 7
          play("swing", .2, 1)
        end
        if not s.hit and s.t >= s.pre + s.dur * s.hitAt then s.hit = true; punchHit(p, s) end
        if s.t >= s.pre + s.dur then p.pu = nil end
      end
      if mouseDown(1) and not p.pu and not p.kk and p.atkCd <= 0 and canAct(p) then
        p.combo = (p.comboT > 0) and (p.combo % 3 + 1) or 1
        p.comboT = .6
        local n = p.combo
        local dir = autoTarget(p, p.aim, 2.4, .7)
        local pre = n == 3 and .16 or 0                    -- 스트레이트 전 텀
        p.pu = { t = 0, n = n, pre = pre, dur = n == 3 and .3 or .19, hitAt = n == 3 and .42 or .4, dir = dir }
        p.atkCd = n == 3 and (pre + .52) or .21           -- 잽 템포 (예전 .13 → .21)
        p.face = dir
        if n ~= 3 then
          p.kx, p.ky = p.kx + cos(dir) * 3.5, p.ky + sin(dir) * 3.5
          play("swing", .2, .6)
        end
      end
    end,
    press = function(p, b)
      if b == 2 and p.cdR <= 0 and canAct(p) and not p.kk and not p.pu then
        p.kk = { t = 0, dur = .36, dir = autoTarget(p, p.aim, 5, .45), hits = {} }   -- 바로 뛰어든다
        p.cdR = 3
        p.inv = max(p.inv, .15)
        play("dash", .1, 1); play("swing", .15, 1)
      end
    end,
    speedMul = function(p)
      if p.kk then return 0 end                -- 날아가는 중엔 이동키 무시 (펀치가 직접 움직인다)
      return p.pu and .5 or 1
    end,
    cdMax = 3, rName = "슈퍼맨 펀치",
    pose = function(p, o)
      if p.kk then
        -- 슈퍼맨처럼: 몸을 수평으로 눕혀 날아가고, 오른 주먹은 앞으로 쭉, 왼팔과 다리는 뒤로 뻗는다
        -- (선 자세에서 '위'로 뻗은 팔이 몸을 앞으로 눕히면 '앞'이 된다)
        local q = min(1, p.kk.t / p.kk.dur)
        o.crouch, o.lean, o.moving = 0, 0, false
        o.fall = -(.55 + .37 * min(1, q * 4))     -- 앞으로 거의 수평까지 눕힘
        local hipU, chF, chU = Rig.body(0, 0)
        o.handR, o.handCol = 10, { .86, .78, .62 }
        o.rh = { chF + 6, 6, chU + 62 }            -- 머리 위 = 날아가는 앞쪽
        o.lh = { chF - 6, -24, hipU + 4 }          -- 몸 옆으로 붙임 = 뒤쪽
        -- 왼다리는 무릎을 굽혀 멋을 낸다: 무릎은 아래(몸 기준 앞)로, 발끝은 위(몸 기준 뒤)로 접힌다
        -- 오른다리는 뒤로 쭉 뻗는다
        o.legs = { [-1] = { 30, hipU - 34, -4, hipU - 58 }, [1] = { 4, hipU * .5, 2, 4 } }
        o.face = p.face
        return
      end
      if p.pu then
        if p.pu.n ~= 3 then o.lean = .14
        elseif p.pu.t < p.pu.pre then o.lean = -.05     -- 텀: 살짝 뒤로
        else o.lean = .3 end
      end
      local hipU, chF, chU = Rig.body(o.crouch, o.lean)
      o.weapon = nil
      o.handR, o.handCol = 10, { .86, .78, .62 }
      local bob = p.moving and sin(p.walk * 2) * 2 or sin(realTime * 4) * 1.2
      local gR = { chF + 16, 9, chU + 2 + bob }          -- 가드: 두 주먹을 턱 앞에
      local gL = { chF + 20, -9, chU + 6 + bob }
      o.rh, o.lh = gR, gL
      if p.pu then
        local s = p.pu
        if s.t < s.pre then
          -- 텀: 오른 주먹을 허리 쪽으로 당기고 몸을 살짝 비튼다
          local q = s.t / s.pre
          o.rh = { lerp(gR[1], chF - 4, q), lerp(9, 14, q), lerp(gR[3], chU - 8, q) }
          o.lh = { gL[1] + 6 * q, -7, gL[3] }
          return
        end
        local t = min(1, (s.t - s.pre) / s.dur)
        local k = t < s.hitAt and t / s.hitAt or max(0, 1 - (t - s.hitAt) / (1 - s.hitAt))
        k = 1 - (1 - k) ^ 2
        if s.n == 3 then
          o.rh = { lerp(chF - 4, chF + 66, k), lerp(14, 1, k), lerp(chU - 8, chU + 4, k) }   -- 스트레이트 (오른손)
        else
          o.lh = { lerp(gL[1], chF + 60, k), lerp(-9, -3, k), lerp(gL[3], chU + 6, k) } -- 잽 (왼손)
        end
      end
    end,
  },
  -- 2 검사 -----------------------------------------------------------------
  {
    id = "blade", name = "검사", tag = "리얼타임 액션", hp = 120, speed = 5.2,
    desc = { "좌클릭  3연격 — 공격 시 전진, 3타는 회전베기(주위 전부)", "공격 중 마우스로 방향 조절 · 앞쪽 적 자동 조준", "우클릭 누르기  칼로 막기 — 공격·투사체를 막지만", "막을 때마다 체력이 조금 닳는다" },
    blockChip = BLADE_BLOCK_CHIP, noPerfect = true,   -- 막아도 체력이 조금 닳는다 (완벽한 막기 없음)
    update = function(p, dt)
      -- 칼로 막기: 우클릭을 누르는 동안 앞쪽에서 오는 공격·투사체를 막는다 (체력은 조금 닳음)
      local want = mouseDown(2) and canAct(p) and not p.sw
      if want and not p.blocking then p.blockStart = gameTime end
      p.blocking = want
      if p.blocking then p.face = turn(p.face, p.aim, dt * 9) end
      p.blockFlash = max(0, p.blockFlash - dt)
      if p.sw then
        local s = p.sw
        s.t = s.t + dt
        if s.spin then
          -- 회전베기: 제자리에서 한 바퀴 돌며 주위를 전부 벤다
          local q = min(1, s.t / s.dur)
          p.face = s.dir + (1 - (1 - q) ^ 2) * pi * 2
          if not s.hit and q >= .25 then
            s.hit = true
            for _, e in ipairs(enemies) do
              if not e.dead and not e.fly then
                local dx, dy = e.x - p.x, e.y - p.y
                if len(dx, dy) < SPIN_R + e.r then
                  local nx, ny = norm(dx, dy)
                  hitEnemy(e, 26, nx, ny, 11, 11, true)
                end
              end
            end
            fx[#fx + 1] = { kind = "ring", x = p.x, y = p.y, r = SPIN_R + .2, t = 0, dur = .3, col = { .9, .95, 1 } }
            addShake(.3)
          end
          if s.t >= s.dur then p.face = s.dir; p.sw = nil end
        else
          s.dir = turn(s.dir, p.aim, dt * 5)            -- 공격하면서 방향 조절
          p.face = s.dir
          if not s.hit and s.t >= s.dur * .3 then
            s.hit = true
            meleeArc(p.x, p.y, s.dir, s.range, s.half, s.dmg, s.kb, 7)
          end
          if s.t >= s.dur then p.sw = nil end
        end
      end
      if mouseDown(1) and not p.sw and not p.blocking and p.atkCd <= 0 and canAct(p) then
        p.combo = (p.comboT > 0) and (p.combo % 3 + 1) or 1
        p.comboT = .55
        local spin = p.combo == 3
        local dir = autoTarget(p, p.aim, 3.2, .6)       -- 전방 자동 조준
        p.sw = { t = 0, dur = spin and .36 or .22, dir = dir, side = (p.combo == 2) and -1 or 1, spin = spin,
          range = 1.75, half = 1.05, dmg = 14, kb = 6 }
        p.atkCd = spin and .55 or .27
        p.face = dir
        if not spin then
          p.kx, p.ky = p.kx + cos(dir) * 6, p.ky + sin(dir) * 6   -- 공격 시 전진 (회전베기는 제자리)
        end
        play("swing", .25, spin and 1 or .8)
      end
    end,
    press = function() end,
    speedMul = function(p) return p.blocking and .5 or (p.sw and (p.sw.spin and .25 or .4) or 1) end,
    rName = "칼로 막기",
    pose = function(p, o)
      if p.blocking then o.crouch = 7 end
      local hipU, chF, chU = Rig.body(o.crouch, o.lean)
      o.weapon = "sword"
      o.blockFlash = p.blockFlash * 2
      if p.blocking then
        -- 칼을 가로로 눕혀 앞을 막는다 (왼손은 칼등을 받친다)
        o.rh = { chF + 24, 12, chU - 4 }
        o.wdir = { .12, -1, .12 }
        o.lh = { chF + 26, -14, chU - 1 }
        o.wglow = p.blockFlash > 0
      elseif p.sw then
        local s = p.sw
        local t = min(1, s.t / s.dur)
        local e = 1 - (1 - t) ^ 2
        if s.spin then
          -- 칼을 오른쪽으로 길게 뻗은 채 몸과 같이 돈다
          o.face = p.face
          o.crouch = 6
          o.rh = { chF + 4, 36, chU - 16 }
          o.wdir = { .18, 1, -.06 }
          o.lh = { chF - 4, -30, chU - 10 }
          o.trail = { kind = "h", a0 = pi * .55 - (1 - (1 - t) ^ 2) * pi * 1.6, a = pi * .55, r = 150, cf = chF, cs = 0, cu = chU - 18, w = 8 }
        else
          local a0, a1 = 1.9, -1.5
          if s.side == -1 then a0, a1 = -1.5, 1.9 end
          local a = a0 + (a1 - a0) * e
          o.rh = { chF + 6 + cos(a) * 30, 4 + sin(a) * 28, chU - 12 }
          o.wdir = { cos(a), sin(a), -.05 }
          o.trail = { kind = "h", a0 = a0, a = a, r = 152, cf = chF + 6, cs = 4, cu = chU - 14, w = 7 }
        end
      else
        o.rh = { chF + 16, 16, hipU + 14 }; o.wdir = { .75, .2, -.55 }
      end
    end,
  },
  -- 2 방패병 ---------------------------------------------------------------
  {
    id = "guard", name = "방패병", tag = "실시간 막기", hp = 160, speed = 4.4,
    desc = { "우클릭 누르기  막기", "막는 동안 데미지 감소 · 약간 밀림", "막으면서 방향 조절 · 막 들었을 때 완벽한 막기", "좌클릭  베기 / 막으며 방패 밀치기" },
    update = function(p, dt)
      local want = mouseDown(2) and canAct(p) and not p.bash
      if want and not p.blocking then p.blockStart = gameTime end
      p.blocking = want
      if p.blocking then p.face = turn(p.face, p.aim, dt * 9) end   -- 막으면서 방향 조절
      p.blockFlash = max(0, p.blockFlash - dt)
      if p.sw then
        local s = p.sw
        s.t = s.t + dt
        if not s.hit and s.t >= s.dur * .3 then
          s.hit = true
          meleeArc(p.x, p.y, s.dir, 1.6, 1.0, 16, 6, 7)
        end
        if s.t >= s.dur then p.sw = nil end
      end
      if p.bash then
        p.bash.t = p.bash.t + dt
        if not p.bash.hit and p.bash.t > .06 then
          p.bash.hit = true
          meleeArc(p.x, p.y, p.face, 1.6, 1.0, 8, 15, 9)
        end
        if p.bash.t > .3 then p.bash = nil end
      end
    end,
    press = function(p, b)
      if b ~= 1 or not canAct(p) or p.atkCd > 0 then return end
      if p.blocking then
        p.bash = { t = 0 }
        p.atkCd = .7
        p.kx, p.ky = p.kx + cos(p.face) * 6, p.ky + sin(p.face) * 6
        play("swing", .1, 1)
      elseif not p.sw then
        p.sw = { t = 0, dur = .24, dir = p.aim, side = 1 }
        p.face = p.aim
        p.atkCd = .42
        p.kx, p.ky = p.kx + cos(p.aim) * 4, p.ky + sin(p.aim) * 4
        play("swing", .2, .8)
      end
    end,
    speedMul = function(p) return p.blocking and .45 or (p.sw and .45 or 1) end,
    pose = function(p, o)
      if p.blocking then o.crouch = 8 end
      local hipU, chF, chU = Rig.body(o.crouch, o.lean)
      o.weapon = "shield"
      o.blockFlash = p.blockFlash * 2
      if p.bash then
        o.lh = { chF + 36, -2, chU - 8 }; o.sdir = { 1, 0, 0 }
        o.rh = { chF + 2, 20, hipU + 12 }; o.wdir = { .6, .2, -.7 }
      elseif p.blocking then
        o.lh = { chF + 26, -4, chU - 6 }; o.sdir = { 1, 0, .05 }
        o.rh = { chF + 2, 20, chU - 18 }; o.wdir = { -.3, .3, .9 }
      elseif p.sw then
        local t = min(1, p.sw.t / p.sw.dur)
        local e = 1 - (1 - t) ^ 2
        local a0, a1 = 1.8, -1.2
        local a = a0 + (a1 - a0) * e
        o.rh = { chF + 6 + cos(a) * 28, 4 + sin(a) * 26, chU - 12 }; o.wdir = { cos(a), sin(a), -.05 }
        o.lh = { chF + 16, -18, chU - 12 }; o.sdir = { .8, -.6, 0 }
        o.trail = { kind = "h", a0 = a0, a = a, r = 122, cf = chF + 6, cs = 4, cu = chU - 14, w = 6 }
      else
        o.lh = { chF + 16, -18, chU - 14 }; o.sdir = { .85, -.5, 0 }
        o.rh = { chF + 14, 18, hipU + 12 }; o.wdir = { .75, .2, -.6 }
      end
    end,
  },
  -- 3 궁수 -----------------------------------------------------------------
  {
    id = "archer", name = "궁수", tag = "모아 쏘기", hp = 100, speed = 5.0,
    desc = { "좌클릭 누르기  게이지 모으기", "떼면 모은 만큼 발사 (가득 = 관통샷)", "이동하면서 모으고 마우스로 조준", "우클릭  부채꼴 3연발" },
    update = function(p, dt)
      p.recoil = max(0, p.recoil - dt)
      if p.charging then
        p.charge = min(1, p.charge + dt / .9)
        p.face = p.aim
        if not mouseDown(1) or not canAct(p) then
          if canAct(p) then fireArrow(p, max(.15, p.charge)) end
          p.charging = false
          p.atkCd = .12
        end
      elseif mouseDown(1) and canAct(p) and p.atkCd <= 0 then
        p.charging, p.charge = true, 0
      end
    end,
    press = function(p, b)
      if b == 2 and p.cdR <= 0 and canAct(p) then
        for k = -1, 1 do
          local a = p.aim + k * .22
          projs[#projs + 1] = { kind = "arrow", owner = "p", x = p.x + cos(a) * .5, y = p.y + sin(a) * .5, z = 1.25,
            vx = cos(a) * 20, vy = sin(a) * 20, dmg = 12, kb = 5, pierce = 1, hit = {}, life = 1.1, trail = {} }
        end
        p.face, p.recoil, p.cdR = p.aim, .2, 2.5
        play("bow", .1, 1)
      end
    end,
    speedMul = function(p) return p.charging and .6 or 1 end,
    cdMax = 2.5, rName = "3연발",
    gauge = function(p) return p.charging and p.charge or nil end,
    pose = function(p, o)
      local hipU, chF, chU = Rig.body(o.crouch, o.lean)
      o.weapon = "bow"
      if p.charging then
        local c = p.charge
        o.lh = { chF + 40, -4, chU - 6 }; o.rh = { chF + 32 - 28 * c, 2, chU - 4 }
        o.wdir = { 1, 0, 0 }; o.pull = 1; o.nock = true; o.nockPower = c >= 1
      elseif p.recoil > 0 then
        o.lh = { chF + 40, -4, chU - 6 }; o.rh = { chF - 4, 10, chU + 4 }; o.wdir = { 1, 0, 0 }
      else
        o.lh = { chF + 12, -18, hipU + 18 }; o.wdir = { .9, 0, -.4 }
      end
    end,
  },
  -- 4 마법사 ---------------------------------------------------------------
  {
    id = "mage", name = "마법사", tag = "범위 지정", hp = 90, speed = 4.8,
    desc = { "좌클릭  마력탄", "우클릭  번개 지대 — 범위 지정 시작", "지정 중엔 WASD·마우스로 범위만 움직이고 캐릭터는 제자리", "좌클릭/우클릭 시전, 시전 후 바로 이동" },
    update = function(p, dt)
      p.boltT = max(0, p.boltT - dt)
      if p.targeting then
        -- 움직여서 지정: 이동키는 범위를 움직인다 (캐릭터는 제자리)
        local ix, iy = 0, 0
        if keyDown("a", "left") then ix = ix - 1 end
        if keyDown("d", "right") then ix = ix + 1 end
        if keyDown("w", "up") then iy = iy - 1 end
        if keyDown("s", "down") then iy = iy + 1 end
        local nx, ny = norm(ix, iy)
        p.tx, p.ty = p.tx + nx * 10 * dt, p.ty + ny * 10 * dt
        if mouseMovedT > 0 then p.tx, p.ty = mouseWorld(0) end
        local dx, dy = p.tx - p.x, p.ty - p.y
        local d = len(dx, dy)
        if d > 9 then p.tx, p.ty = p.x + dx / d * 9, p.y + dy / d * 9 end
        p.face = atan2(p.ty - p.y, p.tx - p.x)
      end
      if p.castT > 0 then
        p.castT = p.castT - dt
        if p.castT <= 0 then
          zones[#zones + 1] = { kind = "storm", x = p.tx, y = p.ty, r = 2.6, t = 0, delay = .45, dur = 1.6, tick = 0 }
          play("zap", .1, .7)
        end
      end
      if mouseDown(1) and not p.targeting and p.castT <= 0 and p.atkCd <= 0 and canAct(p) then castBolt(p) end
    end,
    press = function(p, b)
      if p.targeting then
        if b == 1 or b == 2 then
          p.targeting = false
          p.castT = .3
          p.cdR = 5
          p.atkCd = .35
        end
        return
      end
      if b == 2 and p.cdR <= 0 and canAct(p) then
        p.targeting = true
        local mx, my = mouseWorld(0)
        local dx, dy = mx - p.x, my - p.y
        local d = len(dx, dy)
        if d > 9 then dx, dy = dx / d * 9, dy / d * 9 end
        p.tx, p.ty = p.x + dx, p.y + dy
      end
    end,
    speedMul = function(p) return (p.targeting or p.castT > 0) and 0 or 1 end,   -- 지정·시전 중엔 제자리
    cdMax = 5, rName = "번개 지대",
    pose = function(p, o)
      local hipU, chF, chU = Rig.body(o.crouch, o.lean)
      o.weapon = "staff"
      if p.targeting then
        o.rh = { chF + 12, 16, chU + 28 }; o.lh = { chF + 12, -16, chU + 26 }; o.wdir = { .2, 0, 1 }
        o.orb = .8 + .2 * sin(realTime * 10)
      elseif p.castT > 0 then
        o.rh = { chF + 34, 10, chU - 2 }; o.wdir = { .8, 0, .6 }; o.orb = 1
      elseif p.boltT > 0 then
        o.rh = { chF + 34, 12, chU - 4 }; o.wdir = { .9, 0, .45 }; o.orb = .7
      else
        o.rh = { chF + 12, 18, hipU + 22 }; o.wdir = { .12, 0, 1 }; o.orb = .3
      end
    end,
  },
  -- 5 척탄병 ---------------------------------------------------------------
  {
    id = "bomber", name = "척탄병", tag = "벽 뒤 공격", hp = 110, speed = 4.8,
    desc = { "좌클릭 누르기  떨어질 곳 보기", "떼면 수류탄 — 벽을 넘어 날아간다", "폭발이 적을 바깥으로 튕겨낸다", "우클릭  발차기 (밀쳐내기)" },
    update = function(p, dt)
      p.throwT = max(0, p.throwT - dt)
      p.kickT = max(0, p.kickT - dt)
      if p.holdThrow then
        local mx, my = mouseWorld(0)
        p.face = atan2(my - p.y, mx - p.x)
        if not mouseDown(1) or not canAct(p) then
          if canAct(p) then throwGrenade(p) end
          p.holdThrow = false
        end
      elseif mouseDown(1) and canAct(p) and p.atkCd <= 0 then
        p.holdThrow = true
      end
    end,
    press = function(p, b)
      if b == 2 and p.cdR <= 0 and canAct(p) then
        p.kickT, p.cdR = .3, 1
        p.face = p.aim
        meleeArc(p.x, p.y, p.aim, 1.4, 1.0, 8, 17, 9)
        play("swing", .2, .9)
      end
    end,
    speedMul = function(p) return p.holdThrow and .75 or 1 end,
    cdMax = 1, rName = "발차기",
    pose = function(p, o)
      if p.kickT > 0 then o.kick = sin(min(1, (1 - p.kickT / .3) * 1.5) * pi * .5); o.lean = -.15 end
      local hipU, chF, chU = Rig.body(o.crouch, o.lean)
      o.weapon = "grenade"
      if p.holdThrow then
        o.rh = { chF - 14, 20, chU + 16 }; o.lh = { chF + 30, -10, chU }
      elseif p.throwT > 0 then
        o.rh = { chF + 30, 14, chU + 4 }; o.noGrenade = true
      else
        o.rh = { chF + 10, 18, hipU + 14 }
      end
    end,
  },
  -- 6 거너 -----------------------------------------------------------------
  {
    id = "gunner", name = "거너", tag = "시전 시간", hp = 120, speed = 4.6,
    desc = { "좌클릭 누르기  시전(게이지) 후 광선 발사", "시전·발사 중 이동 속도 감소", "쏘면서 천천히 방향 조절", "맞아도 끊기지 않음 · 과열 주의 / 우클릭 개머리판" },
    update = function(p, dt)
      p.buttT = max(0, p.buttT - dt)
      if p.overT > 0 then
        p.overT = p.overT - dt
        p.heat = max(0, p.heat - 60 * dt)
        p.gcast, p.beaming = 0, false
      elseif mouseDown(1) and not p.dash and not p.vault and p.hp > 0 then
        if not p.beaming then
          if p.gcast == 0 then p.beamDir = p.aim end
          p.gcast = p.gcast + dt
          p.face = turn(p.face, p.aim, dt * 8)
          p.beamDir = p.face
          if p.gcast >= .6 then p.beaming = true end
        else
          p.beamDir = turn(p.beamDir, p.aim, dt * 2.4)    -- 쏘며 방향 조절 (느리게)
          p.face = p.beamDir
          p.heat = p.heat + 26 * dt
          if p.heat >= 100 then
            p.heat, p.overT = 100, 1.6
            addText(p.x, p.y, "과열!", { 1, .5, .2 }, true)
          end
        end
      else
        p.gcast, p.beaming = 0, false
        p.heat = max(0, p.heat - 35 * dt)
      end
    end,
    press = function(p, b)
      if b == 2 and p.cdR <= 0 and canAct(p) and not p.beaming then
        p.buttT, p.cdR = .25, 1.2
        p.face = p.aim
        meleeArc(p.x, p.y, p.aim, 1.4, 1.0, 10, 15, 9)
        play("swing", .2, .9)
      end
    end,
    speedMul = function(p) return (p.beaming or p.gcast > 0) and .45 or 1 end,
    cdMax = 1.2, rName = "개머리판",
    gauge = function(p)
      if p.gcast > 0 and not p.beaming then return min(1, p.gcast / .6) end
    end,
    pose = function(p, o)
      if p.gcast > 0 then o.crouch = 5 end
      local hipU, chF, chU = Rig.body(o.crouch, o.lean)
      o.weapon = "gun"
      if p.buttT > 0 then
        o.rh = { chF + 30, 8, chU - 8 }; o.wdir = { -.2, 0, .98 }
      elseif p.gcast > 0 then
        local j = p.beaming and (rnd() - .5) * 2 or 0
        o.rh = { chF + 14 - (p.beaming and 2 or 0), 10, chU - 14 + j }; o.wdir = { 1, 0, 0 }
      else
        o.rh = { chF + 14, 12, chU - 22 }; o.wdir = { .9, 0, -.42 }
      end
      local wf, ws, wu = Rig.norm3(o.wdir[1], o.wdir[2], o.wdir[3])
      o.lh = { o.rh[1] + wf * 34, o.rh[2] - 10, o.rh[3] + wu * 34 }
      o.gunGlow = p.beaming and (.6 + .4 * rnd()) or 0
    end,
  },
}

-------------------------------------------------------------------------------
-- 플레이어 갱신 (이동, 대쉬, 벽 넘기)
-------------------------------------------------------------------------------
-- 앞쪽 낮은 벽을 넘는다 (넘어갈 자리가 있을 때만)
local function tryVault(p, dx, dy)
  for d = .3, 1.3, .1 do
    local h = cellH(p.x + dx * d, p.y + dy * d)
    if h > 0 then
      if h > LOW then return false end
      for d2 = d + .3, d + 3, .1 do
        local lx, ly = p.x + dx * d2, p.y + dy * d2
        local h2 = cellH(lx, ly)
        if h2 > LOW then return false end
        if h2 == 0 and freeCircle(lx, ly, p.r) then
          p.vault = { t = 0, dur = .26 + d2 * .06, x0 = p.x, y0 = p.y, x1 = lx, y1 = ly, h = h }
          p.dash = nil
          p.face = atan2(dy, dx)
          play("dash", .1, 1)
          return true
        end
      end
      return false
    end
  end
  return false
end

local function doDash(p)
  if p.dashCd > 0 or not canAct(p) or p.targeting or p.castT > 0 then return end
  local dx, dy = p.mvx or 0, p.mvy or 0
  if dx == 0 and dy == 0 then dx, dy = cos(p.face), sin(p.face) end
  p.charging, p.holdThrow, p.blocking, p.sw, p.kk, p.pu = false, false, false, nil, nil, nil
  p.gcast, p.beaming = 0, false
  p.dashCd = .7
  if tryVault(p, dx, dy) then return end
  p.dash = { t = 0, dur = .3, dx = dx, dy = dy }   -- 회피 덤블링 (몸을 말아 한 바퀴)
  p.inv = .32
  p.face = atan2(dy, dx)
  burst(p.x, p.y, .1, 6, { .55, .52, .4 }, 2, 3, .35)
  play("dash")
end

local function updatePlayer(dt)
  local p = player
  local st = p.style
  p.inv = p.inv - dt
  p.stagger = p.stagger - dt
  p.flash = max(0, p.flash - dt)
  p.dashCd = p.dashCd - dt
  p.cdR = max(0, p.cdR - dt)
  p.atkCd = p.atkCd - dt
  p.comboT = p.comboT - dt

  local mx, my = mouseWorld(1)
  p.aim = atan2(my - p.y, mx - p.x)

  local ix, iy = 0, 0
  if not p.targeting then
    if keyDown("a", "left") then ix = ix - 1 end
    if keyDown("d", "right") then ix = ix + 1 end
    if keyDown("w", "up") then iy = iy - 1 end
    if keyDown("s", "down") then iy = iy + 1 end
  end
  local dx, dy = norm(ix, iy)
  p.mvx, p.mvy = dx, dy

  if p.vault then
    local v = p.vault
    v.t = v.t + dt
    local k = min(1, v.t / v.dur)
    p.x, p.y = lerp(v.x0, v.x1, k), lerp(v.y0, v.y1, k)
    p.z = sin(k * pi) * (v.h + .45)
    p.moving = false
    if k >= 1 then p.vault = nil; p.z = 0; burst(p.x, p.y, .1, 5, { .55, .52, .4 }, 2, 3, .3) end
  elseif p.dash then
    local d = p.dash
    d.t = d.t + dt
    local sp = 13 * (1 - d.t / d.dur * .45)          -- 처음엔 빠르고 끝에 느려진다
    p.x, p.y = p.x + d.dx * sp * dt, p.y + d.dy * sp * dt
    -- 대쉬하다 낮은 벽에 닿으면 넘는다
    local fx, fy = p.x + d.dx * (p.r + .12), p.y + d.dy * (p.r + .12)
    local h = cellH(fx, fy)
    if h > 0 and h <= LOW then tryVault(p, d.dx, d.dy) end
    if d.t >= d.dur then p.dash = nil end
    p.moving = false
  else
    local spd = p.speed * st.speedMul(p)
    if p.stagger > 0 then spd = spd * .3 end
    p.x, p.y = p.x + dx * spd * dt, p.y + dy * spd * dt
    p.moving = (dx ~= 0 or dy ~= 0) and spd > 0
    if p.moving then
      p.walk = p.walk + dt * spd * 2.4
      local busy = p.sw or p.pu or p.kk or p.charging or p.blocking or p.holdThrow or p.gcast > 0 or p.dashSlash or p.targeting or p.castT > 0
      if not busy then p.face = turn(p.face, atan2(dy, dx), dt * 14) end
    end
  end
  p.x, p.y = p.x + p.kx * dt, p.y + p.ky * dt
  local k = max(0, 1 - dt * 9)
  p.kx, p.ky = p.kx * k, p.ky * k
  if not p.vault then collide(p, 0) end
  if not p.vault and not p.kk then p.z = 0 end      -- 슈퍼맨 펀치가 끊겨도 땅으로

  st.update(p, dt)

  -- 거너 광선
  if p.beaming then
    local mf = 14 + Rig.GUN_LEN                       -- 손 + 총 길이 (cm)
    local wx, wy = Rig.toWorld(p.face, mf * CS, 10 * CS, 0)
    local sx, sy = p.x + wx, p.y + wy
    local bdx, bdy = cos(p.beamDir), sin(p.beamDir)
    local L = 0
    while L < 15 do
      L = L + .1
      if cellH(sx + bdx * L, sy + bdy * L) > 1.2 then break end
    end
    p.beamL, p.beamX, p.beamY = L, sx, sy
    for _, e in ipairs(enemies) do
      if not e.dead then
        local ex, ey = e.x - sx, e.y - sy
        local along = ex * bdx + ey * bdy
        if along > 0 and along < L then
          local perp = abs(ex * -bdy + ey * bdx)
          if perp < e.r + .25 then
            e.beamTick = (e.beamTick or 0) - dt
            if e.beamTick <= 0 then
              e.beamTick = .12
              hitEnemy(e, 6.5, bdx, bdy, 2.2, 0)
              sparks(e.x, e.y, 1.2, -bdx, -bdy, 3, { 1, .9, .4 })
            end
          end
        end
      end
    end
    addShake(.05)
  end
end

-------------------------------------------------------------------------------
-- 적
-------------------------------------------------------------------------------
local function chaseDir(e, d)
  local tx, ty = floor(e.x), floor(e.y)
  local own = flow[ty] and flow[ty][tx]
  if (own and own <= 1) or d < 1.5 or not own then return norm(player.x - e.x, player.y - e.y) end
  local best, bx, by = own, nil, nil
  for oy = -1, 1 do
    for ox = -1, 1 do
      if ox ~= 0 or oy ~= 0 then
        local v = flow[ty + oy] and flow[ty + oy][tx + ox]
        if v and v < best and (ox == 0 or oy == 0 or (tileH(tx + ox, ty) == 0 and tileH(tx, ty + oy) == 0)) then
          best, bx, by = v, tx + ox, ty + oy
        end
      end
    end
  end
  if bx then return norm(bx + .5 - e.x, by + .5 - e.y) end
  return norm(player.x - e.x, player.y - e.y)
end

local function newEnemy(kind, x, y)
  local T = TYPES[kind]
  local hpMul = 1 + (wave - 1) * .1
  enemies[#enemies + 1] = {
    kind = kind, T = T, x = x, y = y, r = T.r, hp = T.hp * hpMul, maxhp = T.hp * hpMul,
    face = atan2(player.y - y, player.x - x), state = "chase", t = 0, cd = .6 + rnd() * T.cd, cd2 = 1,
    stun = 0, flash = 0, kx = 0, ky = 0, walk = rnd() * 6, aim = 0, hpShow = 0, moving = false,
    strafe = rnd() < .5 and 1 or -1, combo = 0, z = 0,
  }
  burst(x, y, .5, 12, { .5, .1, .1 }, 3, 4, .6)
end

-- 날아가는 적 / 시체가 다른 적과 부딪힌다: 맞은 적도 맞고 같은 쪽으로 날아간다 (연쇄)
local function bowl(src, x, y, r, vx, vy, hitSet)
  local spd = len(vx, vy)
  if spd < 3.5 then return vx, vy end
  for _, o in ipairs(enemies) do
    if o ~= src and not o.dead and not hitSet[o] and len(o.x - x, o.y - y) < o.r + r + .05 then
      hitSet[o] = true
      if AUTO then AUTO.bowls = (AUTO.bowls or 0) + 1 end
      local nx, ny = norm(o.x - x, o.y - y)
      local dx, dy = norm(vx / spd * .6 + nx * .4, vy / spd * .6 + ny * .4)
      o.lastKb = spd
      hitEnemy(o, 5 + spd * .7, dx, dy, 0, 0)          -- 날아가며 부딪힐 땐 히트스톱 없음 (흐름이 안 끊기게)
      if not o.dead then
        launchEnemy(o, dx, dy, spd * .78)
        if o.fly and src then o.fly.hit[src] = true end
      end
      fx[#fx + 1] = { kind = "pow", x = (x + o.x) / 2, y = (y + o.y) / 2, z = 1, t = 0, dur = .12 }
      burst((x + o.x) / 2, (y + o.y) / 2, 1, 6, { 1, .9, .6 }, 4, 3, .3)
      addShake(.15)
      vx, vy = vx * .62, vy * .62          -- 부딪힐 때마다 느려진다
      spd = spd * .62
      if spd < 3.5 then break end
    end
  end
  return vx, vy
end

launchEnemy = function(e, dx, dy, power)
  if e.dead then return end
  local v = power / e.T.mass ^ .6
  if v < 3 then e.kx, e.ky = e.kx + dx * v, e.ky + dy * v; return end
  e.fly = { vx = dx * v, vy = dy * v, hit = {}, t = 0 }
  e.z, e.vz = e.z or 0, 2.5 + v * .12
  e.state = "chase"
  e.stun = max(e.stun, .4)
end

local function updateFlying(e, dt)
  local f = e.fly
  f.t = f.t + dt
  e.flash = max(0, e.flash - dt)
  e.hitT = max(0, (e.hitT or 0) - dt)
  e.hpShow = max(0, e.hpShow - dt)
  e.x, e.y = e.x + f.vx * dt, e.y + f.vy * dt
  e.vz = e.vz - 20 * dt
  e.z = e.z + e.vz * dt
  if e.z <= 0 then e.z, e.vz = 0, 0 end
  local fr = max(0, 1 - dt * (e.z > 0 and 1 or 4.5))
  f.vx, f.vy = f.vx * fr, f.vy * fr
  f.vx, f.vy = bowl(e, e.x, e.y, e.r, f.vx, f.vy, f.hit)
  if e.dead then return end
  local spd = len(f.vx, f.vy)
  -- 벽에 박힘 (낮은 벽은 넘어서 날아간다)
  if collide(e, e.z) then
    if spd > 4 then
      e.fly = nil
      e.lastDx, e.lastDy, e.lastKb = -f.vx / spd, -f.vy / spd, 3
      hitEnemy(e, 8 + spd * .7, 0, 0, 0, 7)
      if not e.dead then e.stun = 1.3 end
      addText(e.x, e.y, "벽꽝!", { 1, .75, .3 }, true)
      if AUTO then AUTO.walls = (AUTO.walls or 0) + 1 end
      fx[#fx + 1] = { kind = "ring", x = e.x, y = e.y, r = 1, t = 0, dur = .25, col = { 1, .85, .5 } }
      burst(e.x, e.y, 1, 12, { .8, .74, .6 }, 4, 4, .5)
      addShake(.3)
      play("heavy", .2, .8)
      e.z = 0
      return
    end
    f.vx, f.vy = f.vx * .3, f.vy * .3
  end
  if spd < 2.2 and e.z <= 0 then e.fly = nil; e.stun = max(e.stun, .45) end
end

local function updateEnemy(e, dt)
  if e.fly then return updateFlying(e, dt) end
  local T, p = e.T, player
  e.flash = max(0, e.flash - dt)
  e.hitT = max(0, (e.hitT or 0) - dt)
  e.hpShow = max(0, e.hpShow - dt)
  e.cd, e.cd2 = e.cd - dt, e.cd2 - dt
  local dx, dy = p.x - e.x, p.y - e.y
  local d = len(dx, dy)
  local toP = atan2(dy, dx)
  local mvx, mvy, spd = 0, 0, 0

  if e.stun > 0 then
    e.stun = e.stun - dt
  elseif e.state == "chase" then
    if e.kind == "sword" then
      if d > T.range * .8 then mvx, mvy = chaseDir(e, d); spd = T.speed
      elseif e.cd <= 0 then e.state, e.t, e.aim, e.combo = "windup", T.windup, toP, (rnd() < .5) and 1 or 0 end
      e.face = turn(e.face, spd > 0 and atan2(mvy, mvx) or toP, dt * 9)
    elseif e.kind == "gun" then
      local see = d < 11 and los(e.x, e.y, p.x, p.y, 1.1)
      if not see or d > 8.5 then mvx, mvy = chaseDir(e, d); spd = T.speed
      elseif d < 4.5 then mvx, mvy = norm(-dx, -dy); spd = T.speed * .9
      else mvx, mvy = norm(-dy * e.strafe, dx * e.strafe); spd = T.speed * .45 end
      if see and d < 9.5 and e.cd <= 0 then e.state, e.t, e.aim = "windup", T.windup, toP end
      e.face = turn(e.face, toP, dt * 8)
    else
      if d < T.range + .2 and e.cd2 <= 0 then
        e.state, e.t, e.cd2 = "slamWind", .75, 3
      elseif d < 7 and d > 2.4 and e.cd <= 0 and los(e.x, e.y, p.x, p.y, .3) then
        e.state, e.t, e.aim = "windup", T.windup, toP
      else
        mvx, mvy = chaseDir(e, d); spd = T.speed
      end
      e.face = turn(e.face, toP, dt * 5)
    end
  elseif e.state == "windup" then
    e.t = e.t - dt
    if e.kind == "sword" then e.aim = turn(e.aim, toP, dt * 2.5) end
    if e.kind == "gun" and e.t > .2 then e.aim = turn(e.aim, toP, dt * 3) end   -- 마지막 0.2초는 조준 고정
    e.face = e.aim
    if e.t <= 0 then
      if e.kind == "sword" then
        e.state, e.t = "swing", .16
        e.kx, e.ky = e.kx + cos(e.aim) * 5, e.ky + sin(e.aim) * 5
        if d < T.range + p.r and abs(angDiff(toP, e.aim)) < 1.05 then
          hurtPlayer(T.dmg, e.x, e.y, 7, e, false)
        end
        play("swing", .2, .5)
      elseif e.kind == "gun" then
        local a = e.aim
        local wx, wy = Rig.toWorld(a, (14 + Rig.RIFLE_LEN) * CS * T.size, 10 * CS, 0)
        projs[#projs + 1] = { kind = "bullet", owner = "e", x = e.x + wx, y = e.y + wy, z = 1.15,
          vx = cos(a) * 16, vy = sin(a) * 16, dmg = T.dmg, life = 1.4, src = e, trail = {} }
        play("shot", .2, .5)
        e.state, e.t, e.cd = "recover", .35, T.cd * (.8 + rnd() * .4)
      else
        e.state, e.t, e.hitDone = "dash", .55, false
        play("dash", .1, 1)
      end
    end
  elseif e.state == "swing" then
    e.t = e.t - dt
    if e.t <= 0 then
      if e.combo > 0 then
        e.combo = e.combo - 1
        e.state, e.t, e.aim = "windup", .28, toP     -- 콤보 공격
      else
        e.state, e.t, e.cd = "recover", .45, T.cd
      end
    end
  elseif e.state == "dash" then
    e.t = e.t - dt
    mvx, mvy, spd = cos(e.aim), sin(e.aim), 11
    if rnd() < .5 then burst(e.x, e.y, .1, 1, { .5, .47, .35 }, 1.5, 4, .5) end
    if not e.hitDone and d < e.r + p.r + .2 then
      if hurtPlayer(T.dmg, e.x, e.y, 13, e, false) == "perfect" then e.state = "chase" end
      e.hitDone = true
    end
    if e.t <= 0 and e.state == "dash" then e.state, e.t, e.cd = "recover", .6, T.cd end
  elseif e.state == "slamWind" then
    e.t = e.t - dt
    e.face = turn(e.face, toP, dt * 3)
    if e.t <= 0 then
      if d < 2.2 then hurtPlayer(T.dmg, e.x, e.y, 11, e, false) end
      fx[#fx + 1] = { kind = "ring", x = e.x, y = e.y, r = 2.2, t = 0, dur = .35, col = { 1, .5, .3 } }
      burst(e.x, e.y, .1, 18, { .55, .5, .38 }, 5, 4, .6)
      addShake(.35)
      play("boom", .2, .5)
      e.state, e.t = "slam", .5
    end
  elseif e.state == "slam" or e.state == "recover" then
    e.t = e.t - dt
    if e.t <= 0 then e.state = "chase" end
  end

  local ox, oy = e.x, e.y
  e.x, e.y = e.x + (mvx * spd + e.kx) * dt, e.y + (mvy * spd + e.ky) * dt
  local k = max(0, 1 - dt * 8)
  e.kx, e.ky = e.kx * k, e.ky * k
  e.moving = spd > 0
  if spd > 0 then e.walk = e.walk + dt * spd * 2.6 end
  collide(e, 0)
  if e.state == "dash" and len(e.x - ox, e.y - oy) < spd * dt * .3 then
    e.state, e.t, e.cd = "recover", 1.0, T.cd
    e.stun = .8
    addShake(.3)
    burst(e.x, e.y, 1, 10, { .6, .58, .5 }, 3, 4, .5)
    play("boom", .3, .4)
  end
end

-- 죽으면 맞은 방향으로 튕겨 나가며 쓰러진다
killEnemy = function(e)
  e.dead = true
  kills = kills + 1
  local dx, dy = e.lastDx or cos(e.face + pi), e.lastDy or sin(e.face + pi)
  local kb = e.lastKb or 6
  local sp = (5 + kb * .5) / e.T.mass ^ .4
  corpses[#corpses + 1] = {
    T = e.T, x = e.x, y = e.y, z = 0, r = e.r * .8,
    vx = dx * sp, vy = dy * sp, vz = 3.5 + kb * .15,
    face = atan2(-dy, -dx),            -- 맞은 쪽을 보며 뒤로 넘어간다
    t = 0, fall = 0, walk = e.walk, spin = (rnd() - .5) * 2,
  }
  burst(e.x, e.y, 1, 14, { .7, .12, .1 }, 4, 3.5, .6)
  if rnd() < .12 then pickups[#pickups + 1] = { x = e.x, y = e.y, t = 0 } end
  play("die", .2, .7)
  -- 웨이브 마지막 적은 결정타 (크게 멈췄다가 느린 화면)
  local last = #waveQueue == 0 and #spawns == 0
  if last then for _, o in ipairs(enemies) do if not o.dead then last = false; break end end end
  if last and wave > 0 then hitStop(16); slowT = 1.4; addShake(.5) end
end

local function separate()
  local n = #enemies
  for i = 1, n do
    local a = enemies[i]
    for j = i + 1, n do
      local b = enemies[j]
      if a.fly or b.fly then goto nextPair end
      local dx, dy = b.x - a.x, b.y - a.y
      local rr = a.r + b.r
      local d2 = dx * dx + dy * dy
      if d2 < rr * rr and d2 > 1e-6 then
        local d = sqrt(d2)
        local push = rr - d
        local wa = b.T.mass / (a.T.mass + b.T.mass)
        local nx, ny = dx / d, dy / d
        a.x, a.y = a.x - nx * push * wa, a.y - ny * push * wa
        b.x, b.y = b.x + nx * push * (1 - wa), b.y + ny * push * (1 - wa)
      end
      ::nextPair::
    end
    local p = player
    if not p.vault and not p.dash and not a.fly then
      local dx, dy = a.x - p.x, a.y - p.y
      local rr = a.r + p.r
      local d2 = dx * dx + dy * dy
      if d2 < rr * rr and d2 > 1e-6 then
        local d = sqrt(d2)
        local push = rr - d
        a.x, a.y = a.x + dx / d * push * .75, a.y + dy / d * push * .75
        p.x, p.y = p.x - dx / d * push * .25, p.y - dy / d * push * .25
      end
    end
  end
end

-------------------------------------------------------------------------------
-- 투사체 · 범위 · 시체 · 웨이브
-------------------------------------------------------------------------------
local function explode(x, y)
  blast(x, y, 2.5, 32, 17, 10)                          -- 범위 공격으로 튕겨냄
  fx[#fx + 1] = { kind = "boom", x = x, y = y, r = 2.5, t = 0, dur = .45 }
  burst(x, y, .3, 26, { 1, .7, .25 }, 7, 4, .5)
  burst(x, y, .3, 14, { .3, .28, .25 }, 3, 6, 1, 2)
  addShake(.5)
  play("boom", .15, 1)
  local p = player
  if len(p.x - x, p.y - y) < 1.6 then hurtPlayer(10, x, y, 9) end   -- 너무 가까우면 나도 맞는다
end

local function updateProjs(dt)
  for i = #projs, 1, -1 do
    local b = projs[i]
    b.life = b.life - dt
    local dead = b.life <= 0
    if b.trail then
      table.insert(b.trail, 1, { b.x, b.y, b.z })
      if #b.trail > (b.power and 10 or 5) then b.trail[#b.trail] = nil end
    end
    if b.kind == "grenade" then
      b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
      b.vz = b.vz - b.g * dt
      b.z = b.z + b.vz * dt
      b.spin = b.spin + dt * 12
      if cellH(b.x, b.y) > b.z then b.vx, b.vy = 0, 0 end          -- 벽 옆면에 부딪히면 그 자리로 떨어진다
      if b.z <= 0 or (cellH(b.x, b.y) >= b.z and cellH(b.x, b.y) < 99) then
        explode(b.x, b.y)
        dead = true
      end
    else
      b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
      if cellH(b.x, b.y) > b.z then
        dead = true
        sparks(b.x, b.y, b.z, -b.vx, -b.vy, 4, b.owner == "p" and { .9, .85, .6 } or { 1, .8, .3 })
      end
      if not dead then
        if b.owner == "p" then
          for _, e in ipairs(enemies) do
            if not e.dead and not b.hit[e] and len(e.x - b.x, e.y - b.y) < e.r + .15 then
              b.hit[e] = true
              local nx, ny = norm(b.vx, b.vy)
              hitEnemy(e, b.dmg, nx, ny, b.kb, 0, b.power)
              if b.kind == "bolt" then
                burst(b.x, b.y, b.z, 8, { .6, .5, 1 }, 3, 3, .3)
              end
              b.pierce = b.pierce - 1
              if b.pierce <= 0 then dead = true; break end
            end
          end
        else
          local p = player
          if len(p.x - b.x, p.y - b.y) < p.r + .15 and p.z < 1 then
            local r = hurtPlayer(b.dmg, b.x - b.vx * .05, b.y - b.vy * .05, 5, b.src, true)
            if r then dead = true end
          end
        end
      end
    end
    if dead then table.remove(projs, i) end
  end
end

local function updateZones(dt)
  for i = #zones, 1, -1 do
    local z = zones[i]
    z.t = z.t + dt
    if z.t >= z.delay then
      if not z.started then
        z.started = true
        blast(z.x, z.y, z.r, 22, 6, 9)
        addShake(.35)
        play("zap", .1, 1)
      end
      z.tick = z.tick - dt
      if z.tick <= 0 then
        z.tick = .22
        for _, e in ipairs(enemies) do
          if not e.dead and len(e.x - z.x, e.y - z.y) < z.r + e.r then
            local nx, ny = norm(e.x - z.x, e.y - z.y)
            hitEnemy(e, 7, nx, ny, 1.5, 0)
          end
        end
        -- 번개 줄기
        for _ = 1, 3 do
          local a, r = rnd() * pi * 2, sqrt(rnd()) * z.r
          fx[#fx + 1] = { kind = "bolt", x = z.x + cos(a) * r, y = z.y + sin(a) * r, t = 0, dur = .16, seed = rnd() * 100 }
        end
      end
    end
    if z.t >= z.delay + z.dur then table.remove(zones, i) end
  end
end

local function updateCorpses(dt)
  for i = #corpses, 1, -1 do
    local c = corpses[i]
    c.t = c.t + dt
    c.fall = min(1, c.t / .38)
    c.x, c.y = c.x + c.vx * dt, c.y + c.vy * dt
    c.vz = c.vz - 22 * dt
    c.z = c.z + c.vz * dt
    if c.z <= 0 then
      if c.vz < -3 then burst(c.x, c.y, .1, 4, { .55, .5, .38 }, 2, 3, .4) end
      c.z, c.vz = 0, 0
      local k = max(0, 1 - dt * 7)
      c.vx, c.vy = c.vx * k, c.vy * k
    end
    -- 날아가는 시체도 다른 적을 쓰러뜨린다
    if c.z < 1.3 and c.t < 1.2 then
      c.hit = c.hit or {}
      c.vx, c.vy = bowl(nil, c.x, c.y, c.r, c.vx, c.vy, c.hit)
    end
    if collide(c, c.z) then c.vx, c.vy = -c.vx * .3, -c.vy * .3 end
    if c.t > 3.2 then table.remove(corpses, i) end
  end
end

local function findSpawn()
  for _ = 1, 80 do
    local x, y = rnd(2, MAPW - 1), rnd(2, MAPH - 1)
    local edge = x <= 4 or y <= 4 or x >= MAPW - 3 or y >= MAPH - 3
    if edge and tileH(x, y) == 0 and flow[y] and flow[y][x] then
      local d = len(x + .5 - player.x, y + .5 - player.y)
      if d > 9 then return x + .5, y + .5 end
    end
  end
  for _ = 1, 200 do
    local x, y = rnd(2, MAPW - 1), rnd(2, MAPH - 1)
    if tileH(x, y) == 0 and len(x - player.x, y - player.y) > 6 then return x + .5, y + .5 end
  end
end

local function startWave(n)
  wave = n
  waveQueue = {}
  local s = 3 + n * 2
  local g = n >= 2 and floor(n / 2) + 1 or 0
  local b = floor(n / 3)
  for _ = 1, s do waveQueue[#waveQueue + 1] = "sword" end
  for _ = 1, g do waveQueue[#waveQueue + 1] = "gun" end
  for _ = 1, b do waveQueue[#waveQueue + 1] = "brute" end
  for i = #waveQueue, 2, -1 do
    local j = rnd(1, i)
    waveQueue[i], waveQueue[j] = waveQueue[j], waveQueue[i]
  end
  spawnT = .8
  banner.text, banner.sub, banner.t = "웨이브 " .. n, (b > 0) and "돌격병이 섞여 있다" or "사방에서 몰려온다", 2.4
end

local function updateWaves(dt)
  for i = #spawns, 1, -1 do
    local s = spawns[i]
    s.t = s.t - dt
    if s.t <= 0 then newEnemy(s.kind, s.x, s.y); table.remove(spawns, i) end
  end
  if #waveQueue > 0 then
    spawnT = spawnT - dt
    if spawnT <= 0 and #enemies < 36 then
      local sx, sy = findSpawn()
      if sx then
        for _ = 1, min(#waveQueue, rnd(1, 3)) do
          local kind = table.remove(waveQueue)
          local x, y = sx + (rnd() - .5) * 1.4, sy + (rnd() - .5) * 1.4
          if cellH(x, y) > 0 then x, y = sx, sy end
          spawns[#spawns + 1] = { kind = kind, x = x, y = y, t = 1, dur = 1 }
        end
        play("spawn", .2, .6)
      end
      spawnT = max(.6, 2.2 - wave * .12)
    end
  elseif #enemies == 0 and #spawns == 0 then
    breakT = breakT - dt
    if breakT <= 0 then startWave(wave + 1); breakT = 3.5 end
  end
end

local function updateFx(dt)
  for i = #pts, 1, -1 do
    local q = pts[i]
    q.t = q.t + dt
    q.vz = q.vz - q.grav * dt
    q.x, q.y, q.z = q.x + q.vx * dt, q.y + q.vy * dt, q.z + q.vz * dt
    if q.z < 0 then q.z, q.vz = 0, -q.vz * .3; q.vx, q.vy = q.vx * .5, q.vy * .5 end
    if q.t >= q.life then table.remove(pts, i) end
  end
  for i = #fx, 1, -1 do
    local f = fx[i]
    f.t = f.t + dt
    if f.t >= f.dur then table.remove(fx, i) end
  end
  local p = player
  for i = #pickups, 1, -1 do
    local o = pickups[i]
    o.t = o.t + dt
    local d = len(p.x - o.x, p.y - o.y)
    if d < 2 then
      local nx, ny = norm(p.x - o.x, p.y - o.y)
      o.x, o.y = o.x + nx * 8 * dt, o.y + ny * 8 * dt
    end
    if d < .5 then
      p.hp = min(p.maxhp, p.hp + 20)
      addText(p.x, p.y, "+20", { .4, 1, .5 })
      play("pick")
      table.remove(pickups, i)
    elseif o.t > 14 then table.remove(pickups, i) end
  end
end

local function updateTexts(dt)
  for i = #texts, 1, -1 do
    local t = texts[i]
    t.t = t.t + dt
    t.z = t.z + dt * 1.5
    t.x = t.x + t.vx * dt
    if t.t >= t.life then table.remove(texts, i) end
  end
  if banner.t > 0 then banner.t = banner.t - dt end
end

local function updateCamera(dt)
  local p = player
  local tx, ty = p.x, p.y
  if state == "play" and not AUTO then
    local mx, my = mouseWorld(0)
    local lx, ly = mx - p.x, my - p.y
    local l = len(lx, ly)
    if l > 5 then lx, ly = lx / l * 5, ly / l * 5 end
    tx, ty = tx + lx * .15, ty + ly * .15
  end
  local k = 1 - math.exp(-dt * 7)
  cam.x, cam.y = lerp(cam.x, tx, k), lerp(cam.y, ty, k)
  shake = max(0, shake - dt * 1.8)
end

local function newGame()
  buildMap()
  player = newPlayer(styleIdx)
  enemies, projs, corpses, pts, texts, fx, zones, spawns, pickups = {}, {}, {}, {}, {}, {}, {}, {}, {}
  wave, kills, waveQueue, spawnT, breakT = 0, 0, {}, 0, 2
  banner.text, banner.sub, banner.t = STYLES[styleIdx].name, STYLES[styleIdx].tag, 2
  cam.x, cam.y = player.x, player.y
  flowTx, flowTy = nil, nil
  shake, freeze, slowT, gameTime = 0, 0, 0, 0
  buildFlow(floor(player.x), floor(player.y))
end

-- 진행 중인 판은 그대로 두고 캐릭터(전투 스타일)만 바꾼다
-- 위치·바라보는 방향·체력 비율은 이어받고, 스타일 전용 상태(모으기, 막기 등)는 새로 시작
local inGame = false            -- 판이 진행 중인지 (스타일 화면에서 돌아갈 곳)
local function switchStyle(i)
  local old = player
  styleIdx = i
  local p = newPlayer(i)
  p.x, p.y, p.face, p.aim, p.walk = old.x, old.y, old.face, old.aim, old.walk
  p.hp = max(1, floor(p.maxhp * old.hp / old.maxhp + .5))
  p.inv, p.dashCd = .6, old.dashCd
  player = p
  if beamSrc then beamSrc:stop() end
  banner.text, banner.sub, banner.t = STYLES[i].name, STYLES[i].tag, 1.6
  burst(p.x, p.y, 1, 16, { .4, .85, 1 }, 3, 3, .5)
  play("pick", .1)
end

-- 스타일 화면에서 고른 뒤: 판이 진행 중이면 이어서, 아니면 새 판
local function chooseStyle(i)
  if inGame and player.hp > 0 then
    switchStyle(i)
  else
    styleIdx = i
    newGame()
  end
  inGame = true
  state = "play"
  player.atkCd = .25
end

local function updatePlay(dt)
  local raw = dt
  if freeze <= 0 and slowT > 0 then slowT = slowT - dt; dt = dt * .3
  elseif slowT > 0 then dt = dt * .3 end
  gameTime = gameTime + dt
  updateTexts(dt)
  updateProjs(dt)                   -- 투사체는 히트스톱 중에도 날아간다
  if freeze > 0 then
    freeze = freeze - raw
    if freeze < 1e-6 then freeze = 0 end
  else
    local ptx, pty = floor(player.x), floor(player.y)
    if ptx ~= flowTx or pty ~= flowTy then buildFlow(ptx, pty); flowTx, flowTy = ptx, pty end
    updatePlayer(dt)
    for _, e in ipairs(enemies) do updateEnemy(e, dt) end
    separate()
    for i = #enemies, 1, -1 do if enemies[i].dead then table.remove(enemies, i) end end
    updateZones(dt)
    updateCorpses(dt)
    updateWaves(dt)
    updateFx(dt)
  end
  -- 광선 소리
  if beamSrc then
    if player.beaming and state == "play" then if not beamSrc:isPlaying() then beamSrc:play() end
    elseif beamSrc:isPlaying() then beamSrc:stop() end
  end
end

-------------------------------------------------------------------------------
-- 그리기
-------------------------------------------------------------------------------
local function camTransform(shx, shy)
  lg.translate(floor(W / 2 - cam.x * S + (shx or 0)), floor(H / 2 - cam.y * KY * S + (shy or 0)))
end
local function groundCircle(mode, x, y, r, seg)
  local sx, sy = proj(x, y, 0)
  lg.ellipse(mode, sx, sy, r * S, r * S * KY, seg or 40)
end
local function groundArc(x, y, r0, r1, a0, a1)
  local n = max(4, floor(abs(a1 - a0) * 10))
  for i = 0, n - 1 do
    local t0, t1 = a0 + (a1 - a0) * i / n, a0 + (a1 - a0) * (i + 1) / n
    local ax, ay = proj(x + cos(t0) * r0, y + sin(t0) * r0)
    local bx, by = proj(x + cos(t0) * r1, y + sin(t0) * r1)
    local cx, cy = proj(x + cos(t1) * r1, y + sin(t1) * r1)
    local dx, dy = proj(x + cos(t1) * r0, y + sin(t1) * r0)
    lg.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
  end
end

local viewX0, viewX1, viewY0, viewY1
local function computeView()
  viewX0 = floor(cam.x - W / S / 2) - 2
  viewX1 = ceil(cam.x + W / S / 2) + 2
  viewY0 = floor(cam.y - H / S / KY / 2) - 2
  viewY1 = ceil(cam.y + H / S / KY / 2) + 5
end

-- 배경 질감 (힉스필드 등으로 만든 그림): bg/ 폴더에 있으면 입히고, 없으면 예전 단색 그대로
--   floor      바닥 (이음매 없이 반복되는 그림, 위에서 내려다본 것)
--   wall_top   벽 윗면 (위에서 내려다본 것)
--   wall_front 벽 앞면 (정면에서 본 것, 그림 아래쪽이 땅)
-- BG_M = 그림 한 장이 덮는 크기 (미터). 캐릭터 키가 약 1.8m
local BG_M = { floor = 4, wall_top = 2, wall_front = 2 }
local bgtex = {}
local bgQuad = nil
local function loadBgTextures()
  for name in pairs(BG_M) do
    for _, ext in ipairs({ ".png", ".jpg", ".jpeg" }) do
      local path = "bg/" .. name .. ext
      if love.filesystem.getInfo(path) then
        local ok, img = pcall(lg.newImage, path, { mipmaps = true })
        if ok then
          img:setWrap("repeat", "repeat")
          img:setMipmapFilter("linear")
          bgtex[name] = img
          print("배경 질감 읽음: " .. path)
          break
        end
      end
    end
  end
  bgQuad = lg.newQuad(0, 0, 1, 1, 1, 1)
end
-- 질감 하나를 화면 사각형(sx, sy 위치)에 그린다. u, v = 그림 위 좌표(미터), w, h = 크기(미터), ppx, ppy = 1미터당 화면 픽셀
local function bgDraw(name, sx, sy, u, v, w, h, ppx, ppy)
  local img = bgtex[name]
  local iw, ih = img:getDimensions()
  local px, py = iw / BG_M[name], ih / BG_M[name]           -- 그림 픽셀 / 미터
  bgQuad:setViewport(u * px, v * py, w * px, h * py, iw, ih)
  lg.draw(img, bgQuad, sx, sy, 0, ppx / px, ppy / py)
end

-- 상자 벽 한 칸: 윗면 + (앞이 낮으면) 앞면 + 경계선
local function wallColors(h)
  if h <= LOW then return { .82, .77, .62 }, { .38, .34, .28 } end   -- 넘을 수 있는 낮은 벽: 밝게
  if h >= 2.3 then return { .56, .52, .44 }, { .1, .09, .08 } end
  return { .74, .67, .55 }, { .12, .1, .09 }
end
local function drawCell(x, y)
  local h = map[y][x]
  local top, front = wallColors(h)
  local x0, x1 = x * S, (x + 1) * S
  local yt0 = (y * KY - h * KZ) * S
  local yt1 = ((y + 1) * KY - h * KZ) * S
  local hs = tileH(x, y + 1)
  -- 높은 벽일수록 조금 어둡게 (질감에 곱하는 색)
  local tint = h <= LOW and 1 or (h >= 2.3 and .78 or .92)
  if hs < h then
    local zb = (hs == 99) and 0 or min(hs, h)
    local yb = ((y + 1) * KY - zb * KZ) * S
    if bgtex.wall_front then
      lg.setColor(tint, tint, tint)
      -- 그림 아래쪽이 땅(z=0)에 오도록: v = (10 - z)
      bgDraw("wall_front", x0, yt1, x, 10 - h, 1, h - zb, S, KZ * S)
    else
      lg.setColor(front)
      lg.rectangle("fill", x0, yt1, S, yb - yt1)
    end
  end
  if bgtex.wall_top then
    lg.setColor(tint, tint, tint)
    bgDraw("wall_top", x0, yt0, x, y, 1, 1, S, KY * S)
  else
    lg.setColor(top)
    lg.rectangle("fill", x0, yt0, S, yt1 - yt0)
  end
  if h <= LOW then
    -- 넘을 수 있다는 표시 (빗금)
    lg.setColor(.95, .78, .3, .45)
    lg.setLineWidth(2)
    lg.line(x0 + 6, yt1 - 4, x0 + 16, yt0 + 4)
    lg.line(x0 + 22, yt1 - 4, x0 + 32, yt0 + 4)
  end
  lg.setColor(0, 0, 0, .35)
  lg.setLineWidth(1)
  if tileH(x, y - 1) ~= h then lg.line(x0, yt0, x1, yt0) end
  if tileH(x - 1, y) ~= h then lg.line(x0, yt0, x0, yt1) end
  if tileH(x + 1, y) ~= h then lg.line(x1, yt0, x1, yt1) end
  if hs ~= h then lg.line(x0, yt1, x1, yt1) end
end

local function renderShadows(shx, shy)
  lg.push()
  lg.origin()
  lg.setCanvas(shadowCanvas)
  lg.clear(0, 0, 0, 0)
  camTransform(shx, shy)
  lg.setColor(0, 0, 0, 1)
  for y = max(1, viewY0), min(MAPH, viewY1) do
    for x = max(1, viewX0), min(MAPW, viewX1) do
      local h = map[y][x]
      if h > 0 then
        local ox, oy = SHX * h, SHY * h
        local c = {}
        for _, q in ipairs({ { x, y }, { x + 1, y }, { x + 1, y + 1 }, { x, y + 1 } }) do
          local ax, ay = proj(q[1], q[2])
          local bx, by = proj(q[1] + ox, q[2] + oy)
          c[#c + 1] = ax; c[#c + 1] = ay; c[#c + 1] = bx; c[#c + 1] = by
        end
        Rig.hullFill(c)
      end
    end
  end
  local function charShadow(x, y, z, r, h)
    local sx, sy = proj(x, y, 0)
    lg.ellipse("fill", sx, sy, r * S * 1.1, r * S * KY * 1.1)
    local tx, ty = proj(x + SHX * h * .8, y + SHY * h * .8, 0)
    lg.ellipse("fill", (sx + tx) / 2, (sy + ty) / 2, r * S * 1.2, r * S * KY * .8)
  end
  if state ~= "dead" and player.hp > 0 then charShadow(player.x, player.y, player.z, player.r, 1.7) end
  for _, e in ipairs(enemies) do charShadow(e.x, e.y, 0, e.r, 1.7 * e.T.size) end
  for _, c in ipairs(corpses) do charShadow(c.x, c.y, 0, c.r, .5) end
  lg.setCanvas()
  lg.pop()
end

local function drawGround()
  lg.setColor(.24, .25, .15)
  lg.rectangle("fill", (cam.x - 40) * S, (cam.y - 40) * KY * S, 80 * S, 80 * KY * S)
  local x0, y0 = proj(1, 1)
  local x1, y1 = proj(MAPW + 1, MAPH + 1)
  if bgtex.floor then
    -- 질감 바닥: 얼룩·격자 없이 그림 그대로
    lg.setColor(1, 1, 1)
    bgDraw("floor", x0, y0, 1, 1, MAPW, MAPH, S, KY * S)
    return
  end
  lg.setColor(.47, .47, .27)
  lg.rectangle("fill", x0, y0, x1 - x0, y1 - y0)
  for _, b in ipairs(blots) do
    lg.setColor(.3, .3, .12, b.a)
    groundCircle("fill", b.x, b.y, b.r, 24)
  end
  lg.setColor(0, 0, 0, .05)
  lg.setLineWidth(1)
  for x = 2, MAPW, 2 do local a, b = proj(x, 1); local c, d = proj(x, MAPH + 1); lg.line(a, b, c, d) end
  for y = 2, MAPH, 2 do local a, b = proj(1, y); local c, d = proj(MAPW + 1, y); lg.line(a, b, c, d) end
end

-- 바닥 위 표시: 적 공격 예고, 소환, 범위 지정, 착탄 지점
local function drawGroundMarks()
  local p = player
  for _, s in ipairs(spawns) do
    local k = 1 - s.t / s.dur
    lg.setColor(.35, .05, .05, .3 + .4 * k)
    groundCircle("fill", s.x, s.y, .25 + .5 * k)
    lg.setColor(.9, .2, .15, .8)
    lg.setLineWidth(2)
    groundCircle("line", s.x, s.y, .8 - .4 * k)
  end
  for _, e in ipairs(enemies) do
    local T = e.T
    if e.state == "windup" then
      local k = clamp(1 - e.t / T.windup, 0, 1)
      if e.kind == "sword" then
        lg.setColor(1, .15, .1, .2); groundArc(e.x, e.y, 0, T.range + .1, e.aim - 1.05, e.aim + 1.05)
        lg.setColor(1, .2, .1, .35); groundArc(e.x, e.y, 0, (T.range + .1) * k, e.aim - 1.05, e.aim + 1.05)
      elseif e.kind == "brute" then
        local L = 6
        local ux, uy = cos(e.aim), sin(e.aim)
        local vx, vy = -uy * e.r, ux * e.r
        local function q(t, a)
          local ax, ay = proj(e.x + vx, e.y + vy)
          local bx, by = proj(e.x - vx, e.y - vy)
          local cx, cy = proj(e.x - vx + ux * L * t, e.y - vy + uy * L * t)
          local dx, dy = proj(e.x + vx + ux * L * t, e.y + vy + uy * L * t)
          lg.setColor(1, .15, .1, a)
          lg.polygon("fill", ax, ay, bx, by, cx, cy, dx, dy)
        end
        q(1, .15); q(k, .3)
      end
    elseif e.state == "slamWind" then
      local k = clamp(1 - e.t / .75, 0, 1)
      lg.setColor(1, .15, .1, .15); groundCircle("fill", e.x, e.y, 2.2)
      lg.setColor(1, .2, .1, .3); groundCircle("fill", e.x, e.y, 2.2 * k)
    end
  end
  for _, z in ipairs(zones) do
    if z.t < z.delay then
      local k = z.t / z.delay
      lg.setColor(1, .2, .1, .9); lg.setLineWidth(2.5); groundCircle("line", z.x, z.y, z.r)
      lg.setColor(1, .3, .1, .18 + .2 * k); groundCircle("fill", z.x, z.y, z.r * k)
    else
      local k = (z.t - z.delay) / z.dur
      lg.setColor(.95, .8, .3, .3 * (1 - k * .6)); groundCircle("fill", z.x, z.y, z.r)
      lg.setColor(1, .9, .4, .5 * (1 - k)); lg.setLineWidth(2); groundCircle("line", z.x, z.y, z.r)
    end
  end
  if state == "play" then
    if p.targeting then
      lg.setColor(1, .25, .15, .9); lg.setLineWidth(2.5)
      groundCircle("line", p.tx, p.ty, 2.6)
      lg.setColor(1, .25, .15, .12); groundCircle("fill", p.tx, p.ty, 2.6)
      lg.setColor(1, 1, 1, .25); lg.setLineWidth(1); groundCircle("line", p.x, p.y, 9, 64)
    end
    if p.holdThrow then
      local mx, my = mouseWorld(0)
      local dx, dy = mx - p.x, my - p.y
      local d = len(dx, dy)
      if d > 9 then mx, my, d = p.x + dx / d * 9, p.y + dy / d * 9, 9 end
      lg.setColor(1, .6, .2, .9); lg.setLineWidth(2); groundCircle("line", mx, my, 2.5)
      lg.setColor(1, .6, .2, .12); groundCircle("fill", mx, my, 2.5)
      -- 포물선 미리보기
      local T = .55 + d * .035
      local vz = (24 * T * T / 2 - 1.6) / T
      local ptsA = {}
      for i = 0, 16 do
        local t = T * i / 16
        local sx, sy = proj(p.x + (mx - p.x) * i / 16, p.y + (my - p.y) * i / 16, max(0, 1.6 + vz * t - 12 * t * t))
        ptsA[#ptsA + 1] = sx; ptsA[#ptsA + 1] = sy
      end
      lg.setColor(1, .8, .4, .6); lg.setLineWidth(1.5); lg.line(ptsA)
    end
  end
  for _, o in ipairs(pickups) do
    lg.setColor(.3, 1, .4, .25 + .1 * sin(o.t * 6)); groundCircle("fill", o.x, o.y, .35)
  end
end

local function poseFor(p, o)
  o.tm, o.fl = realTime, p.flash > 0
  o.face = snap8(p.face)
  if p.beaming or p.gcast > 0 then o.face = p.face end      -- 광선은 부드럽게 돈다
  o.walk, o.moving = p.walk, p.moving
  o.crouch, o.lean, o.tuck, o.kick, o.fall = 0, p.moving and .1 or 0, false, nil, 0
  o.rh, o.lh, o.wdir, o.sdir, o.trail, o.legs = nil, nil, { 1, 0, 0 }, { 1, 0, 0 }, nil, nil
  o.pull, o.nock, o.nockPower, o.orb, o.wglow, o.gunGlow, o.blockFlash, o.noGrenade = nil, nil, nil, nil, nil, nil, nil, nil
  o.col, o.col2, o.visor, o.mark = PCOL, PCOL2, VISOR, nil
  o.accent = ACCENT[p.style.id]
  o.handR, o.handCol = nil, nil
  if p.stagger > 0 then o.lean = -.2 end
  local rolling = p.vault or p.dash
  if rolling then o.tuck = true; o.crouch = 22; o.lean = .5 end
  p.style.pose(p, o)
  if rolling then
    -- 웅크려 구르기: 두 손으로 무릎을 감싼다
    o.crouch, o.lean, o.trail = 22, .5, nil
    local hipU, chF, chU = Rig.body(22, .5)
    o.rh, o.lh = { chF + 22, 11, hipU - 4 }, { chF + 22, -11, hipU - 2 }
    o.pull, o.nock = nil, nil
  end
  if p.dash then o.face = snap8(atan2(p.dash.dy, p.dash.dx)) end
end

local heroO = {}
local function drawPlayer(alphaMul)
  local p = player
  local o = heroO
  poseFor(p, o)
  local sx, sy = proj(p.x, p.y, p.z)
  if p.kk then
    -- 슈퍼맨 펀치: 발끝을 축으로 눕히므로, 몸 가운데가 제자리에 오도록 뒤로 옮긴다
    local bx, by = proj(p.x - cos(p.face) * .85, p.y - sin(p.face) * .85, p.z)
    sx, sy = bx, by
  end
  lg.push()
  lg.translate(sx, sy)
  lg.scale(CS)
  -- 덤블링: 웅크린 몸을 구르는 방향으로 한 바퀴 (벽 넘기는 공중제비)
  local rk, rdx
  if p.dash then rk, rdx = p.dash.t / p.dash.dur, p.dash.dx
  elseif p.vault then rk, rdx = min(1, p.vault.t / p.vault.dur), cos(p.face) end
  if rk then
    local cy = -20
    lg.translate(0, cy - (p.dash and sin(rk * pi) * 6 or 0))
    lg.rotate(rk * pi * 2 * ((rdx or 1) >= -.05 and 1 or -1))
    lg.translate(0, -cy)
  end
  local al = (alphaMul or 1)
  if p.inv > 0 and not p.dash and not p.vault and not p.kk and floor(realTime * 20) % 2 == 0 then al = al * .4 end
  Rig.withAlpha(al, Rig.human, o)
  lg.pop()
end

local enemyO = {}
local function drawEnemy(e)
  local T = e.T
  local o = enemyO
  o.tm, o.fl = realTime, e.flash > 0
  o.face, o.walk, o.moving = snap8(e.face), e.walk, e.moving
  o.crouch, o.lean, o.tuck, o.kick, o.fall = 0, e.moving and .1 or 0, false, nil, 0
  o.rh, o.lh, o.wdir, o.sdir, o.trail, o.wglow, o.gunGlow = nil, nil, { 1, 0, 0 }, nil, nil, nil, nil
  o.col, o.col2, o.visor, o.mark, o.weapon = T.col, { .25, .08, .07 }, { 1, .85, .3 }, nil, T.weapon
  o.accent = { .32, .09, .08 }
  local st = e.state
  if e.stun > 0 then o.lean = -.25 end
  if e.fly then
    -- 날아가는 중: 맞은 쪽을 보며 뒤로 젖혀진 채 팔다리가 벌어진다
    o.face = atan2(-e.fly.vy, -e.fly.vx)
    o.fall = .55
    o.moving = false
    local hipU, chF, chU = Rig.body(0, 0)
    o.rh = { chF + 6, 30, chU + 12 }; o.lh = { chF + 6, -30, chU + 14 }
    o.wdir = { -.3, .6, .7 }
    local sx, sy = proj(e.x, e.y, e.z)
    lg.push(); lg.translate(sx, sy); lg.scale(T.size * CS)
    Rig.human(o)
    lg.pop()
    return
  end
  if (st == "windup" and e.kind == "brute") or st == "dash" then o.crouch, o.lean = 12, .45 end
  -- 맞으면 상체가 뒤로 움찔: 확 젖혀졌다가 빠르게 돌아온다 (덩치 큰 돌격병은 덜 움찔)
  if (e.hitT or 0) > 0 then
    local k = 1 - e.hitT / HIT_FLINCH
    local amt = (e.kind == "brute") and .28 or .5
    -- 맞은 방향으로 젖힌다: 앞에서 맞으면 뒤로, 뒤에서 맞으면 앞으로
    local d = (e.lastDx or -cos(e.face)) * cos(e.face) + (e.lastDy or -sin(e.face)) * sin(e.face)
    local sgn = d >= 0 and max(.5, d) or min(-.5, d)
    o.lean = o.lean + sgn * amt * sin(min(1, k * 1.6) * pi) * (1 - k * .4)
    o.crouch = o.crouch + 5 * (1 - k)
  end
  local hipU, chF, chU = Rig.body(o.crouch, o.lean)
  if e.kind == "sword" or e.kind == "brute" then
    if (st == "windup" and e.kind == "sword") or st == "slamWind" then
      o.rh = { chF - 6, 16, chU + 26 }; o.wdir = { -.45, .1, .88 }; o.wglow = true
      o.lh = { chF + 4, -10, chU + 22 }
    elseif st == "windup" or st == "dash" then
      o.rh = { chF + 24, 16, chU - 12 }; o.wdir = { 1, .05, .1 }; o.wglow = st == "windup"
    elseif st == "swing" or st == "slam" then
      local t = (st == "swing") and (1 - e.t / .16) or 1
      local a0, a1 = 2.2, -.6
      local a = a0 + (a1 - a0) * min(1, t)
      o.rh = { chF + 8 + cos(a) * 28, 10, chU - 4 + sin(a) * 28 }; o.wdir = { cos(a), .05, sin(a) }
      o.trail = { kind = "v", a0 = a0, a = a, r = 132, cf = chF + 8, cs = 10, cu = chU - 4, w = 8,
        alpha = st == "slam" and e.t / .5 or 1 }
    elseif st == "recover" then
      o.rh = { chF + 26, 12, chU - 32 }; o.wdir = { .85, 0, -.5 }
    else
      o.rh = { chF + 14, 16, hipU + 12 }; o.wdir = { .7, .2, -.65 }
    end
  else
    if st == "windup" then
      o.rh = { chF + 14, 10, chU - 14 }; o.wdir = { 1, 0, 0 }
      o.face = e.aim
    else
      o.rh = { chF + 14, 12, chU - 22 }; o.wdir = { .9, 0, -.42 }
    end
    o.lh = { o.rh[1] + o.wdir[1] * 30, o.rh[2] - 10, o.rh[3] + o.wdir[3] * 30 }
  end
  local sx, sy = proj(e.x, e.y, 0)
  lg.push()
  lg.translate(sx, sy)
  lg.scale(T.size * CS)
  Rig.human(o)
  lg.pop()
end

local corpseO = {}
local function drawCorpse(c)
  local o = corpseO
  local a = c.t > 2.4 and max(0, 1 - (c.t - 2.4) / .8) or 1
  o.tm, o.fl = realTime, c.t < .08
  o.face, o.walk, o.moving = c.face + c.spin * c.fall * .3, c.walk, false
  o.crouch, o.lean, o.tuck, o.kick, o.fall = 0, 0, false, nil, c.fall
  o.rh, o.lh, o.wdir, o.trail, o.wglow, o.gunGlow = nil, nil, { .3, .5, -.8 }, nil, nil, nil
  o.col, o.col2, o.visor, o.mark, o.weapon = shade3(c.T.col), { .2, .07, .06 }, { .3, .25, .2 }, nil, nil
  local hipU, chF, chU = Rig.body(0, 0)
  o.rh = { chF + 10, 30, chU + 10 * c.fall }; o.lh = { chF + 10, -30, chU + 12 * c.fall }   -- 팔이 벌어진다
  local sx, sy = proj(c.x, c.y, c.z)
  lg.push()
  lg.translate(sx, sy)
  lg.scale(c.T.size * CS)
  Rig.withAlpha(a, Rig.human, o)
  lg.pop()
end
function shade3(c) return { c[1] * .75, c[2] * .75, c[3] * .75 } end

local function drawProj(b)
  if b.kind == "grenade" then
    local sx, sy = proj(b.x, b.y, b.z)
    lg.setColor(.07, .06, .06); lg.circle("fill", sx, sy, 5.2)
    lg.setColor(.3, .4, .22); lg.circle("fill", sx, sy, 4)
    lg.setColor(1, .8, .3, .6 + .4 * sin(realTime * 30)); lg.circle("fill", sx + cos(b.spin) * 2, sy + sin(b.spin) * 2, 1.5)
    return
  end
  local sx, sy = proj(b.x, b.y, b.z)
  local tr = b.trail
  if tr and #tr > 1 then
    local ex, ey = proj(tr[#tr][1], tr[#tr][2], tr[#tr][3])
    if b.kind == "bullet" then
      lg.setColor(1, .85, .3, .9); lg.setLineWidth(2); lg.line(ex, ey, sx, sy)
    elseif b.kind == "bolt" then
      lg.setColor(.6, .5, 1, .6); lg.setLineWidth(5); lg.line(ex, ey, sx, sy)
    elseif b.power then
      lg.setColor(1, .9, .3, .55); lg.setLineWidth(6); lg.line(ex, ey, sx, sy)
    end
  end
  if b.kind == "arrow" then
    local nx, ny = norm(b.vx, b.vy)
    local bx, by = proj(b.x - nx * .7, b.y - ny * .7, b.z)
    lg.setColor(.07, .06, .06); lg.setLineWidth(3.4); lg.line(bx, by, sx, sy)
    lg.setColor(b.power and { 1, .92, .4 } or { .9, .82, .6 }); lg.setLineWidth(1.8); lg.line(bx, by, sx, sy)
  elseif b.kind == "bolt" then
    lg.setColor(.8, .75, 1); lg.circle("fill", sx, sy, 4)
  else
    lg.setColor(1, .95, .6); lg.circle("fill", sx, sy, 2.2)
  end
end

local function drawPickup(o)
  local sx, sy = proj(o.x, o.y, .4 + sin(o.t * 4) * .08)
  lg.setColor(.07, .06, .06); lg.circle("fill", sx, sy, 6.5)
  lg.setColor(.35, .95, .45); lg.circle("fill", sx, sy, 5)
  lg.setColor(1, 1, 1); lg.rectangle("fill", sx - 1, sy - 3.5, 2, 7); lg.rectangle("fill", sx - 3.5, sy - 1, 7, 2)
end

local function drawParticle(q)
  local sx, sy = proj(q.x, q.y, q.z)
  local k = 1 - q.t / q.life
  lg.setColor(q.col[1], q.col[2], q.col[3], k)
  local s = q.size * (.5 + k * .5)
  lg.rectangle("fill", sx - s / 2, sy - s / 2, s, s)
end

local items = {}
local function drawSorted()
  for i = #items, 1, -1 do items[i] = nil end
  local function add(k, kind, o) items[#items + 1] = { k = k, kind = kind, o = o } end
  for y = max(1, viewY0), min(MAPH, viewY1) do
    for x = max(1, viewX0), min(MAPW, viewX1) do
      if map[y][x] > 0 then add(y + 1, "cell", x + y * 1000) end
    end
  end
  if player.hp > 0 then add(player.y, "player", player) end
  for _, e in ipairs(enemies) do add(e.y, "enemy", e) end
  for _, c in ipairs(corpses) do add(c.y, "corpse", c) end
  for _, b in ipairs(projs) do add(b.y, "proj", b) end
  for _, o in ipairs(pickups) do add(o.y, "pickup", o) end
  for _, q in ipairs(pts) do if not q.glow then add(q.y, "pt", q) end end
  table.sort(items, function(a, b) return a.k < b.k end)
  for _, it in ipairs(items) do
    local k = it.kind
    if k == "cell" then drawCell(it.o % 1000, floor(it.o / 1000))
    elseif k == "player" then drawPlayer()
    elseif k == "enemy" then drawEnemy(it.o)
    elseif k == "corpse" then drawCorpse(it.o)
    elseif k == "proj" then drawProj(it.o)
    elseif k == "pickup" then drawPickup(it.o)
    else drawParticle(it.o) end
  end
end

-- 번개 한 줄기 (하늘에서 바닥까지 지그재그)
local function drawBolt(f)
  local sx, sy = proj(f.x, f.y, 0)
  local tx, ty = proj(f.x, f.y, 6)
  local ptsL = { tx, ty }
  local n = 7
  for i = 1, n - 1 do
    local t = i / n
    ptsL[#ptsL + 1] = lerp(tx, sx, t) + sin(f.seed + i * 7.1) * 9
    ptsL[#ptsL + 1] = lerp(ty, sy, t)
  end
  ptsL[#ptsL + 1] = sx; ptsL[#ptsL + 1] = sy
  local a = 1 - f.t / f.dur
  lg.setColor(1, .95, .5, .5 * a); lg.setLineWidth(6); lg.line(ptsL)
  lg.setColor(1, 1, .85, a); lg.setLineWidth(2); lg.line(ptsL)
end

local function drawEffects()
  lg.setBlendMode("add")
  for _, f in ipairs(fx) do
    local k = f.t / f.dur
    if f.kind == "ring" then
      lg.setColor(f.col[1], f.col[2], f.col[3], .6 * (1 - k))
      local r = f.r * (.3 + .7 * k)
      groundArc(f.x, f.y, r * .8, r, 0, pi * 2)
    elseif f.kind == "boom" then
      lg.setColor(1, .75, .3, .55 * (1 - k)); groundCircle("fill", f.x, f.y, f.r * (.4 + .6 * k))
      local sx, sy = proj(f.x, f.y, .8)
      lg.setColor(1, .9, .6, .8 * (1 - k)); lg.circle("fill", sx, sy, (1 - k) * 30 + 6)
    elseif f.kind == "bolt" then
      drawBolt(f)
    elseif f.kind == "fan" then
      -- 돌려차기 부채꼴: 다리가 쓸고 간 자리
      lg.setColor(1, .9, .6, .45 * (1 - k))
      groundArc(f.x, f.y, f.r * .35, f.r * (.85 + .15 * k), f.a - f.half, f.a + f.half)
    elseif f.kind == "pow" then
      -- 주먹이 꽂힌 자리: 하얀 섬광 + 뾰족한 별
      local sx, sy = proj(f.x, f.y, f.z)
      local r = (f.big and 22 or 13) * (.6 + k * .6)
      lg.setColor(1, 1, .9, .9 * (1 - k)); lg.circle("fill", sx, sy, r * .45)
      lg.setColor(1, .85, .5, .8 * (1 - k)); lg.setLineWidth(f.big and 3 or 2)
      for i = 0, 7 do
        local a = i * pi / 4 + (f.big and .2 or 0)
        local r1 = (i % 2 == 0) and r or r * .6
        lg.line(sx + cos(a) * r * .3, sy + sin(a) * r * .3, sx + cos(a) * r1, sy + sin(a) * r1)
      end
    end
  end
  -- 거너 광선
  local p = player
  if p.beaming and p.beamL and state == "play" then
    local ax, ay = proj(p.beamX, p.beamY, 1.48)
    local bx, by = proj(p.beamX + cos(p.beamDir) * p.beamL, p.beamY + sin(p.beamDir) * p.beamL, 1.48)
    local w = 7 + sin(realTime * 60) * 2
    lg.setColor(1, .8, .3, .35); lg.setLineWidth(w * 2.2); lg.line(ax, ay, bx, by)
    lg.setColor(1, .95, .6, .9); lg.setLineWidth(w * .6); lg.line(ax, ay, bx, by)
    lg.setColor(1, .9, .5, .7); lg.circle("fill", bx, by, 6 + rnd() * 4)
  end
  for _, q in ipairs(pts) do
    if q.glow then
      local sx, sy = proj(q.x, q.y, q.z)
      local kk = 1 - q.t / q.life
      lg.setColor(q.col[1], q.col[2], q.col[3], kk)
      lg.circle("fill", sx, sy, q.size * kk)
    end
  end
  lg.setBlendMode("alpha")
end

local function drawBars()
  local p = player
  -- 내 체력 (머리 위 초록, 영상처럼)
  if p.hp > 0 then
    local gx, gy = worldToGame(p.x, p.y, p.z + 2.55)
    lg.setColor(0, 0, 0, .6); lg.rectangle("fill", gx - 21, gy - 1, 42, 6)
    lg.setColor(.3, .95, .4); lg.rectangle("fill", gx - 20, gy, 40 * p.hp / p.maxhp, 4)
    -- 게이지 (모으기 / 시전)
    local g = p.style.gauge and p.style.gauge(p)
    if g then
      local bx, by = worldToGame(p.x, p.y, 0)
      lg.setColor(0, 0, 0, .6); lg.rectangle("fill", bx - 23, by + 12, 46, 7)
      lg.setColor(g >= 1 and { 1, .9, .3 } or { 1, 1, 1 }); lg.rectangle("fill", bx - 22, by + 13, 44 * g, 5)
    end
    if p.style.id == "gunner" and p.heat > 0 then
      local bx, by = worldToGame(p.x, p.y, 0)
      lg.setColor(0, 0, 0, .5); lg.rectangle("fill", bx - 23, by + 21, 46, 4)
      lg.setColor(p.overT > 0 and { 1, .3, .2 } or { 1, .6, .2 }); lg.rectangle("fill", bx - 22, by + 22, 44 * p.heat / 100, 2)
    end
  end
  for _, e in ipairs(enemies) do
    if e.hpShow > 0 or e.kind == "brute" then
      local gx, gy = worldToGame(e.x, e.y, 2.55 * e.T.size)
      local w = e.kind == "brute" and 44 or 30
      lg.setColor(0, 0, 0, .6); lg.rectangle("fill", gx - w / 2 - 1, gy - 1, w + 2, 5)
      lg.setColor(.95, .25, .2); lg.rectangle("fill", gx - w / 2, gy, w * max(0, e.hp / e.maxhp), 3)
    end
  end
  for _, t in ipairs(texts) do
    local gx, gy = worldToGame(t.x, t.y, t.z)
    local a = 1 - (t.t / t.life) ^ 2
    lg.setColor(t.col[1], t.col[2], t.col[3])
    txt(t.s, gx - 70, gy, t.big and fontM or fontS, "center", 140, a)
  end
end

-- 이름 첫 글자 (한글 1자)
function utf8sub(s)
  local u = require("utf8")
  local o = u.offset(s, 2)
  return o and s:sub(1, o - 1) or s
end

-- 스킬 버튼: 준비되면 노란색으로 켜지고, 막 준비된 순간엔 한 번 번쩍인다
local readyAt = {}
local function cdIcon(x, y, key, label, frac)
  local ready = frac <= 0
  if ready and not readyAt[key] then readyAt[key] = realTime end
  if not ready then readyAt[key] = nil end
  if ready then
    lg.setColor(1, .78, .15, .92); lg.rectangle("fill", x, y, 64, 40, 5)
    lg.setColor(1, .95, .6); lg.setLineWidth(2); lg.rectangle("line", x, y, 64, 40, 5)
    local since = realTime - readyAt[key]
    if since < .35 then                                    -- 막 준비됨: 번쩍 + 테두리 퍼짐
      local k = since / .35
      lg.setColor(1, 1, .85, .7 * (1 - k)); lg.rectangle("fill", x, y, 64, 40, 5)
      lg.setColor(1, .9, .4, 1 - k); lg.setLineWidth(2)
      lg.rectangle("line", x - k * 8, y - k * 8, 64 + k * 16, 40 + k * 16, 6)
    end
    lg.setColor(.15, .1, .02); lg.setFont(fontS)
    lg.printf(label, x, y + 19, 64, "center")
    lg.print(key, x + 4, y + 2)
  else
    lg.setColor(.12, .12, .12, .75); lg.rectangle("fill", x, y, 64, 40, 5)
    lg.setColor(.7, .62, .3, .9); lg.rectangle("fill", x, y + 40 * frac, 64, 40 * (1 - frac), 5)   -- 차오르는 노랑
    lg.setColor(1, 1, 1, .3); lg.setLineWidth(1.5); lg.rectangle("line", x, y, 64, 40, 5)
    lg.setColor(1, 1, 1, .55)
    txt(label, x, y + 19, fontS, "center", 64)
    lg.setColor(1, .85, .4, .7)
    txt(key, x + 4, y + 2, fontS)
  end
end

local function drawHUD()
  local p = player
  local st = p.style
  -- 웨이브
  lg.setColor(1, 1, 1)
  local left = #enemies + #spawns + #waveQueue
  txt(wave > 0 and ("웨이브 " .. wave .. "   ·   남은 적 " .. left) or "준비", 0, 10, fontM, "center", W)
  lg.setColor(.85, .85, .85); txt("처치 " .. kills, 12, 10, fontS)
  -- 스타일 / 조작 안내
  lg.setColor(0, 0, 0, .45); lg.rectangle("fill", 8, H - 108, 300, 100, 6)
  lg.setColor(.4, .85, 1); txt(st.name .. "  —  " .. st.tag, 18, H - 102, fontM)
  lg.setColor(.92, .92, .92)
  for i, l in ipairs(st.desc) do txt(l, 18, H - 102 + 6 + i * 18, fontS) end
  -- 체력 / 쿨타임
  local bw = 260
  local bx = W - bw - 16
  lg.setColor(0, 0, 0, .55); lg.rectangle("fill", bx - 3, H - 34, bw + 6, 20, 4)
  lg.setColor(.3, .9, .4); lg.rectangle("fill", bx, H - 31, bw * p.hp / p.maxhp, 14, 3)
  lg.setColor(1, 1, 1); txt(floor(p.hp) .. " / " .. p.maxhp, bx, H - 32, fontS, "center", bw)
  cdIcon(W - 150, H - 82, "Spc", "덤블링", max(0, p.dashCd) / .7)
  if st.rName then cdIcon(W - 80, H - 82, "우", st.rName, st.cdMax and p.cdR / st.cdMax or 0) end
  lg.setColor(.7, .7, .7); txt("1~" .. #STYLES .. " 캐릭터 교체   Tab 목록   R 체력 채우기(개발자)   Esc 일시정지", W - 460, 10, fontS, "right", 448)
  -- 지금 캐릭터 표시
  for i, s2 in ipairs(STYLES) do
    local x = W - #STYLES * 34 - 12 + (i - 1) * 34
    local on = i == styleIdx
    lg.setColor(0, 0, 0, on and .7 or .4); lg.rectangle("fill", x, 30, 30, 22, 4)
    lg.setColor(on and { .4, .85, 1 } or { 1, 1, 1, .35 }); lg.setLineWidth(on and 2 or 1); lg.rectangle("line", x, 30, 30, 22, 4)
    lg.setColor(on and { 1, 1, 1 } or { .8, .8, .8 })
    txt(i .. utf8sub(s2.name), x, 33, fontS, "center", 30)
  end
  if banner.t > 0 then
    local a = clamp(banner.t, 0, 1) * clamp((2.4 - banner.t) * 3 + .3, 0, 1)
    lg.setColor(1, .9, .6); txt(banner.text, 0, H * .26, fontL, "center", W, a)
    lg.setColor(.9, .9, .9); txt(banner.sub, 0, H * .26 + 34, fontM, "center", W, a)
  end
  if p.hp / p.maxhp < .3 then
    lg.setColor(.8, 0, 0, (.3 - p.hp / p.maxhp) * 2 * (.6 + sin(realTime * 6) * .4))
    lg.setLineWidth(16); lg.rectangle("line", 0, 0, W, H); lg.setLineWidth(1)
  end
end

-- 스타일 선택 화면
local previewP = {}
local function cardRect(i)
  local cw, ch = 222, 222
  local col, row = (i - 1) % 4, floor((i - 1) / 4)
  return 14 + col * (cw + 10), 66 + row * (ch + 10), cw, ch
end
local function drawSelect()
  lg.setColor(.47, .47, .27); lg.rectangle("fill", 0, 0, W, H)
  lg.setColor(0, 0, 0, .25); lg.rectangle("fill", 0, 0, W, H)
  lg.setColor(1, 1, 1)
  txt("전투 스타일 고르기", 0, 18, fontL, "center", W)
  lg.setColor(.85, .85, .8)
  local hint = inGame and player.hp > 0 and ("1 ~ " .. #STYLES .. " 또는 클릭 — 싸우던 상황 그대로 캐릭터만 바뀝니다  ·  Tab/Esc 돌아가기")
    or ("1 ~ " .. #STYLES .. " 또는 클릭  ·  공통: WASD 이동, 마우스 조준, Space 회피 덤블링 (낮은 벽은 넘는다)")
  txt(hint, 0, 48, fontS, "center", W)
  local gx, gy = toGame(love.mouse.getPosition())
  for i, st in ipairs(STYLES) do
    local x, y, w, h = cardRect(i)
    local hov = gx >= x and gx <= x + w and gy >= y and gy <= y + h
    lg.setColor(0, 0, 0, hov and .55 or .4); lg.rectangle("fill", x, y, w, h, 8)
    lg.setColor(hov and { .45, .85, 1 } or { 1, 1, 1, .3 }); lg.setLineWidth(hov and 2.5 or 1.5); lg.rectangle("line", x, y, w, h, 8)
    -- 미리보기 캐릭터 (8방향으로 돈다)
    local p = previewP[i]
    if not p then p = newPlayer(i); previewP[i] = p end
    p.face = (floor(realTime * 1.2) + i) * (pi / 4)
    p.moving = false
    local cx, cy = x + w - 42, y + 92
    lg.setColor(0, 0, 0, .3); lg.ellipse("fill", cx, cy, 22, 8)
    lg.push(); lg.translate(cx, cy); lg.scale(1.8)
    drawPlayerPreview(p)
    lg.pop()
    lg.setColor(1, .9, .55); txt(i .. "  " .. st.name, x + 12, y + 12, fontM)
    lg.setColor(.5, .85, 1); txt(st.tag, x + 12, y + 36, fontS)
    lg.setColor(.92, .92, .9)
    lg.setFont(fontS)
    local yy = y + 104
    for _, l in ipairs(st.desc) do
      local _, wrapped = fontS:getWrap(l, w - 22)
      txt(l, x + 12, yy, fontS, "left", w - 22)
      yy = yy + 16 * #wrapped + 3
    end
  end
end
function drawPlayerPreview(p)
  local o = {}
  poseFor(p, o)
  Rig.human(o)
end

local function drawCenter(title, lines)
  lg.setColor(0, 0, 0, .55); lg.rectangle("fill", 0, 0, W, H)
  lg.setColor(1, .85, .5); txt(title, 0, H * .28, fontXL, "center", W)
  lg.setColor(.92, .92, .92)
  for i, l in ipairs(lines) do txt(l, 0, H * .28 + 64 + i * 24, fontM, "center", W) end
end

-------------------------------------------------------------------------------
-- LÖVE
-------------------------------------------------------------------------------
local function pressBtn(b)
  if state == "play" and player.hp > 0 then player.style.press(player, b) end
end

function love.load(args)
  -- --autotest      : 지금 작업 중인 스타일 하나만 40초 (기본 맨손, --style=2 면 검사)
  -- --autotest-all  : 7개 스타일 모두 25초씩
  for _, a in ipairs(args or {}) do
    local n = a:match("^%-%-style=(%d+)$")
    if n and STYLES[tonumber(n)] then styleIdx = tonumber(n) end
    if a == "--autotest" or a == "--autotest-all" then
      AUTO = { t = 0, keys = {}, mouse = {}, ax = 0, ay = 0, dirT = 0, deaths = 0, styleT = 0, kills = {},
        all = a == "--autotest-all", perStyle = (a == "--autotest-all") and 25 or 40 }
    end
  end
  io.stdout:setvbuf("no")
  lg.setDefaultFilter("linear", "linear")
  updateView()
  fontData = loadFontData()
  makeFonts()
  makeSounds()
  loadBgTextures()
  beamSrc = sfx.beam
  shadowCanvas = lg.newCanvas(W, H)
  newGame()
  if AUTO then state = "play"; inGame = true end
end

function love.resize() updateView(); makeFonts() end

-- 자동 테스트: 스타일 6개를 차례로 25초씩 가짜 입력으로 싸워 본다
local function autoStep(dt)
  local A = AUTO
  A.t, A.styleT = A.t + dt, A.styleT + dt
  if A.styleT > A.perStyle then
    A.kills[#A.kills + 1] = STYLES[styleIdx].name .. " " .. kills .. "처치/웨이브" .. wave
    A.styleT = 0
    if styleIdx >= #STYLES or not A.all then
      print("[자동테스트] 완료: " .. table.concat(A.kills, ", ") .. " / 사망 " .. A.deaths)
      print(string.format("[자동테스트] 날아간 적끼리 부딪힘 %d번, 벽꽝 %d번", A.bowls or 0, A.walls or 0))
      love.event.quit()
      return
    end
    switchStyle(styleIdx + 1)       -- 판은 그대로, 캐릭터만 교체
  end
  A.dirT = A.dirT - dt
  if A.dirT <= 0 then
    A.dirT = .5 + rnd()
    A.keys = {}
    local ks = { "w", "a", "s", "d" }
    if rnd() < .8 then A.keys[ks[rnd(1, 4)]] = true end
  end
  local best, bd = nil, 1e9
  for _, e in ipairs(enemies) do
    local d = len(e.x - player.x, e.y - player.y)
    if d < bd then best, bd = e, d end
  end
  if best then A.ax, A.ay = best.x, best.y else A.ax, A.ay = player.x + 2, player.y end
  local id = player.style.id
  local was1 = A.mouse[1]
  if id == "fist" then
    A.mouse[1] = bd < 2.0
    if bd < 2 and rnd() < .03 then pressBtn(2) end
    if player.kk and player.kk.t > .1 and not A.kickShot then A.kickShot = true; lg.captureScreenshot("auto_fist_kick.png") end
  elseif id == "blade" then
    -- 가까우면 베고, 가끔은 우클릭으로 막는다 (막기 중엔 공격 안 함)
    A.mouse[2] = bd < 4 and (A.t % 3) < 1
    A.mouse[1] = bd < 2.4 and not A.mouse[2]
    if player.sw and player.sw.spin and player.sw.t > .12 and not A.spinShot then A.spinShot = true; lg.captureScreenshot("auto_blade_spin.png") end
    if player.blocking and player.blockFlash > 0 and not A.blockShot then A.blockShot = true; lg.captureScreenshot("auto_blade_block.png") end
  elseif id == "guard" then A.mouse[1] = bd < 2.4
  elseif id == "archer" then A.mouse[1] = (A.t * 1.3) % 1 < .75
  elseif id == "bomber" then A.mouse[1] = (A.t * .9) % 1 < .5
  elseif id == "gunner" then A.mouse[1] = (A.t * .4) % 1 < .7
  else A.mouse[1] = bd < 9 end
  if id == "guard" then A.mouse[2] = bd < 3 and (A.t % 2) < 1.2 end
  if A.mouse[1] and not was1 then pressBtn(1) end
  if rnd() < .008 and id ~= "guard" then pressBtn(2) end
  if id == "mage" and player.targeting and rnd() < .05 then pressBtn(1) end
  if rnd() < .01 then doDash(player) end
  if state == "dead" then
    A.deaths = A.deaths + 1
    newGame(); state = "play"
  end
  if A.styleT >= 12 and A.styleT - dt < 12 then lg.captureScreenshot("auto_" .. STYLES[styleIdx].id .. ".png") end
  -- 맨손: 스트레이트 직후(적이 날아가는 중)를 찍는다
  if player.style.id == "fist" and not A.flyShot then
    for _, e in ipairs(enemies) do
      if e.fly and e.fly.t > .08 then A.flyShot = true; lg.captureScreenshot("auto_fist_fly.png"); break end
    end
  end
  if player.style.id == "fist" and player.dash and player.dash.t > .1 and not A.rollShot then
    A.rollShot = true; lg.captureScreenshot("auto_fist_roll.png")
  end
end

function love.update(dt)
  dt = min(dt, 1 / 30)
  realTime = realTime + dt
  mouseMovedT = max(0, mouseMovedT - dt)
  if AUTO then
    for _ = 1, 6 do
      local sdt = 1 / 60
      realTime = realTime + sdt
      autoStep(sdt)
      if state == "play" then updatePlay(sdt) end
      updateCamera(sdt)
    end
    return
  end
  if state == "play" then updatePlay(dt)
  elseif state == "dead" then updateFx(dt); updateTexts(dt); updateCorpses(dt) end
  if state ~= "select" then updateCamera(dt) end
end

function love.draw()
  lg.clear(.1, .1, .07)
  lg.push()
  lg.translate(view.x, view.y)
  lg.scale(view.s)
  lg.setScissor(view.x, view.y, W * view.s, H * view.s)
  if state == "select" then
    drawSelect()
  else
    local shx, shy = 0, 0
    if shake > 0 then shx, shy = (rnd() - .5) * shake * 14, (rnd() - .5) * shake * 14 end
    computeView()
    renderShadows(shx, shy)
    lg.push(); camTransform(shx, shy); drawGround(); lg.pop()
    lg.setColor(1, 1, 1, .3)
    lg.draw(shadowCanvas, 0, 0)
    lg.push()
    camTransform(shx, shy)
    drawGroundMarks()
    drawSorted()
    -- 벽 뒤에 가려진 나를 흐리게 다시 그린다
    if player.hp > 0 then drawPlayer(.22) end
    drawEffects()
    lg.pop()
    drawBars()
    drawHUD()
    if state == "pause" then drawCenter("일시정지", { "Esc 계속하기", "Tab 스타일 바꾸기", "R 처음부터" })
    elseif state == "dead" then drawCenter("쓰러졌다", { "웨이브 " .. wave .. "  ·  처치 " .. kills, "", "R 다시 하기   ·   Tab 스타일 바꾸기" }) end
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
  if state == "select" then
    local n = tonumber(k)
    if n and STYLES[n] then chooseStyle(n)
    elseif (k == "tab" or k == "escape") and inGame and player.hp > 0 then state = "play" end   -- 그냥 돌아가기
    return
  end
  if k == "tab" then state = "select"; if beamSrc then beamSrc:stop() end; return end
  if state == "play" then
    local n = tonumber(k)
    if n and STYLES[n] then
      if n ~= styleIdx then switchStyle(n) end    -- 싸우는 중에 숫자키로 바로 교체
    elseif k == "space" then doDash(player)
    elseif k == "r" then
      -- 개발자용: 체력 가득 채우기
      player.hp = player.maxhp
      addText(player.x, player.y, "체력 회복 (개발자)", { .4, 1, .5 }, true)
      burst(player.x, player.y, 1, 12, { .4, 1, .5 }, 2.5, 3, .5)
      play("pick", .1)
    elseif k == "escape" then
      if player.targeting then player.targeting = false else state = "pause" end
    end
  elseif state == "pause" then
    if k == "escape" then state = "play"
    elseif k == "r" then newGame(); state = "play" end
  elseif state == "dead" then
    if k == "r" or k == "return" then newGame(); state = "play" end
  end
end

function love.mousepressed(x, y, b)
  if state == "select" then
    local gx, gy = toGame(x, y)
    for i = 1, #STYLES do
      local cx, cy, cw, ch = cardRect(i)
      if gx >= cx and gx <= cx + cw and gy >= cy and gy <= cy + ch then
        chooseStyle(i)
        return
      end
    end
    return
  end
  pressBtn(b)
end

function love.mousemoved() mouseMovedT = .15 end
