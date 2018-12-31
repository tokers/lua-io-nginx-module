
/*
 * Copyright (C) Alex Zhang
 */


#include <ngx_http.h>
#include <lauxlib.h>
#include <ngx_http_lua_api.h>
#include <ngx_http_lua_common.h>
#include <ngx_http_lua_util.h>
#include <ngx_http_lua_output.h>

#include "ngx_http_lua_io.h"
#include "ngx_http_lua_io_input_filter.h"


#define NGX_HTTP_LUA_IO_FILE_CTX_INDEX              1

#define NGX_HTTP_LUA_IO_FILE_READ_MODE              (1 << 0)
#define NGX_HTTP_LUA_IO_FILE_WRITE_MODE             (1 << 1)
#define NGX_HTTP_LUA_IO_FILE_APPEND_MODE            (1 << 2)
#define NGX_HTTP_LUA_IO_FILE_CREATE_MODE            (1 << 3)

#define ngx_http_lua_io_check_busy_reading(r, ctx, L)                         \
    if ((ctx)->read_waiting) {                                                \
        lua_pushnil(L);                                                       \
        lua_pushliteral(L, "io busy reading");                                \
        return 2;                                                             \
    }

#define ngx_http_lua_io_check_busy_writing(r, ctx, L)                         \
    if ((ctx)->write_waiting) {                                               \
        lua_pushnil(L);                                                       \
        lua_pushliteral(L, "io busy writing");                                \
        return 2;                                                             \
    }

#define ngx_http_lua_io_check_busy_flushing(r, ctx, L)                        \
    if ((ctx)->flush_waiting) {                                               \
        lua_pushnil(L);                                                       \
        lua_pushliteral(L, "io busy flushing");                               \
        return 2;                                                             \
    }


typedef struct {
    ngx_flag_t                  log_errors;
    size_t                      read_buf_size;
    size_t                      write_buf_size;
    ngx_http_complex_value_t   *thread_pool;
} ngx_http_lua_io_loc_conf_t;


typedef struct {
    ngx_chain_t                *free_read_bufs;
    ngx_chain_t                *free_write_bufs;
} ngx_http_lua_io_ctx_t;


static char  ngx_http_lua_io_metatable_key;
static char  ngx_http_lua_io_file_ctx_metatable_key;

static ngx_str_t  ngx_http_lua_io_thread_pool_default = ngx_string("default");
static const char*  ngx_http_lua_io_seek_list[] = { "set", "cur", "end", NULL };
static int  ngx_http_lua_io_seek_enum[] = { SEEK_SET, SEEK_CUR, SEEK_END };


static int ngx_http_lua_io_open(lua_State *L);
static int ngx_http_lua_io_file_close(lua_State *L);
static int ngx_http_lua_io_file_read(lua_State *L);
static int ngx_http_lua_io_file_write(lua_State *L);
static int ngx_http_lua_io_file_flush(lua_State *L);
static int ngx_http_lua_io_file_seek(lua_State *L);
static int ngx_http_lua_io_file_lines(lua_State *L);
static int ngx_http_lua_io_file_lines_iter(lua_State *L);
static int ngx_http_lua_io_file_destory(lua_State *L);
static void ngx_http_lua_io_file_cleanup(void *data);
static void ngx_http_lua_io_coctx_cleanup(void *data);
static void ngx_http_lua_io_file_finalize(ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *ctx);
static void ngx_http_lua_io_thread_event_handler(ngx_event_t *ev);
static void ngx_http_lua_io_content_wev_handler(ngx_http_request_t *r);
static ngx_int_t ngx_http_lua_io_resume(ngx_http_request_t *r);
static void ngx_http_lua_io_before_yield(ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *file_ctx);
static ngx_int_t ngx_http_lua_io_prepare_retvals(ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *file_ctx, ngx_http_lua_co_ctx_t *coctx);
static int ngx_http_lua_io_file_read_helper(ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *file_ctx, lua_State *L);
static int ngx_http_lua_io_submit_input_data(ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *file_ctx, lua_State *L);
static ngx_int_t ngx_http_lua_io_file_do_read(ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *file_ctx);
static ngx_int_t ngx_http_lua_io_add_input_buffer(ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *file_ctx);
static int ngx_http_lua_io_file_do_seek(ngx_http_lua_io_file_ctx_t *file_ctx,
    ngx_http_request_t *r, lua_State *L, off_t offset, int whence);
static int ngx_http_lua_io_create_module(lua_State *L);
static void *ngx_http_lua_io_create_loc_conf(ngx_conf_t *cf);
static char *ngx_http_lua_io_merge_loc_conf(ngx_conf_t *cf, void *parent,
    void *child);
