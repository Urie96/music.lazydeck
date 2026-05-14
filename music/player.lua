local M = {}

local tmpdir = os.getenv 'TMPDIR' or '/tmp'
local default_socket = tmpdir .. '/lazydeck-mpv.sock'

local cfg = {
  socket = default_socket,
  mpv_args = {
    '--idle=yes',
    '--no-video',
    '--force-window=no',
    '--audio-display=no',
    '--really-quiet',
  },
  keymap = {
    toggle_pause = 'p',
    next = 'n',
    prev = 'N',
    delete = 'dd',
    volume_up = '+',
    volume_down = '-',
  },
}

local state = {
  mpv_starting = false,
  mpv_pid = nil,
  mpv_waiters = {},
  queue_meta = {},
  sock = nil,
  sock_path = nil,
  next_request_id = 0,
  pending_requests = {},
  player_event_cb = nil,
  player_observing = false,
  runtime_setup = false,
  setup_called = false,
  reload_pending = false,
  follow_current_on_reload = false,
  http_resolver_name = 'music-track',
  next_http_track_id = 0,
}

local socket_send
local MPV_SOCKET_NOT_READY = 'mpv socket not ready yet'

local function dim(s) return deck.style.span(tostring(s or '')):fg 'blue' end
local function warm(s) return deck.style.span(tostring(s or '')):fg 'yellow' end
local function okc(s) return deck.style.span(tostring(s or '')):fg 'green' end
local function titlec(s) return deck.style.span(tostring(s or '')):fg 'white' end

local function volume_bottom_line()
  local vol = state.volume
  if type(vol) ~= 'number' then return nil end
  local color = 'cyan'
  return deck.style.line {
    (''):fg(color),
    string.format('  %.0f%% ', vol):fg('white'):bg(color),
    (''):fg(color),
  }
end

local function current_cfg() return cfg end
local function resolved_true() return true end
local function current_http_resolver_name() return state.http_resolver_name end

local function set_mpv_pid(pid, reason, detail)
  local prev = state.mpv_pid
  state.mpv_pid = pid

  if prev == pid then return end

  deck.log(
    'info',
    'mpv_pid {} -> {}: {}{}',
    tostring(prev),
    tostring(pid),
    tostring(reason or 'unknown'),
    detail and ('; ' .. tostring(detail)) or ''
  )
end

local function current_path_is_music()
  local path = deck.api.get_current_path() or {}
  return path[1] == 'music' or path[2] == 'playing'
end

local function notify_error(err)
  deck.notify(deck.style.line {
    deck.style.span('mpv: '):fg 'red',
    deck.style.span(tostring(err)):fg 'red',
  })
end

local function respond_local_track(request, respond)
  if tostring(request.method or 'GET'):upper() ~= 'GET' then
    respond {
      status = 405,
      body = 'method not allowed',
    }
    return
  end

  local local_id = tostring((request.params or {}).id or ''):match '^%s*(.-)%s*$'
  if local_id == '' then
    respond {
      status = 400,
      body = 'missing track id',
    }
    return
  end

  local track = state.queue_meta[local_id]
  if not track then
    respond {
      status = 404,
      body = 'track not found',
    }
    return
  end

  if type(track.get_play_url) ~= 'function' then
    respond {
      status = 500,
      body = 'track resolver missing',
    }
    return
  end

  track.get_play_url(track, function(url, err)
    if err then
      respond {
        status = 502,
        body = tostring(err),
      }
      return
    end

    local resolved = tostring(url or ''):match '^%s*(.-)%s*$'
    if resolved == '' then
      respond {
        status = 404,
        body = 'track url not found',
      }
      return
    end

    track.resolved_url = resolved
    respond {
      status = 307,
      headers = {
        Location = resolved,
        ['Cache-Control'] = 'no-store',
      },
    }
  end)
end

local function ensure_http_resolver_registered()
  deck.http_server.register_resolver(current_http_resolver_name(), respond_local_track)
end

local function next_local_track_id()
  state.next_http_track_id = state.next_http_track_id + 1
  return tostring(state.next_http_track_id)
end

local function build_local_track_url(local_id)
  return deck.http_server.url(current_http_resolver_name(), { id = tostring(local_id) })
end

