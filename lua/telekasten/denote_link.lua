-- telekasten/denote_link.lua
-- Denote-style link creation with smart tag inheritance and hub assignment

local M = {}
local utils = require("telekasten.utils")
local telekasten = require("telekasten")

-- Parent tracking for return navigation
local parent_stack = {}

-- Store popup window and buffer IDs
local popup_win = nil
local popup_buf = nil
local source_buf = nil

-- Create a bottom split window (like Emacs capture buffer)
local function create_popup_window(filepath)
  -- Create a new buffer
  local buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  vim.api.nvim_buf_set_option(buf, "buftype", "")

  -- Create a bottom split (like Emacs capture)
  -- Use 40% of screen height
  local height = math.floor(vim.api.nvim_get_option("lines") * 0.4)

  vim.cmd("botright " .. height .. "split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  -- Set window options
  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "linebreak", true)
  vim.api.nvim_win_set_option(win, "number", false)
  vim.api.nvim_win_set_option(win, "relativenumber", false)
  vim.api.nvim_win_set_option(win, "signcolumn", "no")

  -- Add Emacs-style hydra hint at the top
  local ns_id = vim.api.nvim_create_namespace("capture_hydra")
  vim.api.nvim_buf_set_extmark(buf, ns_id, 0, 0, {
    virt_lines = {
      {
        { "Capture buffer: ", "Comment" },
        { "Finish ", "String" },
        { "'C-c C-c'", "Keyword" },
        { ", refile ", "Comment" },
        { "'C-c C-w'", "Keyword" },
        { ", abort ", "Comment" },
        { "'C-c C-k'", "Keyword" },
      },
    },
    virt_lines_above = true,
  })

  return win, buf
end

-- Finish capture (save and close) - C-c C-c
local function finish_capture()
  if popup_buf and vim.api.nvim_buf_is_valid(popup_buf) then
    -- Save the buffer if modified
    if vim.api.nvim_buf_get_option(popup_buf, "modified") then
      vim.api.nvim_buf_call(popup_buf, function()
        vim.cmd("write")
      end)
    end
  end

  if popup_win and vim.api.nvim_win_is_valid(popup_win) then
    vim.api.nvim_win_close(popup_win, true)
  end

  popup_win = nil
  popup_buf = nil
  source_buf = nil
  vim.notify("✓ Note saved", vim.log.levels.INFO)
end

-- Abort capture (close without saving) - C-c C-k
local function abort_capture()
  if popup_buf and vim.api.nvim_buf_is_valid(popup_buf) then
    -- Mark as not modified to avoid save prompt
    vim.api.nvim_buf_set_option(popup_buf, "modified", false)
  end

  if popup_win and vim.api.nvim_win_is_valid(popup_win) then
    vim.api.nvim_win_close(popup_win, true)
  end

  popup_win = nil
  popup_buf = nil
  source_buf = nil
  vim.notify("✗ Note discarded", vim.log.levels.WARN)
end

-- Refile capture (move to zettelkasten) - C-c C-w
local function refile_capture()
  if not popup_buf or not vim.api.nvim_buf_is_valid(popup_buf) then
    return
  end

  -- Save first
  if vim.api.nvim_buf_get_option(popup_buf, "modified") then
    vim.api.nvim_buf_call(popup_buf, function()
      vim.cmd("write")
    end)
  end

  -- Get current file path
  local filepath = vim.api.nvim_buf_get_name(popup_buf)

  -- Move from inbox to zettelkasten
  local zettel_dir = vim.fn.expand("~/orgroam/zettelkasten/")
  local filename = vim.fn.fnamemodify(filepath, ":t")
  local new_path = zettel_dir .. filename

  -- Move the file
  vim.fn.rename(filepath, new_path)

  -- Close the capture window
  if popup_win and vim.api.nvim_win_is_valid(popup_win) then
    vim.api.nvim_win_close(popup_win, true)
  end

  popup_win = nil
  popup_buf = nil
  source_buf = nil
  vim.notify("✓ Note refiled to zettelkasten", vim.log.levels.INFO)
