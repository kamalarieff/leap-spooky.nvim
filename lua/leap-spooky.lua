local api = vim.api


local function get_motion_force()
  local force = ""
  local mode = vim.fn.mode(1)
  if mode:sub(2) == 'oV' then force = "V"
  elseif mode:sub(2) == 'o' then force = ""
  end
  return force
end


local function spooky_action(action, kwargs)
  return function (target)
    local on_return = kwargs.on_return
    local keeppos = kwargs.keeppos
    local saved_view = vim.fn.winsaveview()
    -- Handle cross-window operations.
    local source_win = vim.fn.win_getid()
    local cross_window = target.wininfo and target.wininfo.winid ~= source_win
    -- Set an extmark as an anchor, so that we can execute remote delete
    -- commands in the backward direction, and move together with the text.
    local ns = api.nvim_create_namespace("leap-spooky")
    local anchor = api.nvim_buf_set_extmark(0, ns, saved_view.lnum-1, saved_view.col, {})

    -- Jump.
    if cross_window then api.nvim_set_current_win(target.wininfo.winid) end
    api.nvim_win_set_cursor(0, { target.pos[1], target.pos[2]-1 })
    -- Execute :normal action. (Intended usage: select some text object.)
    vim.cmd("normal " .. action())  -- don't use bang - custom text objects should work too
    -- (The operation itself will be executed after exiting.)

    -- Follow-up:
    if keeppos or on_return then
      api.nvim_create_autocmd('ModeChanged', {
        pattern = '*:n',  -- trigger on returning to Normal
        once = true,
        callback = function ()
          if keeppos then
            if cross_window then api.nvim_set_current_win(source_win) end
            vim.fn.winrestview(saved_view)
            local anchorpos = api.nvim_buf_get_extmark_by_id(0, ns, anchor, {})
            api.nvim_win_set_cursor(0, { anchorpos[1]+1, anchorpos[2] })
            api.nvim_buf_clear_namespace(0, ns, 0, -1)  -- remove the anchor
          end
          if on_return then
            vim.cmd("normal " .. on_return)
          end
        end,
      })
    end
  end
end


local default_affixes = {
  remote   = { window = 'r', cross_window = 'R' },
  magnetic = { window = 'm', cross_window = 'M' },
}

local default_text_objects = {
  'iw', 'iW', 'is', 'ip', 'i[', 'i]', 'i(', 'i)', 'ib',
  'i>', 'i<', 'it', 'i{', 'i}', 'iB', 'i"', 'i\'', 'i`',
  'aw', 'aW', 'as', 'ap', 'a[', 'a]', 'a(', 'a)', 'ab',
  'a>', 'a<', 'at', 'a{', 'a}', 'aB', 'a"', 'a\'', 'a`',
}

local function setup(kwargs)
  local kwargs = kwargs or {}
  local affixes = kwargs.affixes
  local yank_paste = kwargs.yank_paste

  local mappings = {}
  for kind, scopes in pairs(affixes or default_affixes) do
    local keeppos = kind == 'remote'
    for scope, key in pairs(scopes) do
      for _, textobj in ipairs(default_text_objects) do
        table.insert(mappings, {
          scope = scope,
          keeppos = keeppos,
          lhs = textobj:sub(1,1) .. key .. textobj:sub(2),
          action = function ()
            return "v" .. vim.v.count1 .. textobj .. get_motion_force()
          end,
        })
      end
      -- Special case: remote lines.
      table.insert(mappings, {
        scope = scope,
        keeppos = keeppos,
        lhs = key .. key,
        action = function ()
          local n_js = vim.v.count1 - 1
          return "V" .. (n_js > 0 and (tostring(n_js) .. "j") or "")
        end,
      })
    end
  end

  for _, mapping in ipairs(mappings) do
    vim.keymap.set('o', mapping.lhs, function ()
      local target_windows = nil
      if mapping.scope == 'window' then
        target_windows = { vim.fn.win_getid() }
      elseif mapping.scope == 'cross_window' then
        target_windows = require'leap.util'.get_enterable_windows()
      end
      local keeppos = mapping.keeppos
      yank_paste = yank_paste and keeppos and vim.v.operator == 'y' and vim.v.register == "\""
      require'leap'.leap {
        action = spooky_action(mapping.action, {
          keeppos = keeppos,
          on_return = yank_paste and "p",
        }),
        target_windows = target_windows,
      }
    end)
  end
end


return {
  spooky_action = spooky_action,
  spookify = setup,
  setup = setup,
}