local function schedule_reload()
  if state.reload_pending then return end
  state.reload_pending = true
  deck.defer_fn(function()
    state.reload_pending = false
    if current_path_is_music() then deck.cmd 'reload' end
  end, 50)
end

local function request_follow_current_on_reload()
  if current_path_is_music() then state.follow_current_on_reload = true end
end

local function setup_runtime()
  if state.runtime_setup then return end
  state.runtime_setup = true
  ensure_http_resolver_registered()

  M.on_player_event(function(event)
    if not event then return end

    if event.event == 'shutdown' then
      schedule_reload()
      return
    end

    if event.event ~= 'property-change' then return end
    local name = tostring(event.name or '')
    if name == 'playlist-pos' then request_follow_current_on_reload() end
    if name == 'volume' then state.volume = event.data end
    if name == 'pause' or name == 'playlist' or name == 'playlist-pos' or name == 'idle-active' then
      schedule_reload()
    end
  end)

  deck.hook.pre_quit(function()
    local ok, err = M.quit_sync()
    if not ok and err then deck.log('warn', 'failed to quit mpv: {}', err) end
  end)
end

local function ensure_setup_called()
  if state.setup_called then return end
  error 'music.setup() must be called before using the music module'
end

local function ensure_ready() ensure_setup_called() end

local function socket_exists() return deck.fs.stat(current_cfg().socket).exists end

local function finish_waiters(ok, err)
  local waiters = state.mpv_waiters
  state.mpv_waiters = {}
  state.mpv_starting = false
  if not ok then set_mpv_pid(nil, 'finish_waiters failed', err) end
  for _, waiter in ipairs(waiters) do
    if ok then
      waiter.resolve(true)
    else
      waiter.reject(err)
    end
  end
end

local function wrap_once(cb)
  local done = false
  return function(...)
    if done then return end
    done = true
    cb(...)
  end
end

local function fail_pending_requests(err)
  local pending = state.pending_requests
  state.pending_requests = {}
  for _, cb in pairs(pending) do
    cb(nil, err or 'mpv socket closed')
  end
end

local function close_socket(err)
  local sock = state.sock
  state.sock = nil
  state.sock_path = nil
  state.player_observing = false
  if sock then pcall(function() sock:close() end) end
  fail_pending_requests(err)
end

local function response_or_error(response)
  if response.error and response.error ~= 'success' then return Promise.reject(response.error) end

  return response
end

local function with_notify(p)
  return p:catch(function(err) notify_error(err) end)
end

local function hydrate_playlist_meta(playlist)
  for _, item in ipairs(playlist or {}) do
    local meta = state.queue_meta[item.filename or ''] or state.queue_meta[tostring(item.id or '')]
    if meta then item._meta = meta end
  end
  return playlist
end

local function build_player_state(playlist_resp, pause_resp, volume_resp)
  local playlist = hydrate_playlist_meta(playlist_resp.data or {})
  if type((volume_resp or {}).data) == 'number' then state.volume = volume_resp.data end
  return {
    running = true,
    pause = pause_resp.data == true,
    playlist = playlist,
  }
end

local function emit_player_event(event)
  if state.player_event_cb then state.player_event_cb(event) end
end

local function handle_socket_line(line)
  local ok, decoded = pcall(deck.json.decode, line or '')
  if not ok or type(decoded) ~= 'table' then return end

  if decoded.event then
    if decoded.event == 'property-change' then emit_player_event(decoded) end
    if decoded.event == 'shutdown' then
      set_mpv_pid(nil, 'mpv shutdown event')
      emit_player_event(decoded)
      close_socket 'mpv socket closed'
    end
    return
  end

  local request_id = decoded.request_id
  if request_id == nil then return end

  local cb = state.pending_requests[request_id]
  state.pending_requests[request_id] = nil
  if cb then cb(decoded) end
end

local function ensure_socket()
  local current = current_cfg()
  if state.sock and state.sock_path == current.socket then return state.sock end

  if state.sock then close_socket 'mpv socket reset' end

  local sock = deck.socket.connect('unix:' .. current.socket)
  sock:on_line(function(line) handle_socket_line(line) end)
  state.sock = sock
  state.sock_path = current.socket
  return sock
end