end

-- Close the capture window
local function close_popup()
  finish_capture()
end

-- Parse frontmatter from a buffer
local function parse_frontmatter(bufnr)
  bufnr = bufnr or 0
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

  local in_frontmatter = false
  local frontmatter = {}
  local frontmatter_end_line = 0

  for i, line in ipairs(lines) do
    if i == 1 and line == "---" then
      in_frontmatter = true
    elseif in_frontmatter and line == "---" then
      frontmatter_end_line = i
      break
    elseif in_frontmatter then
      -- Parse key: value
      local key, value = line:match("^(%w+):%s*(.*)$")
      if key then
        frontmatter[key] = value
      end
    end
  end

  return frontmatter, frontmatter_end_line
end

-- Get the word under cursor or visual selection
local function get_link_text()
  local mode = vim.fn.mode()

  if mode == "v" or mode == "V" then
    -- Visual mode: get selected text
    vim.cmd('noau normal! "vy"')
    return vim.fn.getreg("v")
  else
    -- Normal mode: get word under cursor
    return vim.fn.expand("<cword>")
  end
end

-- Create a slug from title
local function slugify(title)
  return title:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
end

-- Generate filename in Denote style
local function generate_filename(title)
  local id = os.date("%Y%m%dT%H%M%S")
  local slug = slugify(title)
  return string.format("%s-%s.md", id, slug)
end

-- Create frontmatter with inherited properties
local function create_frontmatter(title, source_frontmatter)
  local id = os.date("%Y%m%dT%H%M%S")
  local date = os.date("%Y-%m-%d")

  local lines = {
    "---",
    string.format("title: %s", title),
    string.format("date: %s", date),
    string.format("id: %s", id),
  }

  -- Inherit tags from source note
  if source_frontmatter.tags then
    table.insert(lines, string.format("tags: %s", source_frontmatter.tags))
  end

  -- Set hubs based on source note's type and title (note: plural "hubs")
  if source_frontmatter.type and source_frontmatter.title then
    local hub = string.format('"%s/%s"', source_frontmatter.type, source_frontmatter.title)
    table.insert(lines, string.format("hubs: %s", hub))
  end

  table.insert(lines, "---")
  table.insert(lines, "")

  return table.concat(lines, "\n")
end

-- Find existing note by title
local function find_note_by_title(title)
  local search_dirs = telekasten.Cfg.search_dirs or { telekasten.Cfg.home }

  for _, dir in ipairs(search_dirs) do
    local expanded_dir = vim.fn.expand(dir)
    -- Use find to search for files containing the slugified title
    local slug = slugify(title)
    local cmd = string.format('find "%s" -type f -name "*%s*.md" 2>/dev/null', expanded_dir, slug)
    local handle = io.popen(cmd)

    if handle then
      local result = handle:read("*a")
      handle:close()

      -- Check each found file
      for filepath in result:gmatch("[^\r\n]+") do
        -- Read the file and check if title matches
        local file = io.open(filepath, "r")
        if file then
          local content = file:read("*all")
          file:close()

          -- Check if the title matches in frontmatter (case-insensitive)
          local title_lower = title:lower()
          if content:match("title:%s*" .. title) or content:lower():match("title:%s*" .. title_lower) then
            return filepath
          end
        end
      end
    end
  end

  return nil
end

