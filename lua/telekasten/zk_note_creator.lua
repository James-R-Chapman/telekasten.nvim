-- telekasten/zk_note_creator.lua
-- Note creation functionality

local M = {}
local config = {}
local templates = nil

function M.setup(cfg)
  config = cfg
  templates = require("telekasten.zk_templates")
end

-- Create a slug from title
local function slugify(title)
  return title:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
end

-- Generate filename
local function generate_filename(id, title)
  local slug = slugify(title)
  local format = config.filename_format or "{id}-{slug}"
  local filename = format:gsub("{id}", id):gsub("{slug}", slug)
  return filename .. "." .. config.extension
end

-- Create a new zettelkasten note
function M.create_note(opts)
  opts = opts or {}

  -- Prompt for title
  local title = opts.title or vim.fn.input("Note title: ")
  if title == "" then
    vim.notify("Cancelled", vim.log.levels.INFO)
    return
  end

  -- Generate frontmatter and ID
  local frontmatter, id = templates.create_note_frontmatter(title)

  -- Generate filename
  local filename = generate_filename(id, title)
  local filepath = config.dirs.inbox .. filename

  -- Check if file exists
  if vim.fn.filereadable(filepath) == 1 then
    vim.notify("File already exists: " .. filename, vim.log.levels.ERROR)
    return
  end

  -- Write file
  local lines = vim.split(frontmatter, "\n")
  vim.fn.writefile(lines, filepath)

  -- Open file
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))

  -- Position cursor after frontmatter
  vim.schedule(function()
    local line_count = vim.api.nvim_buf_line_count(0)
    for i = 1, line_count do
      local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
      if line == "---" and i > 1 then
        -- Found closing frontmatter, position cursor after it
        vim.api.nvim_win_set_cursor(0, { i + 2, 0 })
        vim.cmd("startinsert")
        break
      end
    end
  end)

  vim.notify("✓ Created note: " .. filename, vim.log.levels.INFO)
end

-- Create a new source/literature note
function M.create_source_note(opts)
  opts = opts or {}

  -- Prompt for title
  local title = opts.title or vim.fn.input("Source title: ")
  if title == "" then
    vim.notify("Cancelled", vim.log.levels.INFO)
    return
  end

  -- Prompt for type
  local note_type = opts.type or vim.fn.input("Type (book/article/video/etc): ", "article")
  if note_type == "" then
    note_type = "article"
  end

  -- Prompt for URL
  local url = opts.url or vim.fn.input("URL (optional): ")

  -- Generate frontmatter and ID
  local frontmatter, id = templates.create_source_frontmatter(title, note_type, url)

  -- Generate filename
  local filename = generate_filename(id, title)
  local filepath = config.dirs.sources .. filename

  -- Check if file exists
  if vim.fn.filereadable(filepath) == 1 then
    vim.notify("File already exists: " .. filename, vim.log.levels.ERROR)
    return
  end

  -- Write file
  local lines = vim.split(frontmatter, "\n")
  vim.fn.writefile(lines, filepath)

  -- Open file
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))

  -- Position cursor after frontmatter
  vim.schedule(function()
    local line_count = vim.api.nvim_buf_line_count(0)
    for i = 1, line_count do
      local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
      if line == "---" and i > 1 then
        -- Found closing frontmatter, position cursor after it
        vim.api.nvim_win_set_cursor(0, { i + 2, 0 })
        vim.cmd("startinsert")
        break
      end
    end
  end)

  vim.notify("✓ Created source note: " .. filename, vim.log.levels.INFO)
end

return M