static char *ngx_http_lua_io_thread_pool(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
static ngx_int_t ngx_http_lua_io_extract_mode(ngx_http_lua_io_file_ctx_t *ctx,
    ngx_str_t *mode);
static ngx_int_t ngx_http_lua_io_handle_error(lua_State *L,
    ngx_http_request_t *r, ngx_http_lua_io_file_ctx_t *ctx);
static ngx_int_t ngx_http_lua_io_init(ngx_conf_t *cf);


static ngx_command_t  ngx_http_lua_io_commands[] = {

    { ngx_string("lua_io_thread_pool"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
      |NGX_CONF_TAKE1,
      ngx_http_lua_io_thread_pool,
      NGX_HTTP_LOC_CONF_OFFSET,
      0,
      NULL },

    { ngx_string("lua_io_log_errors"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
      |NGX_CONF_TAKE1,
      ngx_conf_set_flag_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_io_loc_conf_t, log_errors),
      NULL },

    { ngx_string("lua_io_read_buffer_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
      |NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_io_loc_conf_t, read_buf_size),
      NULL },

    { ngx_string("lua_io_write_buffer_size"),
      NGX_HTTP_MAIN_CONF|NGX_HTTP_SRV_CONF|NGX_HTTP_LOC_CONF|NGX_HTTP_LIF_CONF
      |NGX_CONF_TAKE1,
      ngx_conf_set_size_slot,
      NGX_HTTP_LOC_CONF_OFFSET,
      offsetof(ngx_http_lua_io_loc_conf_t, write_buf_size),
      NULL },
};


static ngx_http_module_t  ngx_http_lua_io_module_ctx = {
    NULL,                                   /* preconfiguration */
    ngx_http_lua_io_init,                   /* postconfiguration */

    NULL,                                   /* create main configuration */
    NULL,                                   /* init main configuration */

    NULL,                                   /* create server configuration */
    NULL,                                   /* merge server configuration */

    ngx_http_lua_io_create_loc_conf,        /* create location configuration */
    ngx_http_lua_io_merge_loc_conf,         /* merge location configuration */
};


ngx_module_t  ngx_http_lua_io_module = {
    NGX_MODULE_V1,
    &ngx_http_lua_io_module_ctx,            /* module context */
    ngx_http_lua_io_commands,               /* module directives */
    NGX_HTTP_MODULE,                        /* module type */
    NULL,                                   /* init master */
    NULL,                                   /* init module */
    NULL,                                   /* init process */
    NULL,                                   /* init thread */
    NULL,                                   /* exit thread */
    NULL,                                   /* exit process */
    NULL,                                   /* exit master */
    NGX_MODULE_V1_PADDING
};


static char *
ngx_http_lua_io_thread_pool(ngx_conf_t *cf, ngx_command_t *cmd, void *conf)
{
    ngx_http_lua_io_loc_conf_t  *iocf = conf;

    ngx_http_compile_complex_value_t  ccv;
    ngx_str_t                        *value;

    if (iocf->thread_pool != NULL) {
        return "is duplicate";
    }

    iocf->thread_pool = ngx_pcalloc(cf->pool, sizeof(ngx_http_complex_value_t));
    if (iocf->thread_pool == NULL) {
        return NGX_CONF_ERROR;
    }

    ngx_memzero(&ccv, sizeof(ngx_http_compile_complex_value_t));

    value = cf->args->elts;

    ccv.cf = cf;
    ccv.value = &value[1];
    ccv.complex_value = iocf->thread_pool;

    if (ngx_http_compile_complex_value(&ccv) != NGX_OK) {
        return NGX_CONF_ERROR;
    }

    return NGX_CONF_OK;
}


static void *
ngx_http_lua_io_create_loc_conf(ngx_conf_t *cf)
{
    ngx_http_lua_io_loc_conf_t  *iocf;

    iocf = ngx_pcalloc(cf->pool, sizeof(ngx_http_lua_io_loc_conf_t));
    if (iocf == NULL) {
        return NULL;
    }

    /*
     * set by ngx_pcalloc():
     *
     *  iocf->thread_pool = { 0, NULL };
     *  iocf->thread_pool_lengths = NULL;
     *  iocf->thread_pool_values = NULL;
     */

    iocf->write_buf_size = NGX_CONF_UNSET_SIZE;
    iocf->read_buf_size = NGX_CONF_UNSET_SIZE;
    iocf->log_errors = NGX_CONF_UNSET;

    return iocf;
}


static char *
ngx_http_lua_io_merge_loc_conf(ngx_conf_t *cf, void *parent, void *child)
{
    ngx_http_lua_io_loc_conf_t *prev = parent;
    ngx_http_lua_io_loc_conf_t *conf = child;

    ngx_conf_merge_size_value(conf->read_buf_size, prev->read_buf_size,
                              ngx_pagesize);
    ngx_conf_merge_size_value(conf->write_buf_size, prev->write_buf_size,
                              ngx_pagesize);
    ngx_conf_merge_value(conf->log_errors, prev->log_errors, 0);

    if (conf->thread_pool == NULL) {
        conf->thread_pool = prev->thread_pool;
    }

    return NGX_CONF_OK;
}


static ngx_int_t
ngx_http_lua_io_init(ngx_conf_t *cf)
{
    if (ngx_http_lua_add_package_preload(cf, "ngx.io",
                                         ngx_http_lua_io_create_module)
        != NGX_OK)
    {
        return NGX_ERROR;
    }

    return NGX_OK;
}


static int
ngx_http_lua_io_create_module(lua_State *L)
{
    lua_createtable(L, 0 /* narr */, 2 /* nrec */);

    lua_pushcfunction(L, ngx_http_lua_io_open);
    lua_setfield(L, -2, "open");

    /* io file object metatable */
    lua_pushlightuserdata(L, &ngx_http_lua_io_metatable_key);
    lua_createtable(L, 0 /* narr */, 6 /* nrec */);

    lua_pushcfunction(L, ngx_http_lua_io_file_close);
    lua_setfield(L, -2, "close");

    lua_pushcfunction(L, ngx_http_lua_io_file_read);
    lua_setfield(L, -2, "read");

    lua_pushcfunction(L, ngx_http_lua_io_file_write);
    lua_setfield(L, -2, "write");

    lua_pushcfunction(L, ngx_http_lua_io_file_flush);
    lua_setfield(L, -2, "flush");

    lua_pushcfunction(L, ngx_http_lua_io_file_seek);
    lua_setfield(L, -2, "seek");

    lua_pushcfunction(L, ngx_http_lua_io_file_lines);
    lua_setfield(L, -2, "lines");

    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");

    lua_rawset(L, LUA_REGISTRYINDEX);

    /* io file object ctx metatable */
    lua_pushlightuserdata(L, &ngx_http_lua_io_file_ctx_metatable_key);
    lua_createtable(L, 0 /* narr */, 1 /* nrec */);

    lua_pushvalue(L, -1);

    lua_pushcfunction(L, ngx_http_lua_io_file_destory);
    lua_setfield(L, -2, "__gc");

    lua_rawset(L, LUA_REGISTRYINDEX);

    lua_pop(L, 1);

    return 1;
}


static ngx_int_t
ngx_http_lua_io_extract_mode(ngx_http_lua_io_file_ctx_t *ctx,
    ngx_str_t *mode)
{
    char       ch;
    ngx_int_t  flags, plus;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, ctx->request->connection->log, 0,
                   "lua io open mode:\"%V\"", mode);

    plus = 0;

    if (mode->len > 2 || mode->len < 1) {
        return NGX_ERROR;

    } else if (mode->len == 2) {
        if (mode->data[1] != '+') {
            return NGX_ERROR;
        }

        plus = 1;
    }

    flags = 0;
    ch = mode->data[0];

    switch (ch) {

    case 'r':
        flags = O_RDONLY;
        ctx->mode |= NGX_HTTP_LUA_IO_FILE_READ_MODE;
        break;

    case 'w':
        flags = O_WRONLY;
        ctx->mode |= NGX_HTTP_LUA_IO_FILE_WRITE_MODE;
        ctx->mode |= NGX_HTTP_LUA_IO_FILE_CREATE_MODE;
        break;

    case 'a':
        flags = O_WRONLY|O_APPEND;
        ctx->mode |= NGX_HTTP_LUA_IO_FILE_APPEND_MODE;
        ctx->mode |= NGX_HTTP_LUA_IO_FILE_WRITE_MODE;
        ctx->mode |= NGX_HTTP_LUA_IO_FILE_CREATE_MODE;
        break;

    default:
        return NGX_ERROR;
    }

    if (plus) {
        flags = O_RDWR;
        if (ch == 'a') {
            flags |= O_APPEND;
        }

        ctx->mode |= NGX_HTTP_LUA_IO_FILE_WRITE_MODE;
        ctx->mode |= NGX_HTTP_LUA_IO_FILE_READ_MODE;
    }

    if (ch != 'a' && (ctx->mode & NGX_HTTP_LUA_IO_FILE_WRITE_MODE)) {
        flags |= O_TRUNC;
    }

    return flags;
}


static ngx_thread_pool_t *
ngx_http_lua_io_get_thread_pool(ngx_http_request_t *r)
{
    ngx_str_t                    name;
    ngx_http_lua_io_loc_conf_t  *iocf;

    iocf = ngx_http_get_module_loc_conf(r, ngx_http_lua_io_module);

    if (iocf->thread_pool == NULL) {
        name = ngx_http_lua_io_thread_pool_default;

    } else {
        if (ngx_http_complex_value(r, iocf->thread_pool, &name) != NGX_OK) {
            return NULL;
        }
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io use thread pool \"%V\"", &name);

    return ngx_thread_pool_get((ngx_cycle_t *) ngx_cycle, &name);
}


static int
ngx_http_lua_io_open(lua_State *L)
{
    off_t                        offset;
    ngx_str_t                    path, modestr;
    ngx_int_t                    mode, n, create;
    ngx_http_request_t          *r;
    ngx_http_cleanup_t          *cln;
    ngx_http_lua_ctx_t          *ctx;
    ngx_http_lua_io_ctx_t       *ioctx;
    ngx_http_lua_io_file_ctx_t  *file_ctx;

    n = lua_gettop(L);

    if (NGX_UNLIKELY(n != 1 && n != 2)) {
        return luaL_error(L, "expecting 1 or 2 arguments, but got %s", n);
    }

    if (n == 2) {
        path.data = (u_char *) luaL_checklstring(L, -2, &path.len);
        modestr.data = (u_char *) luaL_checklstring(L, -1, &modestr.len);

    } else {
        path.data = (u_char *) luaL_checklstring(L, 1, &path.len);
        modestr.len = 1;
        modestr.data = (u_char *) "r";
    }

    r = ngx_http_lua_get_request(L);
    if (NGX_UNLIKELY(r == NULL)) {
        return luaL_error(L, "no request found");
    }

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (NGX_UNLIKELY(ctx == NULL)) {
        return luaL_error(L, "no ctx found");
    }

    ioctx = ngx_http_get_module_ctx(r, ngx_http_lua_io_module);
    if (ioctx == NULL) {
        ioctx = ngx_pcalloc(r->pool, sizeof(ngx_http_lua_io_ctx_t));
        if (ioctx == NULL) {
            return luaL_error(L, "no memory");
        }

        ngx_http_set_ctx(r, ioctx, ngx_http_lua_io_module);
    }

    ngx_http_lua_check_context(L, ctx, NGX_HTTP_LUA_CONTEXT_REWRITE
                               |NGX_HTTP_LUA_CONTEXT_ACCESS
                               |NGX_HTTP_LUA_CONTEXT_CONTENT
                               |NGX_HTTP_LUA_CONTEXT_TIMER
                               |NGX_HTTP_LUA_CONTEXT_SSL_CERT
                               |NGX_HTTP_LUA_CONTEXT_SSL_SESS_FETCH);

    if (ngx_get_full_name(r->pool, (ngx_str_t *) &ngx_cycle->prefix, &path)
        != NGX_OK)
    {
        return luaL_error(L, "no memory");
    }

    lua_createtable(L, 1 /* narr */, 1 /* nrec */);

    lua_pushlightuserdata(L, &ngx_http_lua_io_metatable_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_setmetatable(L, -2);

    file_ctx = lua_newuserdata(L, sizeof(ngx_http_lua_io_file_ctx_t));
    if (NGX_UNLIKELY(file_ctx == NULL)) {
        return luaL_error(L, "no memory");
    }

    lua_pushlightuserdata(L, &ngx_http_lua_io_file_ctx_metatable_key);
    lua_rawget(L, LUA_REGISTRYINDEX);
    lua_setmetatable(L, -2);

    lua_rawseti(L, -2, NGX_HTTP_LUA_IO_FILE_CTX_INDEX);

    ngx_memzero(file_ctx, sizeof(ngx_http_lua_io_file_ctx_t));

    file_ctx->thread_pool = ngx_http_lua_io_get_thread_pool(r);
    if (NGX_UNLIKELY(file_ctx->thread_pool == NULL)) {
        return luaL_error(L, "no thread pool found");
    }

    file_ctx->request = r;
    file_ctx->fd = NGX_INVALID_FILE;

    cln = ngx_http_lua_cleanup_add(r, 0);
    if (cln == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "no memory");
        return 2;
    }

    cln->handler = ngx_http_lua_io_file_cleanup;
    cln->data = file_ctx;

    file_ctx->cleanup = &cln->handler;
    file_ctx->handler = ngx_http_lua_io_thread_event_handler;

    mode = ngx_http_lua_io_extract_mode(file_ctx, &modestr);
    if (NGX_UNLIKELY(mode == NGX_ERROR)) {
        lua_pushnil(L);
        lua_pushliteral(L, "bad open mode");
        return 2;
    }

    create = (file_ctx->mode & NGX_HTTP_LUA_IO_FILE_CREATE_MODE) ? O_CREAT : 0;

    ngx_log_debug4(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io open \"%V\" r:%d w:%d a:%d",
                   &path, (file_ctx->mode & NGX_HTTP_LUA_IO_FILE_READ_MODE) != 0,
                   (file_ctx->mode & NGX_HTTP_LUA_IO_FILE_WRITE_MODE) != 0,
                   (file_ctx->mode & NGX_HTTP_LUA_IO_FILE_APPEND_MODE) != 0);

    file_ctx->fd = ngx_open_file(path.data, mode, create, S_IRUSR|S_IWUSR|S_IRGRP
                                 |S_IWGRP|S_IROTH|S_IWOTH);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io open fd:%d", file_ctx->fd);

    if (file_ctx->fd == NGX_INVALID_FILE) {
        file_ctx->error = ngx_errno;
        return ngx_http_lua_io_handle_error(L, r, file_ctx);
    }

    if ((file_ctx->mode & NGX_HTTP_LUA_IO_FILE_APPEND_MODE) != 0) {

        offset = lseek(file_ctx->fd, 0, SEEK_END);
        if (NGX_UNLIKELY(offset < 0)) {
            file_ctx->error = ngx_errno;
            return ngx_http_lua_io_handle_error(L, r, file_ctx);
        }

        file_ctx->offset = offset;
    }

    return 1;
}


static int
ngx_http_lua_io_file_close(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_io_file_ctx_t  *ctx;

    if (NGX_UNLIKELY(lua_gettop(L) != 1)) {
        return luaL_error(L, "expecting only one argument (the object), "
                          "but got %d", lua_gettop(L));
    }

    r = ngx_http_lua_get_request(L);
    if (NGX_UNLIKELY(r == NULL)) {
        return luaL_error(L, "no request found");
    }

    luaL_checktype(L, 1, LUA_TTABLE);

    lua_rawgeti(L, 1, NGX_HTTP_LUA_IO_FILE_CTX_INDEX);
    ctx = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (ctx == NULL || ctx->closed) {
        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (ctx->request != r) {
        return luaL_error(L, "bad request");
    }

    ngx_http_lua_io_check_busy_reading(r, ctx, L);
    ngx_http_lua_io_check_busy_writing(r, ctx, L);
    ngx_http_lua_io_check_busy_flushing(r, ctx, L);

    if (!ctx->bufs_out) {
        ngx_http_lua_io_file_finalize(r, ctx);

        if (ctx->ft_type || ctx->error) {
            return ngx_http_lua_io_handle_error(L, r, ctx);
        }

        lua_pushinteger(L, 1);
        return 1;
    }

    /* flush the legacy buffer */

    if (NGX_UNLIKELY(ngx_http_lua_io_thread_post_write_task(ctx, ctx->bufs_out,
                                                            0)
                     == NGX_ERROR))
    {
        return ngx_http_lua_io_handle_error(L, r, ctx);
    }

    ctx->closing = 1;
    ctx->bufs_out = NULL;
    ctx->flush_waiting = 1;

    ngx_http_lua_io_before_yield(r, ctx);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io close flushing saved co ctx:%p", ctx->coctx);

    return lua_yield(L, 0);
}


static int
ngx_http_lua_io_file_read(lua_State *L)
{
    int                          n, type;
    const char                  *p;
    lua_Integer                  bytes;
    ngx_str_t                    pat;
    ngx_http_request_t          *r;
    ngx_http_lua_io_file_ctx_t  *file_ctx;
    ngx_http_lua_io_loc_conf_t  *iocf;

    n = lua_gettop(L);
    if (NGX_UNLIKELY(n != 1 && n != 2)) {
        return luaL_error(L, "expecting two arguments (including the object), ",
                          "but got %d", n);
    }

    r = ngx_http_lua_get_request(L);
    if (NGX_UNLIKELY(r == NULL)) {
        return luaL_error(L, "no request found");
    }

    luaL_checktype(L, 1, LUA_TTABLE);
    lua_rawgeti(L, 1, NGX_HTTP_LUA_IO_FILE_CTX_INDEX);

    file_ctx = lua_touserdata(L, -1);
    lua_pop(L, 1);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io write, ctx:%p", file_ctx);

    iocf = ngx_http_get_module_loc_conf(r, ngx_http_lua_io_module);

    if (file_ctx == NULL || file_ctx->closed) {
        if (iocf->log_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "attempt to read data from a closed file object");
        }

        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (NGX_UNLIKELY(file_ctx->request != r)) {
        return luaL_error(L, "bad request");
    }

    ngx_http_lua_io_check_busy_reading(r, file_ctx, L);
    ngx_http_lua_io_check_busy_writing(r, file_ctx, L);
    ngx_http_lua_io_check_busy_flushing(r, file_ctx, L);

    if (NGX_UNLIKELY(!(file_ctx->mode & NGX_HTTP_LUA_IO_FILE_READ_MODE))) {
        /* FIXME need to be compatible with libc? */
        lua_pushnil(L);
        lua_pushliteral(L, "operation not permitted");
        return 2;
    }

    if (n > 1) {

        type = lua_type(L, 2);
        switch (type) {
        case LUA_TNUMBER:
            bytes = lua_tointeger(L, 2);
            if (NGX_UNLIKELY(bytes < 0)) {
                return luaL_argerror(L, 2, "bad pattern argument");
            }

            if (NGX_UNLIKELY(bytes == 0)) {
                lua_pushliteral(L, "");
                return 1;
            }

            file_ctx->input_filter = ngx_http_lua_io_read_chunk;
            file_ctx->rest = (size_t) bytes;

            break;

        case LUA_TSTRING:
            pat.data = (u_char *) luaL_checklstring(L, 2, &pat.len);
            if (NGX_UNLIKELY(pat.len != 2 || pat.data[0] != '*')) {
                p = lua_pushfstring(L, "bad pattern argument: %s", pat.data);
                return luaL_argerror(L, 2, p);
            }

            switch (pat.data[1]) {
            case 'l':
                file_ctx->input_filter = ngx_http_lua_io_read_line;
                break;

            case 'a':
                file_ctx->input_filter = ngx_http_lua_io_read_all;
                break;

            default:
                p = lua_pushfstring(L, "bad pattern argument: %s", pat.data);
                return luaL_argerror(L, 2, p);
            }

            file_ctx->rest = 0;
            break;

        default:
            return luaL_argerror(L, 2, "bad pattern argument");
        }

    } else {
        file_ctx->input_filter = ngx_http_lua_io_read_line;
        file_ctx->rest = 0;
    }

    return ngx_http_lua_io_file_read_helper(r, file_ctx, L);
}


static int
ngx_http_lua_io_file_write(lua_State *L)
{
    int                          type;
    size_t                       len, size;
    u_char                      *p;
    const char                  *errmsg;
    ngx_chain_t                 *cl, *out;
    ngx_buf_t                   *b;
    ngx_http_lua_io_loc_conf_t  *iocf;
    ngx_http_lua_io_ctx_t       *ioctx;
    ngx_http_lua_io_file_ctx_t  *file_ctx;
    ngx_http_request_t          *r;

    if (NGX_UNLIKELY(lua_gettop(L) != 2)) {
        return luaL_error(L, "expecting two arguments (including the object), ",
                          "but got %d", lua_gettop(L));
    }

    r = ngx_http_lua_get_request(L);
    if (NGX_UNLIKELY(r == NULL)) {
        return luaL_error(L, "no request found");
    }

    luaL_checktype(L, 1, LUA_TTABLE);
    lua_rawgeti(L, 1, NGX_HTTP_LUA_IO_FILE_CTX_INDEX);

    file_ctx = lua_touserdata(L, -1);
    lua_pop(L, 1);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io write, ctx:%p", file_ctx);

    iocf = ngx_http_get_module_loc_conf(r, ngx_http_lua_io_module);

    if (file_ctx == NULL || file_ctx->closed) {
        if (iocf->log_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "attempt to write data on a closed file object");
        }

        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (NGX_UNLIKELY(file_ctx->request != r)) {
        return luaL_error(L, "bad request");
    }

    ngx_http_lua_io_check_busy_reading(r, file_ctx, L);
    ngx_http_lua_io_check_busy_writing(r, file_ctx, L);
    ngx_http_lua_io_check_busy_flushing(r, file_ctx, L);

    if (NGX_UNLIKELY(!(file_ctx->mode & NGX_HTTP_LUA_IO_FILE_WRITE_MODE))) {

        /* FIXME need to be compatible with libc? */
        lua_pushnil(L);
        lua_pushliteral(L, "operation not permitted");
        return 2;
    }

    len = 0;

    type = lua_type(L, 2);
    switch (type) {
    case LUA_TNUMBER:
        /* fallthrough */
    case LUA_TSTRING:
        lua_tolstring(L, 2, &len);
        break;

    case LUA_TTABLE:
        len = ngx_http_lua_calc_strlen_in_table(L, 2, 2, 1 /* strict */);
        break;

    case LUA_TBOOLEAN:
        if (lua_toboolean(L, 2)) {
            len = sizeof("true") - 1;

        } else {
            len = sizeof("false") - 1;
        }

        break;

    case LUA_TNIL:
        len = sizeof("nil") - 1;
        break;

    default:
        errmsg = lua_pushfstring(L, "string, number, boolean, nil"
                                 " or array table expected, got %s",
                                 lua_typename(L, type));

        return luaL_argerror(L, 2, errmsg);
    }

    if (len == 0) {
        lua_pushinteger(L, 0);
        return 1;
    }

    out = NULL;

    ioctx = ngx_http_get_module_ctx(r, ngx_http_lua_io_module);
    size = iocf->write_buf_size;

    if (size == 0) {
        cl = ngx_http_lua_chain_get_free_buf(r->connection->log, r->pool,
                                             &ioctx->free_write_bufs, len);
        if (NGX_UNLIKELY(cl == NULL)) {
            return luaL_error(L, "no memory");
        }

        out = cl;

    } else {
        cl = file_ctx->bufs_out;
        if (cl == NULL || (size_t) (cl->buf->end - cl->buf->last) < len) {

            cl = ngx_http_lua_chain_get_free_buf(r->connection->log, r->pool,
                                                 &ioctx->free_write_bufs,
                                                 size > len ? size : len);

            if (NGX_UNLIKELY(cl == NULL)) {
                return luaL_error(L, "no memory");
            }

            if (file_ctx->bufs_out) {
                out = file_ctx->bufs_out;
            }

            if (len > size) {
                if (out) {
                    out->next = cl;

                } else {
                    out = cl;
                }

                file_ctx->bufs_out = NULL;

            } else {
                file_ctx->bufs_out = cl;
            }
        }
    }

    b = cl->buf;

    switch (type) {
    case LUA_TNUMBER:
        /* fallthrough */
    case LUA_TSTRING:
        p = (u_char *) lua_tolstring(L, -1, &len);
        b->last = ngx_copy(b->last, (u_char *) p, len);
        break;

    case LUA_TTABLE:
        b->last = ngx_http_lua_copy_str_in_table(L, -1, b->last);
        break;

    case LUA_TBOOLEAN:
        if (lua_toboolean(L, 2)) {
            *b->last++ = 't';
            *b->last++ = 'r';
            *b->last++ = 'u';
            *b->last++ = 'e';

        } else {
            *b->last++ = 'f';
            *b->last++ = 'a';
            *b->last++ = 'l';
            *b->last++ = 's';
            *b->last++ = 'e';
        }

        break;

    case LUA_TNIL:
        *b->last++ = 'n';
        *b->last++ = 'i';
        *b->last++ = 'l';
        break;

    default:
        return luaL_error(L, "impossible to reach here");
    }

    if (out == NULL) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua io write cache");
        lua_pushinteger(L, len);
        return 1;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io write through");

    if (NGX_UNLIKELY(ngx_http_lua_io_thread_post_write_task(file_ctx, out, 0)
                     == NGX_ERROR))
    {
        return ngx_http_lua_io_handle_error(L, r, file_ctx);
    }

    file_ctx->nbytes = 0;
    for ( /* void */ ; cl; cl = cl->next) {
        file_ctx->nbytes += ngx_buf_size(cl->buf);
    }

    file_ctx->write_waiting = 1;

    ngx_http_lua_io_before_yield(r, file_ctx);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io write saved co ctx:%p", file_ctx->coctx);

    return lua_yield(L, 0);
}


static int
ngx_http_lua_io_file_flush(lua_State *L)
{
    int                          n;
    ngx_int_t                    full;
    ngx_http_request_t          *r;
    ngx_http_lua_io_file_ctx_t  *file_ctx;
    ngx_http_lua_io_loc_conf_t  *iocf;

    n = lua_gettop(L);

    if (NGX_UNLIKELY(n != 1 && n != 2)) {
        return luaL_error(L, "expecting one or two arguments, but got %d", n);
    }

    r = ngx_http_lua_get_request(L);
    if (NGX_UNLIKELY(r == NULL)) {
        return luaL_error(L, "no request found");
    }

    full = 0;
    if (n == 2) {
        full = lua_toboolean(L, 1);
        lua_pop(L, 1);
    }

    luaL_checktype(L, 1, LUA_TTABLE);
    lua_rawgeti(L, 1, NGX_HTTP_LUA_IO_FILE_CTX_INDEX);

    file_ctx = lua_touserdata(L, -1);
    lua_pop(L, 1);

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io flush");

    if (file_ctx == NULL || file_ctx->closed) {
        iocf = ngx_http_get_module_loc_conf(r, ngx_http_lua_io_module);
        if (iocf->log_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "attempt to flush data on a closed file object");
        }

        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if (NGX_UNLIKELY(r != file_ctx->request)) {
        lua_pushnil(L);
        lua_pushliteral(L, "bad request");
        return 2;
    }

    ngx_http_lua_io_check_busy_reading(r, file_ctx, L);
    ngx_http_lua_io_check_busy_writing(r, file_ctx, L);
    ngx_http_lua_io_check_busy_flushing(r, file_ctx, L);

    if (NGX_UNLIKELY(!(file_ctx->mode & NGX_HTTP_LUA_IO_FILE_WRITE_MODE))) {

        /* FIXME need to be compatible with libc? */
        lua_pushnil(L);
        lua_pushliteral(L, "operation not permitted");
        return 2;
    }

    if (NGX_UNLIKELY(ngx_http_lua_io_thread_post_write_task(file_ctx,
                                                            file_ctx->bufs_out,
                                                            full)
                     == NGX_ERROR))
    {
        return ngx_http_lua_io_handle_error(L, r, file_ctx);
    }

    ngx_http_lua_io_before_yield(r, file_ctx);

    file_ctx->flush_waiting = 1;
    file_ctx->bufs_out = NULL;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io flush saved co ctx:%p", file_ctx->coctx);

    return lua_yield(L, 0);
}


static int
ngx_http_lua_io_file_seek(lua_State *L)
{
    off_t                        offset;
    int                          n, whence, opt;
    ngx_chain_t                **ll, *cl;
    ngx_http_request_t          *r;
    ngx_http_lua_io_ctx_t       *ioctx;
    ngx_http_lua_io_loc_conf_t  *iocf;
    ngx_http_lua_io_file_ctx_t  *file_ctx;

    n = lua_gettop(L);

    if (NGX_UNLIKELY(n > 3)) {
        return luaL_error(L, "expecting one, two or three arguments,"
                          " but got %d", n);
    }

    r = ngx_http_lua_get_request(L);
    if (NGX_UNLIKELY(r == NULL)) {
        return luaL_error(L, "no request found");
    }

    luaL_checktype(L, 1, LUA_TTABLE);
    lua_rawgeti(L, 1, NGX_HTTP_LUA_IO_FILE_CTX_INDEX);

    file_ctx = lua_touserdata(L, -1);
    lua_pop(L, 1);

    whence = SEEK_CUR;
    offset = 0;

    if (n >= 2) {
        opt = luaL_checkoption(L, 2, "cur", ngx_http_lua_io_seek_list);
        whence = ngx_http_lua_io_seek_enum[opt];

        if (n >= 3) {
            offset = (off_t) luaL_checkinteger(L, 3);
        }
    }

    if (file_ctx == NULL || file_ctx->closed) {
        iocf = ngx_http_get_module_loc_conf(r, ngx_http_lua_io_module);
        if (iocf->log_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "attempt to flush data on a closed file object");
        }

        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    ngx_http_lua_io_check_busy_reading(r, file_ctx, L);
    ngx_http_lua_io_check_busy_writing(r, file_ctx, L);
    ngx_http_lua_io_check_busy_flushing(r, file_ctx, L);

    if (NGX_UNLIKELY(r != file_ctx->request)) {
        return luaL_error(L, "bad request");
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io seek whence:%d offset:%O", whence, offset);

    if (file_ctx->bufs_in) {

        /* FIXME keep these buffers and use them in the proper timing? */

        ioctx = ngx_http_get_module_ctx(r, ngx_http_lua_io_module);

        ll = &file_ctx->bufs_in;
        for (cl = file_ctx->bufs_in; cl; cl = cl->next) {
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua io seek drain read chain:%p next:%p",
                           cl, cl->next);

            cl->buf->pos = cl->buf->last;
            ll = &cl->next;
        }

        *ll = ioctx->free_read_bufs;
        ioctx->free_read_bufs = file_ctx->bufs_in;

        file_ctx->bufs_in = NULL;
        file_ctx->buf_in = NULL;

        ngx_memzero(&file_ctx->buffer, sizeof(ngx_buf_t));
    }

    if (file_ctx->bufs_out == NULL) {
        goto seek;
    }

    if (NGX_UNLIKELY(ngx_http_lua_io_thread_post_write_task(file_ctx,
                                                            file_ctx->bufs_out,
                                                            0)
                     == NGX_ERROR))
    {
        return ngx_http_lua_io_handle_error(L, r, file_ctx);
    }

    file_ctx->write_waiting = 1;
    file_ctx->seeking = 1;
    file_ctx->bufs_out = NULL;
    file_ctx->whence = whence;
    file_ctx->seek_offset = offset;

    ngx_http_lua_io_before_yield(r, file_ctx);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io seek saved co ctx:%p", file_ctx->coctx);

    return lua_yield(L, 0);

seek:

    return ngx_http_lua_io_file_do_seek(file_ctx, r, L, offset, whence);
}


static int
ngx_http_lua_io_file_lines(lua_State *L)
{
    ngx_http_request_t          *r;

    if (NGX_UNLIKELY(lua_gettop(L) > 1)) {
        return luaL_error(L, "expecting one argument, but got %d",
                          lua_gettop(L));
    }

    r = ngx_http_lua_get_request(L);
    if (NGX_UNLIKELY(r == NULL)) {
        return luaL_error(L, "no request found");
    }

    luaL_checktype(L, -1, LUA_TTABLE);

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io file lines created an iterator");

    lua_pushcclosure(L, ngx_http_lua_io_file_lines_iter, 1);
    return 1;
}


static int
ngx_http_lua_io_file_lines_iter(lua_State *L)
{
    ngx_http_request_t          *r;
    ngx_http_lua_io_file_ctx_t  *file_ctx;
    ngx_http_lua_io_loc_conf_t  *iocf;

    r = ngx_http_lua_get_request(L);
    if (NGX_UNLIKELY(r == NULL)) {
        return luaL_error(L, "no request found");
    }

    lua_rawgeti(L, lua_upvalueindex(1), NGX_HTTP_LUA_IO_FILE_CTX_INDEX);
    file_ctx = lua_touserdata(L, -1);
    lua_pop(L, 1);

    if (file_ctx == NULL || file_ctx->closed) {
        iocf = ngx_http_get_module_loc_conf(r, ngx_http_lua_io_module);
        if (iocf->log_errors) {
            ngx_log_error(NGX_LOG_ERR, r->connection->log, 0,
                          "attempt to read a line from a closed file object");
        }

        lua_pushnil(L);
        lua_pushliteral(L, "closed");
        return 2;
    }

    if(NGX_UNLIKELY(file_ctx->request != r)) {
        return luaL_error(L, "bad request");
    }

    ngx_http_lua_io_check_busy_reading(r, file_ctx, L);
    ngx_http_lua_io_check_busy_writing(r, file_ctx, L);
    ngx_http_lua_io_check_busy_flushing(r, file_ctx, L);

    if (NGX_UNLIKELY(!(file_ctx->mode & NGX_HTTP_LUA_IO_FILE_READ_MODE))) {

        /* FIXME need to be compatible with libc? */
        lua_pushnil(L);
        lua_pushliteral(L, "operation not permitted");
        return 2;
    }

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io file line iterator called");

    file_ctx->input_filter = ngx_http_lua_io_read_line;
    file_ctx->rest = 0;

    return ngx_http_lua_io_file_read_helper(r, file_ctx, L);
}


static void
ngx_http_lua_io_coctx_cleanup(void *data)
{
    ngx_http_lua_co_ctx_t *coctx = data;

    ngx_http_lua_io_file_ctx_t  *file_ctx;
    ngx_http_request_t          *r;

    file_ctx = coctx->data;
    if (file_ctx == NULL || file_ctx->closed || file_ctx->request == NULL) {
        return;
    }

    r = file_ctx->request;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io coctx cleanup");

    ngx_http_lua_io_file_finalize(r, file_ctx);
}


static void
ngx_http_lua_io_content_wev_handler(ngx_http_request_t *r)
{
    ngx_http_lua_ctx_t  *ctx;

    ctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (ctx == NULL) {
        return;
    }

    (void) ctx->resume_handler(r);
}


static void
ngx_http_lua_io_thread_event_handler(ngx_event_t *ev)
{
    ngx_http_lua_io_file_ctx_t *file_ctx = ev->data;

    ngx_connection_t    *c;
    ngx_http_request_t  *r;
    ngx_http_lua_ctx_t  *lctx;

    r = file_ctx->request;
    c = r->connection;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io thread event handler");

    ev->complete = 0;

    r->main->blocked--;
    r->aio = 0;

    lctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);

    lctx->resume_handler = ngx_http_lua_io_resume;
    lctx->cur_co_ctx = file_ctx->coctx;

    r->write_event_handler(r);
    ngx_http_run_posted_requests(c);

    return;
}


static ngx_int_t
ngx_http_lua_io_resume(ngx_http_request_t *r)
{
    ngx_int_t                      rc, n;
    ngx_uint_t                     nreqs;
    lua_State                     *L;
    ngx_connection_t              *c;
    ngx_http_lua_ctx_t            *lctx;
    ngx_http_lua_co_ctx_t         *coctx;
    ngx_http_lua_io_file_ctx_t    *file_ctx;

#if (NGX_DEBUG)
    const char                    *action;
#endif

    lctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    if (lctx == NULL) {
        return NGX_ERROR;
    }

    lctx->resume_handler = ngx_http_lua_wev_handler;

    coctx = lctx->cur_co_ctx;
    coctx->cleanup = NULL;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io resume cur_co_ctx:%p", coctx);

    file_ctx = coctx->data;

#if (NGX_DEBUG)

    if (file_ctx->write_waiting) {
        action = "write";

    } else if (file_ctx->read_waiting) {
        action = "read";

    } else {
        action = "flush";
    }

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io %s done and resume", action);

#endif

    n = ngx_http_lua_io_prepare_retvals(r, file_ctx, coctx);

    if (n < 0) {
        /* still have to stuck in here */
        return NGX_DONE;
    }

    L = ngx_http_lua_get_lua_vm(r, lctx);

    c = r->connection;
    nreqs = c->requests;

    rc = ngx_http_lua_run_thread(L, r, lctx, n);

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua run thread returned %d", rc);

    if (rc == NGX_AGAIN) {
        return ngx_http_lua_run_posted_threads(c, L, r, lctx, nreqs);
    }

    if (rc == NGX_DONE) {
        ngx_http_lua_finalize_request(r, NGX_DONE);
        return ngx_http_lua_run_posted_threads(c, L, r, lctx, nreqs);
    }

    if (lctx->entered_content_phase) {
        ngx_http_lua_finalize_request(r, rc);
        return NGX_DONE;
    }

    return rc;
}


static ngx_int_t
ngx_http_lua_io_handle_error(lua_State *L, ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *ctx)
{
    u_char   errstr[NGX_MAX_ERROR_STR];
    u_char  *p;

    lua_pop(L, lua_gettop(L));

    lua_pushnil(L);

    if (ctx->ft_type & NGX_HTTP_LUA_IO_FT_CLOSE) {
        lua_pushliteral(L, "closed");

    } else if (ctx->ft_type & NGX_HTTP_LUA_IO_FT_TASK_POST_ERROR) {
        lua_pushliteral(L, "task post failed");

    } else if (ctx->ft_type & NGX_HTTP_LUA_IO_FT_NO_MEMORY) {
        lua_pushliteral(L, "no memory");

    } else {
        if (ctx->error != 0) {
            p = ngx_strerror(ctx->error, errstr, sizeof(errstr));
            ngx_strlow(errstr, errstr, p - errstr);
            lua_pushlstring(L, (char *) errstr, p - errstr);

        } else {
            lua_pushliteral(L, "error");
        }
    }

    return 2;
}


static int
ngx_http_lua_io_file_destory(lua_State *L)
{
    ngx_http_lua_io_file_ctx_t  *ctx;

    ctx = lua_touserdata(L, 1);
    if (ctx == NULL) {
        return 0;
    }

    if (ctx->cleanup) {
        ngx_http_lua_io_file_finalize(ctx->request, ctx);
    }

    return 0;
}


static void
ngx_http_lua_io_file_cleanup(void *data)
{
    ngx_http_lua_io_file_ctx_t *ctx = data;

    ngx_http_request_t  *r;

    r = ctx->request;

    ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io file ctx cleanup");

    ngx_http_lua_io_file_finalize(r, ctx);
}


static void
ngx_http_lua_io_file_finalize(ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *ctx)
{
    ngx_chain_t            *cl, **ll;
    ngx_http_lua_io_ctx_t  *ioctx;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io file ctx finalize, r:%p", r);

    if (ctx->cleanup) {
        *ctx->cleanup = NULL;
        ngx_http_lua_cleanup_free(r, ctx->cleanup);
        ctx->cleanup = NULL;
    }

    ioctx = ngx_http_get_module_ctx(r, ngx_http_lua_io_module);

    if (ctx->bufs_in) {

        ll = &ctx->bufs_in;
        for (cl = ctx->bufs_in; cl; cl = cl->next) {
            ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua io file ctx finalize read chain:%p, next:%p",
                           cl, cl->next);

            cl->buf->pos = cl->buf->last;
            ll = &cl->next;
        }

        *ll = ioctx->free_read_bufs;
        ioctx->free_read_bufs = ctx->bufs_in;

        ctx->bufs_in = NULL;
        ctx->buf_in = NULL;

        ngx_memzero(&ctx->buffer, sizeof(ngx_buf_t));
    }

    if (ctx->bufs_out) {

        ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua io file ctx finalize write chain:%p",
                       ctx->bufs_out);

        ctx->bufs_out->buf->pos = ctx->bufs_out->buf->last;

        ctx->bufs_out->next = ioctx->free_write_bufs;
        ioctx->free_write_bufs = ctx->bufs_out;

        ctx->bufs_out = NULL;
    }

    ctx->error = 0;
    ctx->ft_type = 0;
    ctx->closed = 1;

    if (ctx->fd != NGX_INVALID_FILE && ngx_close_file(ctx->fd) < 0) {
        ctx->error = ngx_errno;
        ngx_log_error(NGX_LOG_ERR, r->connection->log, ngx_errno,
                      ngx_close_file_n " failed");
    }
}


