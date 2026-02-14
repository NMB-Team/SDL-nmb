/*
  Simple DirectMedia Layer
  Copyright (C) 1997-2026 Sam Lantinga <slouken@libsdl.org>

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.
*/
#include "SDL_internal.h"

#if defined(SDL_VIDEO_DRIVER_COCOA) && defined(SDL_VIDEO_OPENGL_EGL)

#include "SDL_cocoavideo.h"
#include "SDL_cocoaopengles.h"
#include "SDL_cocoaopengl.h"
#include "SDL_cocoametalview.h"

// EGL implementation of SDL OpenGL support

bool Cocoa_GLES_LoadLibrary(SDL_VideoDevice *_this, const char *path)
{
    // If the profile requested is not GL ES, switch over to WIN_GL functions
    if (_this->gl_config.profile_mask != SDL_GL_CONTEXT_PROFILE_ES) {
#ifdef SDL_VIDEO_OPENGL_CGL
        Cocoa_GLES_UnloadLibrary(_this);
        _this->GL_LoadLibrary = Cocoa_GL_LoadLibrary;
        _this->GL_GetProcAddress = Cocoa_GL_GetProcAddress;
        _this->GL_UnloadLibrary = Cocoa_GL_UnloadLibrary;
        _this->GL_CreateContext = Cocoa_GL_CreateContext;
        _this->GL_MakeCurrent = Cocoa_GL_MakeCurrent;
        _this->GL_SetSwapInterval = Cocoa_GL_SetSwapInterval;
        _this->GL_GetSwapInterval = Cocoa_GL_GetSwapInterval;
        _this->GL_SwapWindow = Cocoa_GL_SwapWindow;
        _this->GL_DestroyContext = Cocoa_GL_DestroyContext;
        _this->GL_GetEGLSurface = NULL;
        return Cocoa_GL_LoadLibrary(_this, path);
#else
        return SDL_SetError("SDL not configured with OpenGL/CGL support");
#endif
    }

    if (_this->egl_data == NULL) {
        return SDL_EGL_LoadLibrary(_this, NULL, EGL_DEFAULT_DISPLAY);
    }

    return true;
}

SDL_GLContext Cocoa_GLES_CreateContext(SDL_VideoDevice *_this, SDL_Window *window)
{
    @autoreleasepool {
        SDL_GLContext context;
        SDL_CocoaWindowData *data = (__bridge SDL_CocoaWindowData *)window->internal;

#ifdef SDL_VIDEO_OPENGL_CGL
        if (_this->gl_config.profile_mask != SDL_GL_CONTEXT_PROFILE_ES) {
            // Switch to CGL based functions
            Cocoa_GLES_UnloadLibrary(_this);
            _this->GL_LoadLibrary = Cocoa_GL_LoadLibrary;
            _this->GL_GetProcAddress = Cocoa_GL_GetProcAddress;
            _this->GL_UnloadLibrary = Cocoa_GL_UnloadLibrary;
            _this->GL_CreateContext = Cocoa_GL_CreateContext;
            _this->GL_MakeCurrent = Cocoa_GL_MakeCurrent;
            _this->GL_SetSwapInterval = Cocoa_GL_SetSwapInterval;
            _this->GL_GetSwapInterval = Cocoa_GL_GetSwapInterval;
            _this->GL_SwapWindow = Cocoa_GL_SwapWindow;
            _this->GL_DestroyContext = Cocoa_GL_DestroyContext;
            _this->GL_GetEGLSurface = NULL;

            if (!Cocoa_GL_LoadLibrary(_this, NULL)) {
                return NULL;
            }

            return Cocoa_GL_CreateContext(_this, window);
        }
#endif

        context = SDL_EGL_CreateContext(_this, data.egl_surface);
        return context;
    }
}

bool Cocoa_GLES_DestroyContext(SDL_VideoDevice *_this, SDL_GLContext context)
{
    @autoreleasepool {
        SDL_EGL_DestroyContext(_this, context);
    }
    return true;
}

