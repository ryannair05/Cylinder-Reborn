return function(page, offset, screen_width, screen_height)
  page.layer.x = page.layer.x + offset
  local width = page.width
  local percent = offset/width
  local quarter = math.pi/2

  for i, icon in subviews(page) do
    local icon_centerx, icon_centery = icon:center()
    local icon_center_offsetx = (width/2)-icon_centerx
    local radius4icon = screen_height - icon_centery + 0

    local percent2
    if offset < 0 then -- right page
      percent2 = ((icon_centerx) / width)
    else -- left page
      percent2 = ((width-icon_centerx) / width)
    end

    local angle = -percent*(1 + percent2*2) *  quarter
    --angle = angle * (percent*percent*2)
    icon:translate(icon_center_offsetx, radius4icon, 0)
    icon:rotate(angle, 0, 0, 1)
    icon:translate(-icon_center_offsetx, -radius4icon, 0)
  end
end