-- Main function: Link to existing note or create new one
function M.denote_link_or_create()
  -- Get current buffer's frontmatter (source note)
  local source_frontmatter = parse_frontmatter()

  -- Get link text (word under cursor or selection)
  local link_text = get_link_text()

  if not link_text or link_text == "" then
    vim.notify("No text under cursor or selection", vim.log.levels.WARN)
    return
  end

  -- Search for existing note with this title
  local existing_file = find_note_by_title(link_text)

  if existing_file then
    -- Note exists: extract ID and create Denote-style link
    local file = io.open(existing_file, "r")
    local note_id = nil

    if file then
      local content = file:read("*all")
      file:close()
      -- Extract ID from frontmatter
      note_id = content:match("id:%s*(%S+)")
    end

    if not note_id then
      -- Fallback: extract ID from filename
      note_id = existing_file:match("(%d+T%d+)")
    end

    -- Create Denote-style markdown link: [title](denote:ID)
    local link = string.format("[%s](denote:%s)", link_text, note_id or link_text)

    -- Replace visual selection or word under cursor with link
    local mode = vim.fn.mode()
    if mode == "v" or mode == "V" then
      vim.cmd(string.format('noau normal! gv"_c%s', link))
      vim.cmd('noau normal! l')
    else
      vim.cmd(string.format('noau normal! ciw%s', link))
      vim.cmd('noau normal! l')
    end

    vim.notify(string.format("Linked to existing note: %s", link_text), vim.log.levels.INFO)
  else
    -- Note doesn't exist: create it with inherited properties
    local filename = generate_filename(link_text)
    local home_dir = vim.fn.expand(telekasten.Cfg.home)
    -- Ensure home_dir ends with a slash
    if not home_dir:match("/$") then
      home_dir = home_dir .. "/"
    end
    local filepath = home_dir .. filename

    -- Create frontmatter with inheritance
    local frontmatter = create_frontmatter(link_text, source_frontmatter)

    -- Write the file
    local file = io.open(filepath, "w")
    if file then
      file:write(frontmatter)
      file:close()

      -- Extract the ID we just created
      local note_id = os.date("%Y%m%dT%H%M%S")

      -- Insert Denote-style link in current buffer: [title](denote:ID)
      local link = string.format("[%s](denote:%s)", link_text, note_id)
      local mode = vim.fn.mode()
      if mode == "v" or mode == "V" then
        vim.cmd(string.format('noau normal! gv"_c%s', link))
      else
        vim.cmd(string.format('noau normal! ciw%s', link))
      end

      -- Save current buffer reference
      source_buf = vim.api.nvim_get_current_buf()
      local current_file = vim.api.nvim_buf_get_name(source_buf)
      table.insert(parent_stack, current_file)

      -- Create popup window
      popup_win, popup_buf = create_popup_window(filepath)

      -- Load the file into the buffer
      vim.api.nvim_buf_set_name(popup_buf, filepath)
      vim.cmd("edit!")

      -- Set up Emacs-style keybindings
      -- C-c C-c: Finish (save and close)
      vim.api.nvim_buf_set_keymap(popup_buf, "n", "<C-c><C-c>", "", {
        callback = finish_capture,
        noremap = true,
        silent = true,
        desc = "Finish capture (save and close)",
      })
      vim.api.nvim_buf_set_keymap(popup_buf, "i", "<C-c><C-c>", "", {
        callback = function()
          vim.cmd("stopinsert")
          finish_capture()
        end,
        noremap = true,
        silent = true,
        desc = "Finish capture (save and close)",
      })

      -- C-c C-w: Refile to zettelkasten
      vim.api.nvim_buf_set_keymap(popup_buf, "n", "<C-c><C-w>", "", {
        callback = refile_capture,
        noremap = true,
        silent = true,
        desc = "Refile to zettelkasten",
      })
      vim.api.nvim_buf_set_keymap(popup_buf, "i", "<C-c><C-w>", "", {
        callback = function()
          vim.cmd("stopinsert")
          refile_capture()
        end,
        noremap = true,
        silent = true,
        desc = "Refile to zettelkasten",
      })

      -- C-c C-k: Abort (close without saving)
      vim.api.nvim_buf_set_keymap(popup_buf, "n", "<C-c><C-k>", "", {
        callback = abort_capture,
        noremap = true,
        silent = true,
        desc = "Abort capture (discard changes)",
      })
      vim.api.nvim_buf_set_keymap(popup_buf, "i", "<C-c><C-k>", "", {
        callback = function()
          vim.cmd("stopinsert")
          abort_capture()
        end,
        noremap = true,
        silent = true,
        desc = "Abort capture (discard changes)",
      })

      -- Keep legacy keybindings for convenience
      vim.api.nvim_buf_set_keymap(popup_buf, "n", "<leader>zq", "", {
        callback = finish_capture,
        noremap = true,
        silent = true,
        desc = "Finish capture",
      })

      vim.api.nvim_buf_set_keymap(popup_buf, "n", "<Esc><Esc>", "", {
        callback = finish_capture,
        noremap = true,
        silent = true,
        desc = "Finish capture",
      })

      -- Position cursor at the end of the buffer (in normal mode, not insert)
      vim.schedule(function()
        local line_count = vim.api.nvim_buf_line_count(popup_buf)
        vim.api.nvim_win_set_cursor(popup_win, { line_count, 0 })
      end)

      vim.notify(string.format("✓ Created: %s", filename), vim.log.levels.INFO)
    else
      vim.notify("Failed to create note file", vim.log.levels.ERROR)
    end
  end