static void
ngx_http_lua_io_before_yield(ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *file_ctx)
{
    ngx_http_lua_ctx_t     *lctx;
    ngx_http_lua_co_ctx_t  *coctx;

    lctx = ngx_http_get_module_ctx(r, ngx_http_lua_module);
    coctx = lctx->cur_co_ctx;

    ngx_http_lua_cleanup_pending_operation(coctx);
    coctx->cleanup = ngx_http_lua_io_coctx_cleanup;
    coctx->data = file_ctx;

    file_ctx->coctx = coctx;

    if (lctx->entered_content_phase) {
        r->write_event_handler = ngx_http_lua_io_content_wev_handler;

    } else {
        r->write_event_handler = ngx_http_core_run_phases;
    }
}


static ngx_int_t
ngx_http_lua_io_prepare_retvals(ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *file_ctx, ngx_http_lua_co_ctx_t *coctx)
{
    ngx_int_t                      rc;
    ngx_buf_t                     *b;
    ngx_http_lua_io_ctx_t         *ioctx;
    ngx_http_lua_io_thread_ctx_t  *thread_ctx;

    thread_ctx = file_ctx->thread_task->ctx;
    if (thread_ctx->err) {
        file_ctx->error = thread_ctx->err;
        return ngx_http_lua_io_handle_error(coctx->co, r, file_ctx);
    }

    ioctx = ngx_http_get_module_ctx(r, ngx_http_lua_io_module);

    if (file_ctx->write_waiting) {
        file_ctx->offset += thread_ctx->nbytes;
        file_ctx->write_waiting = 0;

        thread_ctx->chain->buf->pos = thread_ctx->chain->buf->last;

        thread_ctx->chain->next = ioctx->free_write_bufs;
        ioctx->free_write_bufs = thread_ctx->chain;

        thread_ctx->chain = NULL;

        if (file_ctx->seeking) {
            file_ctx->seeking = 0;

            return ngx_http_lua_io_file_do_seek(file_ctx, r, coctx->co,
                                                file_ctx->seek_offset,
                                                file_ctx->whence);
        }

        lua_pushinteger(coctx->co, file_ctx->nbytes);
        return 1;
    }

    if (file_ctx->flush_waiting) {
        file_ctx->offset += thread_ctx->nbytes;
        file_ctx->flush_waiting = 0;

        if (thread_ctx->chain) {
            thread_ctx->chain->buf->pos = thread_ctx->chain->buf->last;

            thread_ctx->chain->next = ioctx->free_write_bufs;
            ioctx->free_write_bufs = thread_ctx->chain;

            thread_ctx->chain = NULL;
        }

        if (file_ctx->closing) {
            file_ctx->closing = 0;
            ngx_http_lua_io_file_finalize(r, file_ctx);

            if (file_ctx->ft_type || file_ctx->error) {
                return ngx_http_lua_io_handle_error(coctx->co, r, file_ctx);
            }
        }

        lua_pushinteger(coctx->co, 1);
        return 1;
    }

    /* file_ctx->read_waiting == 1 */

    file_ctx->eof = thread_ctx->eof;
    file_ctx->read_waiting = 0;
    file_ctx->buffer.last += thread_ctx->nbytes;

    if (file_ctx->eof) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua io read eof");
    }

    rc = ngx_http_lua_io_file_do_read(r, file_ctx);

    if (rc == NGX_AGAIN) {
        b = &file_ctx->buffer;
        if (NGX_UNLIKELY(ngx_http_lua_io_thread_post_read_task(file_ctx, b)
                         == NGX_ERROR))
        {
            return ngx_http_lua_io_handle_error(coctx->co, r, file_ctx);
        }

        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua io read need one more try");

        file_ctx->read_waiting = 1;
        return -1;
    }

    if (rc == NGX_ERROR) {
        return ngx_http_lua_io_handle_error(coctx->co, r, file_ctx);
    }

    /* rc == NGX_OK */

    return ngx_http_lua_io_submit_input_data(r, file_ctx, coctx->co);
}


