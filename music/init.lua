local Browser = require 'music.browser'
local config = require 'music.config'
local player = require 'music.player'

local M = {}

function M.meta()
  return {
    icon = '󰝚',
    desc = 'Music player and library browser',
    color = 'magenta',
  }
end

local default_browser = nil

function M.setup(opt)
  config.setup(opt or {})
  player.setup(opt or {})
end

function M.new(provider, opt)
  opt = deck.tbl_deep_extend('force', { keymap = config.get().keymap }, opt or {})
  return Browser.new(provider, opt)
end

function M.list(path, cb)
  -- /music is the player queue page. Provider browsers live under their own roots.
  return player.list(path, cb)
end

function M.preview(entry, cb)
  return player.preview(entry, cb)
end

function M.play_tracks(tracks) return player.play_tracks(tracks) end
function M.append_tracks(tracks) return player.append_tracks(tracks) end
function M.update_track_fields(id, fields) return player.update_track_fields(id, fields) end
function M.get_player_state() return player.get_player_state() end
function M.player_next() return player.player_next() end
function M.player_prev() return player.player_prev() end
function M.player_toggle_pause() return player.player_toggle_pause() end
function M.player_play() return player.player_play() end
function M.player_adjust_volume(delta) return player.player_adjust_volume(delta) end
function M.player_jump(index) return player.player_jump(index) end
function M.player_remove(index) return player.player_remove(index) end
function M.quit_sync() return player.quit_sync() end
function M.on_player_event(cb) return player.on_player_event(cb) end

return M
