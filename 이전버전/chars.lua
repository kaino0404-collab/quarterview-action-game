-- 캐릭터 그리기 : 결투의 캐릭터 디자인을 8방향으로
-- 관절(엉덩이·무릎·발·어깨·팔꿈치·손·머리·칼)을 캐릭터 기준 3D 좌표로 잡고,
-- 바라보는 방향만큼 돌려서 쿼터뷰로 그린다. 부품은 카메라에서 먼 것부터 그린다.
--   f = 앞(+) / 뒤(-),  s = 오른쪽(+) / 왼쪽(-),  u = 위 (발바닥 0, 키 약 130)
-- 화면 단위는 결투 그림과 같은 픽셀 (부르는 쪽에서 크기를 줄여 그린다)
local lg = love.graphics
local sin, cos, sqrt, min, max, abs, pi = math.sin, math.cos, math.sqrt, math.min, math.max, math.abs, math.pi
local atan2 = math.atan2

local C = {}
local WHITE = { 1, 1, 1 }
local function shade(c, k) return { c[1] * k, c[2] * k, c[3] * k } end
C.shade = shade

-------------------------------------------------------------------------------
-- 3D → 화면
-------------------------------------------------------------------------------
local cth, sth, camF, camS = 1, 0, 0, 0
local function setFace(a)
  cth, sth = cos(a), sin(a)
  camF = (cth + sth) * .7071     -- 앞쪽이 카메라를 보는 정도 (1 = 정면, -1 = 뒷모습)
  camS = (cth - sth) * .7071     -- 오른쪽이 카메라를 보는 정도
end
local function P(f, s, u)
  local wx = f * cth - s * sth
  local wy = f * sth + s * cth
  return (wx - wy) * .7071, (wx + wy) * .3536 - u
