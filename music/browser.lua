local player = require 'music.player'
local preview = require 'music.preview'
local style = require 'music.style'

local M = {}

local SECTION_SPECS = {
  { key = 'playing', title = 'Now Playing', icon = '', always = true },
  { key = 'playlist', title = 'Playlists', icon = '󰲹', required = { 'get_playlists', 'get_playlist_tracks' } },
  { key = 'artist', title = 'Artists', icon = '󰎂', required = { 'get_artists', 'get_artist_albums' } },
  { key = 'album', title = 'Albums', icon = '󰀥', required = { 'get_albums', 'get_album_tracks' } },
  {
    key = 'recommend',
    title = 'Recommendations',
    icon = '󰑓',
    any = { 'get_recommend_playlists', 'get_recommend_tracks' },
  },
  { key = 'liked', title = 'Liked', icon = '', required = { 'get_liked_tracks' } },
  { key = 'search', title = 'Search', icon = '󰍉', required = { 'search' } },
}

local SEARCH_KINDS = {
  { key = 'track', field = 'tracks', title = 'Tracks' },
  { key = 'album', field = 'albums', title = 'Albums' },
  { key = 'artist', field = 'artists', title = 'Artists' },
  { key = 'playlist', field = 'playlists', title = 'Playlists' },
}

local function has_fn(provider, name) return type(provider and provider[name]) == 'function' end

local function supports(provider, spec)
  if spec.always then return true end
  for _, name in ipairs(spec.required or {}) do
    if not has_fn(provider, name) then return false end
  end
  if spec.any then
    for _, name in ipairs(spec.any) do
      if has_fn(provider, name) then return true end
    end
    return false
  end
  return true
end

local function line(parts) return deck.style.line(parts) end

local function item_key(item, fallback) return tostring(item and item.id or item and item.key or fallback or '') end

function M.new(provider, opt)
  assert(type(provider) == 'table', 'music provider is required')
  assert(provider.name, 'music provider.name is required')
  assert(provider.title, 'music provider.title is required')
  assert(type(provider.get_play_url) == 'function', 'music provider.get_play_url is required')

  local self = {
    provider = provider,
    root = (opt and opt.root) or provider.name,
    opt = opt or {},
  }
  setmetatable(self, { __index = M })
  return self
end

function M:section_entry(spec)
  return {
    key = spec.key,
    kind = 'section',
    display = line { style.accent(spec.icon or ''), style.dim '  ', style.titlec(spec.title) },
    preview = function(_, cb)
      cb(style.preview_lines {
        deck.style.line { style.titlec(spec.title) },
        '',
        deck.style.line { style.dim('Provider: ' .. tostring(self.provider.title)) },
      })
    end,
  }
end

function M:extra_section_entry(section)
  return {
    key = section.key,
    kind = 'extra_section',
    display = line { style.warm(section.icon or ''), style.dim '  ', style.titlec(section.title or section.key) },
    preview = function(_, cb)
      cb(style.preview_lines {
        deck.style.line { style.titlec(section.title or section.key) },
        '',
        deck.style.line { style.dim(section.description or '') },
      })
    end,
  }
end

function M:root_entries()
  local entries = {}
  for _, spec in ipairs(SECTION_SPECS) do
    if supports(self.provider, spec) then table.insert(entries, self:section_entry(spec)) end
  end
  for _, section in ipairs(self.provider.extra_sections or {}) do
    if section.key and type(section.list) == 'function' then
      table.insert(entries, self:extra_section_entry(section))
    end
  end
  if #entries == 0 then
    table.insert(entries, {
      key = 'empty',
      kind = 'info',
      display = line { style.dim 'No music provider capabilities available.' },
    })
  end
  return entries
end

function M:format_track_display(track)
  return line {
    track.liked == true and style.liked_icon() or style.dim '  ',
    style.titlec(track.title or track.name or track.id or 'Unknown'),
    style.dim '  [',
    style.accent(track.artist or 'Unknown artist'),
    style.dim ']',
  }
end

