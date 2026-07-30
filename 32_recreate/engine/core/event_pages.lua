local EventPages = {}

function EventPages.validate(
    host,
    pages,
    validator,
    path,
    validate_page
)
    pages = validator:array(pages, path, false)
    if not pages then return nil end
    if #pages == 0 then
        validator:error(path, "must contain at least one page")
        return pages
    end

    local seen = {}
    for index, page in ipairs(pages) do
        local page_path = string.format("%s[%d]", path, index)
        if validator:table(page, page_path, true) then
            local id = validator:string(
                page.id,
                page_path .. ".id",
                true
            )
            if id and seen[id] then
                validator:error(
                    page_path .. ".id",
                    "duplicates another page id"
                )
            elseif id then
                seen[id] = true
            end
            if page.condition then
                host.rules:validateCondition(
                    page.condition,
                    validator,
                    page_path .. ".condition"
                )
            end
            validate_page(page, validator, page_path)
        end
    end
    return pages
end

-- Later pages have higher priority, matching the event-page model used by
-- RPG creation tools. No matching page means the event is currently absent.
function EventPages.select(rules, pages, context)
    for index = #(pages or {}), 1, -1 do
        local page = pages[index]
        local matched, match_error =
            rules:evaluate(page.condition, context)
        if match_error then return nil, nil, match_error end
        if matched then return page, index end
    end
    return nil
end

return EventPages
