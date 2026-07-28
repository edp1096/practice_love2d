local filesystem = {}

function filesystem:list(path)
    local success, result = pcall(love.filesystem.getDirectoryItems, path)
    if not success then return nil, result end
    return result
end

function filesystem:info(path)
    return love.filesystem.getInfo(path)
end

function filesystem:loadTable(path)
    local chunk, load_error = love.filesystem.load(path)
    if not chunk then return nil, load_error end

    -- Content chunks can only construct and return data. Engine globals,
    -- require(), os, io, and love are deliberately unavailable.
    setfenv(chunk, {})
    local success, result = pcall(chunk)
    if not success then return nil, result end
    if type(result) ~= "table" then
        return nil, "content file must return one table"
    end
    return result
end

function filesystem:writeAtomic(path, data)
    local directory = path:match("^(.*)/[^/]+$")
    if directory and directory ~= "" then
        local created = love.filesystem.createDirectory(directory)
        if not created then
            return nil, "could not create save directory '" ..
                directory .. "'"
        end
    end

    local temporary = path .. ".tmp"
    local written, write_error =
        love.filesystem.write(temporary, data)
    if not written then return nil, write_error end

    local save_directory = love.filesystem.getSaveDirectory()
    local target_path = save_directory .. "/" .. path
    local temporary_path = save_directory .. "/" .. temporary
    local replaced, replace_error =
        os.rename(temporary_path, target_path)
    if replaced then return true end

    -- Windows cannot replace an existing target with rename(). Preserve the
    -- previous file while performing the fallback so a failed write remains
    -- recoverable.
    local backup_path = target_path .. ".bak"
    os.remove(backup_path)
    local had_target = love.filesystem.getInfo(path) ~= nil
    if had_target then
        local backed_up, backup_error =
            os.rename(target_path, backup_path)
        if not backed_up then
            love.filesystem.remove(temporary)
            return nil, backup_error or replace_error
        end
    end
    replaced, replace_error = os.rename(temporary_path, target_path)
    if not replaced then
        if had_target then os.rename(backup_path, target_path) end
        love.filesystem.remove(temporary)
        return nil, replace_error
    end
    if had_target then os.remove(backup_path) end
    return true
end

return filesystem
