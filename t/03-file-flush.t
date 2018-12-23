use Test::Nginx::Socket::Lua;

repeat_each(1);

plan tests => repeat_each() * (4 * 4);

log_level 'debug';

no_long_string();
run_tests();

__DATA__

=== TEST 1: empty flush
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)

            local n, err = file:flush()
            assert(n)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            ngx.print("OK")

            local prefix = ngx.config.prefix()
            os.execute("rm -f " .. prefix .. "/conf/test.txt")
        }
    }

--- request
GET /t
--- response_body: OK
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



=== TEST 2: native flush
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local _io = io
            local io = require "ngx.io"
            local file, err = io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)

            local data = "Hello, 世界"
            local n, err = file:write(data)
            assert(n == #data)
            assert(err == nil)

            local n, err = file:flush()
            assert(n)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local file = _io.open(name)
            local data = file:read("*a")
            file:close()

            ngx.print(data)

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: Hello, 世界
--- grep_error_log: lua io write
--- grep_error_log_out
lua io write
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



=== TEST 3: flush twice
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local _io = io
            local io = require "ngx.io"
            local file, err = io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)

            local data = "Hello, 世界"
            local n, err = file:write(data)
            assert(n == #data)
            assert(err == nil)

            local n, err = file:flush()
            assert(n)
            assert(err == nil)

            local n, err = file:flush()
            assert(n)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local file = _io.open(name)
            local data = file:read("*a")
            file:close()

            ngx.print(data)

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: Hello, 世界
--- grep_error_log: lua io write
--- grep_error_log_out
lua io write
--- grep_error_log: lua io flush
--- grep_error_log_out
lua io flush
lua io flush
--- grep_error_log: lua io write done and resume
--- grep_error_log_out
lua io write done and resume
--- grep_error_log: lua io flush done and resume
--- grep_error_log_out
lua io flush done and resume
lua io flush done and resume
--- no_error_log
[error]
--- no_error_log
[crit]



=== TEST 4: flush on a closed file handle
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_log_errors on;
        content_by_lua_block {
            local _io = io
            local io = require "ngx.io"
            local file, err = io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)

            local data = "Hello, 世界"
            local n, err = file:write(data)
            assert(n == #data)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local n, err = file:flush()
            assert(not n)
            ngx.print(err)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: closed
--- error_log
attempt to flush data on a closed file object
--- no_error_log
[crit]
