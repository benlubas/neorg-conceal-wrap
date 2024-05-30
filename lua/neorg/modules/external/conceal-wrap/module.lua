--[[
    file: Conceal-Wrap
    title: Hard wrap text based on it's concealed width
    ---

    Features:
    - Avoid joining text into headers
    - Avoid joining list items

--]]

local neorg = require("neorg.core")
local modules, log = neorg.modules, neorg.log

local module = modules.create("external.conceal-wrap")

module.setup = function()
    return {
        success = true,
    }
end

module.load = function()
    local ns = vim.api.nvim_create_augroup("neorg-conceal-wrap", { clear = true })

    module.private.break_at = vim.iter(vim.split(vim.o.breakat, ""))
        :filter(function(x)
            return not vim.list_contains(module.config.private.no_break_at, x)
        end)
        :totable()

    vim.api.nvim_create_autocmd("BufEnter", {
        desc = "Set the format expression on norg buffers",
        pattern = "*.norg",
        group = ns,
        callback = function(ev)
            -- set the format expression for the buffer.
            vim.api.nvim_set_option_value(
                "formatexpr",
                "v:lua.require'neorg.modules.external.conceal-wrap.module'.public.format()",
                { buf = ev.buf }
            )
        end,
    })
end

module.config.public = {}

module.config.private = {}

---Chars that we remove from break-at when wrapping lines. Break-at is global, and we don't want to
---mess with it. We will respect it until it starts to break syntax... Hmm. these are all valid in
---between words though, so maybe we could check that? Like this/that is fine, and doesn't start an
---italic section. so it would be okay to break there. Then we also have to consider when they touch
---against new lines though, that's annoying too. I think I will just remove them from breakat for
---now then.
module.config.private.no_break_at = { "/", ",", "!", "-", "*" }

---join lines defined by the 0 index start and end into a single line. Lines are separated by single
---spaces.
---@param buf number
---@param start number 0 based start
---@param _end number 0 based exclusive end
module.private.join_lines = function(buf, start, _end)
    local og_lines = vim.api.nvim_buf_get_lines(buf, start, _end, false)
    local joined = vim.iter(og_lines)
        :map(function(x)
            x = x:gsub("^%s+", "")
            x = x:gsub("%s+$", "")
            return x
        end)
        :join(" ")
    vim.api.nvim_buf_set_lines(buf, start, _end, false, { joined })
end

---Function to be used as `:h 'formatexpr'` which will hard wrap text in such a way that lines will
---be `textwidth` long when conceal is active
---@return integer
module.public.format = function()
    if vim.api.nvim_get_mode().mode == "i" then
        -- Returning 1 will tell nvim to fallback to the normal format method (which is capable of
        -- handling insert mode much better than we can currently)
        -- TODO: I think the issue might be that we remove blank spaces from the end when in insert
        -- mode, which causes problems
        return 1
    end
    local buf = vim.api.nvim_get_current_buf()
    local current_row = vim.v.lnum - 1

    -- group the lines by header/list items, etc..
    local groups = {}
    local next_group = {}
    local lines = vim.api.nvim_buf_get_lines(buf, current_row, current_row + vim.v.count, true)
    for i, line in ipairs(lines) do
        local ln = i + current_row - 1
        if line:match("^%s*%*+%s") then
            -- this is a header, it get's it's own group
            table.insert(groups, next_group)
            next_group = {}
            table.insert(groups, { ln })
        elseif line:match("^%s*%-+%s") then
            -- this is a list item, don't join the group above, but allow lines below to join
            table.insert(groups, next_group)
            next_group = { ln }
        elseif line:match("^%s*$") then
            -- this is a blank line, break the group
            table.insert(groups, next_group)
            next_group = {}
        else
            table.insert(next_group, ln)
        end
    end
    table.insert(groups, next_group)

    local offset = 0
    for _, group in ipairs(groups) do
        if #group == 0 then
            goto continue
        end
        module.private.join_lines(buf, group[1] + offset, group[#group] + 1 + offset)
        local new_line_len = module.private.format_joined_line(buf, group[1] + offset)
        offset = offset + (new_line_len - #group)
        ::continue::
    end

    -- module.private.join_lines(buf, current_row, current_row + vim.v.count)
    -- module.private.format_joined_line(buf, current_row)

    return 0
end

---Format a single line that's been joined
---@param buf number
---@param line_idx number 0 based line index
---@return number lines the number of lines the formatted text takes up
module.private.format_joined_line = function(buf, line_idx)
    local ok, err = pcall(function()
        local line = vim.api.nvim_buf_get_lines(buf, line_idx, line_idx + 1, false)[1]
        local new_lines = {}

        ---kinda like a byte index, It's just how far we are in the string of text.
        local col_index = 0
        local width = vim.bo.textwidth
        if width == 0 then
            width = 80 -- this is the value the built-in formatter defaults to when tw=0
        end

        -- account for breakindent
        vim.v.lnum = line_idx + 1
        local indent = vim.fn.eval(vim.bo.indentexpr)

        local left_offset = indent

        width = math.max(width - left_offset, 5) -- arbitrary 5 char limit
        while #line > 0 do
            local visible_width, next_cutoff_index =
                module.private.visible_text_width(buf, line_idx, col_index, col_index + #line, width)

            if visible_width <= width then
                table.insert(new_lines, line)
                break
            end
            -- definitely need this + 1 right now
            -- what is this + 1 for though?
            local chunk = line:sub(0, next_cutoff_index - col_index + 1)

            local i = #chunk
            while i > 0 do
                if vim.list_contains(module.private.break_at, chunk:sub(i, i)) then
                    break
                end
                i = i - 1
            end
            if i == 0 then
                -- we didn't find a space, so we just break the line at the width
                i = next_cutoff_index
            end
            table.insert(new_lines, line:sub(0, i))
            col_index = col_index + i
            line = line:sub(i + 1)
        end

        new_lines = vim.iter(new_lines)
            :map(function(l)
                l = l:gsub("^%s*", (" "):rep(indent))
                l = l:gsub("%s+$", "")
                return l
            end)
            :totable()
        -- Now we have new lines, have to write them to the buffer
        vim.api.nvim_buf_set_lines(buf, line_idx, line_idx + 1, false, new_lines)
        return #new_lines
    end)
    if not ok then
        log.error(err)
    end
    return err
end

---Compute the "visible" width of the given range, that is the width of the line when conceal is active.
---If the visible width is larger than target, return the position of the last visible character before target.
---@param buf number
---@param line_idx number 0 based line number
---@param start_col number 0 based
---@param end_col number 0 based, exclusive
---@param target number
---@return number width, number next_index
module.private.visible_text_width = function(buf, line_idx, start_col, end_col, target)
    -- offset x by inline virtual text
    local width = 0
    -- track positions that are concealed by extmarks
    local extmark_concealed = {}
    local same_line_extmarks = vim.api.nvim_buf_get_extmarks(
        buf,
        -1,
        { line_idx, start_col },
        { line_idx, end_col },
        { details = true }
    )
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

    local best_target = start_col
    -- col indexing is 0 based
    for c = start_col, end_col - 1 do
        width = width + 1
        local res = vim.treesitter.get_captures_at_pos(buf, line_idx, c)
        for _, hl in ipairs(res) do
            if hl.capture == "conceal" and not extmark_concealed[c + 1] then
                width = width - 1
                break
            end
        end

        -- target + 1 b/c if the lines ends where "d" in "word " is at `target` then we should break at the " "
        if width <= target + 1 then
            best_target = c
        end
    end
    return width, best_target
end

return module
