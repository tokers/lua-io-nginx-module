use Test::Nginx::Socket::Lua;

repeat_each(3);

plan tests => repeat_each() * (5 * 4 + 1);

log_level 'debug';

no_long_string();
run_tests();

__DATA__

=== TEST 1: native write cache
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_log_errors on;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)

            local n, err = file:write("Hello")
            assert(n == 5)
            assert(err == nil)

            local n, err = file:write(", World")
            assert(n == 7)
            assert(err == nil)

            local ok, err = file:flush()
            assert(ok)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local file = io.open(name, "r")
            ngx.print(file:read("*a"))
            file:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: Hello, World
--- grep_error_log: lua io write cache
--- grep_error_log_out
lua io write cache
lua io write cache
--- grep_error_log: lua io flush
--- grep_error_log_out
lua io flush
--- grep_error_log: lua io flush done and resume
--- grep_error_log_out
lua io flush done and resume
--- no_error_log
[error]
--- no_error_log
[crit]



=== TEST 2: write cache and through alternately
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_log_errors on;
        lua_io_write_buffer_size 5;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)

            -- cache
            local n, err = file:write("Hello")
            assert(n == 5)
            assert(err == nil)

            -- through
            local n, err = file:write(",")
            assert(n == 1)
            assert(err == nil)

            -- cache
            local n, err = file:write(" Wor")
            assert(n == 4)
            assert(err == nil)

            -- through
            local n, err = file:write("ld")
            assert(n == 2)
            assert(err == nil)

            local ok, err = file:flush()
            assert(ok)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local file = io.open(name, "r")
            ngx.print(file:read("*a"))
            file:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: Hello, World
--- grep_error_log: lua io write cache
--- grep_error_log_out
lua io write cache
lua io write cache
--- grep_error_log: lua io write through
--- grep_error_log_out
lua io write through
--- grep_error_log: lua io flush
--- grep_error_log_out
lua io flush
--- grep_error_log: lua io write done and resume
--- grep_error_log_out
lua io write done and resume
--- grep_error_log: lua io flush done and resume
--- grep_error_log_out
lua io flush done and resume
--- no_error_log
[error]
--- no_error_log
[crit]


=== TEST 3: file flush while closing
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_log_errors on;
        lua_io_write_buffer_size 12;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)

            -- cache
            local n, err = file:write("Hello")
            assert(n == 5)
            assert(err == nil)

            -- cache
            local n, err = file:write(",")
            assert(n == 1)
            assert(err == nil)

            -- cache
            local n, err = file:write(" Wor")
            assert(n == 4)
            assert(err == nil)

            -- cache
            local n, err = file:write("ld")
            assert(n == 2)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local f = io.open(name, "r")
            assert(f:read("*a") == "")
            f:close()

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local file = io.open(name, "r")
            ngx.print(file:read("*a"))
            file:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: Hello, World
--- grep_error_log: lua io write cache
--- grep_error_log_out
lua io write cache
lua io write cache
lua io write cache
lua io write cache
--- grep_error_log: lua io flush
--- grep_error_log_out
lua io flush
--- no_error_log
lua io write done and resume
--- grep_error_log: lua io flush done and resume
--- grep_error_log_out
lua io flush done and resume
--- grep_error_log: lua io close flushing
--- grep_error_log_out
lua io close flushing
--- grep_error_log: lua io file ctx finalize
--- grep_error_log_out
lua io file ctx finalize
--- no_error_log
[error]
--- no_error_log
[crit]



=== TEST 4: write data exceeds the buffer size
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_log_errors on;
        lua_io_write_buffer_size 8;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)

            -- cache
            local n, err = file:write("Hello")
            assert(n == 5)
            assert(err == nil)

            -- through
            local n, err = file:write(", World")
            assert(n == 7)
            assert(err == nil)

            -- cache
            local n, err = file:write("This is")
            assert(n == 7)
            assert(err == nil)

            -- through
            local n, err = file:write("a beautiful age")
            assert(n == 15)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local file = io.open(name, "r")
            ngx.print(file:read("*a"))
            file:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: Hello, WorldThis isa beautiful age
--- grep_error_log: lua io write cache
--- grep_error_log_out
lua io write cache
lua io write cache
--- grep_error_log: lua io write through
--- grep_error_log_out
lua io write through
lua io write through
--- grep_error_log: lua io thread write chain
--- grep_error_log_out
lua io thread write chain
lua io thread write chain
--- grep_error_log: lua io write done and resume
--- grep_error_log_out
lua io write done and resume
lua io write done and resume
--- grep_error_log: lua io file ctx finalize
--- grep_error_log_out
lua io file ctx finalize
--- no_error_log
[error]
--- no_error_log
[crit]
--- no_error_log: lua io close flushing



=== TEST 5: 4096 size buffer
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_log_errors on;
        lua_io_write_buffer_size 4096;
        content_by_lua_block {
            local new_tab = require "table.new"
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)

            local total = 5050
            while true do
                local size = math.random(1, total)
                total = total - size

                local t = new_tab(size, 0)
                for i = 1, size do
                    t[i] = string.char(math.random(48, 122))
                end

                local n, err = file:write(t)
                assert(n == size)
                assert(err == nil)

                if total == 0 then
                    break
                end
            end

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            ngx.print("OK")
        }
    }

--- request
GET /t
--- response_body: OK
--- grep_error_log: lua io write through
--- grep_error_log_out
lua io write through
--- grep_error_log: lua io thread write chain
--- grep_error_log_out
lua io thread write chain
--- error_log: lua io close flushing
--- grep_error_log: lua io write done and resume
--- grep_error_log_out
lua io write done and resume
--- grep_error_log: lua io file ctx finalize
--- grep_error_log_out
lua io file ctx finalize
--- no_error_log
[error]
--- no_error_log
[crit]