local function ensure_player_observers()
  if state.player_observing then return end
  state.player_observing = true

  socket_send { command = { 'observe_property', 1, 'pause' } }
  socket_send { command = { 'observe_property', 2, 'playlist' } }
  socket_send { command = { 'observe_property', 3, 'playlist-pos' } }
  socket_send { command = { 'observe_property', 4, 'idle-active' } }
  socket_send { command = { 'observe_property', 5, 'volume' } }
end

socket_send = function(payload, cb)
  if not socket_exists() then
    if cb then cb(nil, 'mpv not running') end
    return
  end

  local sock
  local ok, result = pcall(ensure_socket)
  if ok then
    sock = result
  else
    close_socket(result)
    if cb then cb(nil, tostring(result)) end
    return
  end

  if cb then cb = wrap_once(cb) end

  local request_id = state.next_request_id + 1
  state.next_request_id = request_id
  payload.request_id = request_id

  if cb then state.pending_requests[request_id] = cb end

  local write_ok, write_err = pcall(function() sock:write(deck.json.encode(payload)) end)
  if write_ok then return end

  state.pending_requests[request_id] = nil
  close_socket(write_err)
  if cb then cb(nil, tostring(write_err)) end
end

local function socket_send_p(payload)
  return Promise.new(function(resolve, reject)
    socket_send(payload, function(response, err)
      if err or not response then
        reject(err)
        return
      end
      resolve(response)
    end)
  end)
end

local function mpv_request_no_spawn_p(command)
  if not socket_exists() then
    if state.mpv_starting then
      deck.log(
        'info',
        'mpv socket not ready yet while starting: {}; pid={}',
        table.concat(command or {}, ' '),
        tostring(state.mpv_pid)
      )
      return Promise.reject(MPV_SOCKET_NOT_READY)
    else
      set_mpv_pid(nil, 'socket missing before request', table.concat(command or {}, ' '))
      close_socket 'mpv not running'
      return Promise.reject 'mpv not running'
    end
    close_socket 'mpv not running'
  end

  ensure_player_observers()

  return socket_send_p({ command = command }):next(response_or_error)
end

function M.on_player_event(cb) state.player_event_cb = cb end

local function probe_mpv_p()
  return mpv_request_no_spawn_p({ 'get_property', 'pause' }):next(resolved_true):catch(function(err)
    if err == MPV_SOCKET_NOT_READY and state.mpv_starting then return Promise.reject(err) end

    local current = current_cfg()
    set_mpv_pid(nil, 'probe_mpv failed', err)
    close_socket(err)
    if socket_exists() then deck.fs.remove(current.socket) end
    return Promise.reject(err)
  end)
end

local function wait_for_socket(attempt)
  if attempt > 40 then
    finish_waiters(nil, 'mpv socket did not become ready')
    return
  end

  probe_mpv_p():next(function()
    if state.mpv_starting then finish_waiters(true) end
  end, function()
    deck.defer_fn(function() wait_for_socket(attempt + 1) end, 100)
  end)
end

local function ensure_mpv_p()
  ensure_ready()

  if not deck.system.executable 'mpv' then return Promise.reject 'mpv not found in PATH' end

  return probe_mpv_p():catch(function(err)
    local waiter_p = Promise.new(function(resolve, reject)
      table.insert(state.mpv_waiters, { resolve = resolve, reject = reject })
      if state.mpv_starting then return end

      state.mpv_starting = true
      local current = current_cfg()
      close_socket 'mpv restarting'
      if socket_exists() then deck.fs.remove(current.socket) end

      local cmd = { 'mpv' }
      for _, arg in ipairs(current.mpv_args or {}) do
        table.insert(cmd, arg)
      end
      table.insert(cmd, '--input-ipc-server=' .. current.socket)
      local pid = deck.system.spawn(cmd)
      set_mpv_pid(pid ~= 0 and pid or nil, 'spawned mpv', table.concat(cmd, ' '))
      wait_for_socket(1)
    end)

    if err == MPV_SOCKET_NOT_READY and state.mpv_starting then return waiter_p end

    return waiter_p
  end)
end

local function mpv_request_p(command)
  return ensure_mpv_p():next(function() return mpv_request_no_spawn_p(command) end)
end

