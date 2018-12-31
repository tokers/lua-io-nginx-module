use Test::Nginx::Socket::Lua;

repeat_each(1);

plan tests => repeat_each() * (5 * 5 + 6 * 4);

log_level 'debug';

no_long_string();
run_tests();

__DATA__

=== TEST 1: try to read file but without the read permission
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "a")
            assert(type(file) == "table")
            assert(err == nil)

            local data, err = file:read(123)
            assert(data == nil)
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
["error", "crit"]



=== TEST 2: read file with specified bytes
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_read_buffer_size 1;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local data, err = file:read(123)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/nginx.conf"
            local file = io.open(name, "r")
            local data2 = file:read(123)
            file:close()

            assert(data == data2)
            ngx.print("data ok")
        }
    }

--- request
GET /t
--- response_body: data ok
--- grep_error_log: lua io thread read 1
--- grep_error_log_out eval
"lua io thread read 1\n" x 123
--- no_error_log eval
["error", "crit"]



=== TEST 3: read file with specified bytes and a large buffer
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_read_buffer_size 1000;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local data1, err = file:read(500)
            assert(err == nil)
            local data2, err = file:read(500)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/nginx.conf"
            local file = io.open(name, "r")
            local data3 = file:read(500)
            local data4 = file:read(500)
            file:close()

            assert(data1 == data3)
            assert(data2 == data4)
            ngx.print("data ok")
        }
    }

--- request
GET /t
--- response_body: data ok
--- grep_error_log: lua io thread read 1000
--- grep_error_log_out
lua io thread read 1000
--- no_error_log eval
["error", "crit"]



=== TEST 4: read the whole file and the data can be stuffed in the single buffer
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_read_buffer_size 4096;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local data, err = file:read("*a")
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/nginx.conf"
            local file = io.open(name, "r")
            local data2 = file:read("*a")
            file:close()

            assert(data == data2)
            ngx.print("data ok")
        }
    }

--- request
GET /t
--- response_body: data ok
--- no_error_log eval
["error", "crit"]



=== TEST 5: read the whole file and the data can be stuffed in the single buffer
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_read_buffer_size 2;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local data, err = file:read("*a")
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/nginx.conf"
            local file = io.open(name, "r")
            local data2 = file:read("*a")
            file:close()

            assert(data == data2)
            ngx.print("data ok")
        }
    }

--- request
GET /t
--- response_body: data ok
--- no_error_log eval
["error", "crit"]



=== TEST 6: read some lines with the really really tiny size buffers
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_read_buffer_size 2;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local data_line1, err = file:read("*l")
            assert(err == nil)

            local data_line2, err = file:read()
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/nginx.conf"
            local file = io.open(name, "r")
            local data_line3 = file:read("*l")
            local data_line4 = file:read("*l")
            file:close()

            assert(data_line1 == data_line3)
            assert(data_line2 == data_line4)
            ngx.print("data ok")
        }
    }

--- request
GET /t
--- response_body: data ok
--- no_error_log eval
["error", "crit"]



=== TEST 7: read bytes until eof
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_read_buffer_size 100;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local d = {}
            while true do
                local data, err = file:read(7)
                assert(err == nil)
                assert(data ~= nil)

                if data == "" then
                    break
                end

                d[#d + 1] = data
            end

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/nginx.conf"
            local file = io.open(name, "r")
            local data = file:read("*a")
            file:close()

            assert(data == table.concat(d))

            ngx.print("data ok")
        }
    }

--- request
GET /t
--- response_body: data ok
--- grep_error_log: lua io read eof
--- grep_error_log_out
lua io read eof
--- no_error_log eval
["error", "crit"]



=== TEST 8: read file with mixing the use of read bytes and read lines
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_read_buffer_size 100;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local d = {}

            while true do
                local d1, err = file:read(4)
                assert(d1)
                assert(#d1 <= 4)
                assert(err == nil)

                if d1 == "" then
                    break
                end

                d[#d + 1] = d1

                local d2, err = file:read("*l")
                assert(d2)
                assert(err == nil)
                d[#d + 1] = d2
                d[#d + 1] = "\n"
            end

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/nginx.conf"
            local file = io.open(name, "r")

            assert(table.concat(d) == file:read("*a"))
            file:close()

            ngx.print("data ok")
        }
    }

--- request
GET /t
--- response_body: data ok
--- grep_error_log: lua io read eof
--- grep_error_log_out
lua io read eof
--- no_error_log eval
["error", "crit"]



=== TEST 9: read file with mixing the use of read bytes, read lines and read all
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_read_buffer_size 100;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local d = {}

            local d1, err = file:read(4)
            assert(d1)
            assert(#d1 <= 4)
            assert(err == nil)
            d[#d + 1] = d1

            local d2, err = file:read("*l")
            assert(d2)
            assert(err == nil)
            d[#d + 1] = d2
            d[#d + 1] = "\n"

            local d1, err = file:read(4)
            assert(d1)
            assert(#d1 <= 4)
            assert(err == nil)
            d[#d + 1] = d1

            local d3, err = file:read("*a")
            assert(d3)
            assert(err == nil)
            d[#d + 1] = d3

            local d3, err = file:read("*a")
            assert(d3 == "")
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/nginx.conf"
            local file = io.open(name, "r")

            assert(table.concat(d) == file:read("*a"))
            file:close()

            ngx.print("data ok")
        }
    }

--- request
GET /t
--- response_body: data ok
--- grep_error_log: lua io read eof
--- grep_error_log_out
lua io read eof
--- no_error_log eval
["error", "crit"]



=== TEST 10: read file with bad pattern
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_read_buffer_size 100;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/nginx.conf", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local ok, err = pcall(file.read, file, "bcc")
            assert(ok == false)
            ngx.print(err)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)
        }
    }

--- request
GET /t
--- response_body_like: bad pattern argument: bcc
--- no_error_log eval
["error", "crit"]



=== TEST 11: try to read a closed file
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

            local data, err = file:read("*a")
            assert(data == nil)
            ngx.print(err)
        }
    }

--- request
GET /t
--- response_body: closed
--- grep_error_log: attempt to read data from a closed file object
--- grep_error_log_out
attempt to read data from a closed file object
--- no_error_log eval
["crit"]