end

-- Return to parent note
function M.return_to_parent()
  -- If we're in a popup, just close it
  if popup_win and vim.api.nvim_win_is_valid(popup_win) then
    local current_win = vim.api.nvim_get_current_win()
    if current_win == popup_win then
      -- Save before closing
      if vim.api.nvim_buf_get_option(popup_buf, "modified") then
        vim.cmd("write")
      end
      close_popup()
      vim.notify("Returned to source note", vim.log.levels.INFO)
      return
    end
  end

  -- Otherwise, use the parent stack
  if #parent_stack == 0 then
    vim.notify("No parent note to return to", vim.log.levels.WARN)
    return
  end

  local parent_file = table.remove(parent_stack)

  -- Save current buffer before switching
  if vim.bo.modified then
    vim.cmd("write")
  end

  vim.cmd("edit " .. vim.fn.fnameescape(parent_file))
  vim.notify("Returned to parent note", vim.log.levels.INFO)
end

-- Follow a Denote-style or wiki-style link under cursor (open in capture buffer)
function M.follow_link_in_capture()
  -- Get the link under cursor
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2]

  local note_id = nil
  local link_title = nil
  local filepath = nil

  -- First, try Denote-style link: [text](denote:ID)
  local link_pattern = "%[([^%]]+)%]%(denote:(%w+)%)"

  for title, id in line:gmatch(link_pattern) do
    -- Check if cursor is within this link
    local link_start, link_end = line:find("%[" .. title:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1") .. "%]%(denote:" .. id .. "%)")
    if link_start and link_end and col >= link_start - 1 and col <= link_end then
      note_id = id
      link_title = title
      break
    end
  end

  -- If no Denote-style link found, try wiki-style link: [[title]]
  if not note_id then
    local before = line:sub(1, col + 1)
    local after = line:sub(col + 1)

    local start_pos = before:reverse():find("%[%[")
    local end_pos = after:find("%]%]")

    if start_pos and end_pos then
      local link_start = col + 2 - start_pos
      local link_end = col + end_pos
      link_title = line:sub(link_start, link_end)

      -- Find the note by title
      filepath = find_note_by_title(link_title)

      if not filepath then
        vim.notify("Note not found: " .. link_title, vim.log.levels.WARN)
        return
      end
    end
  end

  if not note_id and not filepath then
    vim.notify("No link under cursor", vim.log.levels.WARN)
    return
  end

  -- Find the note by ID if we have a Denote-style link
  if note_id and not filepath then
    local search_dirs = telekasten.Cfg.search_dirs or { telekasten.Cfg.home }

    for _, dir in ipairs(search_dirs) do
      local expanded_dir = vim.fn.expand(dir)
      -- Search recursively with maxdepth to avoid going too deep
      local cmd = string.format('find "%s" -maxdepth 3 -type f -name "*%s*.md" 2>/dev/null', expanded_dir, note_id)
      local handle = io.popen(cmd)

      if handle then
        local result = handle:read("*l")
        handle:close()
        if result and result ~= "" then
          filepath = result
          break
        end
      end
    end

    if not filepath then
      -- Try a more lenient search - just look for the ID anywhere in the filename
      for _, dir in ipairs(search_dirs) do
        local expanded_dir = vim.fn.expand(dir)
        local cmd = string.format('grep -l "^id: %s" "%s"/*.md 2>/dev/null', note_id, expanded_dir)
        local handle = io.popen(cmd)

        if handle then
          local result = handle:read("*l")
          handle:close()
          if result and result ~= "" then
            filepath = result
            break
          end
        end
      end
    end

    if not filepath then
      vim.notify("Note file not found for ID: " .. note_id, vim.log.levels.WARN)
      return
    end
  end

  -- Save current buffer reference
  source_buf = vim.api.nvim_get_current_buf()

  -- Create capture window
  popup_win, popup_buf = create_popup_window(filepath)

  -- Load the file into the buffer
  vim.api.nvim_buf_set_name(popup_buf, filepath)
  vim.cmd("edit!")

  -- Set up Emacs-style keybindings
  -- C-c C-c: Finish (save and close)
  vim.api.nvim_buf_set_keymap(popup_buf, "n", "<C-c><C-c>", "", {
    callback = finish_capture,
    noremap = true,
    silent = true,
    desc = "Finish capture (save and close)",
  })
  vim.api.nvim_buf_set_keymap(popup_buf, "i", "<C-c><C-c>", "", {
    callback = function()
      vim.cmd("stopinsert")
      finish_capture()
    end,
    noremap = true,
    silent = true,
    desc = "Finish capture (save and close)",
  })

  -- C-c C-w: Refile to zettelkasten
  vim.api.nvim_buf_set_keymap(popup_buf, "n", "<C-c><C-w>", "", {
    callback = refile_capture,
    noremap = true,
    silent = true,
    desc = "Refile to zettelkasten",
  })
  vim.api.nvim_buf_set_keymap(popup_buf, "i", "<C-c><C-w>", "", {
    callback = function()
      vim.cmd("stopinsert")
      refile_capture()
    end,
    noremap = true,
    silent = true,
    desc = "Refile to zettelkasten",
  })

  -- C-c C-k: Abort (close without saving)
  vim.api.nvim_buf_set_keymap(popup_buf, "n", "<C-c><C-k>", "", {
    callback = abort_capture,
    noremap = true,
    silent = true,
    desc = "Abort capture (discard changes)",
  })
  vim.api.nvim_buf_set_keymap(popup_buf, "i", "<C-c><C-k>", "", {
    callback = function()
      vim.cmd("stopinsert")
      abort_capture()
    end,
    noremap = true,
    silent = true,
    desc = "Abort capture (discard changes)",
  })

  -- Keep legacy keybindings
  vim.api.nvim_buf_set_keymap(popup_buf, "n", "<leader>zq", "", {
    callback = finish_capture,
    noremap = true,
    silent = true,
    desc = "Finish capture",
  })

  vim.api.nvim_buf_set_keymap(popup_buf, "n", "<Esc><Esc>", "", {
    callback = finish_capture,
    noremap = true,
    silent = true,
    desc = "Finish capture",
  })

  -- Position cursor at the end (in normal mode)
  vim.schedule(function()
    local line_count = vim.api.nvim_buf_line_count(popup_buf)
    vim.api.nvim_win_set_cursor(popup_win, { line_count, 0 })
  end)

  vim.notify("Opened: " .. (link_title or note_id), vim.log.levels.INFO)
end

return M