static int
ngx_http_lua_io_file_do_seek(ngx_http_lua_io_file_ctx_t *file_ctx,
    ngx_http_request_t *r, lua_State *L, off_t offset, int whence)
{

    if (whence == SEEK_CUR) {

        /*
         * due to the buffered reading mechanism,
         * we rebuild the seek offset, to the correct position.
         */

        whence = SEEK_SET;
        offset = file_ctx->offset + offset;
    }

    offset = lseek(file_ctx->fd, offset, whence);

    if (offset < 0) {
        file_ctx->error = ngx_errno;
        return ngx_http_lua_io_handle_error(L, r, file_ctx);
    }

    file_ctx->eof = 0;
    file_ctx->offset = offset;

    lua_pushinteger(L, offset);
    return 1;
}


static int
ngx_http_lua_io_file_read_helper(ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *file_ctx, lua_State *L)
{
    ngx_int_t                    rc;
    ngx_http_lua_io_loc_conf_t  *iocf;
    ngx_http_lua_io_ctx_t       *ioctx;


    if (file_ctx->bufs_in == NULL) {
        ioctx = ngx_http_get_module_ctx(r, ngx_http_lua_io_module);
        iocf = ngx_http_get_module_loc_conf(r, ngx_http_lua_io_module);

        file_ctx->bufs_in = ngx_http_lua_chain_get_free_buf(r->connection->log,
                                                            r->pool,
                                                            &ioctx->free_read_bufs,
                                                            iocf->read_buf_size);

        if (NGX_UNLIKELY(file_ctx->bufs_in == NULL)) {
            return luaL_error(L, "no memory");
        }

        file_ctx->buf_in = file_ctx->bufs_in;
        file_ctx->buffer = *file_ctx->buf_in->buf;
    }

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io read, bufs_in:%p buf_in:%p",
                   file_ctx->bufs_in, file_ctx->buf_in);

    file_ctx->read_waiting = 0;
    file_ctx->coctx = NULL;

    rc = ngx_http_lua_io_file_do_read(r, file_ctx);

    if (rc == NGX_ERROR) {
        return ngx_http_lua_io_handle_error(L, r, file_ctx);
    }

    if (rc == NGX_OK) {
        ngx_log_debug0(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                       "lua io read done just in one round");

        return ngx_http_lua_io_submit_input_data(r, file_ctx, L);
    }

    /* rc == NGX_AGAIN */

    if (NGX_UNLIKELY(ngx_http_lua_io_thread_post_read_task(file_ctx,
                                                           &file_ctx->buffer)
                     == NGX_ERROR))
    {
        return ngx_http_lua_io_handle_error(L, r, file_ctx);
    }

    file_ctx->read_waiting = 1;

    ngx_http_lua_io_before_yield(r, file_ctx);

    return lua_yield(L, 0);
}


