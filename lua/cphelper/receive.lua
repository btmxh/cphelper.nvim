local prepare = require("cphelper.prepare")
local def = require("cphelper.definitions")
local path = require("plenary.path")
local uv = vim.loop

local M = {
    current = nil,
}

-- warning: AI generated code
local function split_string(string, delim)
    local res, from = {}, 1
    repeat
        local pos = string:find(delim, from)
        table.insert(res, string:sub(from, pos and pos - 1))
        from = pos and pos + #delim
    until not from
    return res
end

-- HTTP request parser function
local function parse_http_request(request)
    local method, path, headers, body = {}, "", {}, nil

    -- Check if the request is complete
    local complete = false

    -- Split request into lines
    local lines = {}
    for _, line in ipairs(split_string(request, "\r\n")) do
        if line == "" then
            complete = true
            break
        end
        table.insert(lines, line)
    end

    -- If request is incomplete, return nil
    if not complete then
        return nil
    end

    -- Parse method and path
    local first_line = lines[1]
    if first_line == nil then
        return nil
    end
    method, path = string.match(first_line, "^(%S+)%s+(%S+)%s+HTTP/%d%.%d$")

    -- Parse headers
    local i = 2
    while lines[i] and lines[i] ~= "" do
        local header, value = string.match(lines[i], "^(.-):%s*(.*)$")
        if header then
            headers[header] = value
        end
        i = i + 1
    end

    -- Check for body
    local sep = '\r\n\r\n'
    local body_start = request:find(sep) + #sep
    local content_length = 0
    if headers["Content-Length"] then
        content_length = tonumber(headers["Content-Length"])
    end
    body = string.sub(request, body_start, body_start + content_length - 1)

    return {
        method = method,
        path = path,
        headers = headers,
        body = body
    }
end

local function respond(client, json)
    client:write("HTTP/1.1 200 OK\r\n\r\n")
    client:write(vim.json.encode(json))
    client:close()
    client:shutdown()
end

local function receive(parse_result, client)
    vim.schedule(function()
        local problem = vim.json.decode(parse_result.body)
        if vim.g["cph#url_register"] then
            vim.fn.setreg(vim.g["cph#url_register"], problem.url)
        end
        local problem_dir = prepare.prepare_folders(problem.name, problem.group)
        prepare.prepare_files(problem_dir, problem)
        print("All the best!")
    end)
    respond(client, { empty = true })
end

local function infer_language(filename)
    for name, extension in pairs(def.extensions) do
        if filename:match("%." .. extension .. "$") then
            return name
        end
    end
    return nil
end

local function language_id(name)
    if name == nil then
        return nil
    end
    local default_ids = {
        c = 43,          -- GNU C11 5.1.0
        cpp = 54,        -- GNU G++17 7.3.0
        java = 87,       -- Java 21 64bit
        python = 31,     -- Python 3.8.10
        rust = 75,       -- Rust 1.75.0 (2021)
        kotlin = 88,     -- Kotlin 1.9.21
        javascript = 34, -- JavaScript V8 4.8.0
    }
    return vim.g["cph#" .. name .. "#language_id"] or default_ids[name]
end

local function submit(client)
    local json = { empty = true }
    if M.current ~= nil then
        -- only supporting auto-submit to codeforces right now
        local current = M.current
        M.current = nil
        local problem_file = assert(io.open(current:parent():joinpath("metadata.json"):absolute(), "r"))
        local problem = vim.json.decode(problem_file:read("*all"))
        problem_file:close()
        local contest_id, problem_name = string.match(problem.url, "codeforces%.com%/contest%/(%d+)%/problem%/([A-Z])")
        if contest_id ~= nil and problem_name ~= nil then
            print("Submitting to Codeforces")
            problem_name = contest_id .. problem_name

            print(vim.inspect(current))
            local lang_name = infer_language(current:absolute())
            local lang_id = language_id(lang_name)
            if lang_id == nil then
                print("Codeforces does not support submissions using this language")
            else
                local source_file = assert(io.open(current:absolute(), "r"))
                local content = source_file:read("*all")
                source_file:close()

                if vim.g["cph#" .. lang_name .. "#transform"] ~= nil then
                    content = vim.g["cph#" .. lang_name .. "#transform"](content)
                end

                json = {
                    empty = false,
                    sourceCode = content,
                    problemName = problem_name,
                    url = problem.url,
                    languageId = lang_id,
                }
            end
        end
    end
    respond(client, json)
end

function M.start()
    print("Listening on port 27121")
    M.server = uv.new_tcp()
    M.server:bind("127.0.0.1", 27121)
    M.server:listen(128, function(err)
        assert(not err, err)
        local client = uv.new_tcp()
        local buffer = ""
        M.server:accept(client)
        client:read_start(function(error, chunk)
            assert(not error, error)
            if chunk then
                buffer = buffer .. chunk
                local parse_result = parse_http_request(buffer)
                if parse_result == nil then
                    return
                end
                if parse_result.method == "POST" and parse_result.path == "/" then
                    receive(parse_result, client)
                elseif parse_result.method == "GET" and parse_result.path == "/getSubmit" then
                    submit(client)
                else
                    client:write("HTTP/1.1 405 Method Not Allowed\r\n\r\n")
                end
            end
        end)
    end)
    uv.run()
end

function M.stop()
    M.server:shutdown()
end

function M.submit()
    M.current = path:new(vim.fn.expand("%:p"))
end

return M
