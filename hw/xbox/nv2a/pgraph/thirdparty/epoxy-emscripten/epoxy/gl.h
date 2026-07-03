#ifndef XEMU_EPOXY_EMSCRIPTEN_GL_H
#define XEMU_EPOXY_EMSCRIPTEN_GL_H

#include <stdbool.h>

#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>

#ifndef GL_BGRA
#define GL_BGRA 0x80E1
#endif

#ifndef GL_BGR
#define GL_BGR 0x80E0
#endif

#ifndef GL_CLAMP
#define GL_CLAMP 0x2900
#endif

#ifndef GL_CLAMP_TO_BORDER
#define GL_CLAMP_TO_BORDER 0x812D
#endif

#ifndef GL_COMPRESSED_RGBA_S3TC_DXT1_EXT
#define GL_COMPRESSED_RGBA_S3TC_DXT1_EXT 0x83F1
#endif

#ifndef GL_COMPRESSED_RGBA_S3TC_DXT3_EXT
#define GL_COMPRESSED_RGBA_S3TC_DXT3_EXT 0x83F2
#endif

#ifndef GL_COMPRESSED_RGBA_S3TC_DXT5_EXT
#define GL_COMPRESSED_RGBA_S3TC_DXT5_EXT 0x83F3
#endif

#ifndef GL_DEBUG_OUTPUT
#define GL_DEBUG_OUTPUT 0x92E0
#endif

#ifndef GL_DEBUG_SEVERITY_NOTIFICATION
#define GL_DEBUG_SEVERITY_NOTIFICATION 0x826B
#endif

#ifndef GL_DEBUG_SOURCE_APPLICATION
#define GL_DEBUG_SOURCE_APPLICATION 0x824A
#endif

#ifndef GL_DEBUG_TYPE_MARKER
#define GL_DEBUG_TYPE_MARKER 0x8268
#endif

#ifndef GL_DEPTH_CLAMP
#define GL_DEPTH_CLAMP 0x864F
#endif

#ifndef GL_FIRST_VERTEX_CONVENTION
#define GL_FIRST_VERTEX_CONVENTION 0x8E4D
#endif

#ifndef GL_GEOMETRY_SHADER
#define GL_GEOMETRY_SHADER 0x8DD9
#endif

#ifndef GL_LINE_SMOOTH
#define GL_LINE_SMOOTH 0x0B20
#endif

#ifndef GL_LINES_ADJACENCY
#define GL_LINES_ADJACENCY 0x000A
#endif

#ifndef GL_LINE_STRIP_ADJACENCY
#define GL_LINE_STRIP_ADJACENCY 0x000B
#endif

#ifndef GL_PACK_ROW_LENGTH
#define GL_PACK_ROW_LENGTH 0x0D02
#endif

#ifndef GL_POLYGON_OFFSET_LINE
#define GL_POLYGON_OFFSET_LINE 0x2A02
#endif

#ifndef GL_POLYGON_OFFSET_POINT
#define GL_POLYGON_OFFSET_POINT 0x2A01
#endif

#ifndef GL_POLYGON_SMOOTH
#define GL_POLYGON_SMOOTH 0x0B41
#endif

#ifndef GL_PROGRAM_BINARY_LENGTH
#define GL_PROGRAM_BINARY_LENGTH 0x8741
#endif

#ifndef GL_PROGRAM_POINT_SIZE
#define GL_PROGRAM_POINT_SIZE 0x8642
#endif

#ifndef GL_R16
#define GL_R16 0x822A
#endif

#ifndef GL_QUERY_RESULT
#define GL_QUERY_RESULT 0x8866
#endif

#ifndef GL_RGB5
#define GL_RGB5 0x8050
#endif

#ifndef GL_SAMPLES_PASSED
#define GL_SAMPLES_PASSED 0x8914
#endif

#ifndef GL_FILL
#define GL_FILL 0x1B02
#endif

#ifndef GL_SMOOTH_LINE_WIDTH_RANGE
#define GL_SMOOTH_LINE_WIDTH_RANGE 0x0B22
#endif

#ifndef GL_TEXTURE_1D
#define GL_TEXTURE_1D 0x0DE0
#endif

#ifndef GL_TEXTURE_BORDER_COLOR
#define GL_TEXTURE_BORDER_COLOR 0x1004
#endif

#ifndef GL_TEXTURE_LOD_BIAS
#define GL_TEXTURE_LOD_BIAS 0x8501
#endif

