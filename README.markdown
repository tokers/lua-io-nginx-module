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

      location /write {
          content_by_lua_block {
              local ngx_io = require "ngx.io"

              local length = tonumber(ngx.var.http_content_length)
              if not length then
                  return ngx.exit(200)
              end

              local sock, err = ngx.req.socket()
              if not sock then
                  ngx.log(ngx.ERR, "ngx.req.socket() failed: ", err)
                  return ngx.exit(500)
              end

              local file, err = ngx_io.open("/tmp/foo.txt", "w")
              assert(file and not err)

              repeat
                  local size = length > 4096 and 4096 or length
                  length = length - size
                  local data, err = sock:receive(size)
                  if err then
                      ngx.log(ngx.ERR, "sock:receive() failed: ", err)
                      return
                  end

                  local bytes, err = file:write(data)
                  assert(bytes == size)
                  assert(not err)
              until length == 0

              local ok, err = file:close()
              assert(ok and not err)

              return ngx.exit(200)
       }
  }
}
```

# Description

This Nginx C module provides the basic file operations APIs with a mechanism that never block Nginx's event loop.
For now, it leverages Nginx's thread pool, I/O operations might be offloaded to one of the free threads,
and current Lua coroutine (Light Thread) will be yield until the I/O operations is done, in the meantime, Nginx in turn processes other events.

It's worth to mention that the cost time of a single I/O operation won't be reduced, it was just transferred from the main thread (the one executes the event loop) to another exclusive thread.
Indeed, the overhead might be a little higher, because of the extra tasks transferring, lock waiting, Lua coroutine resumption (and can only be resumed in the next event loop) and so forth. Nevertheless, after the offloading, the main thread doesn't block due to the I/O operation, and this is the fundamental advantage compared with the native Lua I/O library.

The APIs are similar with the [Lua I/O library](https://www.lua.org/pil/21.html), but with the totally different internal implementations, it doesn't use the stream file facilities in libc (but keep trying to be consistent with it), the buffer is maintained inside this module, and follows Cosocket's internals.

If you want to learn more about Nginx's thread pool, just try this [article](https://www.nginx.com/blog/thread-pools-boost-performance-9x/).

[Back to TOC](#table-of-contents)

# Prerequisites

This Nginx C module relies on the [lua-nginx-module](https://github.com/openresty/lua-nginx-module) and the thread pool option, so configure your Nginx branch like the follow way:

```bash
./auto/configure --with-threads --add-module=/path/to/lua-nginx-module/ --add-module=/path/to/lua-io-nginx-module/
```

Due to some existing limitations in ngx_lua, you must place the `--add-module=/path/to/lua-nginx-module/` **before** `--add-module=/path/to/lua-io-nginx-module/`.
These limitations might be eliminated in the future if ngx_lua exposes more C functions and data structures.

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
**Context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;*

Opens a file and returns the corresponding file object. In case of failure, `nil` and a Lua string will be given, which describes the error reason.

The first parameter is the target file name that would be opened. When `filename` is a relative path, the nginx prefix will be placed in front of `filename`, for instance, if the `filename` is "foo.txt", and you start your Nginx by `nginx -p /tmp`, then file `/tmp/foo.txt` will be opened.

The second optional parameter, specifes the open mode, can be any of the following:
    
* `"r"`: read mode (the default);
* `"w"`: write mode;
* `"a"`: append mode;
* `"r+"`: update mode, all previous data is preserved;
* `"w+"`: update mode, all previous data is erased (file will be truncated);
* `"a+"`: append update mode, previous data is preserved, writing is only allowed at the end of file.

## file:read

**Syntax:** *local data, err = file:read([format])*
**Context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;*

Reads some data from the file, according to the given formats, which specify what to read.

The available formats are:

* `"*a"`: reads the whole file, starting at the current position. On end of file, it returns `nil`.
* `"*l"`: reads the next line (skipping the end of line), returning `nil` on end of file. This is the default format.
* number: reads a string with up to this number of characters, returning `nil` on end of file. If number is zero, it reads nothing and returns an empty string, or `nil` on end of file.

A Lua string will be returned as the expected data; In case of failure, `nil` and an error message will be given.

This method is a synchronous operation and is 100% nonblocking.

## file:write

**Syntax:** *local n, err = file:write(data)*
**Context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;*

Writes data to the file. Note `data` might be cached in the write buffer if suitable.

the number of wrote bytes will be returned; In case of failure, `0` and an error message will be given.

This method is a synchronous operation and is 100% nonblocking.

**CAUTION:** If you opened the file with the append mode, then writing is only allowed at the end of file. The adjustment of the file offset and the write operation are performed as an atomic step, which is guaranteed by the `write` and `writev` system calls.

## file:seek

**Syntax:** *local offset, err = file:seek([whence] [, offset])*
**Context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;*


Sets and gets the file position, measured from the beginning of the file, to the position given by `offset` plus a base specified by the string `whence`, as follows:

* "set": base is position 0 (beginning of the file);
* "cur": base is current position;
* "end": base is end of file;

In case of success, function seek returns the final file position, measured in bytes from the beginning of the file. If this method fails, it returns nil, plus a string describing the error.

The default value for `whence` is "cur", and for `offset` is `0`. Therefore, the call file:seek() returns the current file position, without changing it; the call file:seek("set") sets the position to the beginning of the file (and returns `0`); and the call file:seek("end") sets the position to the end of the file, and returns its size.

Cached write buffer data will be flushed to the file and cached read buffer data will be dropped. This method is a synchronous operation and is 100% nonblocking.

**CAVEAT:** You should always call this method before you switch the I/O operations from `read` to `write` and vice versa.

## file:flush

**Syntax:** *local ok, err = file:flush([sync])*
**Context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;*


Saves any written data to file. In case of success, it returns `1` and if this method fails, `nil` and a Lua string will be given (as the error message).

An optional and sole parameter `sync` can be passed to specify whether this method should call `fsync` and wait until data was saved to the storage, default is `false`.

This method is a synchronous operation and is 100% nonblocking.

## file:lines

**Syntax:** *local iter = file:lines()*
**Context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;*


Returns an iterator that, each time it is called, returns a new line from the file. Therefore, the construction

```lua
for line in file:lines() do body end
```

will iterate over all lines of the file.

The iterator is like the way `file:read("*l")`, and you can always mixed use of these read methods safely.

## file:close

**Syntax:** *local ok, err = file:close()*
**Context:** *rewrite_by_lua&#42;, access_by_lua&#42;, content_by_lua&#42;, ngx.timer.&#42;, ssl_certificate_by_lua&#42;, ssl_session_fetch_by_lua&#42;*


Closes the file. Any cached write buffer data will be flushed to the file. This method is a synchronous operation and is 100% nonblocking.

In case of success, this method returns `1` while `nil` plus a Lua string will be returned if errors occurred.

# Author

Alex Zhang (张超) zchao1995@gmail.com, UPYUN Inc.

[Back to TOC](#table-of-contents)
