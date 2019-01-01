# Name

lua-io-nginx-module - Nginx C module to take over the Lua file operations. It's based on Nginx's thread pool.

![Build Status](https://travis-ci.org/tokers/lua-io-nginx-module.svg?branch=master) [![License](https://img.shields.io/badge/License-BSD%202--Clause-orange.svg)](https://github.com/tokers/lua-io-nginx-module/blob/master/LICENSE)

# Table of Contents

* [Name](#name)
* [Status](#status)
* [Synopsis](#synopsis)
* [Description](#description)
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

The APIs are similar with the [Lua I/O library](https://www.lua.org/pil/21.html), but with the totally different internal implementations, it doesn't use the stream file facilities in libc (but keep trying to be consistent with it), the buffer is maintained inside this module, and follows Cosocket's internals.

[Back to TOC](#table-of-contents)

# Author

Alex Zhang (张超) zchao1995@gmail.com, UPYUN Inc.

[Back to TOC](#table-of-contents)
