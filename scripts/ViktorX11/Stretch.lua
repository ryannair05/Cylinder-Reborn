return function(page, offset, screen_width, screen_height)
  page.layer.x = page.layer.x + offset
  local percent = math.abs(offset/page.width)

  for i, icon in subviews(page) do
    local icon_centerx = icon.x + icon.width/2
	local percent_pright = (icon_centerx) / page.width
    local percent_pleft = (page.width-icon_centerx) / page.width

	if offset < 0 then -- right page
      icon:translate(icon_centerx*percent*percent_pright*4, 0, 0)
      icon:scale(1+(percent*percent*percent_pright/percent_pright), 1)
    else -- left page
      icon:translate(-((page.width-icon_centerx)*percent*percent_pleft)*4, 0, 0)
      icon:scale(1+(percent*percent*percent_pleft/percent_pleft), 1)
    end
  end
  page.layer.x = page.layer.x - (offset * percent *3)
end
