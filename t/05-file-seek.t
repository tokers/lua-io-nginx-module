use Test::Nginx::Socket::Lua;

repeat_each(3);

plan tests => repeat_each() * (6 * 3 + 5 * 14);

log_level 'debug';

no_long_string();
run_tests();

__DATA__

=== TEST 1: file seek to the head with append mode and always write through
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 0;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "a")
            assert(type(file) == "table")
            assert(err == nil)

            local n, err = file:write("Hello")
            assert(n == 5)
            assert(err == nil)

            local n, err = file:write(", World")
            assert(n == 7)
            assert(err == nil)

            local offset, err = file:seek("set", 1)
            assert(offset == 1)
            assert(err == nil)

            local n, err = file:write(". Word from tokers")
            assert(n == 18)
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
--- response_body: Hello, World. Word from tokers
--- grep_error_log: lua io seek whence:0 offset:1
--- grep_error_log_out
lua io seek whence:0 offset:1
--- no_error_log eval
["error", "crit"]



=== TEST 2: file seek to the head with write only mode and combined with write back cache
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 16;
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

            local offset, err = file:seek("set", 7)
            assert(offset == 7)
            assert(err == nil)

            local n, err = file:write("friend")
            assert(n == 6)
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
--- response_body: Hello, friend
--- grep_error_log: lua io seek whence:0 offset:7
--- grep_error_log_out
lua io seek whence:0 offset:7
--- error_log: lua io seek saved co ctx
--- no_error_log eval
["error", "crit"]



=== TEST 3: file seek to the current position
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 16;
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

            local offset, err = file:seek("cur", 0)
            assert(offset == 12)
            assert(err == nil)

            local n, err = file:write("friend")
            assert(n == 6)
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
--- response_body: Hello, Worldfriend
--- grep_error_log: lua io seek whence:1 offset:0
--- grep_error_log_out
lua io seek whence:1 offset:0
--- error_log: lua io seek saved co ctx
--- no_error_log eval
["error", "crit"]



=== TEST 4: file seek to the current position plus negative offset
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 16;
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

            local offset, err = file:seek("cur", -1)
            assert(offset == 11)
            assert(err == nil)

            local n, err = file:write("friend")
            assert(n == 6)
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
--- response_body: Hello, Worlfriend
--- grep_error_log: lua io seek whence:1 offset:-1
--- grep_error_log_out
lua io seek whence:1 offset:-1
--- error_log: lua io seek saved co ctx
--- no_error_log eval
["error", "crit"]



=== TEST 5: file seek to the current position plus negative offset and the ultimate offset is negative
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 16;
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

            local offset, err = file:seek("cur", -100)
            assert(offset == nil)
            ngx.say(err)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local file = io.open(name, "r")
            ngx.say(file:read("*a"))
            file:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body
invalid argument
Hello, World
--- grep_error_log: lua io seek whence:1 offset:-100
--- grep_error_log_out
lua io seek whence:1 offset:-100
--- no_error_log eval
["error", "crit"]



