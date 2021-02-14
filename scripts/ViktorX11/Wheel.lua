return function(page, offset, screen_width, screen_height)
  page.layer.x = page.layer.x + offset
  local percent = offset/page.width

  for i, icon in subviews(page) do
    local icon_centerx = icon.x + icon.width/2
    local icon_centery = icon.y + icon.height/2
    local icon_center_offsetx = (page.width/2)-icon_centerx
    local radius4icon = screen_height - icon_centery + 0

    local percent2
    if offset < 0 then -- right page
      percent2 = ((icon_centerx) / page.width)
    else -- left page
      percent2 = ((page.width-icon_centerx) / page.width)
    end

    local angle = -percent*(1 + percent2*2) *  math.pi/2
    --angle = angle * (percent*percent*2)
    icon:translate(icon_center_offsetx, radius4icon, 0)
    icon:rotate(angle, 0, 0, 1)
    icon:translate(-icon_center_offsetx, -radius4icon, 0)
  end
end