function M:format_playlist_display(playlist)
  return line {
    style.warm(playlist.name or playlist.id or 'Playlist'),
    playlist.source_title and style.dim '  ·  ' or '',
    playlist.source_title and style.accent(playlist.source_title) or '',
    playlist.track_count and style.dim '  ·  ' or '',
    playlist.track_count and style.okc(playlist.track_count) or '',
    playlist.track_count and style.dim ' tracks' or '',
  }
end

function M:format_album_display(album)
  return line {
    style.warm(album.name or album.id or 'Album'),
    album.artist and style.dim '  ·  ' or '',
    album.artist and style.accent(album.artist) or '',
  }
end

function M:format_artist_display(artist)
  return line {
    style.mag(artist.name or artist.id or 'Artist'),
    artist.album_count and style.dim '  ·  ' or '',
    artist.album_count and style.okc(artist.album_count) or '',
    artist.album_count and style.dim ' albums' or '',
  }
end

function M:build_player_track(track)
  local player_track = {
    id = track.id,
    key = tostring(track.id),
    title = track.title,
    artist = track.artist,
    album = track.album,
    duration = track.duration,
    liked = track.liked == true,
    source = self.provider.name,
    raw = track.raw,
    get_play_url = function(player_track_meta, cb)
      self.provider.get_play_url(track, function(url, err)
        if url and url ~= '' then player_track_meta.resolved_url = url end
        cb(url, err)
      end)
    end,
    display = function(item, player_state, meta)
      local current = item.current or item.playing
      local marker = style.dim '  '
      if current then marker = player_state.pause and style.warm '⏸ ' or style.okc '▶ ' end
      return line {
        marker,
        meta.liked == true and style.liked_icon() or style.dim '  ',
        style.titlec(meta.title or item.title or '-'),
        style.dim '  [',
        style.accent(meta.artist or '-'),
        style.dim ']',
      }
    end,
    preview = function(entry, cb)
      local meta = entry.mpv_meta or track
      cb(style.preview_lines {
        deck.style.line { style.okc 'Music queue' },
        '',
        style.kv_line('State', (entry.player or {}).pause and 'paused' or 'playing', 'accent'),
        style.kv_line('Title', meta.title or track.title or '-'),
        style.kv_line('Artist', meta.artist or track.artist or '-', 'accent'),
        style.kv_line('Album', meta.album or track.album or '-', 'warm'),
        style.kv_line('Duration', style.format_duration(meta.duration or track.duration), 'accent'),
        style.kv_line('Liked', tostring(meta.liked == true), meta.liked == true and 'warm' or 'mag'),
      })
    end,
  }

  if has_fn(self.provider, 'set_track_liked') then
    local keymap = (self.opt and self.opt.keymap) or {}
    player_track.keymap = {
      [keymap.toggle_liked or keymap.toggle_star or 'l'] = {
        callback = function()
          local target = deck.api.get_hovered()
          if target and target.mpv_meta and target.mpv_meta.id then
            return self:set_track_liked(target.mpv_meta, target.mpv_meta.liked ~= true)
          end
          return self:set_track_liked(track, track.liked ~= true)
        end,
        desc = 'toggle liked',
      },
    }
  end

  return player_track
end

function M:go_to_playing()
  deck.api.go_to { self.root, 'playing' }
end

function M:play_from_entry()
  local target = deck.api.get_hovered()
  if not target or target.kind ~= 'track' or not target.item then
    deck.cmd 'enter'
    return
  end

  local entries = deck.api.get_entries() or {}
  local tracks, started = {}, false
  for _, entry in ipairs(entries) do
    if entry.kind == 'track' and entry.item then
      if tostring(entry.item.id) == tostring(target.item.id) then started = true end
      if started then table.insert(tracks, self:build_player_track(entry.item)) end
    end
  end

  player
    .play_tracks(tracks)
    :next(function()
      style.notify_info(self.provider.title, 'Sent tracks to music queue')
      self:go_to_playing()
    end)
    :catch(function(err) style.notify_error(self.provider.title, err) end)
end

