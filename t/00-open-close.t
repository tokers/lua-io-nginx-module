use Test::Nginx::Socket::Lua;

repeat_each(3);

plan tests => repeat_each() * 4 * 13;

log_level 'debug';

no_long_string();
run_tests();

__DATA__

=== TEST 1: ngx.io.open() with nonexistent file
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("foo")
            assert(file == nil)
            ngx.print(err)
        }
    }

--- request
GET /t
--- response_body: no such file or directory
--- grep_error_log: lua io open fd:-1
--- grep_error_log_out
lua io open fd:-1
--- no_error_log
[error]



=== TEST 2: ngx.io.open() with empty open mode
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("foo", "")
            assert(file == nil)
            ngx.print(err)
        }
    }

--- request
GET /t
--- response_body: bad open mode
--- grep_error_log: lua io open mode:""
--- grep_error_log_out
lua io open mode:""
--- no_error_log
[error]



=== TEST 3: ngx.io.open() with invalid open mode
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("foo", "+")
            assert(file == nil)
            ngx.say(err)

            local file, err = io.open("foo", "rr")
            assert(file == nil)
            ngx.say(err)

            local file, err = io.open("foo", "rw")
            assert(file == nil)
            ngx.say(err)

            local file, err = io.open("foo", "rw+")
            assert(file == nil)
            ngx.say(err)

            local file, err = io.open("foo", "+r")
            assert(file == nil)
            ngx.say(err)

            local file, err = io.open("foo", "+w")
            assert(file == nil)
            ngx.say(err)

            local file, err = io.open("foo", "x+")
            assert(file == nil)
            ngx.say(err)
        }
    }

--- request
GET /t
--- response_body
bad open mode
bad open mode
bad open mode
bad open mode
bad open mode
bad open mode
bad open mode
--- grep_error_log eval
qr/lua io open mode:".*"/
--- grep_error_log_out
lua io open mode:"+"
lua io open mode:"rr"
lua io open mode:"rw"
lua io open mode:"rw+"
lua io open mode:"+r"
lua io open mode:"+w"
lua io open mode:"x+"
--- no_error_log
[error]



=== TEST 4: ngx.io.open() with default mode ("r")
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("foo")
            assert(file == nil)
            ngx.say(err)
        }
    }

--- request
GET /t
--- response_body
no such file or directory
--- grep_error_log: lua io open mode:"r"
--- grep_error_log_out
lua io open mode:"r"
--- no_error_log
[error]



=== TEST 5: ngx.io.open() is successful and file is closed by file:close()
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("conf/nginx.conf")
            assert(file ~= nil)
            assert(err == nil)
            assert(type(file) == "table")

            local ok, err = file:close()
            assert(ok ~= nil)
            assert(err == nil)
            ngx.print("OK")
        }
    }

--- request
GET /t
--- response_body: OK
--- grep_error_log: lua io open mode:"r"
--- grep_error_log_out
lua io open mode:"r"
--- grep_error_log: lua io file ctx finalize
--- grep_error_log_out
lua io file ctx finalize
--- no_error_log
[error]



=== TEST 6: ngx.io.open() is success and file is closed by nginx http request cleanup handler 
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("conf/nginx.conf")
            assert(file ~= nil)
            assert(err == nil)
            assert(type(file) == "table")
            ngx.print("OK")
        }
    }

--- request
GET /t
--- response_body: OK
--- grep_error_log: lua io open mode:"r"
--- grep_error_log_out
lua io open mode:"r"
--- grep_error_log: lua io file ctx cleanup
--- grep_error_log_out
lua io file ctx cleanup
--- grep_error_log: lua io file ctx finalize
--- grep_error_log_out
lua io file ctx finalize
--- no_error_log
[error]



=== TEST 7: ngx.io.open() is success and file is closed duplicately
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("conf/nginx.conf")
            assert(file ~= nil)
            assert(err == nil)
            assert(type(file) == "table")

            local ok, err = file:close()
            assert(ok ~= nil)
            assert(err == nil)

            local ok, err = file:close()
            assert(ok == nil)
            assert(err == "closed")

            local ok, err = file:close()
            assert(ok == nil)
            assert(err == "closed")

            ngx.print("OK")
        }
    }

--- request
GET /t
--- response_body: OK
--- grep_error_log: lua io open mode:"r"
--- grep_error_log_out
lua io open mode:"r"
--- grep_error_log: lua io file ctx finalize
--- grep_error_log_out
lua io file ctx finalize
--- no_error_log
[error]
--- no_error_log
lua io file ctx cleanup



