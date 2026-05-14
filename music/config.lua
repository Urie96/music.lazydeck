local M = {}

local cfg = {
  keymap = {
    -- browser actions
    play_now = '<enter>',
    append_to_player = 'a',
    append_playlist_to_player = 'A',
    add_to_playlist = 'A',
    toggle_liked = 'l',
    toggle_star = 'l',
    search = 's',
    new = 'n',
    delete = 'dd',

    -- player controls
    toggle_pause = 'p',
    next = 'n',
    prev = 'N',
    volume_up = '+',
    volume_down = '-',
  },
}

function M.setup(opt)
  local global_keymap = deck.config.get().keymap or {}
  cfg = deck.tbl_deep_extend('force', cfg, { keymap = global_keymap }, opt or {})
end

function M.get() return cfg end

return M