local function normalize_track(track)
  if type(track) ~= 'table' then return nil, 'track must be a table' end

  local normalized = {}
  for key, value in pairs(track) do
    normalized[key] = value
  end

  local url = track.url or track.filename
  if (type(url) ~= 'string' or url == '') and type(track.get_play_url) ~= 'function' then
    return nil, 'track.url or track.get_play_url is required'
  end

  if type(track.get_play_url) == 'function' and (type(url) ~= 'string' or url == '') then
    normalized.local_id = next_local_track_id()
    normalized.url = build_local_track_url(normalized.local_id)
  else
    normalized.url = url
  end

  normalized.key = track.key or track.id or normalized.url
  normalized.id = track.id
  normalized.title = track.title or track.name

  return normalized
end

local function load_tracks_step(normalized, replace, index)
  if index > #normalized then return mpv_request_no_spawn_p({ 'set_property', 'pause', false }):next(resolved_true) end

  local track = normalized[index]
  state.queue_meta[track.url] = track
  if track.local_id then state.queue_meta[track.local_id] = track end
  local mode = (replace and index == 1) and 'replace' or 'append-play'

  return mpv_request_no_spawn_p({ 'loadfile', track.url, mode }):next(
    function() return load_tracks_step(normalized, replace, index + 1) end
  )
end

local function queue_tracks_p(tracks, replace)
  if not tracks or #tracks == 0 then return Promise.resolve(true) end

  local normalized = {}
  for _, track in ipairs(tracks) do
    local item, err = normalize_track(track)
    if not item then return Promise.reject(err) end
    table.insert(normalized, item)
  end

  return ensure_mpv_p():next(function() return load_tracks_step(normalized, replace, 1) end)
end

local function default_track_display(item, player, meta)
  local current = item.current or item.playing
  local marker = dim '  '
  if current then marker = (player.pause == true) and warm '⏸ ' or okc '▶ ' end

  return deck.style.line {
    marker,
    titlec(item.title or item.filename or meta.url or ('#' .. tostring(item.id or '?'))),
  }
end

local function jump_to_entry()
  local target = deck.api.get_hovered()
  if not target or target.playlist_index == nil then return false end

  with_notify(M.player_jump(target.playlist_index))

  return true
end

local function toggle_pause()
  with_notify(M.player_toggle_pause())

  return true
end

local function play_next()
  with_notify(M.player_next())

  return true
end

local function play_prev()
  with_notify(M.player_prev())

  return true
end

local function remove_entry()
  local target = deck.api.get_hovered()
  if not target or target.playlist_index == nil then return false end

  with_notify(M.player_remove(target.playlist_index))

  return true
end

local function adjust_volume(delta)
  M.player_adjust_volume(delta)
    :next(function(volume)
      if type(volume) == 'number' then
        deck.notify(deck.style.line {
          deck.style.span('mpv: '):fg 'cyan',
          deck.style.span(string.format('Volume %.0f%%', volume)):fg 'white',
        })
      end
    end)
    :catch(function(err) notify_error(err) end)

  return true
end

local function base_track_keymap()
  local keymap = current_cfg().keymap or {}
  local enter = keymap.enter or keymap.play_now or '<enter>'
  return {
    [enter] = { callback = jump_to_entry, desc = 'jump to this song' },
    [keymap.toggle_pause or 'p'] = { callback = toggle_pause, desc = 'pause or resume player' },
    [keymap.next or 'n'] = { callback = play_next, desc = 'next song' },
    [keymap.prev or 'N'] = { callback = play_prev, desc = 'previous song' },
    [keymap.delete or 'dd'] = { callback = remove_entry, desc = 'remove from queue' },
    [keymap.volume_up or '+'] = { callback = function() return adjust_volume(5) end, desc = 'volume up' },
    [keymap.volume_down or '-'] = { callback = function() return adjust_volume(-5) end, desc = 'volume down' },
  }
end

local function control_only_keymap()
  local keymap = base_track_keymap()
  local current = current_cfg().keymap or {}
  keymap[current.enter or current.play_now or '<enter>'] = nil
  return keymap
end

local function merge_keymap(extra)
  local merged = base_track_keymap()
  for key, value in pairs(extra or {}) do
    merged[key] = value
  end
  return merged
end