=== TEST 8: try to open a nonexistent file with the read-only mode (r)
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("conf/nginx.con", "r")
            assert(file == nil)
            local code = os.execute("test -f " .. ngx.config.prefix() .. "/conf/nginx.con")
            assert(code ~= 0)
            ngx.print(err)
        }
    }

--- request
GET /t
--- response_body: no such file or directory
--- grep_error_log: lua io open mode:"r"
--- grep_error_log_out
lua io open mode:"r"
--- grep_error_log: lua io file ctx cleanup
--- grep_error_log_out
lua io file ctx cleanup
--- grep_error_log: lua io file ctx finalize
--- grep_error_log_out
lua io file ctx finalize
--- no_error_log
[error]



=== TEST 9: open a nonexistent file with the write-only mode (w)
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("conf/nginx.con", "w")
            assert(type(file) == "table")
            assert(err == nil)
            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local code = os.execute("test -f " .. ngx.config.prefix() .. "/conf/nginx.con")
            assert(code == 0)
            code = os.execute("rm -f " .. ngx.config.prefix() .. "/conf/nginx.con")
            ngx.print("OK")
        }
    }

--- request
GET /t
--- response_body: OK
--- grep_error_log: lua io open mode:"w"
--- grep_error_log_out
lua io open mode:"w"
--- grep_error_log: lua io file ctx finalize
--- grep_error_log_out
lua io file ctx finalize
--- no_error_log
[error]
--- no_error_log
lua io file ctx cleanup



=== TEST 10: open a nonexistent file with the read/write mode (r+)
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("conf/nginx.con", "r+")
            assert(file == nil)
            assert(err == "no such file or directory")
            local code = os.execute("test -f " .. ngx.config.prefix() .. "/conf/nginx.con")
            assert(code ~= 0)
            ngx.print("OK")
        }
    }

--- request
GET /t
--- response_body: OK
--- grep_error_log: lua io open mode:"r+"
--- grep_error_log_out
lua io open mode:"r+"
--- no_error_log
[error]



=== TEST 11: open a nonexistent file with the read/write mode (w+)
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("conf/nginx.con", "w+")
            assert(type(file) == "table")
            assert(err == nil)
            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local code = os.execute("test -f " .. ngx.config.prefix() .. "/conf/nginx.con")
            assert(code == 0)
            code = os.execute("rm -f " .. ngx.config.prefix() .. "/conf/nginx.con")
            ngx.print("OK")
        }
    }

--- request
GET /t
--- response_body: OK
--- grep_error_log: lua io open mode:"r+"
--- grep_error_log_out
lua io open mode:"w+"
--- grep_error_log: lua io file ctx finalize
--- grep_error_log_out
lua io file ctx finalize
--- no_error_log
[error]
--- no_error_log
lua io file ctx cleanup


=== TEST 12: open a nonexistent file with the read/write/append mode (a+)
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("conf/nginx.con", "a+")
            assert(type(file) == "table")
            assert(err == nil)
            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local code = os.execute("test -f " .. ngx.config.prefix() .. "/conf/nginx.con")
            assert(code == 0)
            code = os.execute("rm -f " .. ngx.config.prefix() .. "/conf/nginx.con")
            ngx.print("OK")
        }
    }

--- request
GET /t
--- response_body: OK
--- grep_error_log: lua io open mode:"a+"
--- grep_error_log_out
lua io open mode:"a+"
--- grep_error_log: lua io file ctx finalize
--- grep_error_log_out
lua io file ctx finalize
--- no_error_log
[error]
--- no_error_log
lua io file ctx cleanup



=== TEST 13: open a nonexistent file with the append mode (a)
--- main_config
thread_pool default threads=2 max_queue=10;
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("conf/nginx.con", "a")
            assert(type(file) == "table")
            assert(err == nil)
            local ok, err = file:close()
            assert(ok)
            assert(err == nil)

            local code = os.execute("test -f " .. ngx.config.prefix() .. "/conf/nginx.con")
            assert(code == 0)
            code = os.execute("rm -f " .. ngx.config.prefix() .. "/conf/nginx.con")
            ngx.print("OK")
        }
    }

--- request
GET /t
--- response_body: OK
--- grep_error_log: lua io open mode:"a"
--- grep_error_log_out
lua io open mode:"a"
--- grep_error_log: lua io file ctx finalize
--- grep_error_log_out
lua io file ctx finalize
--- no_error_log
[error]
--- no_error_log
lua io file ctx cleanup
