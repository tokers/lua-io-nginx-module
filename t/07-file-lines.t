use Test::Nginx::Socket::Lua;

repeat_each(3);

plan tests => repeat_each() * (4 * 6);

log_level 'debug';

no_long_string();
run_tests();

__DATA__

=== TEST 1: use lines iterator in the for loop
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local t = {}
            for line in file:lines() do
                t[#t + 1] = line
            end

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local name = ngx.config.prefix() .. "/conf/nginx.conf"
            local file = io.open(name)
            local t2 = {}
            for line in file:lines() do
                t2[#t2 + 1] = line
            end

            assert(table.concat(t) == table.concat(t2))
            ngx.print("data ok")
        }
    }

--- request
GET /t
--- response_body: data ok
--- no_error_log eval
["crit", "error"]



=== TEST 2: use lines iterator and mix it with file:read("*l")
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local t = {}
            for line in file:lines() do
                t[#t + 1] = line
                if #t == 4 then
                    break
                end
            end

            while true do
                local line, err = file:read("*l")
                if line == nil then
                    break
                end
                assert(err == nil)
                t[#t + 1] = line
            end

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local name = ngx.config.prefix() .. "/conf/nginx.conf"
            local file = io.open(name)
            local t2 = {}
            for line in file:lines() do
                t2[#t2 + 1] = line
            end

            assert(table.concat(t) == table.concat(t2))
            ngx.print("data ok")
        }
    }

--- request
GET /t
--- response_body: data ok
--- no_error_log eval
["crit", "error"]



=== TEST 3: use lines iterator and mix it with file:read(num)
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local t = {}
            local data, err = file:read(1)
            assert(data)
            assert(err == nil)
            t[#t + 1] = data

            local data, err = file:read(1)
            assert(data)
            assert(err == nil)
            t[#t + 1] = data

            for line in file:lines() do
                t[#t + 1] = line
            end

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local name = ngx.config.prefix() .. "/conf/nginx.conf"
            local file = io.open(name)
            local t2 = {}
            local data, err = file:read(1)
            assert(data)
            assert(err == nil)
            t2[#t2 + 1] = data

            local data, err = file:read(1)
            assert(data)
            assert(err == nil)
            t2[#t2 + 1] = data
            for line in file:lines() do
                t2[#t2 + 1] = line
            end

            assert(table.concat(t) == table.concat(t2))
            ngx.print("data ok")
        }
    }

--- request
GET /t
--- response_body: data ok
--- no_error_log eval
["crit", "error"]



=== TEST 4: use lines iterator and mix it with file:read("*a")
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local t = {}

            for line in file:lines() do
                t[#t + 1] = line
                if #t == 3 then
                    break
                end
            end

            local data, err = file:read("*a")
            assert(data)
            assert(err == nil)
            t[#t + 1] = data

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local name = ngx.config.prefix() .. "/conf/nginx.conf"
            local file = io.open(name)
            local t2 = {}
            for line in file:lines() do
                t2[#t2 + 1] = line
                if #t2 == 3 then
                    break
                end
            end

            t2[#t2 + 1] = file:read("*a")

            assert(table.concat(t) == table.concat(t2))
            ngx.print("data ok")
        }
    }

--- request
GET /t
--- response_body: data ok
--- no_error_log eval
["crit", "error"]



=== TEST 5: use lines iterator on a closed file
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_log_errors on;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local iter = file:lines()

            local line, err = iter()
            assert(line == nil)
            ngx.print(err)
        }
    }

--- request
GET /t
--- response_body: closed
--- grep_error_log: attempt to read a line from a closed file object
--- grep_error_log_out
attempt to read a line from a closed file object
--- no_error_log
[crit]



=== TEST 6: use lines iterator on a file which misses the read permission
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_log_errors on;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "a")
            assert(type(file) == "table")
            assert(err == nil)

            local iter = file:lines()

            local line, err = iter()
            assert(line == nil)
            ngx.print(err)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)
        }
    }

--- request
GET /t
--- response_body: operation not permitted
--- no_error_log eval
["crit", "error"]