static ngx_int_t
ngx_http_lua_io_file_do_read(ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *file_ctx)
{

    size_t      size;
    ngx_buf_t  *b;
    ngx_int_t   rc;

    ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua io do read, waiting:%d", file_ctx->read_waiting);

    b = &file_ctx->buffer;

    for ( ;; ) {

        size = b->last - b->pos;

        if (size == 0 && !file_ctx->eof) {
            break;
        }

        rc = file_ctx->input_filter(file_ctx, b, size);
        if (rc == NGX_OK) {
            ngx_log_debug1(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                           "lua io read done, waiting:%d",
                           file_ctx->read_waiting);

            return NGX_OK;
        }

        if (rc == NGX_AGAIN) {
            break;
        }
    }

    if (file_ctx->eof) {
        return NGX_OK;
    }

    size = b->end - b->last;
    if (size == 0) {
        rc = ngx_http_lua_io_add_input_buffer(r, file_ctx);

        if (NGX_UNLIKELY(rc == NGX_ERROR)) {
            file_ctx->ft_type |= NGX_HTTP_LUA_IO_FT_NO_MEMORY;
            return NGX_ERROR;
        }
    }

    return NGX_AGAIN;
}


static ngx_int_t
ngx_http_lua_io_add_input_buffer(ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *file_ctx)
{
    ngx_chain_t                 *cl;
    ngx_http_lua_io_loc_conf_t  *iocf;
    ngx_http_lua_io_ctx_t       *ioctx;

    ioctx = ngx_http_get_module_ctx(r, ngx_http_lua_io_module);
    iocf = ngx_http_get_module_loc_conf(r, ngx_http_lua_io_module);

    cl = ngx_http_lua_chain_get_free_buf(r->connection->log, r->pool,
                                         &ioctx->free_read_bufs,
                                         iocf->read_buf_size);

    if (cl == NULL) {
        return NGX_ERROR;
    }

    file_ctx->buf_in->next = cl;
    file_ctx->buf_in = cl;
    file_ctx->buffer = *cl->buf;

    return NGX_OK;
}


