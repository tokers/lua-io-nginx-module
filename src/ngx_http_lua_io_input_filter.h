
/*
 * Copyright (C) Alex Zhang
 */


#ifndef _NGX_HTTP_LUA_IO_INPUT_FILTER_H_INCLUDED_
#define _NGX_HTTP_LUA_IO_INPUT_FILTER_H_INCLUDED_


ngx_int_t ngx_http_lua_io_read_chunk(void *data, ngx_buf_t *buf, size_t size);
ngx_int_t ngx_http_lua_io_read_line(void *data, ngx_buf_t *buf, size_t size);
ngx_int_t ngx_http_lua_io_read_all(void *data, ngx_buf_t *buf, size_t size);


#endif /* _NGX_HTTP_LUA_IO_INPUT_FILTER_H_INCLUDED_ */