bool Cocoa_GLES_SwapWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
    @autoreleasepool {
        return SDL_EGL_SwapBuffers(_this, ((__bridge SDL_CocoaWindowData *)window->internal).egl_surface);
    }
}

bool Cocoa_GLES_MakeCurrent(SDL_VideoDevice *_this, SDL_Window *window, SDL_GLContext context)
{
    @autoreleasepool {
        return SDL_EGL_MakeCurrent(_this, window ? ((__bridge SDL_CocoaWindowData *)window->internal).egl_surface : EGL_NO_SURFACE, context);
    }
}

bool Cocoa_GLES_SetupWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
    @autoreleasepool {
        NSView *v;
        // The current context is lost in here; save it and reset it.
        SDL_CocoaWindowData *windowdata = (__bridge SDL_CocoaWindowData *)window->internal;
        SDL_Window *current_win = SDL_GL_GetCurrentWindow();
        SDL_GLContext current_ctx = SDL_GL_GetCurrentContext();
        SDL_MetalView metalview;

        if (_this->egl_data == NULL) {
// !!! FIXME: commenting out this assertion is (I think) incorrect; figure out why driver_loaded is wrong for ANGLE instead. --ryan.
#if 0 // When hint SDL_HINT_OPENGL_ES_DRIVER is set to "1" (e.g. for ANGLE support), _this->gl_config.driver_loaded can be 1, while the below lines function.
        SDL_assert(!_this->gl_config.driver_loaded);
#endif
            if (!SDL_EGL_LoadLibrary(_this, NULL, EGL_DEFAULT_DISPLAY)) {
                SDL_EGL_UnloadLibrary(_this);
                return false;
            }
            _this->gl_config.driver_loaded = 1;
        }

        /* Create the Metal view for window */
        metalview = Cocoa_Metal_CreateView(_this, window);
        if (metalview == NULL) {
            return SDL_SetError("Could not create Metal view for window");
        }

        /* Access the CAMetalLayer to control color space and compositing behavior */
        CAMetalLayer *layer = (__bridge CAMetalLayer *)Cocoa_Metal_GetLayer(_this, metalview);
        if (layer != nil) {
            /* Force Display P3 color space to prevent washed-out rendering */
            CGColorSpaceRef p3 = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
            layer.colorspace = p3;
            CGColorSpaceRelease(p3);

            /* Disable extended dynamic range to keep SDR brightness consistent */
            if (@available(macOS 10.15, *)) {
                layer.wantsExtendedDynamicRangeContent = NO;
            }

            /* Mark the layer as opaque to avoid unnecessary compositor blending */
            layer.opaque = YES;

            /* Disable VSync by default to prevent frame drops on high refresh displays. */
            layer.displaySyncEnabled = NO;

            /* Reduce buffering for lower latency (default is 3) */
            layer.maximumDrawableCount = 2;
        }

        /* Create the GLES window surface */
        windowdata.egl_surface = SDL_EGL_CreateSurface(_this, window, (__bridge NativeWindowType)layer);

        if (windowdata.egl_surface == EGL_NO_SURFACE) {
            Cocoa_Metal_DestroyView(_this, metalview);
            return SDL_SetError("Could not create GLES window surface");
        }

        /* Right now the metal view's ref count is +2 (one from returning a new view object in CreateView, and one because it's a subview of the window.)
         * If we release the view here to make it +1, it will be destroyed when the window is destroyed. */
        CFBridgingRelease(metalview);

        return Cocoa_GLES_MakeCurrent(_this, current_win, current_ctx);
    }
}

SDL_EGLSurface Cocoa_GLES_GetEGLSurface(SDL_VideoDevice *_this, SDL_Window *window)
{
    @autoreleasepool {
        return ((__bridge SDL_CocoaWindowData *)window->internal).egl_surface;
    }
}

#endif // SDL_VIDEO_DRIVER_COCOA && SDL_VIDEO_OPENGL_EGL
