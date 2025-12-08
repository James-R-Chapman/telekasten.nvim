-- telekasten/zk_notes.lua
-- Zettelkasten note creation module for Telekaster
-- Handles creating notes with proper Denote-style frontmatter

local M = {}

-- Default configuration
M.config = {
  dirs = {
    inbox = vim.fn.expand("~/orgroam/inbox/"),
    zettelkasten = vim.fn.expand("~/orgroam/zettelkasten/"),
    notes = vim.fn.expand("~/orgroam/notes/"),
    sources = vim.fn.expand("~/orgroam/sources/"),
    templates = vim.fn.expand("~/orgroam/templates/"),
  },
  extension = "md",
  id_format = "%Y%m%dT%H%M%S",
  filename_format = "{id}-{slug}",
}

-- Setup function
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Ensure directories exist
  for _, dir in pairs(M.config.dirs) do
    vim.fn.mkdir(dir, "p")
  end

  -- Load submodules
  M.templates = require("telekasten.zk_templates")
  M.notes = require("telekasten.zk_note_creator")

  -- Pass config to submodules
  M.templates.setup(M.config)
  M.notes.setup(M.config)
end

-- Public API
function M.new_note(opts)
  return M.notes.create_note(opts)
end

function M.new_source_note(opts)
  return M.notes.create_source_note(opts)
end

return M
