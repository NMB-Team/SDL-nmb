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
#include "../SDL_internal.h"

/* Drag and drop event handling code for SDL */

#include "SDL_events.h"
#include "SDL_events_c.h"
#include "SDL_dropevents_c.h"

#include "../video/SDL_sysvideo.h" /* for SDL_Window internals. */

static SDL_bool app_is_dragging = SDL_FALSE;

static int SDL_SendDrag(SDL_Window *window, const SDL_EventType evtype, const char *data)
{
    int posted = 0;
    if (SDL_GetEventState(evtype) == SDL_ENABLE) {
        const SDL_bool is_already_dragging = (window ? window->is_dragging : app_is_dragging);
        if(is_already_dragging && (evtype == SDL_DRAGENTER)) {
            return 0;
        }
        if(!is_already_dragging && (evtype == SDL_DRAGEXIT)) {
            return 0;
        }
        SDL_Event event;
        SDL_zero(event);
        event.type = evtype;
        event.drop.file = data ? SDL_strdup(data) : NULL;
        event.drop.windowID = window ? window->id : 0;
        posted = (SDL_PushEvent(&event) > 0);
        if (posted) {
            SDL_bool value = evtype == SDL_DRAGENTER ? SDL_TRUE : SDL_FALSE;
            if (window) {
                window->is_dragging = value;
            } else {
                app_is_dragging = value;
            }
        }
    }
    return posted;
}

static int SDL_SendDrop(SDL_Window *window, const SDL_EventType evtype, const char *data)
{
    static SDL_bool app_is_dropping = SDL_FALSE;
    int posted = 0;

    /* Post the event, if desired */
    if (SDL_GetEventState(evtype) == SDL_ENABLE) {
        const SDL_bool need_begin = window ? !window->is_dropping : !app_is_dropping;
        SDL_Event event;

        if (need_begin) {
            SDL_zero(event);
            event.type = SDL_DROPBEGIN;

            event.drop.windowID = window ? window->id : 0;

            posted = (SDL_PushEvent(&event) > 0);
            if (!posted) {
                return 0;
            }
            if (window) {
                window->is_dropping = SDL_TRUE;
            } else {
                app_is_dropping = SDL_TRUE;
            }
        }

        SDL_zero(event);
        event.type = evtype;
        event.drop.file = data ? SDL_strdup(data) : NULL;
        event.drop.windowID = window ? window->id : 0;
        posted = (SDL_PushEvent(&event) > 0);

        if (posted && (evtype == SDL_DROPCOMPLETE)) {
            if (window) {
                window->is_dropping = SDL_FALSE;
            } else {
                app_is_dropping = SDL_FALSE;
            }
			const SDL_bool is_in_drag = (window ? window->is_dragging : app_is_dragging);
            if(is_in_drag) {
                SDL_SendDrag(window, SDL_DRAGEXIT, NULL);
            }
        }
    }
    return posted;
}

int SDL_SendDragEnter(SDL_Window *window)
{
    return SDL_SendDrag(window, SDL_DRAGENTER, NULL);
}

int SDL_SendDragExit(SDL_Window *window)
{
    return SDL_SendDrag(window, SDL_DRAGEXIT, NULL);
}

int SDL_SendDropFile(SDL_Window *window, const char *file)
{
    return SDL_SendDrop(window, SDL_DROPFILE, file);
}

int SDL_SendDropText(SDL_Window *window, const char *text)
{
    return SDL_SendDrop(window, SDL_DROPTEXT, text);
}

int SDL_SendDropComplete(SDL_Window *window)
{
    return SDL_SendDrop(window, SDL_DROPCOMPLETE, NULL);
}

/* vi: set ts=4 sw=4 expandtab: */