function M:append_track_entry()
  local target = deck.api.get_hovered()
  if not target or target.kind ~= 'track' or not target.item then return false end
  player
    .append_tracks({ self:build_player_track(target.item) })
    :next(function()
      style.notify_info(self.provider.title, 'Track appended to music queue')
      self:go_to_playing()
    end)
    :catch(function(err) style.notify_error(self.provider.title, err) end)
  return true
end

function M:append_playlist_entry()
  local target = deck.api.get_hovered()
  if not target or target.kind ~= 'playlist' or not target.item or not has_fn(self.provider, 'get_playlist_tracks') then
    return false
  end
  self.provider.get_playlist_tracks(target.item.id, function(tracks, err)
    if err then return style.notify_error(self.provider.title, err) end
    local out = {}
    for _, track in ipairs(tracks or {}) do
      table.insert(out, self:build_player_track(track))
    end
    player
      .append_tracks(out)
      :next(function()
        style.notify_info(self.provider.title, 'Playlist appended to music queue')
        self:go_to_playing()
      end)
      :catch(function(append_err) style.notify_error(self.provider.title, append_err) end)
  end)
  return true
end

function M:refresh_visible_track(track_id, fields)
  local entries = deck.api.get_entries() or {}
  for _, entry in ipairs(entries) do
    if entry.kind == 'track' and entry.item and tostring(entry.item.id) == tostring(track_id) then
      for key, value in pairs(fields or {}) do
        entry.item[key] = value
      end
      entry.display = self:format_track_display(entry.item)
    elseif entry.mpv_meta and tostring(entry.mpv_meta.id) == tostring(track_id) then
      for key, value in pairs(fields or {}) do
        entry.mpv_meta[key] = value
      end
      local item = entry.player_item or {}
      item._meta = entry.mpv_meta
      entry.player_item = item
      if type(entry.mpv_meta.display) == 'function' then
        entry.display = entry.mpv_meta.display(item, entry.player or {}, entry.mpv_meta)
      end
    end
  end
  deck.api.set_entries(nil, entries)
end

function M:set_track_liked(track, liked)
  if not has_fn(self.provider, 'set_track_liked') or not track or not track.id then return false end

  local prev_liked = track.liked == true
  track.liked = liked == true
  player.update_track_fields(track.id, { liked = track.liked })
  self:refresh_visible_track(track.id, { liked = track.liked })

  self.provider.set_track_liked(track, track.liked, function(_, err)
    if err then
      track.liked = prev_liked
      player.update_track_fields(track.id, { liked = prev_liked })
      self:refresh_visible_track(track.id, { liked = prev_liked })
      style.notify_error(self.provider.title, err)
    end
  end)
  return true
end

function M:toggle_liked_entry()
  if not has_fn(self.provider, 'set_track_liked') then return false end
  local target = deck.api.get_hovered()
  if not target then return false end

  if target.kind == 'track' and target.item then
    return self:set_track_liked(target.item, target.item.liked ~= true)
  end

  if target.mpv_meta and target.mpv_meta.id then
    return self:set_track_liked(target.mpv_meta, target.mpv_meta.liked ~= true)
  end

  return false
end

function M:add_track_to_playlist_entry()
  if not has_fn(self.provider, 'add_track_to_playlist') or not has_fn(self.provider, 'get_playlists') then
    return false
  end
  local target = deck.api.get_hovered()
  if not target or target.kind ~= 'track' or not target.item then return false end

  self.provider.get_playlists(function(playlists, err)
    if err then return style.notify_error(self.provider.title, err) end
    local options = {}
    for _, playlist in ipairs(playlists or {}) do
      table.insert(options, {
        value = playlist.id,
        display = self:format_playlist_display(playlist),
      })
    end
    if #options == 0 then return style.notify_info(self.provider.title, 'No playlists available') end

    deck.select({ prompt = 'Add track to playlist', options = options }, function(choice)
      if not choice then return end
      self.provider.add_track_to_playlist(target.item, choice, function(_, add_err)
        if add_err then return style.notify_error(self.provider.title, add_err) end
        style.notify_info(self.provider.title, 'Track added to playlist')
      end)
    end)
  end)
  return true
