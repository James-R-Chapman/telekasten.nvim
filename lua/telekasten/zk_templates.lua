-- telekasten/zk_templates.lua
-- Template rendering for zettelkasten notes

local M = {}
local config = {}

function M.setup(cfg)
  config = cfg
end

-- Generate Denote-style ID (YYYYMMDDTHHMMSS)
local function generate_id()
  return os.date(config.id_format or "%Y%m%dT%H%M%S")
end

-- Create a slug from title
local function slugify(title)
  return title:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
end

-- Render template with variables
local function render_template(template_content, vars)
  local result = template_content
  for key, value in pairs(vars) do
    result = result:gsub("{{" .. key .. "}}", value)
  end
  return result
end

-- Create frontmatter for regular note
function M.create_note_frontmatter(title)
  local id = generate_id()
  local date = os.date("%Y-%m-%d")

  local frontmatter = string.format([[---
title: %s
date: %s
id: %s
tags:
hubs:
---

]], title, date, id)

  return frontmatter, id
end

-- Create frontmatter for source note
function M.create_source_frontmatter(title, note_type, url)
  local id = generate_id()
  local date = os.date("%Y-%m-%d")

  local frontmatter = string.format([[---
title: %s
date: %s
id: %s
type: %s
tags:
url: %s
---

]], title, date, id, note_type or "article", url or "")

  return frontmatter, id
end

-- Read template file
function M.read_template(template_name)
  local template_path = config.dirs.templates .. template_name
  if vim.fn.filereadable(template_path) == 1 then
    local lines = vim.fn.readfile(template_path)
    return table.concat(lines, "\n")
  end
  return nil
end

return M
