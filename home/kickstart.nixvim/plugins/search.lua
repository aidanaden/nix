package.preload['aidan.search'] = function()
  local M = {}
  local state = {
    resume = nil,
    warned_find_files_fallback = false,
    warned_jj_live_grep_fallback = false,
    warned_live_grep_fallback = false,
  }

  local severity_names = {
    [vim.diagnostic.severity.ERROR] = 'ERROR',
    [vim.diagnostic.severity.WARN] = 'WARN',
    [vim.diagnostic.severity.INFO] = 'INFO',
    [vim.diagnostic.severity.HINT] = 'HINT',
  }

  local function notify(message, level)
    vim.notify(message, level or vim.log.levels.INFO, { title = 'Search' })
  end

  local function normalize(value)
    return tostring(value or ''):lower()
  end

  local function display_path(path)
    if path == nil or path == '' then
      return '[No Name]'
    end

    return vim.fn.fnamemodify(path, ':~:.')
  end

  local function sort_items(items)
    table.sort(items, function(left, right)
      return left.label < right.label
    end)

    return items
  end

  local function matches(item, query)
    if query == '' then
      return true
    end

    return normalize(item.search or item.label):find(normalize(query), 1, true) ~= nil
  end

  local function prompt(label, allow_empty)
    local value = vim.trim(vim.fn.input(label))
    if value == '' and not allow_empty then
      return nil
    end

    return value
  end

  local function set_resume(fn)
    state.resume = fn
  end

  local function jump_to_item(item)
    if item.bufnr and item.bufnr ~= 0 and vim.api.nvim_buf_is_valid(item.bufnr) then
      if item.bufnr ~= vim.api.nvim_get_current_buf() then
        vim.cmd({ cmd = 'buffer', args = { tostring(item.bufnr) } })
      end
    elseif item.filename and item.filename ~= '' then
      vim.cmd({ cmd = 'edit', args = { item.filename } })
    end

    if item.lnum then
      vim.api.nvim_win_set_cursor(0, { item.lnum, math.max((item.col or 1) - 1, 0) })
    end
  end

  local function select_items(title, items, query, on_choice, empty_message)
    local filtered = {}

    for _, item in ipairs(items) do
      if matches(item, query or '') then
        table.insert(filtered, item)
      end
    end

    if #filtered == 0 then
      notify(empty_message or ('No matches for ' .. title), vim.log.levels.WARN)
      return
    end

    if #filtered == 1 then
      on_choice(filtered[1])
      return
    end

    vim.ui.select(filtered, {
      prompt = title,
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if choice then
        on_choice(choice)
      end
    end)
  end

  local function open_list(kind, title, items, empty_message)
    if #items == 0 then
      notify(empty_message or ('No results for ' .. title), vim.log.levels.WARN)
      return
    end

    if #items == 1 then
      jump_to_item(items[1])
      return
    end

    if kind == 'loc' then
      vim.fn.setloclist(0, {}, 'r', { title = title, items = items })
      vim.cmd.lopen()
      return
    end

    vim.fn.setqflist({}, 'r', { title = title, items = items })
    vim.cmd.copen()
  end

  local function all_help_items()
    local items = {}
    local seen = {}

    for _, tag in ipairs(vim.fn.getcompletion('', 'help')) do
      if not seen[tag] then
        seen[tag] = true
        table.insert(items, {
          label = tag,
          search = tag,
          value = tag,
        })
      end
    end

    return sort_items(items)
  end

  local function run_help(query)
    select_items('Help Tags', all_help_items(), query, function(item)
      vim.cmd({ cmd = 'help', args = { item.value } })
    end, 'No help tags matched')
  end

  local function all_keymap_items()
    local items = {}
    local seen = {}
    local modes = { 'n', 'i', 'v', 'x', 's', 'o', 'c', 't' }

    local function add(scope, mode, map)
      local lhs = map.lhs or ''
      if lhs == '' then
        return
      end

      local rhs = tostring(map.desc or map.rhs or '<Lua>'):gsub('%s+', ' ')
      local id = table.concat({ scope, mode, lhs, rhs }, '::')
      if seen[id] then
        return
      end

      seen[id] = true
      table.insert(items, {
        label = string.format('[%s%s] %s -> %s', mode, scope == 'buffer' and '*' or '', lhs, rhs),
        search = table.concat({ mode, lhs, rhs, scope }, ' '),
      })
    end

    for _, mode in ipairs(modes) do
      for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
        add('global', mode, map)
      end

      for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
        add('buffer', mode, map)
      end
    end

    return sort_items(items)
  end

  local function all_buffer_items()
    local items = {}
    local current = vim.api.nvim_get_current_buf()

    for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
      local flags = {}
      if info.bufnr == current then
        table.insert(flags, '%')
      end
      if info.changed == 1 then
        table.insert(flags, '+')
      end

      local suffix = #flags > 0 and (' [' .. table.concat(flags, '') .. ']') or ''
      local name = display_path(info.name)

      table.insert(items, {
        label = string.format('%d %s%s', info.bufnr, name, suffix),
        search = table.concat({ tostring(info.bufnr), name }, ' '),
        bufnr = info.bufnr,
      })
    end

    return sort_items(items)
  end

  local function all_oldfile_items()
    local items = {}
    local seen = {}

    for _, path in ipairs(vim.v.oldfiles or {}) do
      if path ~= '' and vim.fn.filereadable(path) == 1 and not seen[path] then
        seen[path] = true
        table.insert(items, {
          label = display_path(path),
          search = path,
          filename = path,
        })
      end
    end

    return sort_items(items)
  end

  local function all_diagnostic_items()
    local items = {}

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local filename = vim.api.nvim_buf_get_name(bufnr)
      if filename ~= '' then
        for _, diagnostic in ipairs(vim.diagnostic.get(bufnr)) do
          local message = diagnostic.message:gsub('%s+', ' ')
          local severity = severity_names[diagnostic.severity] or 'UNKNOWN'

          table.insert(items, {
            label = string.format(
              '%s:%d:%d [%s] %s',
              display_path(filename),
              diagnostic.lnum + 1,
              diagnostic.col + 1,
              severity,
              message
            ),
            search = table.concat({ filename, severity, message }, ' '),
            bufnr = bufnr,
            filename = filename,
            lnum = diagnostic.lnum + 1,
            col = diagnostic.col + 1,
            text = message,
            type = severity:sub(1, 1),
          })
        end
      end
    end

    return sort_items(items)
  end

  local function current_buffer_matches(query)
    local items = {}
    local bufnr = vim.api.nvim_get_current_buf()
    local filename = vim.api.nvim_buf_get_name(bufnr)

    for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      if line ~= '' and matches({ search = line }, query) then
        table.insert(items, {
          bufnr = bufnr,
          filename = filename,
          lnum = lnum,
          col = 1,
          text = line,
        })
      end
    end

    return items
  end

  local function open_file_paths()
    local paths = {}
    local seen = {}

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      local filename = vim.api.nvim_buf_get_name(bufnr)
      if filename ~= '' and vim.fn.filereadable(filename) == 1 and not seen[filename] then
        seen[filename] = true
        table.insert(paths, filename)
      end
    end

    return paths
  end

  local function parse_vimgrep_output(output, cwd)
    local items = {}

    for line in (output or ''):gmatch('[^\r\n]+') do
      local filename, lnum, col, text = line:match('^(.-):(%d+):(%d+):(.*)$')
      if filename then
        if cwd and not vim.startswith(filename, '/') then
          filename = vim.fs.normalize(cwd .. '/' .. filename)
        end

        table.insert(items, {
          filename = filename,
          lnum = tonumber(lnum),
          col = tonumber(col),
          text = text,
        })
      end
    end

    return items
  end

  local function parse_file_output(output, cwd)
    local items = {}

    for line in (output or ''):gmatch('[^\r\n]+') do
      if line ~= '' then
        table.insert(items, {
          label = line,
          search = line,
          filename = vim.fs.normalize(cwd .. '/' .. line),
          lnum = 1,
          col = 1,
          text = line,
        })
      end
    end

    return sort_items(items)
  end

  local function has_upward_path(name, path)
    return #vim.fs.find(name, {
      path = path,
      upward = true,
      limit = 1,
    }) > 0
  end

  local function uses_jj_only_repo(cwd)
    return has_upward_path('.jj', cwd) and not has_upward_path('.git', cwd)
  end

  local function telescope_find_files(opts)
    local ok, builtin = pcall(require, 'telescope.builtin')
    if not ok then
      return false
    end

    builtin.find_files({
      cwd = vim.fn.fnamemodify(opts.cwd or vim.fn.getcwd(), ':p'),
      default_text = opts.query,
      hidden = true,
      prompt_title = opts.title or 'Files',
      find_command = {
        'rg',
        '--files',
        '--hidden',
        '--glob',
        '!.git',
        '--glob',
        '!.git/**',
        '--glob',
        '!.jj',
        '--glob',
        '!.jj/**',
      },
    })

    return true
  end

  local function telescope_live_grep(opts)
    local ok, builtin = pcall(require, 'telescope.builtin')
    if not ok then
      return false
    end

    builtin.live_grep({
      cwd = vim.fn.fnamemodify(opts.cwd or vim.fn.getcwd(), ':p'),
      default_text = opts.query,
      prompt_title = opts.title or 'Live Grep',
      additional_args = function()
        return {
          '--glob',
          '!.git',
          '--glob',
          '!.git/**',
          '--glob',
          '!.jj',
          '--glob',
          '!.jj/**',
        }
      end,
    })

    return true
  end

  local function set_telescope_resume(fallback)
    set_resume(function()
      local ok, builtin = pcall(require, 'telescope.builtin')
      if ok then
        builtin.resume()
        return
      end

      fallback()
    end)
  end

  local function warn_find_files_fallback()
    if state.warned_find_files_fallback then
      return
    end

    state.warned_find_files_fallback = true
    notify('Pure jj repo detected; using Telescope file search fallback', vim.log.levels.WARN)
  end

  local function grep_open_files(query)
    local paths = open_file_paths()
    if #paths == 0 then
      notify('No open files to search', vim.log.levels.WARN)
      return
    end

    local command = { 'rg', '--vimgrep', '--smart-case', '--color', 'never', '--', query }
    vim.list_extend(command, paths)

    local result = vim.system(command, { text = true }):wait()
    if result.code > 1 then
      notify(result.stderr ~= '' and result.stderr or 'ripgrep failed', vim.log.levels.ERROR)
      return
    end

    open_list('qf', 'Open Files Grep', parse_vimgrep_output(result.stdout), 'No open file matches')
  end

  local function grep_directory(query, cwd, title)
    local command = { 'rg', '--vimgrep', '--smart-case', '--color', 'never', '--', query }
    local result = vim.system(command, { cwd = cwd, text = true }):wait()
    if result.code > 1 then
      notify(result.stderr ~= '' and result.stderr or 'ripgrep failed', vim.log.levels.ERROR)
      return
    end

    open_list(
      'qf',
      title or 'Live Grep',
      parse_vimgrep_output(result.stdout, cwd),
      'No matches for ' .. query
    )
  end

  local function open_file_matches(title, items, query, empty_message)
    local filtered = {}

    for _, item in ipairs(items) do
      if matches(item, query or '') then
        table.insert(filtered, item)
      end
    end

    if #filtered == 0 then
      notify(empty_message or ('No matches for ' .. title), vim.log.levels.WARN)
      return
    end

    if #filtered == 1 then
      jump_to_item(filtered[1])
      return
    end

    if #filtered <= 200 then
      select_items(title, filtered, '', jump_to_item, empty_message)
      return
    end

    local qf_items = {}
    for _, item in ipairs(filtered) do
      table.insert(qf_items, {
        filename = item.filename,
        lnum = item.lnum,
        col = item.col,
        text = item.text,
      })
    end

    open_list('qf', title, qf_items, empty_message)
  end

  local function find_files_with_rg(opts)
    local cwd = vim.fn.fnamemodify(opts.cwd or vim.fn.getcwd(), ':p')
    local command = {
      'rg',
      '--files',
      '--hidden',
      '--color',
      'never',
      '-g',
      '!.git',
      '-g',
      '!.git/**',
      '-g',
      '!.jj',
      '-g',
      '!.jj/**',
    }
    local result = vim.system(command, { cwd = cwd, text = true }):wait()
    if result.code > 1 then
      notify(result.stderr ~= '' and result.stderr or 'ripgrep failed', vim.log.levels.ERROR)
      return
    end

    open_file_matches(
      opts.title or 'Files',
      parse_file_output(result.stdout, cwd),
      opts.query or '',
      opts.query and opts.query ~= '' and ('No files matched ' .. opts.query) or 'No files found'
    )
  end

  local function warn_live_grep_fallback()
    if state.warned_live_grep_fallback then
      return
    end

    state.warned_live_grep_fallback = true
    notify('Installed fff.nvim has no live_grep; using ripgrep quickfix fallback', vim.log.levels.WARN)
  end

  local function warn_jj_live_grep_fallback()
    if state.warned_jj_live_grep_fallback then
      return
    end

    state.warned_jj_live_grep_fallback = true
    notify('Pure jj repo detected; using Telescope live grep fallback', vim.log.levels.WARN)
  end

  function M.resume()
    if state.resume then
      state.resume()
      return
    end

    notify('No search to resume', vim.log.levels.WARN)
  end

  function M.find_files(opts)
    opts = vim.deepcopy(opts or {})
    local cwd = vim.fn.fnamemodify(opts.cwd or vim.fn.getcwd(), ':p')

    if uses_jj_only_repo(cwd) then
      warn_find_files_fallback()
      set_telescope_resume(function()
        M.find_files(vim.deepcopy(opts))
      end)
      if not telescope_find_files(opts) then
        find_files_with_rg(opts)
      end
      return
    end

    set_resume(function()
      M.find_files(vim.deepcopy(opts))
    end)
    require('fff').find_files(opts)
  end

  function M.find_config_files()
    set_resume(M.find_config_files)
    require('fff').find_files_in_dir(vim.fn.stdpath('config'))
  end

  function M.live_grep(opts)
    opts = vim.deepcopy(opts or {})
    local cwd = vim.fn.fnamemodify(opts.cwd or vim.fn.getcwd(), ':p')

    if uses_jj_only_repo(cwd) then
      warn_jj_live_grep_fallback()
      set_telescope_resume(function()
        M.live_grep(vim.deepcopy(opts))
      end)
      if not telescope_live_grep(opts) then
        if not opts.query or opts.query == '' then
          opts.query = prompt('Live grep> ', false)
          if not opts.query then
            return
          end
        end
        grep_directory(opts.query, cwd, opts.title)
      end
      return
    end

    local fff = require('fff')

    if type(fff.live_grep) == 'function' then
      set_resume(function()
        M.live_grep(vim.deepcopy(opts))
      end)
      fff.live_grep(opts)
      return
    end

    if not opts.query or opts.query == '' then
      opts.query = prompt('Live grep> ', false)
      if not opts.query then
        return
      end
    end

    warn_live_grep_fallback()
    set_resume(function()
      M.live_grep(vim.deepcopy(opts))
    end)
    grep_directory(
      opts.query,
      vim.fn.fnamemodify(opts.cwd or vim.fn.getcwd(), ':p'),
      opts.title
    )
  end

  function M.search_word()
    M.live_grep({ query = vim.fn.expand('<cword>') })
  end

  function M.search_help()
    local query = prompt('Help> ', false)
    if not query then
      return
    end

    set_resume(function()
      run_help(query)
    end)
    run_help(query)
  end

  function M.search_keymaps()
    local query = prompt('Keymaps> ', true) or ''
    local run = function(value)
      select_items('Keymaps', all_keymap_items(), value, function(item)
        notify(item.label)
      end, 'No keymaps matched')
    end

    set_resume(function()
      run(query)
    end)
    run(query)
  end

  function M.search_buffers()
    local query = prompt('Buffers> ', true) or ''
    local run = function(value)
      select_items('Buffers', all_buffer_items(), value, jump_to_item, 'No buffers matched')
    end

    set_resume(function()
      run(query)
    end)
    run(query)
  end

  function M.search_recent_files()
    local query = prompt('Recent files> ', true) or ''
    local run = function(value)
      select_items('Recent Files', all_oldfile_items(), value, jump_to_item, 'No recent files matched')
    end

    set_resume(function()
      run(query)
    end)
    run(query)
  end

  function M.search_diagnostics()
    local query = prompt('Diagnostics> ', true) or ''
    local run = function(value)
      local items = {}
      for _, item in ipairs(all_diagnostic_items()) do
        if matches(item, value) then
          table.insert(items, {
            bufnr = item.bufnr,
            filename = item.filename,
            lnum = item.lnum,
            col = item.col,
            text = item.text,
            type = item.type,
          })
        end
      end

      open_list('qf', 'Diagnostics', items, 'No diagnostics matched')
    end

    set_resume(function()
      run(query)
    end)
    run(query)
  end

  function M.search_current_buffer()
    local query = prompt('Buffer search> ', false)
    if not query then
      return
    end

    local run = function(value)
      open_list('loc', 'Current Buffer Search', current_buffer_matches(value), 'No buffer lines matched')
    end

    set_resume(function()
      run(query)
    end)
    run(query)
  end

  function M.search_open_files()
    local query = prompt('Open files grep> ', false)
    if not query then
      return
    end

    set_resume(function()
      grep_open_files(query)
    end)
    grep_open_files(query)
  end

  function M.search_menu()
    local items = {
      { label = 'Help tags', run = M.search_help },
      { label = 'Keymaps', run = M.search_keymaps },
      { label = 'Files', run = M.find_files },
      { label = 'Recent files', run = M.search_recent_files },
      { label = 'Buffers', run = M.search_buffers },
      { label = 'Current word', run = M.search_word },
      { label = 'Live grep', run = M.live_grep },
      { label = 'Current buffer', run = M.search_current_buffer },
      { label = 'Open files', run = M.search_open_files },
      { label = 'Diagnostics', run = M.search_diagnostics },
      { label = 'Neovim files', run = M.find_config_files },
      { label = 'Resume', run = M.resume },
    }

    vim.ui.select(items, {
      prompt = 'Search',
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if choice then
        choice.run()
      end
    end)
  end

  return M
end
