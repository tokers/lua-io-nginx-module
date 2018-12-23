use Test::Nginx::Socket::Lua;

repeat_each(3);

plan tests => repeat_each() * (3 * 6 + 4 * 4 + 8);

log_level 'debug';

no_long_string();
run_tests();

__DATA__

=== TEST 1: empty write
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("conf/test.txt", "a")
            assert(type(file) == "table")
            assert(err == nil)
            local n, err = file:write("")
            assert(n == 0)
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
--- no_error_log
[error]



=== TEST 2: bool write
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)
            local data = true
            local n, err = file:write(data)
            assert(n == 4)
            assert(err == nil)
            data = false
            local n, err = file:write(data)
            assert(n == 5)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local f = io.open(name, "r")
            local data = f:read("*a")
            ngx.print(data)
            f:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: truefalse
--- grep_error_log: lua io thread event handler
--- grep_error_log_out
lua io thread event handler
lua io thread event handler
--- grep_error_log: lua io resume
--- grep_error_log_out
lua io resume
lua io resume
--- grep_error_log: lua io write done and resume
--- grep_error_log_out
lua io write done and resume
lua io write done and resume
--- no_error_log
[error]
--- no_error_log
[crit]



=== TEST 3: nil write
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)
            local data = nil
            local n, err = file:write(data)
            assert(n == 3)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local f = io.open(name, "r")
            local data = f:read("*a")
            ngx.print(data)
            f:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: nil
--- grep_error_log: lua io thread event handler
--- grep_error_log_out
lua io thread event handler
--- grep_error_log: lua io resume
--- grep_error_log_out
lua io resume
--- grep_error_log: lua io write done and resume
--- grep_error_log_out
lua io write done and resume
--- no_error_log
[error]
--- no_error_log
[crit]



=== TEST 3: table write
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)
            local data = {1, 2, 3, "4", "55", "snoopy", "\n"}
            local n, err = file:write(data)
            assert(n == 13)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local f = io.open(name, "r")
            local data = f:read("*a")
            ngx.print(data)
            f:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body
123455snoopy
--- grep_error_log: lua io thread event handler
--- grep_error_log_out
lua io thread event handler
--- grep_error_log: lua io resume
--- grep_error_log_out
lua io resume
--- grep_error_log: lua io write done and resume
--- grep_error_log_out
lua io write done and resume
--- no_error_log
[error]
--- no_error_log
[crit]



=== TEST 4: string, number write
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)
            local n, err = file:write("Hello, ")
            assert(n == 7)
            assert(err == nil)

            local n, err = file:write("World")
            assert(n == 5)
            assert(err == nil)

            local n, err = file:write(12345)
            assert(n == 5)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local f = io.open(name, "r")
            local data = f:read("*a")
            ngx.print(data)
            f:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: Hello, World12345
--- grep_error_log: lua io thread event handler
--- grep_error_log_out
lua io thread event handler
lua io thread event handler
lua io thread event handler
--- grep_error_log: lua io resume
--- grep_error_log_out
lua io resume
lua io resume
lua io resume
--- grep_error_log: lua io write done and resume
--- grep_error_log_out
lua io write done and resume
lua io write done and resume
lua io write done and resume
--- no_error_log
[error]
--- no_error_log
[crit]



=== TEST 5: bad write (bad parameter type)
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)
            local data = { a = 1 }
            local ok, err = pcall(file.write, file, data)
            assert(not ok)
            ngx.print(err)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)
        }
    }

--- request
GET /t
--- response_body eval
qr/.*non-array table found/
--- no_error_log
[error]
--- no_error_log
[crit]



=== TEST 6: try to write but miss the write permission
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
            local n, err = file:write("Hello, ")
            assert(n == nil)
            ngx.print(err)
            local ok, err = file:close()
            assert(ok)
            assert(err == nil)
        }
    }

--- request
GET /t
--- response_body: operation not permitted
--- no_error_log
[error]
--- no_error_log
[crit]



=== TEST 7: append mode
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        rewrite_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "a")
            assert(type(file) == "table")
            assert(err == nil)
            local n, err = file:write("Hello, ")
            assert(n == 7)
            assert(err == nil)
            local ok, err = file:close()
            assert(ok)
            assert(err == nil)
        }

        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "a")
            assert(type(file) == "table")
            assert(err == nil)
            local n, err = file:write("World")
            assert(n == 5)
            assert(err == nil)
            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local f = io.open(name, "r")
            local data = f:read("*a")
            ngx.print(data)
            f:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: Hello, World
