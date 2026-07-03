/*
 *  Offscreen OpenGL abstraction layer -- SDL based
 *
 *  Copyright (c) 2018-2024 Matt Borgerson
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <stdbool.h>

#include "gloffscreen.h"

#ifdef __EMSCRIPTEN__

#include <emscripten/emscripten.h>
#include <emscripten/html5_webgl.h>

struct _GloContext {
    EMSCRIPTEN_WEBGL_CONTEXT_HANDLE gl_context;
    char canvas_id[64];
};

#ifndef XEMU_BROWSER_GL_EXPERIMENT
static int next_context_id;
#endif

EM_JS(int, register_offscreen_canvas_js, (const char *canvas_id), {
    if (typeof OffscreenCanvas !== "function" || typeof GL === "undefined") {
        return 0;
    }

    const selector = UTF8ToString(canvas_id);
    const id = selector.replace(/^#/, "");
    const canvas = new OffscreenCanvas(640, 480);
    canvas.id = id;
    GL.offscreenCanvases[id] = {
        canvas: canvas,
        id: id,
    };
    return 1;
});

static int register_offscreen_canvas(const char *canvas_id)
{
    return register_offscreen_canvas_js(canvas_id);
}

EM_JS(int, browser_make_context_current_js,
      (EMSCRIPTEN_WEBGL_CONTEXT_HANDLE gl_context), {
    if (typeof GL === "undefined" || typeof GL.makeContextCurrent !== "function") {
        return -1;
    }
    return GL.makeContextCurrent(gl_context) ? 0 : -5;
});

EM_JS(int, browser_gl_has_current_context_js, (void), {
    return (typeof GL !== "undefined" &&
            typeof GLctx !== "undefined" &&
            !!GLctx &&
            !!GL.currentContext) ? 1 : 0;
});

EM_JS(void, browser_patch_gl_context_helpers_js, (void), {
    if (typeof GL === "undefined" || GL.xemuGenObjectPatched) {
        return;
    }

    GL.genObject = (n, buffers, createFunction, objectTable) => {
        const ctx = (typeof GLctx !== "undefined" && GLctx) ||
            (GL.currentContext && GL.currentContext.GLctx) ||
            Module.ctx;
        if (!ctx || typeof ctx[createFunction] !== "function") {
            GL.recordError(0x502 /* GL_INVALID_OPERATION */);
            return;
        }
        if (typeof GLctx === "undefined" || !GLctx) {
            Module.ctx = GLctx = ctx;
        }

        for (let i = 0; i < n; i++) {
            const object = ctx[createFunction]();
            const id = object && GL.getNewId(objectTable);
            if (object) {
                object.name = id;
                objectTable[id] = object;
            } else {
                GL.recordError(0x502 /* GL_INVALID_OPERATION */);
            }
            HEAP32[((buffers + i * 4) >> 2)] = id;
        }
    };
    GL.xemuGenObjectPatched = true;
});

EM_JS(void, browser_gl_gen_object_js,
      (int n, GLuint *ids, int object_kind), {
    const specs = [
        ["createBuffer", GL.buffers],
        ["createFramebuffer", GL.framebuffers],
        ["createQuery", GL.queries],
        ["createRenderbuffer", GL.renderbuffers],
        ["createTexture", GL.textures],
        ["createVertexArray", GL.vaos],
    ];
    const spec = specs[object_kind];
    const ctx = (typeof GLctx !== "undefined" && GLctx) ||
        (GL.currentContext && GL.currentContext.GLctx) ||
        Module.ctx;

    if (!spec || !ctx || typeof ctx[spec[0]] !== "function") {
        GL.recordError(0x502 /* GL_INVALID_OPERATION */);
        return;
    }

    if (typeof GLctx === "undefined" || !GLctx) {
        Module.ctx = GLctx = ctx;
    }

    const createFunction = spec[0];
    const objectTable = spec[1];
    for (let i = 0; i < n; i++) {
        const object = ctx[createFunction]();
        const id = object && GL.getNewId(objectTable);
        if (object) {
            object.name = id;
            objectTable[id] = object;
        } else {
            GL.recordError(0x502 /* GL_INVALID_OPERATION */);
        }
        HEAPU32[((ids + i * 4) >> 2)] = id;
    }
});

