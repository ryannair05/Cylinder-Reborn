
return function(page, offset, screen_width, screen_height)

    local percent = math.abs(offset/page.layer.width)
    local alpha = 1 - percent

    page.alpha = alpha

    for i, icon in subviews(page) do
        icon.alpha = alpha
    end

end
