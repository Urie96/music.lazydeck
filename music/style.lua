local M = {}

function M.dim(text) return deck.style.span(tostring(text or '')):fg 'blue' end
function M.accent(text) return deck.style.span(tostring(text or '')):fg 'cyan' end
function M.warm(text) return deck.style.span(tostring(text or '')):fg 'yellow' end
function M.okc(text) return deck.style.span(tostring(text or '')):fg 'green' end
function M.mag(text) return deck.style.span(tostring(text or '')):fg 'magenta' end
function M.titlec(text) return deck.style.span(tostring(text or '')):fg 'white' end
function M.liked_icon() return deck.style.span(' '):fg 'red' end

local function aligned_line(line) return { line = line, align = true } end

function M.kv_line(label, value, label_color)
  local label_span = deck.style.span(tostring(label or ''))
  if label_color == 'accent' then
    label_span = label_span:fg 'cyan'
  elseif label_color == 'warm' then
    label_span = label_span:fg 'yellow'
  elseif label_color == 'mag' then
    label_span = label_span:fg 'magenta'
  else
    label_span = label_span:fg 'blue'
  end

  return aligned_line(deck.style.line {
    label_span,
    M.dim ': ',
    M.titlec(value or '-'),
  })
end

function M.preview_lines(lines)
  local out, aligned = {}, {}
  for _, line in ipairs(lines or {}) do
    local item = line
    local should_align = false

    if type(line) == 'table' and line.line ~= nil then
      item = line.line
      should_align = line.align == true
    elseif type(line) == 'string' or type(line) == 'number' or type(line) == 'boolean' or line == nil then
      item = deck.style.line { deck.style.span(tostring(line or '')) }
    end

    table.insert(out, item)
    if should_align then table.insert(aligned, item) end
  end
  if #aligned > 0 then deck.style.align_columns(aligned) end
  return deck.style.text(out)
end

function M.format_duration(seconds)
  local n = tonumber(seconds or 0)
  if not n or n <= 0 then return '--:--' end
  local h = math.floor(n / 3600)
  local m = math.floor((n % 3600) / 60)
  local s = math.floor(n % 60)
  if h > 0 then return string.format('%d:%02d:%02d', h, m, s) end
  return string.format('%d:%02d', m, s)
end

function M.notify_error(title, err)
  deck.notify(deck.style.line {
    deck.style.span(tostring(title or 'music') .. ': '):fg 'red',
    deck.style.span(tostring(err)):fg 'red',
  })
end

function M.notify_info(title, msg)
  deck.notify(deck.style.line {
    deck.style.span(tostring(title or 'music') .. ': '):fg 'cyan',
    deck.style.span(tostring(msg)):fg 'white',
  })
end

return M
