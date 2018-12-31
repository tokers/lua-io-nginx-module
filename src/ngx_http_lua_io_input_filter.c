
/*
 * Copyright (C) Alex Zhang
 */


#include <ngx_core.h>
#include "ngx_http_lua_io.h"
#include "ngx_http_lua_io_input_filter.h"


ngx_int_t
ngx_http_lua_io_read_chunk(void *data, ngx_buf_t *buf, size_t size)
{
    ngx_http_lua_io_file_ctx_t *file_ctx = data;

    size_t  rest;

    rest = file_ctx->rest;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, file_ctx->request->connection->log, 0,
                   "lua io read chunk, need:%uz got:%uz", rest, size);

    if (size == 0) {
        return NGX_OK;
    }

    if (size >= rest) {
        buf->pos += rest;
        file_ctx->buf_in->buf->last += rest;
        file_ctx->rest = 0;

        return NGX_OK;
    }

    buf->pos += size;
    file_ctx->buf_in->buf->last += size;
    file_ctx->rest -= size;

    return NGX_AGAIN;
}


ngx_int_t
ngx_http_lua_io_read_line(void *data, ngx_buf_t *buf, size_t size)
{
    ngx_http_lua_io_file_ctx_t *file_ctx = data;

    u_char               c, *dst;

#if (NGX_DEBUG)
    ngx_http_request_t  *r;
#endif


    dst = file_ctx->buf_in->buf->last;

#if (NGX_DEBUG)

    r = file_ctx->request;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io read line");

#endif

    while (size--) {

        c = *buf->pos++;

        switch (c) {
        case '\n':
            ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua io read the final linefeed");

            file_ctx->buf_in->buf->last = dst;

            return NGX_OK;

        case '\r':
            /* just ignore this CR */
            break;

        default:
            *dst++ = c;
            break;
        }
    }

    file_ctx->buf_in->buf->last = dst;

    return NGX_AGAIN;
}


ngx_int_t
ngx_http_lua_io_read_all(void *data, ngx_buf_t *buf, size_t size)
{
    ngx_http_lua_io_file_ctx_t *file_ctx = data;

    file_ctx->buf_in->buf->last += size;
    buf->pos += size;

    return file_ctx->eof ? NGX_OK : NGX_AGAIN;
}
