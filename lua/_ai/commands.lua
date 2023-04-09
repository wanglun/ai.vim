local M = {}

local openai = require("_ai/openai")
local config = require("_ai/config")
local indicator = require("_ai/indicator")

local function chat_complete_messages (prompt, buffer_prompt, prefix)
    local messages = {}
    table.insert(messages, {
        role = "system",
        content = "You complete user's text. " .. (prompt and "Follow the user's instructions carefully & to the letter. " or "")
            .. "Only respond with the text that should be in ##complete_here##. "
            .. "Preserve indentation to be consistent with the surrounding content." .. buffer_prompt
    })

    local content = prefix

    if prompt then
        content = content .. "\n\n---\n\nCompletion instructions: " .. prompt
    end

    table.insert(messages, {
        role = "user",
        content = content
    })

    table.insert(messages, {
        role = "assistant",
        content = "Contents of ##complete_here##:"
    })

    return messages
end

local function chat_edit_messages (prompt, buffer_prompt, prefix, selected_text)
    local messages = {}

    table.insert(messages, {
        role = "system",
        content = "You modify user's text. Follow the user's requirements carefully & to the letter. "
            .. "Only respond with the text that should be in user's selection. "
            .. "Preserve indentation to be consistent with the surrounding content." .. buffer_prompt
    })

    table.insert(messages, {
        role = "user",
        content = prefix .. "\n\n---\n\nSelection:\n\n" .. selected_text
            .. "\n\n---\n\nModify selection accordingly: " .. (prompt or "improve") -- default to improve instructions
    })

    table.insert(messages, {
        role = "assistant",
        content = "Modified selection:"
    })

    return messages
end

---@param args { args: string, range: integer }
function M.ai (args)
    local prompt = args.args
    local visual_mode = args.range > 0

    local buffer = vim.api.nvim_get_current_buf()

    local start_row, start_col
    local end_row, end_col

    if visual_mode then
        -- Use the visual selection
        local start_pos = vim.api.nvim_buf_get_mark(buffer, "<")
        start_row = start_pos[1] - 1
        start_col = start_pos[2]

        local end_pos = vim.api.nvim_buf_get_mark(buffer, ">")
        end_row = end_pos[1] - 1
        local line = vim.fn.getline(end_pos[1])
        if line == "" then
            end_col = 0
        else
            end_col = vim.fn.byteidx(line, vim.fn.charcol("'>"))
        end

    else
        -- Use the cursor position
        local start_pos = vim.api.nvim_win_get_cursor(0)
        start_row = start_pos[1] - 1
        local line = vim.fn.getline(start_pos[1])
        if line == "" then
            start_col = 0
        else
            start_col = vim.fn.byteidx(line, vim.fn.charcol("."))
        end
        end_row = start_row
        end_col = start_col
    end

    local start_line_length = vim.api.nvim_buf_get_lines(buffer, start_row, start_row+1, true)[1]:len()
    start_col = math.min(start_col, start_line_length)

    local end_line_length = vim.api.nvim_buf_get_lines(buffer, end_row, end_row+1, true)[1]:len()
    end_col = math.min(end_col, end_line_length)

    local indicator_obj = indicator.create(buffer, start_row, start_col, end_row, end_col)
    local accumulated_text = ""

    local function on_data (data)
        accumulated_text = accumulated_text .. data.choices[1].text
        indicator.set_preview_text(indicator_obj, accumulated_text)
    end

    local function on_complete (err)
        if err then
            vim.api.nvim_err_writeln("ai.vim: " .. err)
        else
            indicator.set_buffer_text(indicator_obj, accumulated_text)
        end
        indicator.finish(indicator_obj)
    end

    if visual_mode then
        local selected_text = table.concat(vim.api.nvim_buf_get_text(buffer, start_row, start_col, end_row, end_col, {}), "\n")
        if prompt == "" then
            -- Replace the selected text, also using it as a prompt
            openai.completions({
                prompt = selected_text,
            }, on_data, on_complete)
        else
            -- Edit selected text
            openai.edits({
                input = selected_text,
                instruction = prompt,
            }, on_data, on_complete)
        end
    else
        if prompt == "" then
            -- Insert some text generated using surrounding context
            local prefix = table.concat(vim.api.nvim_buf_get_text(buffer,
                math.max(0, start_row-config.context_before), 0, start_row, start_col, {}), "\n")

            local line_count = vim.api.nvim_buf_line_count(buffer)
            local suffix = table.concat(vim.api.nvim_buf_get_text(buffer,
                end_row, end_col, math.min(end_row+config.context_after, line_count-1), 99999999, {}), "\n")

            openai.completions({
                prompt = prefix,
                suffix = suffix,
            }, on_data, on_complete)
        else
            -- Insert some text generated using the given prompt
            openai.completions({
                prompt = prompt,
            }, on_data, on_complete)
        end
    end