end

function M:remove_track_from_playlist_entry()
  if not has_fn(self.provider, 'remove_track_from_playlist') then return false end
  local target = deck.api.get_hovered()
  local path = deck.api.get_current_path() or {}
  if not target or target.kind ~= 'track' or not target.item then return false end
  if path[2] ~= 'playlist' or not path[3] then return false end

  local index = nil
  local count = 0
  for _, entry in ipairs(deck.api.get_entries() or {}) do
    if entry.kind == 'track' and entry.item then
      if tostring(entry.item.id) == tostring(target.item.id) and index == nil then index = count end
      count = count + 1
    end
  end
  if index == nil then return style.notify_error(self.provider.title, 'failed to locate playlist item index') end

  self.provider.remove_track_from_playlist(target.item, {
    playlist_id = path[3],
    index = index,
    path = path,
    entries = deck.api.get_entries() or {},
  }, function(_, err)
    if err then return style.notify_error(self.provider.title, err) end
    style.notify_info(self.provider.title, 'Track removed from playlist')
    deck.cmd 'reload'
  end)
  return true
end

function M:create_playlist_from_input()
  if not has_fn(self.provider, 'create_playlist') then return false end
  local path = deck.api.get_current_path() or {}
  if path[2] ~= 'playlist' or #path ~= 2 then return false end

  deck.input {
    prompt = 'New playlist',
    placeholder = 'playlist name',
    on_submit = function(input)
      local name = tostring(input or ''):trim()
      if name == '' then return end
      self.provider.create_playlist(name, function(_, err)
        if err then return style.notify_error(self.provider.title, err) end
        style.notify_info(self.provider.title, 'Playlist created')
        deck.cmd 'reload'
      end)
    end,
  }
  return true
end

function M:delete_playlist_entry()
  if not has_fn(self.provider, 'delete_playlist') then return false end
  local target = deck.api.get_hovered()
  if not target or target.kind ~= 'playlist' or not target.item then return false end
  deck.confirm {
    title = 'Delete Playlist',
    prompt = 'Delete playlist "' .. tostring(target.item.name or target.item.id or '?') .. '"?',
    on_confirm = function()
      self.provider.delete_playlist(target.item, function(_, err)
        if err then return style.notify_error(self.provider.title, err) end
        style.notify_info(self.provider.title, 'Playlist deleted')
        deck.cmd 'reload'
      end)
    end,
  }
  return true
end

function M:track_keymap()
  local keymap = (self.opt and self.opt.keymap) or {}
  local out = {
    [keymap.play_now or '<enter>'] = {
      callback = function() return self:play_from_entry() end,
      desc = 'play from here',
    },
    [keymap.append_to_player or 'a'] = {
      callback = function() return self:append_track_entry() end,
      desc = 'append to music queue',
    },
  }
  if has_fn(self.provider, 'set_track_liked') then
    out[keymap.toggle_liked or keymap.toggle_star or 'l'] =
      { callback = function() return self:toggle_liked_entry() end, desc = 'toggle liked' }
  end
  if has_fn(self.provider, 'add_track_to_playlist') and has_fn(self.provider, 'get_playlists') then
    out[keymap.add_to_playlist or 'A'] =
      { callback = function() return self:add_track_to_playlist_entry() end, desc = 'add to playlist' }
  end
  if has_fn(self.provider, 'remove_track_from_playlist') then
    out[keymap.delete or 'dd'] =
      { callback = function() return self:remove_track_from_playlist_entry() end, desc = 'remove from playlist' }
  end
  return out
end

function M:playlist_keymap()
  local keymap = (self.opt and self.opt.keymap) or {}
  local out = {
    [keymap.append_playlist_to_player or keymap.append_to_player or 'A'] = {
      callback = function() return self:append_playlist_entry() end,
      desc = 'append playlist to music queue',
    },
  }
  if has_fn(self.provider, 'create_playlist') then
    out[keymap.new or 'n'] =
      { callback = function() return self:create_playlist_from_input() end, desc = 'new playlist' }
  end
  if has_fn(self.provider, 'delete_playlist') then
    out[keymap.delete or 'dd'] =
      { callback = function() return self:delete_playlist_entry() end, desc = 'delete playlist' }
  end
  return out
