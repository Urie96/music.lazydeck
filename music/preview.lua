local style = require 'music.style'

local M = {}

function M.track(track)
  track = track or {}
  return style.preview_lines {
    deck.style.line { style.titlec(track.title or track.name or track.id or 'Track') },
    '',
    style.kv_line('Artist', tostring(track.artist or '-'), 'accent'),
    style.kv_line('Album', tostring(track.album or '-'), 'warm'),
    style.kv_line('Duration', style.format_duration(track.duration), 'accent'),
    style.kv_line('Liked', tostring(track.liked == true), track.liked == true and 'warm' or 'mag'),
    style.kv_line('ID', tostring(track.id or '-')),
  }
end

function M.playlist(playlist)
  playlist = playlist or {}
  return style.preview_lines {
    deck.style.line { style.warm(playlist.name or playlist.id or 'Playlist') },
    '',
    style.kv_line('Owner', tostring(playlist.owner or '-'), 'accent'),
    style.kv_line('Tracks', tostring(playlist.track_count or playlist.song_count or 0), 'accent'),
    style.kv_line('Duration', style.format_duration(playlist.duration), 'accent'),
    playlist.source_title and style.kv_line('Source', tostring(playlist.source_title), 'warm') or nil,
    '',
    deck.style.line { style.dim(playlist.description or '') },
  }
end

function M.album(album)
  album = album or {}
  return style.preview_lines {
    deck.style.line { style.warm(album.name or album.id or 'Album') },
    '',
    style.kv_line('Artist', tostring(album.artist or '-'), 'accent'),
    style.kv_line('Year', tostring(album.year or '-'), 'warm'),
    style.kv_line('Tracks', tostring(album.track_count or 0), 'accent'),
    style.kv_line('Duration', style.format_duration(album.duration), 'accent'),
    style.kv_line('Genre', tostring(album.genre or '-'), 'mag'),
  }
end

function M.artist(artist)
  artist = artist or {}
  return style.preview_lines {
    deck.style.line { style.mag(artist.name or artist.id or 'Artist') },
    '',
    style.kv_line('Albums', tostring(artist.album_count or 0), 'accent'),
    style.kv_line('ID', tostring(artist.id or '-')),
  }
end

function M.item(item)
  if not item then return '' end
  if item.type == 'track' then return M.track(item) end
  if item.type == 'playlist' then return M.playlist(item) end
  if item.type == 'album' then return M.album(item) end
  if item.type == 'artist' then return M.artist(item) end
  return style.preview_lines { tostring(item.title or item.name or item.key or '') }
end

return M
