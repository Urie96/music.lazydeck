# music.lazydeck

通用音乐插件，包含两部分：

- `/music`：基于后台 `mpv` 的播放队列和控制页
- `music.new(provider, opt)`：音乐 provider 浏览器工厂，用于 OpenSubsonic、网易云音乐等插件复用通用 playlist / artist / album / track / search / recommendation UI

## 配置

```lua
{
  dir = 'plugins/music.lazydeck',
  config = function()
    require('music').setup {
      -- socket = (os.getenv 'TMPDIR' or '/tmp') .. '/lazydeck-mpv.sock', -- 默认值
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
  end,
}
```

## Player API

`music` 保留原 `mpv.lazydeck` 的播放器 API：

- `music.play_tracks(tracks)`
- `music.append_tracks(tracks)`
- `music.update_track_fields(id, fields)`
- `music.get_player_state()`
- `music.player_next()` / `player_prev()` / `player_toggle_pause()` / `player_play()`
- `music.player_adjust_volume(delta)`
- `music.player_jump(index)`
- `music.player_remove(index)`

track 至少需要 `url` 或 `get_play_url(track, cb)`：

```lua
{
  id = '123',
  title = 'Song',
  artist = 'Artist',
  album = 'Album',
  duration = 240,
  get_play_url = function(track, cb)
    cb('https://example.com/song.mp3')
  end,
}
```

## Provider browser

provider 插件自己完成配置和可用性检查，然后把已初始化 provider 传给 `music.new()`：

```lua
local music = require 'music'
local provider = require 'my-provider.provider'

local browser = music.new(provider, { root = 'my-provider' })

function M.list(path, cb)
  browser:list(path, cb)
end

function M.preview(entry, cb)
  browser:preview(entry, cb)
end
```

## Provider 接口

必需字段：

```lua
provider.name = 'my-provider'
provider.title = 'My Provider'
function provider.get_play_url(track, cb) end
```

`playing`（正在播放）section 始终显示。其他可选浏览能力，music 会根据函数是否存在自动生成 section：

```lua
function provider.get_playlists(cb) end
function provider.get_playlist_tracks(playlist_id, cb) end

function provider.get_artists(cb) end
function provider.get_artist_albums(artist_id, cb) end

function provider.get_albums(cb) end
function provider.get_album_tracks(album_id, cb) end

function provider.get_recommend_playlists(cb) end
function provider.get_recommend_tracks(cb) end

function provider.get_liked_tracks(cb) end
function provider.search(query, cb) end
```

可选写操作：

```lua
function provider.set_track_liked(track, liked, cb) end
function provider.add_track_to_playlist(track, playlist_id, cb) end
function provider.remove_track_from_playlist(track, context, cb) end
function provider.create_playlist(name, cb) end
function provider.delete_playlist(playlist, cb) end
```

provider 特有页面通过 `extra_sections` 注入，例如账号二维码登录页：

```lua
provider.extra_sections = {
  {
    key = 'account',
    title = 'Account',
    icon = '',
    description = 'Login and account status',
    list = function(path, cb)
      cb(entries)
    end,
  },
}
```

## 标准数据结构

### Track

```lua
{
  type = 'track',
  id = '123',
  title = 'Song Title',
  artist = 'Artist',
  album = 'Album',
  duration = 240, -- 秒
  liked = true,
  source = 'my-provider',
  raw = original_song,
}
```

### Playlist

```lua
{
  type = 'playlist',
  id = '456',
  name = 'Playlist Name',
  owner = 'User',
  track_count = 20,
  duration = 3600,
  description = '...',
  source = 'recommend',
  source_title = 'Recommended',
  raw = original_playlist,
}
```

### Album

```lua
{
  type = 'album',
  id = '789',
  name = 'Album Name',
  artist = 'Artist',
  year = 2024,
  track_count = 12,
  duration = 3000,
  raw = original_album,
}
```

### Artist

```lua
{
  type = 'artist',
  id = 'abc',
  name = 'Artist Name',
  album_count = 10,
  raw = original_artist,
}
```