end

---@param args { args: string, range: integer }
function M.chat (args)
    local prompt = args.args
    local visual_mode = args.range > 0

    local buffer = vim.api.nvim_get_current_buf()
    local buffer_name = vim.api.nvim_buf_get_name(buffer)
    local buffer_prompt = ""

    if buffer_name ~= "" then
        buffer_name = buffer_name:match("^.+/(.+)$") or buffer_name
        buffer_prompt = " User is editing " .. buffer_name .. ", respond in the same file format."
    end

    local start_row, start_col
    local end_row, end_col

    if visual_mode then
        -- Use the visual selection
        local start_pos = vim.api.nvim_buf_get_mark(buffer, "<")
        start_row = start_pos[1] - 1
        start_col = start_pos[2]

        local end_pos = vim.api.nvim_buf_get_mark(buffer, ">")
        end_row = end_pos[1] - 1
        local line = vim.fn.getline(end_pos[1])
        if line == "" then
            end_col = 0
        else
            end_col = vim.fn.byteidx(line, vim.fn.charcol("'>"))
        end

    else
        -- Use the cursor position
        local start_pos = vim.api.nvim_win_get_cursor(0)
        start_row = start_pos[1] - 1
        local line = vim.fn.getline(start_pos[1])
        if line == "" then
            start_col = 0
        else
            start_col = vim.fn.byteidx(line, vim.fn.charcol("."))
        end
        end_row = start_row
        end_col = start_col
    end

    local start_line_length = vim.api.nvim_buf_get_lines(buffer, start_row, start_row+1, true)[1]:len()
    start_col = math.min(start_col, start_line_length)

    local end_line_length = vim.api.nvim_buf_get_lines(buffer, end_row, end_row+1, true)[1]:len()
    end_col = math.min(end_col, end_line_length)

    local indicator_obj = indicator.create(buffer, start_row, start_col, end_row, end_col)
    local accumulated_text = ""

    local function on_data (data)
        local content = data.choices[1].delta.content
        if content then
            accumulated_text = accumulated_text .. content
            indicator.set_preview_text(indicator_obj, accumulated_text)
        end
    end

    local function on_complete (err)
        if err then
            vim.api.nvim_err_writeln("ai.vim: " .. err)
        else
            indicator.set_buffer_text(indicator_obj, accumulated_text)
        end
        indicator.finish(indicator_obj)
    end

    -- Surrounding context
    local prefix = table.concat(vim.api.nvim_buf_get_text(buffer,
        math.max(0, start_row-config.context_before), 0, start_row, start_col, {}), "\n")

    if visual_mode then
        local selected_text = table.concat(vim.api.nvim_buf_get_text(buffer, start_row, start_col, end_row, end_col, {}), "\n")
        -- Edit selected text
        openai.chat_completions({
            messages = chat_edit_messages(prompt, buffer_prompt, prefix, selected_text)
        }, on_data, on_complete)
    else
        if prompt == "" then
            openai.chat_completions({
                messages = chat_complete_messages(prefix, buffer_prompt, "")
            }, on_data, on_complete)
        else
            -- Insert some text generated using the given prompt
            openai.chat_completions({
                messages = chat_complete_messages(prompt, buffer_prompt, prefix)
            }, on_data, on_complete)
        end
    end
end

return M