end
-- 깊이 (클수록 카메라에 가깝다)
local function D(f, s) return f * camF + s * camS end
local function push(c, f, s, u)
  local x, y = P(f, s, u)
  c[#c + 1] = x; c[#c + 1] = y
end
local function line3(w, ...)
  local a = { ... }
  local s = {}
  for i = 1, #a, 3 do
    local x, y = P(a[i], a[i + 1], a[i + 2])
    s[#s + 1] = x; s[#s + 1] = y
  end
  lg.setLineWidth(w)
  lg.line(s)
end
local function dot3(f, s, u, r)
  local x, y = P(f, s, u)
  lg.circle("fill", x, y, r)
end

-- 점들을 감싸는 볼록 다각형으로 칠한다 (어느 방향에서 봐도 몸통·망토가 두께를 가진다)
local function cross(o, a, b) return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1]) end
local function ptLess(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end
local function hullFill(c)
  local n = #c / 2
  local arr = {}
  for i = 1, n do arr[i] = { c[2 * i - 1], c[2 * i] } end
  table.sort(arr, ptLess)
  local h = {}
  for i = 1, n do
    local p = arr[i]
    while #h >= 2 and cross(h[#h - 1], h[#h], p) <= 0 do h[#h] = nil end
    h[#h + 1] = p
  end
  local lo = #h + 1
  for i = n - 1, 1, -1 do
    local p = arr[i]
    while #h >= lo and cross(h[#h - 1], h[#h], p) <= 0 do h[#h] = nil end
    h[#h + 1] = p
  end
  h[#h] = nil
  if #h < 3 then return end
  local out = {}
  for i = 1, #h do out[2 * i - 1], out[2 * i] = h[i][1], h[i][2] end
  lg.polygon("fill", out)
end
-- 위/아래 직사각형 두 개로 된 상자(사다리꼴 기둥)의 외곽
local function boxHull(f0, f1, sw0, u0, f2, f3, sw1, u1, extra)
  local c = {}
  push(c, f0, -sw0, u0); push(c, f0, sw0, u0); push(c, f1, -sw0, u0); push(c, f1, sw0, u0)
  push(c, f2, -sw1, u1); push(c, f2, sw1, u1); push(c, f3, -sw1, u1); push(c, f3, sw1, u1)
  if extra then for i = 1, #extra do c[#c + 1] = extra[i] end end
  hullFill(c)
end

-- 부품을 모았다가 먼 것부터 그린다
local parts, np = {}, 0
local sorted = {}
local function add(d, fn)
  np = np + 1
  local t = parts[np]
  if not t then t = {}; parts[np] = t end
  t.d, t.fn = d + np * 1e-4, fn
end
local function byD(a, b) return a.d < b.d end
local function flush()
  for i = 1, np do sorted[i] = parts[i] end
  for i = np + 1, #sorted do sorted[i] = nil end
  table.sort(sorted, byD)
  for i = 1, np do sorted[i].fn() end
  np = 0
end

-- 그리는 동안 모든 색에 투명도를 곱한다 (무적 깜빡임, 귀신 반투명)
function C.withAlpha(al, fn, ...)
  if al >= 1 then return fn(...) end
  local orig = lg.setColor
  lg.setColor = function(r, g, b, a)
    if type(r) == "table" then r, g, b, a = r[1], r[2], r[3], r[4] end
    orig(r, g, b, (a or 1) * al)
  end
  local ok, err = pcall(fn, ...)
  lg.setColor = orig
  if not ok then error(err, 0) end
end

local function norm3(f, s, u)
  local l = sqrt(f * f + s * s + u * u)
  if l < 1e-6 then return 1, 0, 0 end
  return f / l, s / l, u / l
end

-- 팔: 어깨 → 팔꿈치(아래·바깥으로 굽힘) → 손
local function elbowOf(sf, ss, su, hf, hs, hu, side)
  return (sf + hf) / 2 - 2, (ss + hs) / 2 + side * 5, (su + hu) / 2 - 9
end

-------------------------------------------------------------------------------
-- 칼 (결투 '검': 곧은 양날, 날개 코등이, 남색 술) — 손 위치와 3D 방향으로
-------------------------------------------------------------------------------
local function drawSword3(hf, hs, hu, df, ds, du, len, fl, glow, tm)
  local steel  = fl and WHITE or { 0.86, 0.89, 0.95 }
  local metal  = fl and WHITE or { 0.78, 0.8, 0.86 }
  local tassel = fl and WHITE or { 0.22, 0.28, 0.5 }
  local hx, hy = P(hf, hs, hu)
  local tx, ty = P(hf + df * len, hs + ds * len, hu + du * len)
  local gx, gy = P(hf - df * 12, hs - ds * 12, hu - du * 12)
  local vx, vy = tx - hx, ty - hy
  local l = sqrt(vx * vx + vy * vy)
  local nx, ny = 0, 1
  if l > .01 then nx, ny = -vy / l, vx / l end
  if glow then
    lg.setColor(1, 0.55, 0.15, 0.35 + 0.25 * sin(tm * 20)); lg.setLineWidth(14)
    lg.line(hx, hy, tx, ty)
  end
  -- 손잡이 + 폼멜 + 늘어진 술
  lg.setColor(fl and WHITE or { 0.3, 0.18, 0.1 }); lg.setLineWidth(4.5); lg.line(hx, hy, gx, gy)
  lg.setColor(metal); lg.circle("fill", gx, gy, 3)
  lg.setColor(tassel); lg.setLineWidth(1.6)
  local sw = sin(tm * 4) * 2
  for k = -1, 1 do lg.line(gx, gy, gx - 2 + k * 1.5 + sw, gy + 14 + k) end
  -- 날
  local bw = 3
  local mx, my = hx + vx * .86, hy + vy * .86
  local blade = { hx + nx * bw, hy + ny * bw, mx + nx * bw * .85, my + ny * bw * .85, tx, ty,
    mx - nx * bw * .85, my - ny * bw * .85, hx - nx * bw, hy - ny * bw }
  lg.setColor(steel); lg.polygon("fill", blade)
  if not fl then
    lg.setColor(1, 1, 1, .55)
    lg.polygon("fill", hx + nx * bw, hy + ny * bw, mx + nx * bw * .85, my + ny * bw * .85, tx, ty, mx, my, hx, hy)
    lg.setColor(0, 0, 0, .35); lg.setLineWidth(1); lg.polygon("line", blade)
  end
  -- 날개 모양 코등이
  lg.setColor(metal); lg.setLineWidth(3.2)
  lg.line(hx + nx * 8, hy + ny * 8, hx - nx * 8, hy - ny * 8)
  lg.circle("fill", hx, hy, 2.6)
end

-------------------------------------------------------------------------------
-- 주인공 : 흑갑주 대검사 (결투)
-- o: face walk moving idle crouch stride lean mode(idle/slash/heavy/spin/shoot/roll) t side tuck fl tm
-------------------------------------------------------------------------------
local HERO = {
  outer = { 0.16, 0.16, 0.18 }, outerD = { 0.07, 0.06, 0.07 }, inner = { 0.1, 0.09, 0.1 },
  trim = { 0.42, 0.42, 0.46 }, skin = { 0.88, 0.72, 0.58 }, hair = { 0.04, 0.04, 0.05 },
  boot = { 0.08, 0.07, 0.07 }, pants = { 0.1, 0.09, 0.1 },
  steel = { 0.24, 0.25, 0.28 }, steelH = { 0.42, 0.43, 0.48 },
}

-- 칼 위치: 손(hf,hs,hu)과 칼 방향(df,ds,du). 휘두르기는 몸 기준 3D 궤도를 돈다
local function heroSword(o, shF, shU, hipU, t)
  local mode = o.mode
  local e = 1 - (1 - t) ^ 2
  if mode == "slash" then
    -- 가로 베기: 오른쪽 뒤 → 왼쪽 앞 (2타는 반대로)
    local a0, a1 = 1.9, -1.4
    if o.side == -1 then a0, a1 = -1.4, 1.9 end
    local a = a0 + (a1 - a0) * e
    return shF + 4 + cos(a) * 24, 3 + sin(a) * 22, shU - 14, cos(a), sin(a), -.08, a0, a, "h"
  elseif mode == "heavy" then
    -- 강타: 머리 위 뒤쪽에서 앞으로 내려찍기 (두 손)
    local a0, a1 = 2.2, -.75
    local a = a0 + (a1 - a0) * e
    return shF + 6 + cos(a) * 22, 4, shU - 8 + sin(a) * 22, cos(a), .05, sin(a), a0, a, "v"
  elseif mode == "spin" then
    return shF + 8, 20, shU - 14, norm3(.25, 1, -.05)
  elseif mode == "shoot" then
    return shF + 30, 6, shU - 6, norm3(1, 0, .08)
  elseif mode == "roll" then
    return shF + 10, 10, hipU + 6, norm3(-.6, .2, .4)
  end
  local bob = o.moving and sin(o.walk * 2) * 1.5 or 0
  local df, ds, du = norm3(.72, .22, -.62)    -- 칼끝을 앞 아래로 늘어뜨린 기본 자세
  return shF + 12, 10, hipU + 14 + bob, df, ds, du
end

function C.hero(o)
  local tm, fl = o.tm, o.fl
  setFace(o.face)
  local function K(c) return fl and WHITE or c end
  local outer, outerD, inner, trim = K(HERO.outer), K(HERO.outerD), K(HERO.inner), K(HERO.trim)
  local skin, hairC, boot, pants = K(HERO.skin), K(HERO.hair), K(HERO.boot), K(HERO.pants)
  local steel, steelH = K(HERO.steel), K(HERO.steelH)
  lg.setLineJoin("bevel")

  local crouch = o.crouch or 0
  local hipU = 62 - crouch + (o.idle and sin(tm * 3) * 1.5 or 0)
  local lean = o.lean or 0
  local shF, shU = sin(lean) * 44, hipU + cos(lean) * 44
  local hdF, hdU = sin(lean) * 62, hipU + cos(lean) * 62
  local st = o.stride or 0
  local flap = sin(tm * 5) * 3 + (o.moving and 6 or 0)

  -- 다리: 넉넉한 검은 바지 + 천 장화
  for side = -1, 1, 2 do
    local s0 = side * 7
    local sw = st * side
    local footF, footU = 26 * sw + 2, 0
    local knF, knU = footF / 2 + 6 + crouch * .8, hipU / 2 + 2
    if o.tuck then footF, footU, knF, knU = 6, hipU - 14, 22, hipU + 4 end
    local far = side * camS < 0
    add(D(knF * .5, s0), function()
      lg.setColor(far and K(shade(HERO.pants, .8)) or pants)
      line3(10, 0, s0, hipU, knF, s0, knU, (knF + footF) / 2, s0, (knU + footU) / 2)
      lg.setColor(far and K(shade(HERO.boot, .8)) or boot)
      line3(8.5, knF + (footF - knF) * .4, s0, knU + (footU - knU) * .4, footF, s0, footU)
      line3(6, footF - 2, s0, footU + 1, footF + 12, s0, footU + 1)
    end)
  end

  -- 망토: 어깨 뒤에서 무릎 아래까지, 끝이 찢어진 톱니
  add(D(-10, 0), function()
    lg.setColor(outerD)
    local c = {}
    push(c, shF - 4, -13, shU); push(c, shF - 4, 13, shU)
    push(c, -15 - flap, -18, 12); push(c, -15 - flap, 18, 12)
    push(c, -3, -14, 14); push(c, -3, 14, 14)
    hullFill(c)
    for k = 0, 4 do
      local s0, s1 = -18 + k * 7.2, -18 + (k + 1) * 7.2
      local ax, ay = P(-14 - flap, s0, 13)
      local bx, by = P(-14 - flap, s1, 13)
      local tx, ty = P(-15 - flap, (s0 + s1) / 2, 5 - (k % 2) * 5 + sin(tm * 6 + k) * 2)
      lg.polygon("fill", ax, ay, bx, by, tx, ty)
    end
  end)

  -- 앞자락 (안감)
  if camF > -.4 then
    add(D(9, 0), function()
      lg.setColor(inner)
      local c = {}
      push(c, 6, -5, hipU); push(c, 6, 12, hipU)
      push(c, 9 + st * 3, -3, hipU - 36); push(c, 9 + st * 3, 14, hipU - 34)
      hullFill(c)
    end)
  end

  -- 상체: 넓은 어깨 + 앞면은 검은 강철 흉갑, 허리띠는 빙 둘러
  add(D(shF * .5, 0), function()
    lg.setColor(outer)
    boxHull(shF + 7, shF - 7, 13, shU, 6, -6, 11, hipU)
    if camF > 0 then
      lg.setColor(steel)
      local q = {}
      push(q, shF + 7.4, -10, shU - 3); push(q, shF + 7.4, 10, shU - 3)
      push(q, 6.4, 9, hipU + 9); push(q, 6.4, -9, hipU + 9)
      hullFill(q)
      if not fl then
        lg.setColor(steelH)
        line3(1.4, (shF + 14) / 2 + .2, -9, (shU + hipU) / 2, (shF + 14) / 2 + .2, 9, (shU + hipU) / 2)
        line3(1.4, shF + 7.5, -9, shU - 5, shF + 7.5, 9, shU - 5)
      end
      -- 교차 옷깃
      lg.setColor(inner); line3(4.5, shF + 7.6, 7, shU - 1, 6.6, -2, hipU + 10)
      lg.setColor(trim); line3(1.6, shF + 7.8, 9, shU - 2, 6.8, 1, hipU + 9)
    end
    lg.setColor(K({ 0.06, 0.06, 0.08 }))
    boxHull(7, -7, 12, hipU + 1, 7, -7, 12, hipU + 9)
    lg.setColor(trim)
    if camF > 0 then dot3(7.3, 6, hipU + 5, 2) end
    -- 주머니 (왼쪽 허리)
    if camS < .2 then lg.setColor(K({ 0.3, 0.22, 0.15 })); dot3(0, -12.5, hipU + 2, 3.5) end
  end)

  -- 칼과 손
  local hf, hs, hu, df, ds, du, a0, a, kind = heroSword(o, shF, shU, hipU, o.t or 0)
  local twoHand = o.mode == "heavy"

  -- 뒷팔(왼팔): 넓은 소매 + 철 건틀릿
  local lf, ls, lu = shF + 10, -7, hipU + 8
  if twoHand then lf, ls, lu = hf - df * 8, hs - ds * 8 - 5, hu - du * 8 end
  do
    local sf, ss, su = shF, -13, shU - 2
    local ef, es, eu = elbowOf(sf, ss, su, lf, ls, lu, -1)
    add(D((sf + lf) / 2, (ss + ls) / 2) + .4, function()
      lg.setColor(outerD); line3(12, sf, ss, su, ef, es, eu)
      lg.setColor(steel); line3(10, ef, es, eu, lf, ls, lu); dot3(lf, ls, lu, 5.5)
      if not fl then lg.setColor(steelH); lg.setLineWidth(1.2); local x, y = P(ef, es, eu); lg.circle("line", x, y, 5) end
      lg.setColor(steel); dot3(sf, ss, su + 2, 10)    -- 견갑
      if not fl then lg.setColor(steelH); lg.setLineWidth(1.4); local x, y = P(sf, ss, su + 2); lg.arc("line", "open", x, y, 10, pi * 1.05, pi * 1.95) end
    end)
  end
  -- 칼 든 팔(오른팔)
  do
    local sf, ss, su = shF, 13, shU - 2
    local ef, es, eu = elbowOf(sf, ss, su, hf, hs, hu, 1)
    add(D((sf + hf) / 2, (ss + hs) / 2) + .4, function()
      lg.setColor(outer); line3(13, sf, ss, su, ef, es, eu)
      lg.setColor(inner); line3(7, ef, es, eu, hf, hs, hu)
      if not fl then lg.setColor(trim); line3(1, ef, es, eu - 2, hf, hs, hu - 2) end
      lg.setColor(skin); dot3(hf, hs, hu, 4.5)
      lg.setColor(steel); dot3(sf, ss, su + 2, 11)    -- 크고 둥근 견갑
      if not fl then
        lg.setColor(steelH); lg.setLineWidth(1.4)
        local x, y = P(sf, ss, su + 2); lg.arc("line", "open", x, y, 11, pi * 1.05, pi * 1.95)
      end
    end)
  end
  add(D(hf + df * 30, hs + ds * 30) + .3, function()
    drawSword3(hf, hs, hu, df, ds, du, 64, fl, o.windGlow, tm)
  end)

  -- 머리: 뻗친 짧은 흑발 (뒤통수 쪽으로), 앞에서 보면 찌푸린 눈썹·콧등 흉터
  add(D(hdF, 0) + 4, function()
    local cx, cy = P(hdF, 0, hdU)
    local hx, hy = P(hdF - 3, 0, hdU + 2)
    local bx, by = P(hdF - 10, 0, hdU)
    local dx, dy = (bx - cx) * .6, (by - cy) * .6 - 10
    local base = atan2(dy, dx)
    local sway = sin(tm * 3) * .06
    local function spikes()
      lg.setColor(hairC)
      for k = 0, 6 do
        local ang = base + (k - 3) * .42 + sway
        local r2 = 15 + (k % 2) * 4
        local px, py = hx + cos(ang) * 8, hy + sin(ang) * 8
        local tx, ty = hx + cos(ang - .15) * r2, hy + sin(ang - .15) * r2
        lg.polygon("fill", px - sin(ang) * 3, py + cos(ang) * 3, tx, ty, px + sin(ang) * 3, py - cos(ang) * 3)
      end
    end
    if camF > -.3 then
      lg.setColor(hairC); lg.circle("fill", hx, hy, 11); spikes()
      lg.setColor(skin); dot3(hdF + 1.5, 0, hdU - .5, 9.6)
      dot3(hdF + 5, 0, hdU - 5, 5.5)               -- 각진 턱
      -- 앞머리 삐침
      lg.setColor(hairC); dot3(hdF + 3, 0, hdU + 7.5, 4.5)
      for side = -1, 1, 2 do
        local ef, es, eu = hdF + 8.6, side * 4, hdU + .5
        if D(ef, es) > D(hdF, 0) + .5 then
          lg.setColor(K({ 0.06, 0.05, 0.05 }))
          dot3(ef, es, eu, 1.4)
          line3(2.2, ef + .3, side * 1.5, eu + 4.5, ef - .5, side * 7, eu + 2.5)   -- 찌푸린 눈썹
        end
      end
      if not fl and camF > 0 then
        lg.setColor(0.6, 0.32, 0.28); line3(1.6, hdF + 9.6, -4, hdU - 1, hdF + 9.6, 4, hdU + 1.5)   -- 콧등 흉터
      end
    else
      lg.setColor(skin); lg.circle("fill", cx, cy, 10)
      lg.setColor(hairC); lg.circle("fill", hx, hy, 11.5); spikes()
    end
  end)

  flush()

  -- 휘두른 궤적 (칼끝이 지나간 길)
  if kind then
    lg.setColor(1, 1, 1, .35)
    lg.setLineWidth(kind == "v" and 16 or 10)
    local pts = {}
    local n = 10
    for i = 0, n do
      local b = a0 + (a - a0) * i / n
      local x, y
      if kind == "h" then
        x, y = P(shF + 4 + cos(b) * 88, 3 + sin(b) * 86, shU - 19)
      else
        x, y = P(shF + 6 + cos(b) * 86, 4, shU - 8 + sin(b) * 86)
      end
      pts[#pts + 1] = x; pts[#pts + 1] = y
    end
    if #pts >= 4 then lg.line(pts) end
  end
end

-------------------------------------------------------------------------------
-- 오크형 몬스터 (결투 오크): 구부정한 2족 보행, 굵은 팔다리, 큰 턱·송곳니·뾰족귀
-- o: face walk moving crouch stride lean mode(idle/raise/strike/stun/forward) k trailA L w fl glow tm
-------------------------------------------------------------------------------
local function orcArm(o, shF, shU)
  local m, k = o.mode, o.k or 0
  local idleH = { shF + 16, 15, shU - 30, .55, .15, -.8 }
  local upH   = { shF - 4, 13, shU + 16, -.45, .05, .9 }
  local t
  if m == "raise" then
    t = {}
    for i = 1, 6 do t[i] = idleH[i] + (upH[i] - idleH[i]) * k end
  elseif m == "strike" then t = { shF + 26, 11, shU - 22, .9, 0, -.45 }
  elseif m == "stun" then t = { shF + 2, 17, shU - 18, .2, .3, -.9 }
  elseif m == "forward" then t = { shF + 22, 14, shU - 12, 1, .05, 0 }
  else t = idleH end
  local df, ds, du = norm3(t[4], t[5], t[6])
  return t[1], t[2], t[3], df, ds, du
end

local function orcWeapon3(w, hf, hs, hu, df, ds, du, fl, glow, tm)
  local hx, hy = P(hf, hs, hu)
  local L = w.len
  if w.style == "claw" then
    if glow then lg.setColor(1, .4, .2, .5 + .3 * sin(tm * 20)); lg.circle("fill", hx, hy, 12) end
    local tx, ty = P(hf + df * 14, hs + ds * 14, hu + du * 14)
    local a = atan2(ty - hy, tx - hx)
    local l = max(6, sqrt((tx - hx) ^ 2 + (ty - hy) ^ 2))
    lg.setColor(fl and WHITE or { .92, .88, .75 }); lg.setLineWidth(2.5)
    for k = -1, 1 do
      local a2 = a + k * .35
      lg.line(hx, hy, hx + cos(a2) * l, hy + sin(a2) * l)
    end
    return
  end
  local tx, ty = P(hf + df * L, hs + ds * L, hu + du * L)
  local bx, by = P(hf - df * 6, hs - ds * 6, hu - du * 6)
  if glow then
    lg.setColor(1, .55, .15, .35 + .25 * sin(tm * 20)); lg.setLineWidth(w.width + 10)
    lg.line(hx, hy, tx, ty)
  end
  lg.setColor(fl and WHITE or { .45, .3, .17 }); lg.setLineWidth(w.width)
  lg.line(bx, by, tx, ty)
  lg.circle("fill", tx, ty, w.width * .9)
  if w.style == "bigclub" then
    local vx, vy = tx - hx, ty - hy
    local l = sqrt(vx * vx + vy * vy)
    if l > 1 then
      local nx, ny = -vy / l, vx / l
      local cx, cy = vx / l, vy / l
      lg.setColor(fl and WHITE or { .7, .7, .72 })
      for k = 0, 3 do
        local t = .55 + k * .13
        local px, py = hx + vx * t, hy + vy * t
        lg.polygon("fill", px + nx * 6, py + ny * 6, px + nx * 13, py + ny * 13, px + nx * 6 + cx * 4, py + ny * 6 + cy * 4)
        lg.polygon("fill", px - nx * 6, py - ny * 6, px - nx * 13, py - ny * 13, px - nx * 6 + cx * 4, py - ny * 6 + cy * 4)
      end
    end
  end
end

function C.orc(o)
  local tm, fl, L, w = o.tm, o.fl, o.L, o.w
  setFace(o.face)
  local skin = fl and WHITE or L.skin
  local dark = fl and WHITE or shade(L.skin, .72)
  lg.setLineJoin("bevel")
  local crouch = o.crouch or 0
  local lean = (o.lean or 0) + .3                  -- 늘 구부정하다
  local hipU = 58 - crouch
  local shF, shU = sin(lean) * 42, hipU + cos(lean) * 42
  local hdF, hdU = sin(lean) * 58 + 8, hipU + cos(lean) * 58 - 6   -- 머리가 앞으로 튀어나옴
  local st = o.stride or 0

  -- 다리
  for side = -1, 1, 2 do
    local s0 = side * 9
    local sw = st * side
    local footF = 24 * sw + 4
    local knF, knU = footF / 2 + 8 + crouch * .8, hipU / 2 + 2
    local far = side * camS < 0
    add(D(knF * .5, s0), function()
      lg.setColor(far and dark or skin)
      line3(11, 0, s0, hipU, knF, s0, knU, footF, s0, 0)
      line3(8, footF - 4, s0, 2, footF + 12, s0, 2)
    end)
  end

  -- 몸통 (넓고 배가 나옴)
  add(D(shF * .5, 0), function()
    lg.setColor(skin)
    local mid = (hipU + shU) / 2
    local ex = {}
    push(ex, 13 + L.belly, -8, mid - 4); push(ex, 13 + L.belly, 8, mid - 4)
    push(ex, 9 + L.belly, -10, mid - 14); push(ex, 9 + L.belly, 10, mid - 14)
    boxHull(shF + 9, shF - 9, 15, shU, 8, -8, 12, hipU + 2, ex)
    if camF > 0 and not fl then
      if L.scar then
        lg.setColor(.35, .2, .18); line3(2, shF + 10, -6, shU - 6, shF + 9, 6, shU - 20)
      end
      if L.necklace then
        lg.setColor(.92, .9, .82)
        for k = -1, 1 do
          local ax, ay = P(shF + 10, k * 5 - 2, shU - 4)
          local bx, by = P(shF + 10, k * 5 + 2, shU - 4)
          local tx, ty = P(shF + 10, k * 5, shU - 12)
          lg.polygon("fill", ax, ay, bx, by, tx, ty)
        end
      end
    end
    -- 허리 천 + 띠
    lg.setColor(fl and WHITE or L.cloth)
    boxHull(9.5, -9.5, 13, hipU + 6, 9, -9, 12, hipU - 16)
    lg.setColor(fl and WHITE or { .3, .2, .12 })
    boxHull(10, -10, 13.5, hipU + 3, 10, -10, 13.5, hipU + 7)
  end)

  -- 뒷팔(왼팔): 빈손 주먹
  do
    local sf, ss, su = shF, -15, shU - 2
    add(D(shF + 4, -15) + .4, function()
      lg.setColor(dark)
      line3(10, sf, ss, su, shF + 4, -18, shU - 22, shF + 14, -15, shU - 30)
      dot3(shF + 14, -15, shU - 30, 6)
    end)
  end
  -- 무기 든 팔(오른팔)
  local hf, hs, hu, df, ds, du = orcArm(o, shF, shU)
  do
    local sf, ss, su = shF, 15, shU - 2
    local ef, es, eu = elbowOf(sf, ss, su, hf, hs, hu, 1)
    add(D((sf + hf) / 2, (ss + hs) / 2) + .4, function()
      lg.setColor(skin)
      line3(11, sf, ss, su, ef, es, eu, hf, hs, hu)
      dot3(hf, hs, hu, 6.5)
    end)
    local L2 = max(w.len, 14) / 2
    add(D(hf + df * L2, hs + ds * L2) + .3, function()
      orcWeapon3(w, hf, hs, hu, df, ds, du, fl, o.glow, tm)
    end)
  end

  -- 머리: 큰 턱, 송곳니, 뾰족 귀, 짙은 눈썹, 머리(모히칸/상투), 뿔
  add(D(hdF, 0) + 4, function()
    local function ear(side)
      lg.setColor(dark)
      local ax, ay = P(hdF - 2, side * 11, hdU + 3)
      local bx, by = P(hdF - 2, side * 11, hdU - 6)
      local tx, ty = P(hdF - 12, side * 23, hdU + 9)
      lg.polygon("fill", ax, ay, bx, by, tx, ty)
    end
    local nearSide = camS >= 0 and 1 or -1
    ear(-nearSide)
    lg.setColor(skin)
    dot3(hdF, 0, hdU, 13)
    dot3(hdF + 8, 0, hdU - 6, 8.5)                    -- 튀어나온 턱
    ear(nearSide)
    if camF > -.3 then
      for side = -1, 1, 2 do
        local ef, es, eu = hdF + 11, side * 5, hdU + 1
        if D(ef, es) > D(hdF, 0) + .5 then
          lg.setColor(fl and WHITE or { .15, .12, .1 })
          line3(3, ef + .5, side * 1.5, eu + 5, ef - .5, side * 9, eu + 3)   -- 찌푸린 눈썹
          lg.setColor(fl and WHITE or L.eye); dot3(ef, es, eu, 2.2)
          -- 송곳니
          lg.setColor(fl and WHITE or { .95, .92, .8 })
          local tf, ts, tu = hdF + 15, side * 4, hdU - 9
          local ax, ay = P(tf, ts - 1.5, tu)
          local bx, by = P(tf, ts + 1.5, tu)
          local tx, ty = P(tf, ts, tu + 7 * L.tusk)
          lg.polygon("fill", ax, ay, bx, by, tx, ty)
        end
      end
    end
    if L.hair == 1 then
      lg.setColor(fl and WHITE or { .12, .1, .08 })
      for k = -2, 2 do line3(3, hdF + k * 4, 0, hdU + 12, hdF + k * 4 - 2, 0, hdU + 22 - abs(k) * 2) end   -- 모히칸
    elseif L.hair == 2 then
      lg.setColor(fl and WHITE or { .12, .1, .08 })
      dot3(hdF - 6, 0, hdU + 13, 5); line3(3, hdF - 6, 0, hdU + 13, hdF - 14, 0, hdU + 4)               -- 상투
    end
    if L.horns then
      lg.setColor(fl and WHITE or L.horns)
      for side = -1, 1, 2 do
        local ax, ay = P(hdF - 1, side * 4, hdU + 10)
        local bx, by = P(hdF - 1, side * 9, hdU + 9)
        local tx, ty = P(hdF - 6, side * 11, hdU + 26)
        lg.polygon("fill", ax, ay, bx, by, tx, ty)
      end
    end
  end)

  flush()

  -- 내려친 궤적 (머리 위 → 앞 아래)
  if o.mode == "strike" and (o.trailA or 0) > 0 then
    lg.setColor(1, 1, 1, .35 * o.trailA)
    lg.setLineWidth(w.len > 40 and 18 or 12)
    local R = 40 + w.len
    local pts = {}
    for i = 0, 10 do
      local b = 2.0 + (-.5 - 2.0) * i / 10
      local x, y = P(shF + 4 + cos(b) * R, 13, shU - 6 + sin(b) * R)
      pts[#pts + 1] = x; pts[#pts + 1] = y
    end
    lg.line(pts)
  end
end

-------------------------------------------------------------------------------
-- 원귀 : 결투의 두건 마법사를 떠다니는 귀신으로. 손에 보라 불을 모아 던진다
-- o: face walk moving charge fl tm
-------------------------------------------------------------------------------
function C.caster(o)
  local tm, fl = o.tm, o.fl
  setFace(o.face)
  local function col(c) if fl then lg.setColor(1, 1, 1) else lg.setColor(c) end end
  local robe = { .3, .2, .42 }
  local robeD = { .24, .16, .34 }
  local pale = { .78, .8, .88 }
  lg.setLineJoin("bevel")
  local sway = o.moving and sin(o.walk) * 3 or sin(tm * 2) * 1.5

  -- 로브 + 꼬리처럼 흩어지는 자락
  add(D(0, 0), function()
    col(robe)
    local ex = {}
    push(ex, -10 - sway, 0, 2)
    boxHull(7, -7, 11, 84, 10, -10, 16, 18, ex)
    col(robeD)
    for k = 0, 3 do
      local s0 = -15 + k * 8
      local ax, ay = P(8, s0, 20)
      local bx, by = P(8, s0 + 7, 20)
      local tx, ty = P(8, s0 + 3.5, 8 - (k % 2) * 5 + sin(tm * 5 + k) * 2)
      if camF > 0 then lg.polygon("fill", ax, ay, bx, by, tx, ty) end
    end
  end)
  -- 왼팔 (로브 소매)
  add(D(4, -11) + .4, function()
    col(robe); line3(6, 2, -11, 80, 8, -13, 56)
    col(pale); dot3(9, -13, 54, 3)
  end)
  -- 오른팔: 앞으로 내밀어 불을 모은다
  add(D(14, 9) + .4, function()
    col(pale); line3(5, 2, 10, 80, 24, 8, 70)
    local q = o.charge or 0
    local x, y = P(30, 8, 70)
    if q > 0 then
      lg.setColor(.7, .3, 1, .5 + .4 * q); lg.circle("fill", x, y, 4 + 8 * q)
      lg.setColor(1, .85, 1, .9); lg.circle("fill", x, y, 2 + 3 * q)
    else
      lg.setColor(.7, .3, 1, .5 + .2 * sin(tm * 6)); lg.circle("fill", x, y, 3)
    end
  end)
  -- 두건 + 창백한 얼굴 + 빛나는 눈
  add(D(0, 0) + 4, function()
    col(robeD); dot3(-1, 0, 95, 11.5)
    if camF > -.3 then
      col(pale); dot3(3.5, 0, 93, 8)
      col(robeD)
      local ax, ay = P(4, -9, 101); local bx, by = P(4, 9, 101); local cx, cy = P(-2, 0, 106)
      lg.polygon("fill", ax, ay, bx, by, cx, cy)                -- 두건 앞챙
      for side = -1, 1, 2 do
        if D(10, side * 3.5) > D(0, 0) + .5 then
          if fl then lg.setColor(1, 1, 1) else lg.setColor(.45, .95, 1) end
          dot3(10.5, side * 3.5, 95, 1.8)
        end
      end
    end
  end)
  flush()
end

return C