=== TEST 6: file seek to the current position plus positive offset and generate the file hole
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 16;
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

            local offset, err = file:seek("cur", 3)
            assert(offset == 15)
            assert(err == nil)

            local n, err = file:write(" after the hole")
            assert(n == 15)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local file = io.open(name, "r")
            local data = file:read("*a")
            ngx.print("data length: ", #data)
            file:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: data length: 30
--- grep_error_log: lua io seek whence:1 offset:3
--- grep_error_log_out
lua io seek whence:1 offset:3
--- no_error_log eval
["error", "crit"]



=== TEST 7: file seek to the end of file plus a negative offset (backward)
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 16;
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

            local offset, err = file:seek("end", -1)
            assert(offset == 11)
            assert(err == nil)

            local n, err = file:write("D")
            assert(n == 1)
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
--- response_body: Hello, WorlD
--- grep_error_log: lua io seek whence:2 offset:-1
--- grep_error_log_out
lua io seek whence:2 offset:-1
--- no_error_log eval
["error", "crit"]



=== TEST 8: file seek to the end of file plus a negative offset and result in the final offset is negative
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 16;
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

            local offset, err = file:seek("end", -1111)
            assert(offset == nil)
            ngx.say(err)

            local n, err = file:write(". I'm just go ahead~")
            assert(n == 20)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local file = io.open(name, "r")
            ngx.say(file:read("*a"))
            file:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body
invalid argument
Hello, World. I'm just go ahead~
--- grep_error_log: lua io seek whence:2 offset:-1111
--- grep_error_log_out
lua io seek whence:2 offset:-1111
--- no_error_log eval
["error", "crit"]



=== TEST 9: file seek to the end of file plus a positive offset and generate the file hole
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 16;
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

            local offset, err = file:seek("end", 31)
            assert(offset == 43)
            assert(err == nil)

            local n, err = file:write(". I'm just go ahead~")
            assert(n == 20)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local file = io.open(name, "r")
            ngx.print("data length: ", #file:read("*a"))
            file:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: data length: 63
--- grep_error_log: lua io seek whence:2 offset:31
--- grep_error_log_out
lua io seek whence:2 offset:31
--- no_error_log eval
["error", "crit"]



=== TEST 10: file seek to a fixed postition
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 16;
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

            local offset, err = file:seek("set", 8)
            assert(offset == 8)
            assert(err == nil)

            local n, err = file:write(". I'm just go ahead~")
            assert(n == 20)
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
--- response_body: Hello, W. I'm just go ahead~
--- grep_error_log: lua io seek whence:0 offset:8
--- grep_error_log_out
lua io seek whence:0 offset:8
--- no_error_log eval
["error", "crit"]



=== TEST 11: file seek to a fixed postition and generate a file hole
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 16;
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

            local offset, err = file:seek("set", 88)
            assert(offset == 88)
            assert(err == nil)

            local n, err = file:write(". I'm just go ahead~")
            assert(n == 20)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            local file = io.open(name, "r")
            ngx.print("data length: ", #file:read("*a"))
            file:close()

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: data length: 108
--- grep_error_log: lua io seek whence:0 offset:88
--- grep_error_log_out
lua io seek whence:0 offset:88
--- no_error_log eval
["error", "crit"]



=== TEST 12: buffered read file and do seek
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 16;
        lua_io_read_buffer_size 256;
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

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local file, err = ngx_io.open("conf/test.txt", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local data, err = file:read(6)
            ngx.print(data)
            assert(err == nil)

            local offset, err = file:seek("cur", -3)
            assert(offset == 3)
            assert(err == nil)

            local data, err = file:read("*a")
            ngx.print(data)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)
        }
    }

--- request
GET /t
--- response_body: Hello,lo, World
--- grep_error_log: lua io seek drain read chain
--- grep_error_log_out
lua io seek drain read chain
--- no_error_log eval
["error", "crit"]



=== TEST 13: buffered read file and do seek, to a fixed position
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 16;
        lua_io_read_buffer_size 256;
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

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local file, err = ngx_io.open("conf/test.txt", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local data, err = file:read(6)
            ngx.print(data)
            assert(err == nil)

            local offset, err = file:seek("set", 1)
            assert(offset == 1)
            assert(err == nil)

            local data, err = file:read(4)
            ngx.print(data)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: Hello,ello
--- grep_error_log: lua io seek drain read chain
--- grep_error_log_out
lua io seek drain read chain
--- no_error_log eval
["error", "crit"]



=== TEST 14: buffered read file and do seek, to the position where it is relative to the end of file
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 16;
        lua_io_read_buffer_size 256;
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

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local file, err = ngx_io.open("conf/test.txt", "r")
            assert(type(file) == "table")
            assert(err == nil)

            local data, err = file:read(6)
            ngx.print(data)
            assert(err == nil)

            local offset, err = file:seek("end", -1)
            assert(offset == 11)
            assert(err == nil)

            local data, err = file:read(4)
            ngx.print(data)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: Hello,d
--- grep_error_log: lua io seek drain read chain
--- grep_error_log_out
lua io seek drain read chain
--- no_error_log eval
["error", "crit"]



=== TEST 15: mix non-buffered write with buffered read (switch them with calling seek)
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 0;
        lua_io_read_buffer_size 256;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w+")
            assert(type(file) == "table")
            assert(err == nil)

            local n, err = file:write("Hello")
            assert(n == 5)
            assert(err == nil)

            local n, err = file:write(", World")
            assert(n == 7)
            assert(err == nil)

            local offset, err = file:seek("cur", -1)
            assert(offset == 11)
            assert(err == nil)

            local data, err = file:read(6)
            ngx.print(data)
            assert(err == nil)

            local offset, err = file:seek("end", 0)
            assert(offset == 12)
            assert(err == nil)

            local n, err = file:write("!")
            assert(n == 1)
            assert(err == nil)

            local offset, err = file:seek("set", 0)
            assert(offset == 0)
            assert(err == nil)

            local data, err = file:read("*a")
            assert(err == nil)
            ngx.print(data)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: dHello, World!
--- grep_error_log: lua io seek drain read chain
--- grep_error_log_out
lua io seek drain read chain
--- no_error_log eval
["error", "crit"]



=== TEST 16: mix buffered write with read (switch them with calling seek)
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 10;
        lua_io_read_buffer_size 256;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "w+")
            assert(type(file) == "table")
            assert(err == nil)

            local n, err = file:write("Hello")
            assert(n == 5)
            assert(err == nil)

            local n, err = file:write(", World")
            assert(n == 7)
            assert(err == nil)

            local offset, err = file:seek("cur", -1)
            assert(offset == 11)
            assert(err == nil)

            local data, err = file:read(6)
            ngx.print(data)
            assert(err == nil)

            local offset, err = file:seek("end", 0)
            assert(offset == 12)
            assert(err == nil)

            local n, err = file:write("!")
            assert(n == 1)
            assert(err == nil)

            local offset, err = file:seek("set", 0)
            assert(offset == 0)
            assert(err == nil)

            local data, err = file:read("*a")
            assert(err == nil)
            ngx.print(data)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local prefix = ngx.config.prefix()
            local name = prefix .. "/conf/test.txt"

            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: dHello, World!
--- grep_error_log: lua io seek drain read chain
--- grep_error_log_out
lua io seek drain read chain
--- no_error_log eval
["error", "crit"]



=== TEST 17: mix buffered write with read (switch them with seek explicitly), and open with append mode
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        lua_io_write_buffer_size 100;
        lua_io_read_buffer_size 256;
        content_by_lua_block {
            local ngx_io = require "ngx.io"
            local file, err = ngx_io.open("conf/test.txt", "a+")
            assert(type(file) == "table")
            assert(err == nil)

            local n, err = file:write("Hello")
            assert(n == 5)
            assert(err == nil)

            local n, err = file:write(", World")
            assert(n == 7)
            assert(err == nil)

            local offset, err = file:seek("cur", -10)
            assert(offset == 2)
            assert(err == nil)

            local n, err = file:write(", again!")
            assert(n == 8)
            assert(err == nil)

            local offset, err = file:seek("set", 0)
            assert(offset == 0)
            assert(err == nil)

            local data, err = file:read(6)
            assert(err == nil)
            ngx.print(data)

            local offset, err = file:seek("set", 8)
            assert(offset == 8)
            assert(err == nil)

            local n, err = file:write("!")
            assert(n == 1)
            assert(err == nil)

            local offset, err = file:seek("set", 4)
            assert(offset == 4)
            assert(err == nil)

            local data, err = file:read("*a")
            assert(err == nil)
            ngx.print(data)

            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local name = ngx.config.prefix() .. "/conf/test.txt"
            os.execute("rm -f " .. name)
        }
    }

--- request
GET /t
--- response_body: Hello,o, World, again!!
--- grep_error_log: lua io seek drain read chain
--- grep_error_log_out
lua io seek drain read chain
--- no_error_log eval
["error", "crit"]
