-- 마네킹 캐릭터 (참고 영상 '전투테스트'의 마네킹처럼) — 8방향 3D 뼈대
-- 캐릭터 기준 좌표 (cm):  f = 앞(+)/뒤(-),  s = 오른쪽(+)/왼쪽(-),  u = 위 (발바닥 0, 키 약 170)
-- 바라보는 방향만큼 돌려서 화면에 투영하고, 부품은 카메라에서 먼 것부터 그린다.
local lg = love.graphics
local sin, cos, sqrt, min, max, abs, pi = math.sin, math.cos, math.sqrt, math.min, math.max, math.abs, math.pi
local atan2 = math.atan2

local R = {}
local KY, KZ, K = .77, .64, .4        -- 바닥 세로 압축, 높이 압축, cm → 픽셀
function R.setup(ky, kz, k) KY, KZ, K = ky, kz, k end

local WHITE = { 1, 1, 1 }
local OUT = { .07, .06, .06 }
R.GUN_LEN, R.RIFLE_LEN = 112, 96     -- 총구 위치 계산에 main 에서도 쓴다
local function shade(c, k) return { c[1] * k, c[2] * k, c[3] * k } end
R.shade = shade

-------------------------------------------------------------------------------
-- 투영
-------------------------------------------------------------------------------
local ct, stt, camF, camS = 1, 0, 0, 1
local pc, ps, fallK = 1, 0, 0
local function setFace(a, fall)
  ct, stt = cos(a), sin(a)
  camF, camS = stt, ct                       -- 앞/오른쪽이 카메라(화면 아래)를 보는 정도
  fallK = fall or 0
  local p = fallK * 1.5                      -- 뒤로 넘어지는 각도
  pc, ps = cos(p), sin(p)
end
local function tilt(f, u)
  if fallK == 0 then return f, u end
  return f * pc - u * ps, f * ps + u * pc + 5 * fallK
end
local function P(f, s, u)
  f, u = tilt(f, u)
  local wx = f * ct - s * stt
  local wy = f * stt + s * ct
  return wx * K, (wy * KY - u * KZ) * K
end
local function D(f, s, u)
  f = tilt(f, u or 0)
  return f * camF + s * camS
end
-- 캐릭터 기준 좌표 → 월드 오프셋 (m)
function R.toWorld(face, f, s, u)
  local c, sn = cos(face), sin(face)
  return (f * c - s * sn) / 100, (f * sn + s * c) / 100, u / 100
end
-- 몸 기준점: 엉덩이 높이, 가슴 앞뒤, 가슴 높이
-- 체형: 다리는 짧게, 몸통은 길고 크게 (상체 강조)
local TORSO = 52
function R.body(crouch, lean)
  local hipU = 86 - (crouch or 0)
  lean = lean or 0
  return hipU, sin(lean) * TORSO, hipU + cos(lean) * TORSO
end

local function pushP(c, f, s, u)
  local x, y = P(f, s, u)
  c[#c + 1] = x; c[#c + 1] = y
end

-- 볼록 다각형 (어느 방향에서 봐도 몸통이 두께를 가진다)
local function cross(o, a, b) return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1]) end
local function ptLess(a, b) return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]) end
local function hullFill(c, outline)
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
  if outline then
    lg.setColor(OUT); lg.setLineWidth(1.6)
    lg.polygon("line", out)
  end
end
R.hullFill = hullFill

-- 부품 모아서 먼 것부터
local parts, np, sorted = {}, 0, {}
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

-- 모든 색에 투명도를 곱해서 그린다
function R.withAlpha(al, fn, ...)
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