static int
ngx_http_lua_io_submit_input_data(ngx_http_request_t *r,
    ngx_http_lua_io_file_ctx_t *file_ctx, lua_State *L)
{
    luaL_Buffer             luabuf;
    ngx_int_t               nbufs, eof;
    ngx_chain_t            *cl, **ll;
    ngx_buf_t              *b;
    size_t                  size;
    off_t                   offset;
    ngx_http_lua_io_ctx_t  *ioctx;

    ngx_log_debug2(NGX_LOG_DEBUG_HTTP, r->connection->log, 0,
                   "lua submit input data, bufs_in:%p buf_in: %p",
                   file_ctx->bufs_in, file_ctx->buf_in);

    luaL_buffinit(L, &luabuf);

    offset = 0;

    nbufs = 0;
    ll = NULL;

    for (cl = file_ctx->bufs_in; cl; cl = cl->next) {
        b = cl->buf;
        size = b->last - b->pos;

        luaL_addlstring(&luabuf, (const char *) b->pos, size);

        offset += size;

        if (cl->next) {
            ll = &cl->next;
        }

        nbufs++;
    }

    eof = file_ctx->buffer.last == file_ctx->buffer.pos;

    if (file_ctx->eof && eof && offset == 0) {
        lua_pushnil(L);

    } else {
        file_ctx->offset += offset;
        luaL_pushresult(&luabuf);
    }

    if (nbufs > 1 && ll) {
        ioctx = ngx_http_get_module_ctx(r, ngx_http_lua_io_module);

        *ll = ioctx->free_read_bufs;
        ioctx->free_read_bufs = file_ctx->bufs_in;
        file_ctx->bufs_in = file_ctx->buf_in;
    }

    b = &file_ctx->buffer;

    if (eof) {
        b->pos = b->start;
        b->last = b->start;
    }

    if (file_ctx->bufs_in) {
        file_ctx->bufs_in->buf->pos = b->pos;
        file_ctx->bufs_in->buf->last = b->pos;
    }

    return 1;
}
