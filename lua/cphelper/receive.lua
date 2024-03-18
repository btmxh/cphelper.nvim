local prepare = require("cphelper.prepare")
local uv = vim.loop

local M = {}

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

function M.receive()
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

                client:write("HTTP/1.1 200 OK\r\n\r\n")
                client:shutdown()
                client:close()
                if parse_result.method == "POST" then
                    vim.schedule(function()
                        local problem = vim.json.decode(parse_result.body)
                        if vim.g["cph#url_register"] then
                            vim.fn.setreg(vim.g["cph#url_register"], problem.url)
                        end
                        local problem_dir = prepare.prepare_folders(problem.name, problem.group)
                        prepare.prepare_files(problem_dir, problem.tests)
                        print("All the best!")
                    end)
                end
            end
        end)
    end)
    uv.run()
end

function M.stop()
    M.server:shutdown()
end

return M