void xemu_browser_glGenBuffers(GLsizei n, GLuint *buffers)
{
    browser_gl_gen_object_js(n, buffers, 0);
}

void xemu_browser_glGenFramebuffers(GLsizei n, GLuint *framebuffers)
{
    browser_gl_gen_object_js(n, framebuffers, 1);
}

void xemu_browser_glGenQueries(GLsizei n, GLuint *queries)
{
    browser_gl_gen_object_js(n, queries, 2);
}

void xemu_browser_glGenRenderbuffers(GLsizei n, GLuint *renderbuffers)
{
    browser_gl_gen_object_js(n, renderbuffers, 3);
}

void xemu_browser_glGenTextures(GLsizei n, GLuint *textures)
{
    browser_gl_gen_object_js(n, textures, 4);
}

void xemu_browser_glGenVertexArrays(GLsizei n, GLuint *arrays)
{
    browser_gl_gen_object_js(n, arrays, 5);
}

EM_JS(void, browser_gl_get_integerv_js, (GLenum pname, GLint *data), {
    const ctx = (typeof GLctx !== "undefined" && GLctx) ||
        (GL.currentContext && GL.currentContext.GLctx) ||
        Module.ctx;

    if (!ctx || !data) {
        GL.recordError(0x502 /* GL_INVALID_OPERATION */);
        return;
    }

    if (typeof GLctx === "undefined" || !GLctx) {
        Module.ctx = GLctx = ctx;
    }

    let value = ctx.getParameter(pname);
    if (value && typeof value === "object" && typeof value.name === "number") {
        value = value.name;
    }

    if (typeof value === "boolean") {
        HEAP32[data >> 2] = value ? 1 : 0;
    } else if (typeof value === "number") {
        HEAP32[data >> 2] = value;
    } else if (value && typeof value.length === "number") {
        for (let i = 0; i < value.length; i++) {
            let item = value[i];
            if (item && typeof item === "object" && typeof item.name === "number") {
                item = item.name;
            }
            HEAP32[(data >> 2) + i] = Number(item) || 0;
        }
    } else {
        HEAP32[data >> 2] = 0;
    }
});

void xemu_browser_glGetIntegerv(GLenum pname, GLint *data)
{
    browser_gl_get_integerv_js(pname, data);
}

EM_JS(void, browser_gl_bind_buffer_js, (GLenum target, GLuint buffer), {
    const ctx = (typeof GLctx !== "undefined" && GLctx) ||
        (GL.currentContext && GL.currentContext.GLctx) ||
        Module.ctx;

    if (!ctx) {
        GL.recordError(0x502 /* GL_INVALID_OPERATION */);
        return;
    }
    if (typeof GLctx === "undefined" || !GLctx) {
        Module.ctx = GLctx = ctx;
    }

    if (buffer && !GL.buffers[buffer]) {
        const object = ctx.createBuffer();
        object.name = buffer;
        GL.buffers[buffer] = object;
    }
    if (target === 0x8892 /* GL_ARRAY_BUFFER */) {
        ctx.currentArrayBufferBinding = buffer;
    } else if (target === 0x8893 /* GL_ELEMENT_ARRAY_BUFFER */) {
        ctx.currentElementArrayBufferBinding = buffer;
    } else if (target === 0x88EB /* GL_PIXEL_PACK_BUFFER */) {
        ctx.currentPixelPackBufferBinding = buffer;
    } else if (target === 0x88EC /* GL_PIXEL_UNPACK_BUFFER */) {
        ctx.currentPixelUnpackBufferBinding = buffer;
    }
    ctx.bindBuffer(target, buffer ? GL.buffers[buffer] : null);
});

