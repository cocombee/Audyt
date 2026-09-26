#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <setjmp.h>
#include "jpeglib.h"
#ifdef _WIN32
#define API __declspec(dllexport)
#else
#define API __attribute__((visibility("default")))
#endif
struct safe_error { struct jpeg_error_mgr base; jmp_buf jump; };
static void fail(j_common_ptr c) { struct safe_error *e=(struct safe_error*)c->err; longjmp(e->jump,1); }
API void *audyt_jpeg_alloc(size_t n) { return malloc(n); }
API void audyt_jpeg_free(void *p) { free(p); }
API unsigned char *audyt_jpeg_encode(const unsigned char *rgb, int w, int h, int quality, size_t *length) {
 if (!rgb || !length || w<=0 || h<=0 || (uint64_t)w*h>24000000 || quality<1 || quality>100) return NULL;
 *length=0;
 struct jpeg_compress_struct c={0}; struct safe_error error;
 unsigned char *out=NULL; unsigned long size=0;
 c.err=jpeg_std_error(&error.base); error.base.error_exit=fail;
 if(setjmp(error.jump)) { jpeg_destroy_compress(&c); free(out); return NULL; }
 jpeg_create_compress(&c); jpeg_mem_dest(&c,&out,&size);
 c.image_width=w; c.image_height=h; c.input_components=3; c.in_color_space=JCS_RGB;
 jpeg_set_defaults(&c); jpeg_set_quality(&c,quality,TRUE);
 c.optimize_coding=TRUE; jpeg_simple_progression(&c);
 jpeg_start_compress(&c,TRUE);
 while(c.next_scanline<c.image_height) { JSAMPROW row=(JSAMPROW)(rgb+(size_t)c.next_scanline*w*3); jpeg_write_scanlines(&c,&row,1); }
 jpeg_finish_compress(&c); jpeg_destroy_compress(&c); *length=size; return out;
}

API unsigned char *audyt_jpeg_decode(const unsigned char *bytes, size_t length, int *w, int *h, size_t *output_length) {
 if(!bytes || !length || !w || !h || !output_length) return NULL;
 struct decode_context { struct jpeg_decompress_struct c; struct safe_error error; unsigned char *out; };
 struct decode_context *ctx=calloc(1,sizeof(*ctx)); if(!ctx) return NULL;
 ctx->c.err=jpeg_std_error(&ctx->error.base);ctx->error.base.error_exit=fail;
 if(setjmp(ctx->error.jump)) {jpeg_destroy_decompress(&ctx->c);free(ctx->out);free(ctx);return NULL;}
 jpeg_create_decompress(&ctx->c);jpeg_mem_src(&ctx->c,bytes,length);jpeg_read_header(&ctx->c,TRUE);
 if((uint64_t)ctx->c.image_width*ctx->c.image_height>40000000) {jpeg_destroy_decompress(&ctx->c);free(ctx);return NULL;}
 ctx->c.out_color_space=JCS_RGB;jpeg_start_decompress(&ctx->c);
 *w=ctx->c.output_width;*h=ctx->c.output_height;*output_length=(size_t)*w**h*3;
 ctx->out=malloc(*output_length);if(!ctx->out) {jpeg_destroy_decompress(&ctx->c);free(ctx);return NULL;}
 while(ctx->c.output_scanline<ctx->c.output_height) {JSAMPROW row=ctx->out+(size_t)ctx->c.output_scanline**w*3;jpeg_read_scanlines(&ctx->c,&row,1);}
 jpeg_finish_decompress(&ctx->c);jpeg_destroy_decompress(&ctx->c);unsigned char *out=ctx->out;free(ctx);return out;
}