-- 캡슐 팔다리: 외곽선 → 채움, 마디마다 둥글게
local function limb(col, w, pts)
  local sp = {}
  for i = 1, #pts, 3 do
    local x, y = P(pts[i], pts[i + 1], pts[i + 2])
    sp[#sp + 1] = x; sp[#sp + 1] = y
  end
  -- 마디마다 따로 그린다 (이어 그리면 화면에서 접히는 각도일 때 꺾임 처리가 긴 가시처럼 튀어나온다)
  local wp = max(2, w * K)
  lg.setColor(OUT)
  lg.setLineWidth(wp + 2.2)
  for i = 1, #sp - 3, 2 do lg.line(sp[i], sp[i + 1], sp[i + 2], sp[i + 3]) end
  for i = 1, #sp, 2 do lg.circle("fill", sp[i], sp[i + 1], (wp + 2.2) / 2) end
  lg.setColor(col)
  lg.setLineWidth(wp)
  for i = 1, #sp - 3, 2 do lg.line(sp[i], sp[i + 1], sp[i + 2], sp[i + 3]) end
  for i = 1, #sp, 2 do lg.circle("fill", sp[i], sp[i + 1], wp / 2) end
end
local function ball(col, r, f, s, u)
  local x, y = P(f, s, u)
  lg.setColor(OUT); lg.circle("fill", x, y, r * K + 1.2)
  lg.setColor(col); lg.circle("fill", x, y, r * K)
end

local function norm3(f, s, u)
  local l = sqrt(f * f + s * s + u * u)
  if l < 1e-6 then return 1, 0, 0 end
  return f / l, s / l, u / l
end
R.norm3 = norm3

-- 팔 IK: 어깨 → 팔꿈치 → 손 (팔꿈치는 바깥·아래로)
local function ik(sf, ss, su, hf, hs, hu, L1, L2, side)
  local df, ds, du = hf - sf, hs - ss, hu - su
  local d = sqrt(df * df + ds * ds + du * du)
  if d < 1e-3 then return sf, ss + side * L1, su, hf, hs, hu end
  local Lt = L1 + L2 - .01
  if d > Lt then
    local k = Lt / d
    df, ds, du = df * k, ds * k, du * k
    hf, hs, hu = sf + df, ss + ds, su + du
    d = Lt
  end
  local a = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
  local h = sqrt(max(0, L1 * L1 - a * a))
  local nf, ns, nu = df / d, ds / d, du / d
  local bf, bs, bu = -.3, side * .7, -.65
  local dt = bf * nf + bs * ns + bu * nu
  bf, bs, bu = bf - nf * dt, bs - ns * dt, bu - nu * dt
  local bl = sqrt(bf * bf + bs * bs + bu * bu)
  if bl < 1e-4 then bf, bs, bu, bl = 0, side, 0, 1 end
  bf, bs, bu = bf / bl, bs / bl, bu / bl
  return sf + nf * a + bf * h, ss + ns * a + bs * h, su + nu * a + bu * h, hf, hs, hu
end

-------------------------------------------------------------------------------
-- 무기
-------------------------------------------------------------------------------
local function screenPerp(x1, y1, x2, y2)
  local vx, vy = x2 - x1, y2 - y1
  local l = sqrt(vx * vx + vy * vy)
  if l < .01 then return 0, 1, 0, 0 end
  return -vy / l, vx / l, vx / l, vy / l
end

-- 칼: 손잡이 + 코등이 + 날
local function wSword(o, h, len, blade)
  local df, ds, du = norm3(o.wdir[1], o.wdir[2], o.wdir[3])
  add(D(h[1] + df * len * .5, h[2] + ds * len * .5, h[3]) + .6, function()
    local hx, hy = P(h[1], h[2], h[3])
    local tx, ty = P(h[1] + df * len, h[2] + ds * len, h[3] + du * len)
    local gx, gy = P(h[1] - df * 16, h[2] - ds * 16, h[3] - du * 16)
    if o.wglow then
      lg.setColor(1, .5, .15, .35 + .25 * sin(o.tm * 20)); lg.setLineWidth(13); lg.line(hx, hy, tx, ty)
    end
    -- 넓은 날 (끝이 뾰족한 다각형)
    local nx, ny, ux, uy = screenPerp(hx, hy, tx, ty)
    local bw = 3
    local mx, my = hx + (tx - hx) * .85, hy + (ty - hy) * .85
    local bl = { hx + nx * bw, hy + ny * bw, mx + nx * bw, my + ny * bw, tx, ty, mx - nx * bw, my - ny * bw, hx - nx * bw, hy - ny * bw }
    lg.setColor(OUT); lg.setLineWidth(4); lg.polygon("line", bl)
    lg.setColor(OUT); lg.setLineWidth(6.5); lg.line(gx, gy, hx, hy)
    lg.setColor(.4, .25, .13); lg.setLineWidth(4); lg.line(gx, gy, hx, hy)
    lg.setColor(o.fl and WHITE or blade); lg.polygon("fill", bl)
    if not o.fl then
      lg.setColor(1, 1, 1, .6)
      lg.polygon("fill", hx + nx * bw, hy + ny * bw, mx + nx * bw, my + ny * bw, tx, ty, mx, my, hx, hy)
    end
    lg.setColor(OUT); lg.setLineWidth(5.5); lg.line(hx + nx * 8, hy + ny * 8, hx - nx * 8, hy - ny * 8)
    lg.setColor(o.fl and WHITE or { .85, .72, .35 }); lg.setLineWidth(3); lg.line(hx + nx * 7, hy + ny * 7, hx - nx * 7, hy - ny * 7)
  end)
end

-- 둔기 (몽둥이)
local function wClub(o, h, len, width, col)
  local df, ds, du = norm3(o.wdir[1], o.wdir[2], o.wdir[3])
  add(D(h[1] + df * len * .5, h[2] + ds * len * .5, h[3]) + .6, function()
    local bx, by = P(h[1] - df * 10, h[2] - ds * 10, h[3] - du * 10)
    local tx, ty = P(h[1] + df * len, h[2] + ds * len, h[3] + du * len)
    if o.wglow then lg.setColor(1, .5, .15, .35 + .25 * sin(o.tm * 20)); lg.setLineWidth(width * K + 8); lg.line(bx, by, tx, ty) end
    lg.setColor(OUT); lg.setLineWidth(width * K + 2.4); lg.line(bx, by, tx, ty); lg.circle("fill", tx, ty, width * K * .7 + 1.2)
    lg.setColor(o.fl and WHITE or col); lg.setLineWidth(width * K); lg.line(bx, by, tx, ty); lg.circle("fill", tx, ty, width * K * .7)
  end)
end

-- 총: 몸통 + 총열 (총구 위치는 R.muzzle 로 계산)
local function wGun(o, h, len, thick, col)
  local df, ds, du = norm3(o.wdir[1], o.wdir[2], o.wdir[3])
  add(D(h[1] + df * len * .5, h[2] + ds * len * .5, h[3]) + .6, function()
    local bx, by = P(h[1] - df * 18, h[2] - ds * 18, h[3] - du * 18)
    local mx, my = P(h[1] + df * len * .6, h[2] + ds * len * .6, h[3] + du * len * .6)
    local tx, ty = P(h[1] + df * len, h[2] + ds * len, h[3] + du * len)
    lg.setColor(OUT); lg.setLineWidth(thick * K + 2.4); lg.line(bx, by, tx, ty)
    lg.setColor(o.fl and WHITE or col); lg.setLineWidth(thick * K); lg.line(bx, by, mx, my)
    lg.setColor(o.fl and WHITE or shade(col, .7)); lg.setLineWidth(thick * K * .55); lg.line(mx, my, tx, ty)
    if o.gunGlow and o.gunGlow > 0 then
      lg.setColor(1, .85, .3, o.gunGlow); lg.circle("fill", tx, ty, 3 + o.gunGlow * 4)
    end
  end)
end

-- 방패: 앞을 향한 원판
local function wShield(o, h)
  local nf, ns, nu = norm3(o.sdir[1], o.sdir[2], o.sdir[3])
  -- 원판 평면의 두 축 (수평 옆, 위)
  local af, as, au = norm3(-ns, nf, 0)
  local bf, bs, bu = -nu * nf, -nu * ns, 1 - nu * nu
  bf, bs, bu = norm3(bf, bs, bu)
  local cf, cs, cu = h[1] + nf * 6, h[2] + ns * 6, h[3]
  add(D(cf, cs, cu) + .7, function()
    local pts = {}
    for i = 0, 13 do
      local t = i / 14 * pi * 2
      local r = 44
      pushP(pts, cf + (af * cos(t) + bf * sin(t)) * r, cs + (as * cos(t) + bs * sin(t)) * r, cu + (au * cos(t) + bu * sin(t)) * r)
    end
    lg.setColor(o.fl and WHITE or { .36, .44, .58 }); hullFill(pts, true)
    -- 테두리와 가운데 징
    local inner = {}
    for i = 0, 13 do
      local t = i / 14 * pi * 2
      pushP(inner, cf + nf + (af * cos(t) + bf * sin(t)) * 33, cs + ns + (as * cos(t) + bs * sin(t)) * 33, cu + nu + (au * cos(t) + bu * sin(t)) * 33)
    end
    lg.setColor(o.fl and WHITE or { .48, .57, .72 }); hullFill(inner)
    local x, y = P(cf + nf * 3, cs + ns * 3, cu + nu * 3)
    lg.setColor(o.fl and WHITE or { .85, .82, .6 }); lg.circle("fill", x, y, 3.6)
    if o.blockFlash and o.blockFlash > 0 then
      lg.setColor(1, 1, .7, o.blockFlash); hullFill(pts)
    end
  end)
end

-- 활: 손잡이(왼손) 위아래로 휜 활대, 시위는 오른손까지 당겨진다
local function wBow(o, lh, rh)
  local ff, fs, fu = norm3(o.wdir[1], o.wdir[2], o.wdir[3])
  add(D(lh[1] + ff * 8, lh[2], lh[3]) + .7, function()
    local pts = {}
    for i = -4, 4 do
      local t = i / 4
      local f = lh[1] + ff * (12 - t * t * 22)
      local s = lh[2] + fs * (12 - t * t * 22)
      pushP(pts, f, s, lh[3] + t * 74)
    end
    lg.setColor(OUT); lg.setLineWidth(7.5); lg.line(pts)
    lg.setColor(o.fl and WHITE or { .58, .38, .18 }); lg.setLineWidth(4.5); lg.line(pts)
    -- 시위
    local ax, ay = pts[1], pts[2]
    local bx, by = pts[#pts - 1], pts[#pts]
    local sx, sy = (ax + bx) / 2, (ay + by) / 2
    if o.pull and o.pull > 0 then sx, sy = P(rh[1], rh[2], rh[3]) end
    lg.setColor(.92, .92, .88); lg.setLineWidth(1)
    lg.line(ax, ay, sx, sy, bx, by)
    -- 걸린 화살
    if o.nock then
      local hx, hy = P(rh[1], rh[2], rh[3])
      local tx, ty = P(rh[1] + ff * 95, rh[2] + fs * 95, rh[3] + fu * 95)
      lg.setColor(OUT); lg.setLineWidth(4.5); lg.line(hx, hy, tx, ty)
      lg.setColor(o.nockPower and { 1, .9, .3 } or { .85, .75, .55 }); lg.setLineWidth(2.4); lg.line(hx, hy, tx, ty)
      if o.nockPower then lg.setColor(1, .9, .3, .5 + .3 * sin(o.tm * 25)); lg.circle("fill", tx, ty, 4) end
    end
  end)
end

-- 지팡이 + 빛나는 구슬
local function wStaff(o, h)
  local df, ds, du = norm3(o.wdir[1], o.wdir[2], o.wdir[3])
  add(D(h[1] + df * 40, h[2] + ds * 40, h[3]) + .6, function()
    local bx, by = P(h[1] - df * 70, h[2] - ds * 70, h[3] - du * 70)
    local tx, ty = P(h[1] + df * 95, h[2] + ds * 95, h[3] + du * 95)
    lg.setColor(OUT); lg.setLineWidth(7.5); lg.line(bx, by, tx, ty)
    lg.setColor(o.fl and WHITE or { .45, .32, .2 }); lg.setLineWidth(4.5); lg.line(bx, by, tx, ty)
    -- 머리 장식 (갈래)
    local nx, ny = screenPerp(bx, by, tx, ty)
    lg.setColor(OUT); lg.setLineWidth(4)
    lg.line(tx + nx * 7, ty + ny * 7, tx, ty + 6, tx - nx * 7, ty - ny * 7)
    local g = o.orb or .3
    lg.setColor(.55, .45, 1, .35 * (g + .3)); lg.circle("fill", tx, ty, 9 + g * 12)
    lg.setColor(OUT); lg.circle("fill", tx, ty, 6 + g * 2.5)
    lg.setColor(.82, .76, 1); lg.circle("fill", tx, ty, 4.8 + g * 2.5)
  end)
end

-- 수류탄
local function wGrenade(o, h)
  add(D(h[1], h[2], h[3]) + .7, function()
    ball(o.fl and WHITE or { .28, .38, .22 }, 11, h[1], h[2], h[3])
    local x, y = P(h[1], h[2], h[3] + 11)
    lg.setColor(OUT); lg.circle("fill", x, y, 3)
    lg.setColor(.85, .78, .5); lg.circle("fill", x, y, 2)
  end)
end

-------------------------------------------------------------------------------
-- 마네킹
-- o: face fall walk moving crouch lean tuck kick col col2 visor fl tm
--    rh lh (손 위치 {f,s,u})  weapon wdir sdir pull nock nockPower orb wglow gunGlow blockFlash
--    trail {kind "h"/"v", a0, a, r, cf, cs, cu, alpha}
-------------------------------------------------------------------------------
function R.human(o)
  setFace(o.face, o.fall)
  local fl = o.fl
  local col = fl and WHITE or o.col
  local colD = fl and WHITE or shade(o.col, .78)
  local joint = fl and WHITE or (o.col2 or shade(o.col, .6))
  lg.setLineJoin("bevel")

  local crouch = o.crouch or 0
  local lean = o.lean or 0
  local hipU, chF, chU = R.body(crouch, lean)
  local hdF, hdU = sin(lean) * (TORSO + 28), hipU + cos(lean) * (TORSO + 28)
  local acc = fl and WHITE or (o.accent or joint)
  local amt = o.moving and 1 or 0
  local walk = o.walk or 0

  -- 다리
  for side = -1, 1, 2 do
    local ph = walk + (side == 1 and 0 or pi)
    local ff = sin(ph) * 30 * amt
    local fu = max(0, cos(ph)) * 12 * amt
    local hs = side * 10
    local kf, ku = ff * .5 + 9 + crouch * .5, (hipU + fu) * .5 + 3
    if o.tuck then ff, fu, kf, ku = 14, hipU - 36, 36, hipU - 10 end
    if o.kick and side == 1 then
      local k = o.kick
      ff, fu, kf, ku = 20 + 38 * k, 8 + 40 * k, 30 + 10 * k, hipU - 20 + 10 * k
    end
    -- 다리 하나를 직접 지정 {무릎 f, 무릎 u, 발 f, 발 u} (슈퍼맨 펀치의 굽힌 다리 등)
    if o.legs and o.legs[side] then
      local L = o.legs[side]
      kf, ku, ff, fu = L[1], L[2], L[3], L[4]
    end
    local far = side * camS < 0
    add(D(kf * .6, hs, ku), function()
      limb(far and colD or col, 12, { 0, hs, hipU, kf, hs * 1.05, ku, ff, hs, fu + 6 })
      limb(joint, 10, { ff - 4, hs, fu + 4, ff + 14, hs, fu + 4 })
    end)
  end

  -- 몸통: 넓은 어깨 → 좁은 허리 (역삼각형) + 골반
  add(D(chF * .5, 0, (hipU + chU) / 2), function()
    lg.setColor(col)
    local c = {}
    pushP(c, chF + 14, -27, chU + 6); pushP(c, chF + 14, 27, chU + 6); pushP(c, chF - 13, -27, chU + 6); pushP(c, chF - 13, 27, chU + 6)
    pushP(c, chF + 13, -22, chU - 18); pushP(c, chF + 13, 22, chU - 18); pushP(c, chF - 11, -22, chU - 18); pushP(c, chF - 11, 22, chU - 18)
    pushP(c, 9, -12, hipU + 4); pushP(c, 9, 12, hipU + 4); pushP(c, -9, -12, hipU + 4); pushP(c, -9, 12, hipU + 4)
    hullFill(c, true)
    lg.setColor(joint)
    local p = {}
    pushP(p, 10, -14, hipU + 6); pushP(p, 10, 14, hipU + 6); pushP(p, -10, -14, hipU + 6); pushP(p, -10, 14, hipU + 6)
    pushP(p, 10, -14, hipU - 7); pushP(p, 10, 14, hipU - 7); pushP(p, -10, -14, hipU - 7); pushP(p, -10, 14, hipU - 7)
    hullFill(p, true)
    -- 가슴 표식 (앞에서만, 스타일 색)
    if camF > -.1 and (o.accent or o.mark) then
      local x, y = P(chF + 14.5, 0, chU - 6)
      lg.setColor(fl and WHITE or (o.accent or o.mark))
      lg.circle("fill", x, y, 4.2)
      lg.setColor(OUT); lg.setLineWidth(1.2); lg.circle("line", x, y, 4.2)
    end
  end)

  -- 팔 (IK) : 굵은 팔 + 어깨 견갑
  local hands = {}
  for side = -1, 1, 2 do
    local sf, ss, su = chF, side * 26, chU + 2
    local hand = (side == 1) and o.rh or o.lh
    local hf, hs, hu
    if hand then hf, hs, hu = hand[1], hand[2], hand[3]
    else
      local ph = walk + (side == 1 and pi or 0)
      hf, hs, hu = chF + 4 + sin(ph) * 20 * amt, side * 31, hipU - 4
    end
    local ef, es, eu
    ef, es, eu, hf, hs, hu = ik(sf, ss, su, hf, hs, hu, 33, 31, side)
    hands[side] = { hf, hs, hu }
    local far = side * camS < 0
    add(D((sf + hf) / 2, (ss + hs) / 2, (su + hu) / 2) + .5, function()
      limb(far and colD or col, 15, { sf, ss, su, ef, es, eu, hf, hs, hu })
      ball((not fl and o.handCol) or joint, o.handR or 7, hf, hs, hu)   -- 맨손이면 붕대 감은 큰 주먹
      ball(far and shade(acc, .8) or acc, 11, sf, ss, su + 3)           -- 견갑 (스타일 색)
    end)
  end

  -- 머리 + 바이저 (바라보는 쪽 표시)
  add(D(hdF, 0, hdU) + 2, function()
    ball(col, 12.5, hdF, 0, hdU)
    if D(hdF + 10, 0, hdU) > D(hdF, 0, hdU) - 3 then
      local x1, y1 = P(hdF + 10.5, -7, hdU + 2)
      local x2, y2 = P(hdF + 10.5, 7, hdU + 2)
      lg.setColor(fl and WHITE or o.visor or OUT)
      lg.setLineWidth(max(2, 5 * K)); lg.line(x1, y1, x2, y2)
    end
  end)

  -- 무기
  local w = o.weapon
  if w == "sword" then wSword(o, hands[1], 120, { .88, .9, .96 })
  elseif w == "esword" then wSword(o, hands[1], 100, { .62, .6, .6 })
  elseif w == "shield" then wSword(o, hands[1], 82, { .88, .9, .96 }); wShield(o, hands[-1])
  elseif w == "bow" then wBow(o, hands[-1], hands[1])
  elseif w == "staff" then wStaff(o, hands[1])
  elseif w == "grenade" then if not o.noGrenade then wGrenade(o, hands[1]) end
  elseif w == "gun" then wGun(o, hands[1], R.GUN_LEN, 16, { .25, .26, .3 })
  elseif w == "rifle" then wGun(o, hands[1], R.RIFLE_LEN, 11, { .2, .16, .14 })
  elseif w == "club" then wClub(o, hands[1], 118, 18, { .42, .28, .16 })
  end

  flush()

  -- 휘두른 궤적 (몸 기준 원호)
  local tr = o.trail
  if tr and (tr.alpha or 1) > 0 then
    lg.setColor(1, 1, 1, .4 * (tr.alpha or 1))
    lg.setLineWidth(tr.w or 7)
    local pts = {}
    for i = 0, 12 do
      local b = tr.a0 + (tr.a - tr.a0) * i / 12
      if tr.kind == "h" then pushP(pts, tr.cf + cos(b) * tr.r, tr.cs + sin(b) * tr.r, tr.cu)
      else pushP(pts, tr.cf + cos(b) * tr.r, tr.cs, tr.cu + sin(b) * tr.r) end
    end
    lg.line(pts)
  end
  return hands
end

return R
