use Test::Nginx::Socket::Lua;

repeat_each(3);

plan tests => repeat_each() * 16;

log_level 'debug';

no_long_string();
run_tests();

__DATA__

=== TEST 1: thread pool not found 
--- config
    server_tokens off;
    location /t {
        content_by_lua_block {
            local io = require "ngx.io"
            local ok, err = pcall(io.open, "conf/nginx.conf")
            assert(not ok)
            ngx.print(err)
        }
    }

--- request
GET /t
--- response_body: no thread pool found
--- grep_error_log eval: qr/lua io use thread pool ".*?"/
--- grep_error_log_out
lua io use thread pool "default"
--- no_error_log
[error]



=== TEST 2: complex thread pool and use it
--- main_config
thread_pool alex threads=1 max_queue=1;
--- config
    server_tokens off;
    location /t {
        set $n1 a;
        set $n2 l;
        lua_io_thread_pool ${n1}${n2}ex;
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("conf/nginx.conf")
            assert(type(file) == "table")
            assert(err == nil)
            local ok, err = file:close()
            assert(ok ~= nil)
            assert(err == nil)
            ngx.print("OK")
        }
    }

--- request
GET /t
--- response_body: OK
--- grep_error_log eval: qr/lua io use thread pool ".*?"/
--- grep_error_log_out
lua io use thread pool "alex"
--- no_error_log
[error]



=== TEST 3: not found a defined thread pool 
--- main_config
thread_pool alex threads=1 max_queue=1;
--- config
    server_tokens off;
    location /t {
        set $n1 a;
        set $n2 l;
        lua_io_thread_pool $n1$n2;
        content_by_lua_block {
            local io = require "ngx.io"
            local ok, err = pcall(io.open, "conf/nginx.conf")
            assert(not ok)
            ngx.print(err)
        }
    }

--- request
GET /t
--- response_body: no thread pool found
--- grep_error_log eval: qr/lua io use thread pool ".*?"/
--- grep_error_log_out
lua io use thread pool "al"
--- no_error_log
[error]



=== TEST 4: use a trivial thread pool
--- main_config
thread_pool alex threads=1 max_queue=1;
--- config
    server_tokens off;
    location /t {
        lua_io_thread_pool alex;
        content_by_lua_block {
            local io = require "ngx.io"
            local file, err = io.open("conf/nginx.conf")
            assert(type(file) == "table")
            assert(err == nil)
            local ok, err = file:close()
            assert(ok ~= nil)
            assert(err == nil)
            ngx.print("OK")
        }
    }

--- request
GET /t
--- response_body: OK
--- grep_error_log eval: qr/lua io use thread pool ".*?"/
--- grep_error_log_out
lua io use thread pool "alex"
--- no_error_log
[error]