--- grep_error_log: lua io thread event handler
--- grep_error_log_out
lua io thread event handler
lua io thread event handler
--- grep_error_log: lua io write done and resume 
--- grep_error_log_out
lua io write done and resume
lua io write done and resume
--- grep_error_log: lua io open mode:"a"
--- grep_error_log_out
lua io open mode:"a"
lua io open mode:"a"
--- no_error_log
[error]
--- no_error_log
[crit]



=== TEST 8: append mode first, then the normal write mode follows
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        rewrite_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "a")
            assert(type(file) == "table")
            assert(err == nil)
            local n, err = file:write("Hello, ")
            assert(n == 7)
            assert(err == nil)
            local ok, err = file:close()
            assert(ok)
            assert(err == nil)
        }

        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)
            local n, err = file:write("World")
            assert(n == 5)
            assert(err == nil)
            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local f = io.open(name, "r")
            local data = f:read("*a")
            ngx.print(data)
            f:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body eval
"World, "
--- grep_error_log: lua io thread event handler
--- grep_error_log_out
lua io thread event handler
lua io thread event handler
--- grep_error_log: lua io write done and resume 
--- grep_error_log_out
lua io write done and resume
lua io write done and resume
--- grep_error_log: lua io open mode:"a"
--- grep_error_log_out
lua io open mode:"a"
--- grep_error_log: lua io open mode:"w"
--- grep_error_log_out
lua io open mode:"w"
--- no_error_log
[error]
--- no_error_log
[crit]



=== TEST 9: write multiple times with varying the write stuff's size
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)
            local t = {}
            for i = 1, 256 do
                local n, err = file:write("a")
                assert(n == 1)
                assert(err == nil)
                t[#t + 1] = "a"
            end

            for i = 1, 64 do
                local n, err = file:write("b")
                assert(n == 1)
                assert(err == nil)
                t[#t + 1] = "b"
            end

            for i = 1, 32 do
                local n, err = file:write("c")
                assert(n == 1)
                assert(err == nil)
                t[#t + 1] = "c"
            end

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local f = io.open(name, "r")
            local data = f:read("*a")
            f:close()

            os.execute("rm -f " .. name)

            assert(data == table.concat(t))
            ngx.log(ngx.WARN, data)
            ngx.print("OK")
        }
    }

--- request
GET /t
--- response_body: OK
--- no_error_log
[error]
--- no_error_log
[crit]



=== TEST 10: execute file:write operations in subrequest
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local res = ngx.location.capture("/write")
            ngx.status = res.status
            ngx.print(res.body)
        }
    }
    location /write {
        internal;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w")
            assert(type(file) == "table")
            assert(err == nil)

            local n, err = file:write("Hello, ")
            assert(n == 7)
            assert(err == nil)

            local n, err = file:write("World")
            assert(n == 5)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local f = io.open(name, "r")
            local data = f:read("*a")
            f:close()

            os.execute("rm -f " .. name)
            ngx.print(data)
        }
    }

--- request
GET /t
--- response_body: Hello, World
--- no_error_log
[error]
--- no_error_log
[crit]



=== TEST 10: execute file:write operations in other light thread
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local f = function()
                local ngx_io = require "ngx.io"
                local file, err = ngx_io.open("conf/test.txt", "w")
                assert(type(file) == "table")
                assert(err == nil)

                local n, err = file:write("Hello, ")
                assert(n == 7)
                assert(err == nil)

                local n, err = file:write("World")
                assert(n == 5)
                assert(err == nil)

                local ok, err = file:close()
                assert(ok)
                assert(err == nil)
            end

            local co = ngx.thread.spawn(f)

            local ok = ngx.thread.wait(co)
            assert(ok)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local f = io.open(name, "r")
            local data = f:read("*a")
            f:close()

            os.execute("rm -f " .. name)
            ngx.print(data)
        }
    }

--- request
GET /t
--- response_body: Hello, World
--- no_error_log
[error]
--- no_error_log
[crit]
