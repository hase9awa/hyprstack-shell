// A translucent fullscreen viewer whose initial buffer is deliberately stale.
#define _GNU_SOURCE
#include <wayland-client.h>
#include "xdg-shell.h"
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static struct wl_display *display;
static struct wl_compositor *compositor;
static struct wl_shm *shm;
static struct xdg_wm_base *wm;
struct window {
    struct wl_surface *surface;
    struct xdg_surface *xdg;
    struct xdg_toplevel *top;
    int width, height, viewer, initial, ready;
    double ready_at;
};
static struct window chat, viewer;
static int delay = 140;
static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000.0 + t.tv_nsec / 1000000.0;
}
static void released(void *data, struct wl_buffer *buffer) { wl_buffer_destroy(buffer); }
static const struct wl_buffer_listener buffer_listener = {released};
static void paint(struct window *w, int width, int height, int stale) {
    int stride = width * 4, bytes = stride * height;
    int fd = memfd_create("media-viewer-test", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, bytes)) exit(3);
    uint32_t *pixels = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (pixels == MAP_FAILED) exit(4);
    for (int y = 0; y < height; y++) for (int x = 0; x < width; x++)
        pixels[y * width + x] = !w->viewer ? 0xff203070 : stale ? 0xffff0000
            : (abs(x - width/2) < width/8 && abs(y - height/2) < height/8) ? 0xff00cc66 : 0x99000000;
    struct wl_shm_pool *pool = wl_shm_create_pool(shm, fd, bytes);
    struct wl_buffer *buffer = wl_shm_pool_create_buffer(pool, 0, width, height, stride, WL_SHM_FORMAT_ARGB8888);
    wl_buffer_add_listener(buffer, &buffer_listener, NULL);
    wl_shm_pool_destroy(pool);
    munmap(pixels, bytes);
    close(fd);
    xdg_surface_set_window_geometry(w->xdg, 0, 0, width, height);
    wl_surface_attach(w->surface, buffer, 0, 0);
    wl_surface_damage_buffer(w->surface, 0, 0, width, height);
    wl_surface_commit(w->surface);
}
static void configured(void *data, struct xdg_surface *surface, uint32_t serial) {
    struct window *w = data;
    xdg_surface_ack_configure(surface, serial);
    if (!w->initial) {
        w->initial = 1;
        if (w->viewer) {
            paint(w, 400, 300, 1);
            w->ready_at = now() + delay;
            puts("placeholder");
        } else {
            paint(w, w->width, w->height, 0);
            puts("chat");
        }
    } else if (!w->viewer || w->ready) paint(w, w->width, w->height, 0);
}
static const struct xdg_surface_listener surface_listener = {configured};
static void top_configured(void *data, struct xdg_toplevel *top, int32_t width, int32_t height, struct wl_array *states) {
    struct window *w = data;
    if (width > 0) w->width = width;
    if (height > 0) w->height = height;
}
static void top_closed(void *data, struct xdg_toplevel *top) { exit(0); }
static const struct xdg_toplevel_listener top_listener = {.configure=top_configured, .close=top_closed};
static void ping(void *data, struct xdg_wm_base *base, uint32_t serial) { xdg_wm_base_pong(base, serial); }
static const struct xdg_wm_base_listener wm_listener = {ping};
static void global(void *data, struct wl_registry *registry, uint32_t name, const char *interface, uint32_t version) {
    if (!strcmp(interface, "wl_compositor")) compositor = wl_registry_bind(registry, name, &wl_compositor_interface, 4);
    else if (!strcmp(interface, "wl_shm")) shm = wl_registry_bind(registry, name, &wl_shm_interface, 1);
    else if (!strcmp(interface, "xdg_wm_base")) {
        wm = wl_registry_bind(registry, name, &xdg_wm_base_interface, 1);
        xdg_wm_base_add_listener(wm, &wm_listener, NULL);
    }
}
static void global_removed(void *data, struct wl_registry *registry, uint32_t name) {}
static const struct wl_registry_listener registry_listener = {global, global_removed};
static void create(struct window *w, int is_viewer) {
    memset(w, 0, sizeof(*w));
    w->viewer = is_viewer; w->width = 900; w->height = 600;
    w->surface = wl_compositor_create_surface(compositor);
    w->xdg = xdg_wm_base_get_xdg_surface(wm, w->surface);
    xdg_surface_add_listener(w->xdg, &surface_listener, w);
    w->top = xdg_surface_get_toplevel(w->xdg);
    xdg_toplevel_add_listener(w->top, &top_listener, w);
    xdg_toplevel_set_app_id(w->top, "com.ayugram.desktop");
    xdg_toplevel_set_title(w->top, is_viewer ? "Media viewer" : "AyuGram");
    if (is_viewer) xdg_toplevel_set_fullscreen(w->top, NULL);
    wl_surface_commit(w->surface);
}
int main(void) {
    setbuf(stdout, NULL);
    display = wl_display_connect(NULL);
    if (!display) return 2;
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!compositor || !shm || !wm) return 3;
    create(&chat, 0);
    for (;;) {
        if (viewer.initial && !viewer.ready && now() >= viewer.ready_at) {
            viewer.ready = 1;
            paint(&viewer, viewer.width, viewer.height, 0);
            puts("ready");
        }
        while (wl_display_prepare_read(display)) if (wl_display_dispatch_pending(display) < 0) return 5;
        wl_display_flush(display);
        struct pollfd fds[] = {{wl_display_get_fd(display), POLLIN, 0}, {STDIN_FILENO, POLLIN, 0}};
        if (poll(fds, 2, 5) < 0) { wl_display_cancel_read(display); continue; }
        if (fds[0].revents & POLLIN) {
            if (wl_display_read_events(display) < 0) return 6;
            wl_display_dispatch_pending(display);
        } else wl_display_cancel_read(display);
        if (fds[1].revents & POLLIN) {
            char command;
            if (read(STDIN_FILENO, &command, 1) != 1) return 0;
            if ((command == 'o' || command == 'q') && !viewer.surface) {
                delay = command == 'q' ? 5000 : 140;
                create(&viewer, 1);
            }
            if (command == 'c' && viewer.surface) {
                xdg_toplevel_destroy(viewer.top);
                xdg_surface_destroy(viewer.xdg);
                wl_surface_destroy(viewer.surface);
                memset(&viewer, 0, sizeof(viewer));
                puts("closed");
            }
        }
    }
}