void xemu_browser_glBindBuffer(GLenum target, GLuint buffer)
{
    browser_gl_bind_buffer_js(target, buffer);
}

EM_JS(void, browser_gl_buffer_data_js,
      (GLenum target, GLsizeiptr size, const void *data, GLenum usage), {
    const ctx = (typeof GLctx !== "undefined" && GLctx) ||
        (GL.currentContext && GL.currentContext.GLctx) ||
        Module.ctx;

    if (!ctx) {
        GL.recordError(0x502 /* GL_INVALID_OPERATION */);
        return;
    }
    if (typeof GLctx === "undefined" || !GLctx) {
        Module.ctx = GLctx = ctx;
    }

    if (data && size) {
        const start = Number(data) >>> 0;
        const length = Number(size) >>> 0;
        const end = start + length;
        if (end > HEAPU8.length) {
            GL.recordError(0x501 /* GL_INVALID_VALUE */);
            return;
        }
        ctx.bufferData(target, HEAPU8.subarray(start, end), usage);
    } else {
        ctx.bufferData(target, size, usage);
    }
});

void xemu_browser_glBufferData(GLenum target, GLsizeiptr size,
                               const void *data, GLenum usage)
{
    browser_gl_buffer_data_js(target, size, data, usage);
}

EM_JS(void, browser_gl_buffer_sub_data_js,
      (GLenum target, GLintptr offset, GLsizeiptr size, const void *data), {
    const ctx = (typeof GLctx !== "undefined" && GLctx) ||
        (GL.currentContext && GL.currentContext.GLctx) ||
        Module.ctx;

    if (!ctx) {
        GL.recordError(0x502 /* GL_INVALID_OPERATION */);
        return;
    }
    if (typeof GLctx === "undefined" || !GLctx) {
        Module.ctx = GLctx = ctx;
    }

    if (size) {
        const start = Number(data) >>> 0;
        const length = Number(size) >>> 0;
        const end = start + length;
        if (end > HEAPU8.length) {
            GL.recordError(0x501 /* GL_INVALID_VALUE */);
            return;
        }
        ctx.bufferSubData(target, Number(offset), HEAPU8.subarray(start, end));
    }
});

void xemu_browser_glBufferSubData(GLenum target, GLintptr offset,
                                  GLsizeiptr size, const void *data)
{
    browser_gl_buffer_sub_data_js(target, offset, size, data);
}

EM_JS(void, browser_gl_bind_vertex_array_js, (GLuint array), {
    const ctx = (typeof GLctx !== "undefined" && GLctx) ||
        (GL.currentContext && GL.currentContext.GLctx) ||
        Module.ctx;

    if (!ctx) {
        GL.recordError(0x502 /* GL_INVALID_OPERATION */);
        return;
    }
    if (typeof GLctx === "undefined" || !GLctx) {
        Module.ctx = GLctx = ctx;
    }

    ctx.bindVertexArray(array ? GL.vaos[array] : null);
    const ibo = ctx.getParameter(0x8895 /* ELEMENT_ARRAY_BUFFER_BINDING */);
    ctx.currentElementArrayBufferBinding = ibo ? (ibo.name | 0) : 0;
});

void xemu_browser_glBindVertexArray(GLuint array)
{
    browser_gl_bind_vertex_array_js(array);
}

EM_JS(GLenum, browser_gl_get_error_js, (void), {
    const ctx = (typeof GLctx !== "undefined" && GLctx) ||
        (GL.currentContext && GL.currentContext.GLctx) ||
        Module.ctx;

    if (!ctx) {
        return GL.lastError || 0x502 /* GL_INVALID_OPERATION */;
    }
    if (typeof GLctx === "undefined" || !GLctx) {
        Module.ctx = GLctx = ctx;
    }

    const error = ctx.getError() || GL.lastError || 0;
    GL.lastError = 0;
    return error;
});

