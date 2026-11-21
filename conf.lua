function love.conf(t)
  t.identity = "quarterview"
  t.window.title = "쿼터뷰 액션 - 전투 테스트"
  -- 게임은 960x540 기준으로 그리고 창 크기에 맞춰 늘린다. F11 전체화면
  t.window.width = 1440
  t.window.height = 810
  t.window.resizable = true
  t.window.minwidth = 640
  t.window.minheight = 360
  t.window.msaa = 4
  t.window.vsync = 1
  t.console = false
end