function M.setup(opt)
  local global_keymap = deck.config.get().keymap or {}
  cfg = deck.tbl_deep_extend('force', cfg, { keymap = global_keymap }, opt or {})
  state.http_resolver_name = 'music-track-' .. tostring(cfg.socket or default_socket):gsub('[^%w]+', '-')
  state.setup_called = true
  setup_runtime()
end

function M.play_tracks(tracks)
  ensure_ready()
  return queue_tracks_p(tracks, true)
end

function M.append_tracks(tracks)
  ensure_ready()
  return queue_tracks_p(tracks, false)
end

function M.update_track_fields(id, fields)
  ensure_ready()
  for _, meta in pairs(state.queue_meta) do
    if tostring(meta.id) == tostring(id) then
      for key, value in pairs(fields or {}) do
        meta[key] = value
      end
    end
  end
end

function M.player_next()
  ensure_ready()
  return mpv_request_p { 'playlist-next', 'force' }
end

function M.player_prev()
  ensure_ready()
  return mpv_request_p { 'playlist-prev', 'force' }
end

function M.player_toggle_pause()
  ensure_ready()
  return mpv_request_p { 'cycle', 'pause' }
end

function M.player_play()
  ensure_ready()
  return mpv_request_p { 'set_property', 'pause', false }
end

function M.player_adjust_volume(delta)
  ensure_ready()
  return mpv_request_p({ 'add', 'volume', delta }):next(function()
    return mpv_request_no_spawn_p({ 'get_property', 'volume' })
      :next(function(response) return response and response.data or true end)
      :catch(function() return true end)
  end)
end

function M.player_jump(index)
  ensure_ready()
  return mpv_request_p({ 'set_property', 'playlist-pos', index }):next(function() return M.player_play() end)
end

function M.player_remove(index)
  ensure_ready()
  return mpv_request_p { 'playlist-remove', index }
end

function M.quit_sync()
  deck.log('info', 'quitting mpv: {}', tostring(state.mpv_pid))
  if not state.mpv_pid then return true end
  local ok, err = pcall(deck.system.kill, state.mpv_pid)
  if not ok then return nil, tostring(err) end

  set_mpv_pid(nil, 'quit_sync killed process')
  close_socket 'mpv socket closed'
  return true
end

local function get_player_state_p()
  ensure_ready()

  return probe_mpv_p()
    :next(function()
      return mpv_request_no_spawn_p({ 'get_property', 'playlist' }):next(function(playlist_resp)
        return mpv_request_no_spawn_p({ 'get_property', 'pause' }):next(function(pause_resp)
          return mpv_request_no_spawn_p({ 'get_property', 'volume' }):next(
            function(volume_resp) return build_player_state(playlist_resp, pause_resp, volume_resp) end
          )
        end)
      end)
    end)
    :catch(
      function()
        return {
          running = false,
          pause = true,
          playlist = {},
        }
      end
    )
end

function M.get_player_state() return get_player_state_p() end

function M.list(path, cb)
  ensure_ready()

  if #path > 1 then
    cb {}
    return
  end

  M.get_player_state()
    :next(function(player)
      local entries = {}
      for index, item in ipairs(player.playlist or {}) do
        local meta = item._meta or {}
        item._player = player

        local entry = {
          key = tostring(meta.key or index - 1),
          player = player,
          player_item = item,
          mpv_meta = meta,
          playlist_index = index - 1,
          display = type(meta.display) == 'function' and meta.display(item, player, meta)
            or meta.display
            or default_track_display(item, player, meta),
          bottom_line = volume_bottom_line,
          keymap = merge_keymap(meta.keymap),
        }

        if type(meta.preview) == 'function' then
          entry.preview = function(self, preview_cb)
            local preview = meta.preview(self, preview_cb)
            if preview then preview_cb(preview) end
          end
        end

        table.insert(entries, entry)
      end

      if #entries == 0 then
        entries = {
          {
            key = 'empty',
            kind = 'info',
            keymap = control_only_keymap(),
            player = player,
            mpv_meta = {},
            display = deck.style.line {
              dim(player.running and 'mpv queue is empty' or 'mpv is not running'),
            },
          },
        }
      end

      cb(entries)
    end)
    :catch(function(err) cb(nil, err) end)
end

function M.preview(entry, cb) cb '' end

return M