GLenum xemu_browser_glGetError(void)
{
    return browser_gl_get_error_js();
}

EM_JS(const GLubyte *, browser_gl_get_string_js, (GLenum name), {
    const stringToOwnedUTF8 = (value) => {
        const bytes = new TextEncoder().encode(String(value));
        const ptr = _malloc(bytes.length + 1);
        if (!ptr) {
            return 0;
        }
        HEAPU8.set(bytes, ptr);
        HEAPU8[ptr + bytes.length] = 0;
        return ptr;
    };
    const ctx = (typeof GLctx !== "undefined" && GLctx) ||
        (GL.currentContext && GL.currentContext.GLctx) ||
        Module.ctx;

    if (!ctx) {
        GL.recordError(0x502 /* GL_INVALID_OPERATION */);
        return 0;
    }
    if (typeof GLctx === "undefined" || !GLctx) {
        Module.ctx = GLctx = ctx;
    }

    let ret = GL.stringCache[name];
    if (ret) {
        return ret;
    }

    switch (name) {
    case 0x1F03: /* GL_EXTENSIONS */
        ret = stringToOwnedUTF8(webglGetExtensions().join(" "));
        break;
    case 0x1F00: /* GL_VENDOR */
    case 0x1F01: /* GL_RENDERER */
    case 0x9245: /* UNMASKED_VENDOR_WEBGL */
    case 0x9246: /* UNMASKED_RENDERER_WEBGL */ {
        const value = ctx.getParameter(name);
        if (!value) {
            GL.recordError(0x500 /* GL_INVALID_ENUM */);
        }
        ret = value ? stringToOwnedUTF8(value) : 0;
        break;
    }
    case 0x1F02: { /* GL_VERSION */
        const webGLVersion = ctx.getParameter(0x1F02 /* GL_VERSION */);
        ret = stringToOwnedUTF8(`OpenGL ES 3.0 (${webGLVersion})`);
        break;
    }
    case 0x8B8C: { /* GL_SHADING_LANGUAGE_VERSION */
        let glslVersion = ctx.getParameter(0x8B8C);
        const verNum = glslVersion.match(/^WebGL GLSL ES ([0-9][.][0-9][0-9]?)(?:$| .*)/);
        if (verNum !== null) {
            if (verNum[1].length === 3) {
                verNum[1] = verNum[1] + "0";
            }
            glslVersion = `OpenGL ES GLSL ES ${verNum[1]} (${glslVersion})`;
        }
        ret = stringToOwnedUTF8(glslVersion);
        break;
    }
    default:
        GL.recordError(0x500 /* GL_INVALID_ENUM */);
        ret = 0;
        break;
    }

    GL.stringCache[name] = ret;
    return ret;
});

const GLubyte *xemu_browser_glGetString(GLenum name)
{
    return browser_gl_get_string_js(name);
}

/* Create an OpenGL context */
GloContext *glo_context_create(void)
{
    GloContext *context = (GloContext *)calloc(1, sizeof(GloContext));
    assert(context != NULL);

#ifdef XEMU_BROWSER_GL_EXPERIMENT
    snprintf(context->canvas_id, sizeof(context->canvas_id), "#canvas");
    if (!register_offscreen_canvas(context->canvas_id)) {
        fprintf(stderr, "%s: Failed to create browser OffscreenCanvas\n",
                __func__);
        exit(1);
    }
#else
    snprintf(context->canvas_id, sizeof(context->canvas_id),
             "#xemu-glo-%d", next_context_id++);
    if (!register_offscreen_canvas(context->canvas_id)) {
        fprintf(stderr, "%s: Failed to create browser OffscreenCanvas\n",
                __func__);
        exit(1);
    }
#endif

    EmscriptenWebGLContextAttributes attrs;
    emscripten_webgl_init_context_attributes(&attrs);
    attrs.alpha = true;
    attrs.depth = true;
    attrs.stencil = true;
    attrs.majorVersion = 2;
    attrs.minorVersion = 0;
    attrs.enableExtensionsByDefault = true;
    attrs.proxyContextToMainThread = EMSCRIPTEN_WEBGL_CONTEXT_PROXY_DISALLOW;

    context->gl_context = emscripten_webgl_create_context(context->canvas_id,
                                                          &attrs);
    if (!context->gl_context) {
        fprintf(stderr, "%s: Failed to create browser WebGL context\n",
                __func__);
        exit(1);
    }

    browser_patch_gl_context_helpers_js();
    glo_set_current(context);
    return context;
}

