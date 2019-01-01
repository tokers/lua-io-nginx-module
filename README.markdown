# Name

lua-io-nginx-module - Nginx C module to take over the Lua file operations. It's based on Nginx's thread pool.

![Build Status](https://travis-ci.org/tokers/lua-io-nginx-module.svg?branch=master) [![License](https://img.shields.io/badge/License-BSD%202--Clause-orange.svg)](https://github.com/tokers/lua-io-nginx-module/blob/master/LICENSE)

# Table of Contents

* [Name](#name)
* [Status](#status)
* [Synopsis](#synopsis)
* [Description](#description)
* [Prerequisites](#prerequisites)
* [Directives](#directives)
  * [lua_io_thread_pool](#lua_io_thread_pool)
  * [lua_io_log_errors](#lua_io_log_errors)
  * [lua_io_read_buffer_size](#lua_io_read_buffer_size)
  * [lua_io_write_buffer_size](#lua_io_write_buffer_size)
* [APIs](#apis)
  * [ngx_io.open](#ngx_ioopen)
  * [file:read](#fileread)
  * [file:write](#filewrite)
  * [file:seek](#fileseek)
  * [file:flush](#fileflush)
  * [file:close](#fileclose)
* [Author](#author)
    
# Status

This Nginx module is currently considered experimental.

# Synopsis

```nginx
# configure a thread pool.
thread_pool default threads=16 max_queue=65536;

http {
  
  ...
    
  server {
      listen *:8080;
      lua_io_thread_pool default;
      location /read_by_line {
          lua_io_read_buffer_size 8192;
          content_by_lua_block {
              local ngx_io = require "ngx.io"
              local filename = "/tmp/foo.txt"
              local file, err = ngx_io.open(filename, "r")
              assert(file and not err)

              for line in file:lines() do
                  ngx.say(line)
              end

              local ok, err = file:close()
              assert(ok and not err)
          }
      }

      location /read_by_bytes {
          content_by_lua_block {
              local ngx_io = require "ngx.io"
              local filename = "/tmp/foo.txt"

              local file, err = ngx_io.open(filename, "r")
              assert(file and not err)

              while true do
                  local data, err = file:read(512)
                  if err ~= nil then
                      ngx.log(ngx.ERR, "file:read() error: ", err)
                      break
                  end

                  if data == nil then
                      break
                  end

                  ngx.print(data)
              end

              local ok, err = file:close()
              assert(ok and not err)
          }
      }
  }
}
```

# Description

This Nginx C module provides the basic file operations APIs with a mechanism that never block Nginx's event loop.
For now, it leverages Nginx's thread pool. I/O operations might be offloaded to one of the free thread,
and current Lua thread will be yield until the I/O operations is done, in the meantime, Nginx can in turn process other events.

It's worth to mention that the cost time of a single I/O operation won't be reduced, it just transfer from the main thread (the one executes the event loop) to another exclusive thread.
Indeed, the overhead might be a little higher, because of the extra tasks transferring, lock waiting, Lua thread resume (and can only resume in the next event loop) and so forth. Nevertheless, after the offloading, the main thread doesn't block due to the I/O operation, and this is the fundamental advantage compared with the native Lua I/O library.

The APIs are similar with the [Lua I/O library](https://www.lua.org/pil/21.html), but with the totally different internal implementations, it doesn't use the stream file facilities in libc (but keep trying to be consistent with it), the buffer is maintained inside this module, and follows Cosocket's internals.

If you want to learn more about Nginx's thread pool, just try this [article](https://www.nginx.com/blog/thread-pools-boost-performance-9x/).

[Back to TOC](#table-of-contents)

# Prerequisites

This Nginx C module relies on the [lua-nginx-module](https://github.com/openresty/lua-nginx-module) and the thread pool option, so configure your Nginx branch like the follow way:

```bash
./auto/configure --with-threads --add-module=/path/to/lua-nginx-module/ --add-module=/path/to/lua-io-nginx-module/
```

Due to some existing limitations in ngx_lua, you must place the `--add-module=/path/to/lua-nginx-module/` **before** `--add-module=/path/to/lua-io-nginx-module/`.
This limitations might be eliminated in the future if ngx_lua exposes more C functions and data structures.

# Directives

## lua_io_thread_pool

**Syntax:** *lua_io_thread_pool thread-pool-name;*  
**Default:** *lua_io_thread_pool default;*  
**Context:** *http, server, location, if in location*  

Specifies which thread pool should be used, note you should configure the thread pool by the `thread_pool` direction.

## lua_io_log_errors

**Syntax:** *lua_io_log_errors on | off*  
**Default:** *lua_io_log_errors off;*  
**Context:** *http, server, location, if in location*  

Specifies whether logs the error message when failures occur. If you are already doing proper error handling and logging in your Lua code, then it is recommended to turn this directive off to prevent data flushing in your nginx error log files (which is usually rather expensive).

## lua_io_read_buffer_size

**Syntax:** *lua_io_read_buffer_size <size>*  
**Default:** *lua_io_read_buffer_size 4k/8k;*  
**Context:** *http, server, location, if in location*  

Specifies the buffer size used by the reading operations.

## lua_io_write_buffer_size

**Syntax:** *lua_io_write_buffer_size <size>*  
**Default:** *lua_io_write_buffer_size 4k/8k;*  
**Context:** *http, server, location, if in location*  

Specifies the buffer size used by the writing operations.

Data will be cached in this buffer until overflow or you call these "flushable" APIs (like `file:flush`) explicitly.

You can set this value to zero and always "write through the cache".

# APIs

To use these APIs, just import this module by:

```lua
local ngx_io = require "ngx.io"
```

## ngx_io.open

**Syntax:** *local file, err = ngx_io.open(filename [, mode])*

Opens a file and returns the corresponding file object. In case of failure, `nil` and a Lua string will be given, which describes the error reason.

The first parameter is the target file name that would be opened. When `filename` is a relative path, the nginx prefix will be placed in front of `filename`, for instance, if the `filename` is "foo.txt", and you start your Nginx by `nginx -p /tmp`, then file `/tmp/foo.txt` will be opened.

The second optional parameter, specifes the open mode, can be any of the following:
    
* `"r"`: read mode (the default);
* `"w"`: write mode;
* `"a"`: append mode;
* `"r+`": update mode, all previous data is preserved;
* `"w+`": update mode, all previous data is erased (file will be truncated);
* `"a+`": append update mode, previous data is preserved, writing is only allowed at the end of file.

## file:read

## file:write

## file:seek

## file:flush

## file:lines

## file:close

# Author

Alex Zhang (张超) zchao1995@gmail.com, UPYUN Inc.

[Back to TOC](#table-of-contents)
