local async = require("diffview.async")
local Window = require("diffview.scene.window").Window
local Diff2 = require("diffview.scene.layouts.diff_2").Diff2
local oop = require("diffview.oop")
local utils = require("diffview.utils")

local api = vim.api
local await = async.await

local M = {}

---@class DiffUnified : Diff2
---@field a Window
---@field b Window
---@field hidden_win integer|nil
local DiffUnified = oop.create_class("DiffUnified", Diff2)

DiffUnified.name = "diff_unified"

---@class DiffUnified.init.Opt
---@field a vcs.File
---@field b vcs.File
---@field winid_a integer
---@field winid_b integer

---@param opt DiffUnified.init.Opt
function DiffUnified:init(opt)
  self:super(opt)
end

---@override
---@param self DiffUnified
---@param pivot integer?
DiffUnified.create = async.void(function(self, pivot)
  self:create_pre()
  local a_win, b_win

  pivot = pivot or self:find_pivot()
  assert(api.nvim_win_is_valid(pivot), "Layout creation requires a valid window pivot!")

  for _, win in ipairs(self.windows) do
    if win.id ~= pivot then
      win:close(true)
    end
  end

  -- Create both windows - one visible and one hidden
  api.nvim_win_call(pivot, function()
    -- Create window 'a' as a hidden window using floating window
    local buf = api.nvim_create_buf(false, true)
    -- Create the window off-screen with minimal size
    local opts = {
      relative = 'editor',
      width = 1,
      height = 1,
      row = -999, -- Position it off-screen
      col = -999,
      style = 'minimal',
    }
    a_win = api.nvim_open_win(buf, true, opts)
    
    if self.a then
      self.a:set_id(a_win)
    else
      self.a = Window({ id = a_win })
    end
    
    -- Now create the visible window that user will see
    vim.cmd("new") -- Create the visible window for 'b'
    b_win = api.nvim_get_current_win()
    
    if self.b then
      self.b:set_id(b_win)
    else
      self.b = Window({ id = b_win })
    end
  end)

  api.nvim_win_close(pivot, true)
  self.windows = { self.a, self.b } -- Both windows needed for diff machinery
  self.hidden_win = a_win  -- Track the hidden window
  
  await(self:create_post())
end)

---@override
---@param entry FileEntry
DiffUnified.use_entry = async.void(function(self, entry)
  local layout = entry.layout --[[@as DiffUnified ]]
  assert(layout:instanceof(DiffUnified))

  -- Set both files to make diffview work properly
  self:set_file_a(layout.a.file)
  self:set_file_b(layout.b.file)

  if self:is_valid() then
    await(self:open_files())
  end
end)

---@override
---@param self DiffUnified
DiffUnified.open_files = async.void(function(self)
  -- Call the parent's open_files to set up both buffers with proper diff mode
  await(Diff2.open_files(self))
  
  -- Make sure the floating window stays hidden
  if self.hidden_win and api.nvim_win_is_valid(self.hidden_win) then
    -- Keep the window off-screen
    api.nvim_win_set_config(self.hidden_win, {
      relative = 'editor',
      row = -999,
      col = -999,
      width = 1,
      height = 1,
    })
    
    -- We don't need to force focus on the visible window
    -- This was causing issues with terminal floats like lazygit
  end
end)

---@override
function DiffUnified:destroy()
  -- Clean up the hidden window if it exists
  if self.hidden_win and api.nvim_win_is_valid(self.hidden_win) then
    pcall(api.nvim_win_close, self.hidden_win, true)
  end
  
  -- Call the parent's destroy method
  Diff2.destroy(self)
end

M.DiffUnified = DiffUnified
return M