vim.api.nvim_create_user_command("AI", function (args)
    require("_ai/commands").ai(args)
end, {
    range = true,
    nargs = "*",
})

vim.api.nvim_create_user_command("Chat", function (args)
    require("_ai/commands").chat(args)
end, {
    range = true,
    nargs = "*",
})

if not vim.g.ai_no_mappings then
    vim.api.nvim_set_keymap("n", "<C-a>", ":Chat ", { noremap = true })
    vim.api.nvim_set_keymap("v", "<C-a>", ":Chat ", { noremap = true })
    vim.api.nvim_set_keymap("i", "<C-a>", "<Esc>:Chat<CR>a", { noremap = true })
end