/* Set current context */
void glo_set_current(GloContext *context)
{
    EMSCRIPTEN_WEBGL_CONTEXT_HANDLE gl_context =
        context ? context->gl_context : 0;
    EMSCRIPTEN_RESULT result =
        emscripten_webgl_make_context_current(gl_context);
    int active = browser_gl_has_current_context_js();

    if (result == EMSCRIPTEN_RESULT_SUCCESS && gl_context && !active) {
        result = browser_make_context_current_js(gl_context);
        active = browser_gl_has_current_context_js();
    }

    if (result == EMSCRIPTEN_RESULT_SUCCESS && gl_context) {
        browser_patch_gl_context_helpers_js();
    }

    if (result != EMSCRIPTEN_RESULT_SUCCESS) {
        fprintf(stderr, "%s: Failed to make browser WebGL context current: %d\n",
                __func__, result);
    }
}

/* Destroy a previously created OpenGL context */
void glo_context_destroy(GloContext *context)
{
    if (!context) {
        return;
    }
    if (context->gl_context) {
        emscripten_webgl_destroy_context(context->gl_context);
    }
    free(context);
}

#else

#include <SDL3/SDL.h>

struct _GloContext {
    SDL_Window    *window;
    SDL_GLContext gl_context;
};

/* Create an OpenGL context */
GloContext *glo_context_create(void)
{
    GloContext *context = (GloContext *)malloc(sizeof(GloContext));
    assert(context != NULL);

    SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);
    SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
    SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);

    // Initialize rendering context
    SDL_GL_SetAttribute(SDL_GL_SHARE_WITH_CURRENT_CONTEXT, 1);
#ifdef __EMSCRIPTEN__
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    SDL_GL_SetAttribute(
        SDL_GL_CONTEXT_PROFILE_MASK,
        SDL_GL_CONTEXT_PROFILE_ES);
#else
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 4);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    SDL_GL_SetAttribute(
        SDL_GL_CONTEXT_PROFILE_MASK,
        SDL_GL_CONTEXT_PROFILE_CORE);
#endif

    // Create main window
    context->window = SDL_CreateWindow(
        "SDL Offscreen Window",
        640, 480,
        SDL_WINDOW_OPENGL | SDL_WINDOW_HIDDEN);
    if (context->window == NULL) {
        fprintf(stderr, "%s: Failed to create window\n", __func__);
        SDL_Quit();
        exit(1);
    }

    context->gl_context = SDL_GL_CreateContext(context->window);
    if (context->gl_context == NULL) {
        fprintf(stderr, "%s: Failed to create GL context\n", __func__);
        SDL_DestroyWindow(context->window);
        SDL_Quit();
        exit(1);
    }

    glo_set_current(context);

    return context;
}

/* Set current context */
void glo_set_current(GloContext *context)
{
    if (context == NULL) {
        SDL_GL_MakeCurrent(NULL, NULL);
    } else {
        SDL_GL_MakeCurrent(context->window, context->gl_context);
    }
}

/* Destroy a previously created OpenGL context */
void glo_context_destroy(GloContext *context)
{
    if (!context) return;
    glo_set_current(NULL);
    free(context);
}

#endif
