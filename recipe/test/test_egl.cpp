#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GL/gl.h>
#include <stdio.h>

int main() {
    // Step 1: Get EGL display
    EGLDisplay display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (display == EGL_NO_DISPLAY) {
        printf("No EGL display\n");
        return 1;
    }

    if (!eglInitialize(display, nullptr, nullptr)) {
        printf("Failed to initialize EGL\n");
        return 2;
    }

    printf("EGL initialized successfully\n");

    // Step 2: Choose an EGL config
    EGLint configAttribs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT,
        EGL_NONE
    };

    EGLConfig config;
    EGLint numConfigs;
    if (!eglChooseConfig(display, configAttribs, &config, 1, &numConfigs)) {
        printf("Failed to choose EGL config\n");
        return 3;
    }

    // Step 3: Create a small PBuffer surface (offscreen)
    EGLint pbufferAttribs[] = {
        EGL_WIDTH, 64,
        EGL_HEIGHT, 64,
        EGL_NONE,
    };

    EGLSurface surface = eglCreatePbufferSurface(display, config, pbufferAttribs);
    if (surface == EGL_NO_SURFACE) {
        printf("Failed to create EGL PBuffer surface\n");
        return 4;
    }

    // Step 4: Bind OpenGL API (not OpenGL ES!)
    if (!eglBindAPI(EGL_OPENGL_API)) {
        printf("Failed to bind OpenGL API\n");
        return 5;
    }

    // Step 5: Create a desktop OpenGL context
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT, nullptr);
    if (context == EGL_NO_CONTEXT) {
        printf("Failed to create EGL context\n");
        return 6;
    }

    // Step 6: Make context current
    if (!eglMakeCurrent(display, surface, surface, context)) {
        printf("Failed to make EGL context current\n");
        return 7;
    }

    // Step 7: Print OpenGL info
    const GLubyte *renderer = glGetString(GL_RENDERER);
    const GLubyte *version  = glGetString(GL_VERSION);

    printf("OpenGL Renderer: %s\n", renderer);
    printf("OpenGL Version : %s\n", version);

    printf("EGL + OpenGL context initialized!\n");

    // Step 8: Cleanup
    eglDestroySurface(display, surface);
    eglDestroyContext(display, context);
    eglTerminate(display);

    return 0;
}