#ifndef GL_TEXTURE_MAX_ANISOTROPY_EXT
#define GL_TEXTURE_MAX_ANISOTROPY_EXT 0x84FE
#endif

#ifndef GL_TEXTURE_SWIZZLE_RGBA
#define GL_TEXTURE_SWIZZLE_RGBA 0x8E46
#endif

#ifndef GL_UNSIGNED_INT_8_8_8_8
#define GL_UNSIGNED_INT_8_8_8_8 0x8035
#endif

#ifndef GL_UNSIGNED_INT_8_8_8_8_REV
#define GL_UNSIGNED_INT_8_8_8_8_REV 0x8367
#endif

#ifndef GL_UNSIGNED_SHORT_1_5_5_5_REV
#define GL_UNSIGNED_SHORT_1_5_5_5_REV 0x8366
#endif

#ifndef GL_UNSIGNED_SHORT_4_4_4_4_REV
#define GL_UNSIGNED_SHORT_4_4_4_4_REV 0x8365
#endif

static inline void glClearDepth(GLdouble depth)
{
    glClearDepthf((GLfloat)depth);
}

static inline void glMultiDrawArrays(GLenum mode, const GLint *first,
                                     const GLsizei *count, GLsizei drawcount)
{
    for (GLsizei i = 0; i < drawcount; i++) {
        glDrawArrays(mode, first[i], count[i]);
    }
}

static inline void glPolygonMode(GLenum face, GLenum mode)
{
    (void)face;
    (void)mode;
}

static inline void glProgramUniform1i(GLuint program, GLint location,
                                      GLint v0)
{
    GLint previous_program = 0;

    glGetIntegerv(GL_CURRENT_PROGRAM, &previous_program);
    glUseProgram(program);
    glUniform1i(location, v0);
    glUseProgram((GLuint)previous_program);
}

static inline void glProgramUniform2f(GLuint program, GLint location,
                                      GLfloat v0, GLfloat v1)
{
    GLint previous_program = 0;

    glGetIntegerv(GL_CURRENT_PROGRAM, &previous_program);
    glUseProgram(program);
    glUniform2f(location, v0, v1);
    glUseProgram((GLuint)previous_program);
}

static inline void glProvokingVertex(GLenum provoke_mode)
{
    (void)provoke_mode;
}

static inline bool epoxy_has_gl_extension(const char *name)
{
    return true;
}

#ifdef XEMU_BROWSER_GL_EXPERIMENT
void xemu_browser_glGenBuffers(GLsizei n, GLuint *buffers);
void xemu_browser_glGenFramebuffers(GLsizei n, GLuint *framebuffers);
void xemu_browser_glGenQueries(GLsizei n, GLuint *queries);
void xemu_browser_glGenRenderbuffers(GLsizei n, GLuint *renderbuffers);
void xemu_browser_glGenTextures(GLsizei n, GLuint *textures);
void xemu_browser_glGenVertexArrays(GLsizei n, GLuint *arrays);
void xemu_browser_glBindBuffer(GLenum target, GLuint buffer);
void xemu_browser_glBindVertexArray(GLuint array);
void xemu_browser_glBufferData(GLenum target, GLsizeiptr size,
                               const void *data, GLenum usage);
void xemu_browser_glBufferSubData(GLenum target, GLintptr offset,
                                  GLsizeiptr size, const void *data);
GLenum xemu_browser_glGetError(void);
void xemu_browser_glGetIntegerv(GLenum pname, GLint *data);
const GLubyte *xemu_browser_glGetString(GLenum name);

#define glGenBuffers xemu_browser_glGenBuffers
#define glGenFramebuffers xemu_browser_glGenFramebuffers
#define glGenQueries xemu_browser_glGenQueries
#define glGenRenderbuffers xemu_browser_glGenRenderbuffers
#define glGenTextures xemu_browser_glGenTextures
#define glGenVertexArrays xemu_browser_glGenVertexArrays
#define glBindBuffer xemu_browser_glBindBuffer
#define glBindVertexArray xemu_browser_glBindVertexArray
#define glBufferData xemu_browser_glBufferData
#define glBufferSubData xemu_browser_glBufferSubData
#define glGetError xemu_browser_glGetError
#define glGetIntegerv xemu_browser_glGetIntegerv
#define glGetString xemu_browser_glGetString
#endif

#endif