end

function M:track_entries(tracks)
  local entries = {}
  for i, track in ipairs(tracks or {}) do
    track.type = track.type or 'track'
    table.insert(entries, {
      key = item_key(track, i),
      kind = 'track',
      item = track,
      display = self:format_track_display(track),
      keymap = self:track_keymap(),
      preview = function(entry, cb) cb(preview.item(entry.item)) end,
    })
  end
  if #entries == 0 then
    table.insert(entries, { key = 'empty', kind = 'info', display = line { style.dim 'No tracks.' } })
  end
  return entries
end

function M:playlist_entries(playlists)
  local entries = {}
  for i, playlist in ipairs(playlists or {}) do
    playlist.type = playlist.type or 'playlist'
    table.insert(entries, {
      key = item_key(playlist, i),
      kind = 'playlist',
      item = playlist,
      display = self:format_playlist_display(playlist),
      keymap = self:playlist_keymap(),
      preview = function(entry, cb) cb(preview.item(entry.item)) end,
    })
  end
  if #entries == 0 then
    table.insert(entries, { key = 'empty', kind = 'info', display = line { style.dim 'No playlists.' } })
  end
  return entries
end

function M:album_entries(albums)
  local entries = {}
  for i, album in ipairs(albums or {}) do
    album.type = album.type or 'album'
    table.insert(entries, {
      key = item_key(album, i),
      kind = 'album',
      item = album,
      display = self:format_album_display(album),
      preview = function(entry, cb) cb(preview.item(entry.item)) end,
    })
  end
  if #entries == 0 then
    table.insert(entries, { key = 'empty', kind = 'info', display = line { style.dim 'No albums.' } })
  end
  return entries
end

function M:artist_entries(artists)
  local entries = {}
  for i, artist in ipairs(artists or {}) do
    artist.type = artist.type or 'artist'
    table.insert(entries, {
      key = item_key(artist, i),
      kind = 'artist',
      item = artist,
      display = self:format_artist_display(artist),
      preview = function(entry, cb) cb(preview.item(entry.item)) end,
    })
  end
  if #entries == 0 then
    table.insert(entries, { key = 'empty', kind = 'info', display = line { style.dim 'No artists.' } })
  end
  return entries
end

function M:recommend_entries(cb)
  local entries = {}
  if has_fn(self.provider, 'get_recommend_playlists') then
    table.insert(entries, {
      key = 'playlist',
      kind = 'section',
      display = line { style.warm '󰲹', style.dim '  ', style.titlec 'Recommended Playlists' },
    })
  end
  if has_fn(self.provider, 'get_recommend_tracks') then
    table.insert(entries, {
      key = 'track',
      kind = 'section',
      display = line { style.okc '󰎈', style.dim '  ', style.titlec 'Recommended Tracks' },
    })
  end
  cb(entries)
end

function M:search_root(cb)
  local keymap = ((self.opt or {}).keymap or {}).search or 's'
  cb {
    {
      key = 'prompt',
      kind = 'info',
      display = line { style.titlec(('Press %s to search'):format(keymap)) },
      keymap = {
        [keymap] = { callback = function() return self:open_search_input() end, desc = 'search' },
      },
      preview = function(_, done) done(style.preview_lines { deck.style.line { style.titlec 'Search music' } }) end,
    },
  }
end

function M:open_search_input()
  deck.input {
    prompt = 'Search music',
    placeholder = 'keyword',
    on_submit = function(input)
      local query = tostring(input or ''):trim()
      if query == '' then
        deck.api.go_to { self.root, 'search' }
      else
        deck.api.go_to { self.root, 'search', query }
      end
    end,
  }
end

