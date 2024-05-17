--[[
    file: Conceal-Wrap
    title: Hard wrap text based on it's concealed width
    ---

--]]

local neorg = require("neorg.core")
local modules, log = neorg.modules, neorg.log

local module = modules.create("external.conceal_wrap")

module.setup = function()
    return {
        success = true,
    }
end

module.load = function()
    local ns = vim.api.nvim_create_augroup("neorg-conceal-wrap", { clear = true })
    vim.api.nvim_create_autocmd("BufEnter", {
        desc = "Set the format expression on norg buffers",
        pattern = "*.norg",
        group = ns,
        callback = function(ev)
            vim.api.nvim_set_option_value(
                "formatexpr",
                "v:lua.require'neorg.modules.external.conceal_wrap.module'.public.format()",
                { buf = ev.buf }
            )
        end,
    })
end

module.config.public = {}

---take an index, and a list that represents lines, and return the real row and column of that
---index. Returns nil when i is out of range
---@param lines string[]
---@param i number
---@return {[1]: number, [2]: number}
module.private.index_to_rc = function(lines, i)
    local remaining_index = i
    for current_row, line in ipairs(lines) do
        if line:len() >= remaining_index then
            return { current_row, remaining_index }
        end
        remaining_index = remaining_index - line:len() - 1
    end
    return { -1, -1 }
end

---take a row, col tuple and return the index into a string of lines
---@param lines string[]
---@param pos {[1]: number, [2]: number}
---@return number
module.private.rc_to_index = function(lines, pos)
    local idx = 0
    for i = 1, pos[1] do
        if i < pos[1] then
            idx = idx + lines[i]:len() + 1
        else
            idx = idx + pos[2] -- not this + 1
        end
    end
    return idx
end

---Function to be used as `:h 'formatexpr'` which will hard wrap text in such a way that lines will
---be `textwidth` long when conceal is active
---@return integer
module.public.format = function()
    if vim.api.nvim_get_mode().mode == "i" then
        -- Returning 1 will tell nvim to fallback to the normal format method (which is capable of
        -- handling insert mode much better than we can currently)
        -- TODO: I think the issue might be that we remove blank lines from the end when in insert
        -- mode, which causes problems
        return 1
    end
    local ok, err = pcall(function()
        local buf = vim.api.nvim_get_current_buf()
        local current_row = vim.v.lnum - 1
        ---kinda like a byte index, It's just how far we are in the string of text.
        local col_index = 1
        local og_lines = vim.api.nvim_buf_get_lines(buf, current_row, current_row + vim.v.count, false)
        local new_lines = {}

        local width = vim.bo.textwidth

        local left_offset = 0
        -- account for breakindent
        local leading_white_space = og_lines[1]:match("^%s*")
        if leading_white_space then
            left_offset = #leading_white_space
        end
        og_lines = vim.iter(og_lines)
            :map(function(l)
                local ret = string.gsub(l, "^%s+", "")
                return ret
            end)
            :totable()

        local line = table.concat(og_lines, " ")

        width = math.max(width - left_offset, 5) -- arbitrary 5 char limit
        while #line > 0 do
            local s = module.private.index_to_rc(og_lines, col_index)
            local e = module.private.index_to_rc(og_lines, col_index + #line - 1)
            s = { s[1] + current_row - 1, s[2] + #leading_white_space }
            e = { e[1] + current_row - 1, e[2] + #leading_white_space }
            local visible_width, next_cutoff_rc =
                module.private.visible_text_width(buf, s, e, width, leading_white_space)
            local next_index =
                module.private.rc_to_index(og_lines, { next_cutoff_rc[1] - current_row + 1, next_cutoff_rc[2] })
            if visible_width <= width then
                table.insert(new_lines, line)
                break
            end
            -- definitely need this + 1 right now
            local chunk = line:sub(0, next_index - col_index + 1)
            --NOTE: The error is probably happening before this, right?

            local i = #chunk
            while i > 0 do
                if vim.tbl_contains(vim.split(vim.o.breakat, ""), chunk:sub(i, i)) then
                    break
                end
                i = i - 1
            end
            if i == 0 then
                -- we didn't find a space, so we just break the line at the width
                i = next_index
            end
            table.insert(new_lines, line:sub(0, i))
            col_index = col_index + i
            line = line:sub(i + 1)
        end

        new_lines = vim.iter(new_lines)
            :map(function(l)
                l = l:gsub("^%s*", leading_white_space)
                l = l:gsub("%s+$", "")
                return l
            end)
            :totable()
        -- Now we have new lines, have to write them to the buffer
        vim.api.nvim_buf_set_lines(buf, vim.v.lnum - 1, vim.v.lnum + vim.v.count - 1, false, new_lines)
        return 0
    end)
    if not ok then
        log.error(err)
    end
    return 0
end

---Compute the "visible" width of the given range, that is the width of the line when conceal is active.
---If the visible width is larger than target, return the position of the last visible character before target.
---@param buf number
---@param start {[1]: number, [2]: number}
---@param _end {[1]: number, [2]: number}
---@param target number
---@param leading_white_space string
---@return number, {[1]: number, [2]: number}
module.private.visible_text_width = function(buf, start, _end, target, leading_white_space)
    -- offset x by inline virtual text
    local width = 0
    -- track positions that are concealed by extmarks
    local extmark_concealed = {}
    local same_line_extmarks = vim.api.nvim_buf_get_extmarks(buf, -1, start, _end, { details = true })
    for _, extmark in ipairs(same_line_extmarks) do
        local details = extmark[4]
        -- we don't care if conceal is on or off. Always wrap for when it's on
        if details.conceal and details.end_col then
            -- remove width b/c this is removing space
            for i = extmark[3], details.end_col do
                extmark_concealed[i] = true
            end
            width = width - (details.end_col - extmark[3])
        end
    end

    local best_target = start
    for r = start[1], _end[1] do
        local line = vim.api.nvim_buf_get_lines(buf, r, r + 1, false)[1]
        -- local clean_line = line:gsub("^%s+", "")
        -- local line_len = clean_line:len()
        local start_c = #leading_white_space
        local end_c = line:len() - 1
        if r == start[1] then
            start_c = start[2]
        end
        if r == _end[1] then
            end_c = _end[2]
        end
        for c = start_c, end_c do
            width = width + 1
            local res = vim.inspect_pos(
                buf,
                r,
                c,
                { semantic_tokens = false, syntax = false, extmarks = false, treesitter = true }
            )
            for _, hl in ipairs(res.treesitter) do
                if hl.capture == "conceal" and not extmark_concealed[c + 1] then
                    width = width - 1
                    break
                end
            end

            -- target + 1 b/c if the lines ends where "d" in "word " is at `target` then we should break at the " "
            if width <= target + 1 then
                best_target = { r, c }
            end
        end
        width = width + 1
    end
    width = width - 1
    return width, best_target
end

return module
