return function(page, offset, screen_width, screen_height)
  page.layer.x = page.layer.x + offset
  local width = page.width
  local percent = math.abs(offset/width)
  local stretch = 1 + percent*percent

  for i, icon in subviews(page) do
    local icon_centerx = icon:center()

	if offset < 0 then -- right page
      local percent_pright = (icon_centerx) / width
      icon:translate(icon_centerx*percent*percent_pright*4, 0, 0)
    else -- left page
      local percent_pleft = (width-icon_centerx) / width
      icon:translate(-((width-icon_centerx)*percent*percent_pleft)*4, 0, 0)
    end
    icon:scale(stretch, 1)
  end
  page.layer.x = page.layer.x - (offset * percent *3)
end
