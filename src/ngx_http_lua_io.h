
/*
 * Copyright (C) Alex Zhang
 */


#ifndef _NGX_HTTP_LUA_IO_H_INCLUDED_
#define _NGX_HTTP_LUA_IO_H_INCLUDED_


#include <ngx_http.h>
#include <ngx_http_lua_common.h>


#ifdef __GNUC__
#define NGX_LIKELY(x)                               __builtin_expect(!!(x), 1)
#define NGX_UNLIKELY(x)                             __builtin_expect(!!(x), 0)
#else
#define NGX_LIKELY(x)                               (x)
#define NGX_UNLIKELY(x)                             (x)
#endif

#define NGX_HTTP_LUA_IO_FT_CLOSE                    (1 << 0)
#define NGX_HTTP_LUA_IO_FT_TASK_POST_ERROR          (1 << 1)
#define NGX_HTTP_LUA_IO_FT_NO_MEMORY                (1 << 2)


typedef struct {
    ngx_file_t                  file;

    ngx_int_t                 (*thread_handler)(ngx_thread_task_t *task,
                                                ngx_file_t *file);
    ngx_thread_task_t          *thread_task;
    ngx_thread_pool_t          *thread_pool;

    ngx_chain_t                *bufs_out;
    ngx_chain_t                *bufs_in;
    ngx_chain_t                *buf_in;
    ngx_buf_t                   buffer;

    ngx_int_t                 (*input_filter)(void *data, ngx_buf_t *buf,
                                              size_t size);

    ngx_err_t                   error;

    ngx_http_request_t         *request;
    ngx_http_cleanup_pt        *cleanup;
    ngx_event_handler_pt        handler;

    ngx_http_lua_co_ctx_t      *coctx;

    off_t                       offset;

    int                         whence;
    off_t                       seek_offset;

    size_t                      nbytes;
    size_t                      rest;

    unsigned                    mode;
    unsigned                    ft_type;

    unsigned                    read_waiting:1;
    unsigned                    write_waiting:1;
    unsigned                    flush_waiting:1;
    unsigned                    seeking:1;
    unsigned                    closing:1;
    unsigned                    closed:1;
    unsigned                    eof:1;
} ngx_http_lua_io_file_ctx_t;


typedef struct {
    ngx_fd_t                    fd;

    ngx_chain_t                *chain;
    off_t                       offset;

    u_char                     *buf;

    ngx_err_t                   err;
    size_t                      nbytes;
    size_t                      size;

    unsigned                    flush:1;
    unsigned                    eof:1;
} ngx_http_lua_io_thread_ctx_t;


ngx_int_t ngx_http_lua_io_thread_post_write_task(
    ngx_http_lua_io_file_ctx_t *file_ctx, ngx_chain_t *cl, ngx_int_t flush);
ngx_int_t ngx_http_lua_io_thread_post_read_task(
    ngx_http_lua_io_file_ctx_t *file_ctx, ngx_buf_t *buf);


#endif /* _NGX_HTTP_LUA_IO_H_INCLUDED_ */