function M:search_groups(query, cb)
  self.provider.search(query, function(result, err)
    if err then
      cb(nil, err)
      return
    end
    local entries = {}
    for _, spec in ipairs(SEARCH_KINDS) do
      local items = (result or {})[spec.field] or {}
      table.insert(entries, {
        key = spec.key,
        kind = 'search_group',
        display = line { style.accent(spec.title), style.dim '  ·  ', style.okc(#items) },
        preview = function(_, done)
          done(style.preview_lines {
            style.kv_line('Query', query, 'accent'),
            style.kv_line('Type', spec.title, 'warm'),
            style.kv_line('Count', tostring(#items), 'accent'),
          })
        end,
      })
    end
    cb(entries)
  end)
end

function M:search_items(query, kind, cb)
  self.provider.search(query, function(result, err)
    if err then
      cb(nil, err)
      return
    end
    local field = ({ track = 'tracks', album = 'albums', artist = 'artists', playlist = 'playlists' })[kind]
    local items = field and (result or {})[field] or {}
    if kind == 'track' then return cb(self:track_entries(items)) end
    if kind == 'album' then return cb(self:album_entries(items)) end
    if kind == 'artist' then return cb(self:artist_entries(items)) end
    if kind == 'playlist' then return cb(self:playlist_entries(items)) end
    cb {}
  end)
end

function M:route(section, path, cb)
  if section == 'playing' then return player.list({ 'music' }, cb) end

  if section == 'playlist' then
    if #path == 2 then
      return self.provider.get_playlists(function(items, err) cb(items and self:playlist_entries(items), err) end)
    end
    return self.provider.get_playlist_tracks(
      path[3],
      function(items, err) cb(items and self:track_entries(items), err) end
    )
  end

  if section == 'artist' then
    if #path == 2 then
      return self.provider.get_artists(function(items, err) cb(items and self:artist_entries(items), err) end)
    end
    if #path == 3 then
      return self.provider.get_artist_albums(
        path[3],
        function(items, err) cb(items and self:album_entries(items), err) end
      )
    end
    return self.provider.get_album_tracks(
      path[4],
      function(items, err) cb(items and self:track_entries(items), err) end
    )
  end

  if section == 'album' then
    if #path == 2 then
      return self.provider.get_albums(function(items, err) cb(items and self:album_entries(items), err) end)
    end
    return self.provider.get_album_tracks(
      path[3],
      function(items, err) cb(items and self:track_entries(items), err) end
    )
  end

  if section == 'recommend' then
    if #path == 2 then return self:recommend_entries(cb) end
    if path[3] == 'playlist' then
      if #path == 3 then
        return self.provider.get_recommend_playlists(
          function(items, err) cb(items and self:playlist_entries(items), err) end
        )
      end
      return self.provider.get_playlist_tracks(
        path[4],
        function(items, err) cb(items and self:track_entries(items), err) end
      )
    end
    if path[3] == 'track' then
      return self.provider.get_recommend_tracks(function(items, err) cb(items and self:track_entries(items), err) end)
    end
  end

  if section == 'liked' then
    return self.provider.get_liked_tracks(function(items, err) cb(items and self:track_entries(items), err) end)
  end

  if section == 'search' then
    if #path == 2 or not path[3] or path[3] == '' then return self:search_root(cb) end
    if #path == 3 then return self:search_groups(path[3], cb) end
    return self:search_items(path[3], path[4], cb)
  end

  for _, extra in ipairs(self.provider.extra_sections or {}) do
    if extra.key == section and type(extra.list) == 'function' then return extra.list(path, cb) end
  end

  cb {}
end

function M:list(path, cb)
  if #path == 1 then
    cb(self:root_entries())
    return
  end

  self:route(path[2], path, function(entries, err)
    if err then
      style.notify_error(self.provider.title, err)
      cb {
        { key = 'error', kind = 'info', display = line { style.dim(tostring(err)) } },
      }
      return
    end
    cb(entries or {})
  end)
end

function M:preview(entry, cb)
  if not entry then return cb '' end
  if entry.item then return cb(preview.item(entry.item)) end
  cb ''
end

return M
