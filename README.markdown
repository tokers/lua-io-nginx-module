# Name

lua-io-nginx-module - Nginx C module to take over the file operations.

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

              for line in file:lines()
                  ngx.say(line)
              end

              local ok, err = file:close()
              assert(ok and not err)
          }
      }
  }
}
```

# Description

[Back to TOC](#table-of-contents)

# Author

Alex Zhang (张超) zchao1995@gmail.com, UPYUN Inc.

[Back to TOC](#table-of-contents)
