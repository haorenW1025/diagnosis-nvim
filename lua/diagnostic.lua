local vim = vim
local util = require 'diagnostic.util'
local M = {}

-- TODO change this to use vim.lsp.util.diagnostics_by_buf
local diagnosticTable = {}


local remove_diagnostics = function(diagnostics)
  -- Remove Index
  local remove = {}
  local level = vim.lsp.protocol.DiagnosticSeverity[vim.api.nvim_get_var('diagnostic_level')]
  for idx, diagnostic in ipairs(diagnostics) do
    if diagnostic.severity > level then
      remove[idx] = true
    else
      remove[idx] = false
    end
  end
  for i = #diagnostics, 1, -1 do
    if remove[i] then
      table.remove(diagnostics, i)
    end
  end
  return diagnostics
end

local get_diagnostics_count = function(diagnostics, bufnr)
  diagnosticTable.bufnr = {0, 0, 0, 0}
  for idx, diagnostic in pairs(diagnostics) do
    diagnosticTable.bufnr[diagnostic.severity] = diagnosticTable.bufnr[diagnostic.severity] + 1
  end
end

function M.modifyCallback()
  local callback = 'textDocument/publishDiagnostics'
  vim.lsp.callbacks[callback] = function(_, _, result, _)
    if not result then
      return
    end
    uri = result.uri
    local bufnr = vim.uri_to_bufnr(uri)
    if not bufnr then
      vim.lsp.err_message("LSP.publishDiagnostics: Couldn't find buffer for ", uri)
      return
    end
    if vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win()) ~= bufnr then
      return
    end
    get_diagnostics_count(result.diagnostics, bufnr)
    if vim.api.nvim_get_var('diagnostic_level') ~= nil then
      result.diagnostics = remove_diagnostics(result.diagnostics)
    end
    vim.lsp.util.buf_clear_diagnostics(bufnr)
    vim.lsp.util.buf_diagnostics_save_positions(bufnr, result.diagnostics)
    if vim.api.nvim_get_var('diagnostic_insert_delay') == 1 then
      if vim.api.nvim_get_mode()['mode'] == "i" or vim.api.nvim_get_mode()['mode'] == "ic" then
        return
      end
    end

    M.publish_diagnostics(bufnr)
  end
end

function M.diagnostics_loclist(local_result)
  if local_result then
    for _, v in ipairs(local_result) do
      v.uri = v.uri or uri
    end
  end
  if #vim.fn.getloclist(vim.fn.winnr()) == 0 then
    vim.lsp.util.set_loclist(util.locations_to_items(local_result))
  end
end

function M.publish_diagnostics(bufnr)
  if vim.fn.getcmdwintype() == ':' then return end
  if #vim.lsp.buf_get_clients() == 0 then return end
  local diagnostics = vim.lsp.util.diagnostics_by_buf[bufnr]
  if diagnostics == nil then return end
  util.align_diagnostic_indices(diagnostics)
  if vim.api.nvim_get_var('diagnostic_enable_underline') == 1 then
    vim.lsp.util.buf_diagnostics_underline(bufnr, diagnostics)
  end
  if vim.api.nvim_get_var('diagnostic_show_sign') == 1 then
    util.buf_diagnostics_signs(bufnr, diagnostics)
  end
  if vim.api.nvim_get_var('diagnostic_enable_virtual_text') == 1 then
    util.buf_diagnostics_virtual_text(bufnr, diagnostics)
  end
  local title = vim.fn.getloclist(vim.fn.winnr(), {title= 1})['title']
  if title == "Language Server" or string.len(title) == 0 then
    vim.fn.setloclist(0, {}, 'r')
    M.diagnostics_loclist(diagnostics)
  end
  M.trigger_diagnostics_changed()
end

M.trigger_diagnostics_changed = vim.schedule_wrap(function()
    vim.api.nvim_command("doautocmd User LspDiagnosticsChanged")
end)

function M.refresh_diagnostics()
  local bufnr = vim.api.nvim_win_get_buf(0)
  M.publish_diagnostics(bufnr)
end

function M.on_BufEnter()
  vim.schedule(function()
    M.refresh_diagnostics()
  end)
end

function M.on_InsertLeave()
  M.refresh_diagnostics()
end

function M.getDiagnosticCount(level, bufnr)
  if diagnosticTable.bufnr == nil then
    return 0
  end
  return diagnosticTable.bufnr[level]
end


local warned = false
M.on_attach = function(_, _)
  if not warned and vim.lsp.diagnostic then
    warned = true
    vim.api.nvim_err_write([['vim.lsp.diagnostic' is now builtin. 'nvim-lua/diagnostic-nvim' is now deprecated.
To migrate from 'nvim-lua/diagnostic-nvim' to builtin,
  See: https://github.com/nvim-lua/diagnostic-nvim/issues/73
For more information about new features,
  See: https://github.com/neovim/neovim/pull/12655
]])
  end

  -- Setup autocmd
  M.modifyCallback()
  vim.api.nvim_command [[augroup DiagnosticRefresh]]
    vim.api.nvim_command("autocmd! * <buffer>")
    vim.api.nvim_command [[autocmd BufEnter,BufWinEnter,TabEnter <buffer> lua require'diagnostic'.on_BufEnter()]]
  vim.api.nvim_command [[augroup end]]

  if vim.api.nvim_get_var('diagnostic_insert_delay') == 1 then
    vim.api.nvim_command [[augroup DiagnosticInsertDelay]]
      vim.api.nvim_command("autocmd! * <buffer>")
      vim.api.nvim_command [[autocmd InsertLeave <buffer> lua require'diagnostic'.on_InsertLeave()]]
    vim.api.nvim_command [[augroup end]]
  end
end

return M
