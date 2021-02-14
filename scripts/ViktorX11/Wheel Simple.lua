return function(page, offset, screen_width, screen_height)		
  page.layer.x = page.layer.x + offset
  local percent = offset/page.width
  local angle = -percent * math.pi/2 * 0.7
  local radius = screen_height * 0.9

  page:translate(0, radius, 0)
  page:rotate(angle, 0, 0, 1)
  page:translate(0, -radius, 0)
end
