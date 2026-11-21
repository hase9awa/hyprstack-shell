// Pixel-aligned traffic-light controls, independent of installed fonts.
#pragma once
#include <string_view>

static SP<Render::ITexture> renderDecorationControl(std::string_view symbol, const CHyprColor& color,
    const CHyprColor& background, int size, bool hovered) {
    auto surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, size, size);
    auto cr = cairo_create(surface);
    cairo_set_antialias(cr, CAIRO_ANTIALIAS_GRAY);
    cairo_scale(cr, size / 16.0, size / 16.0);
    cairo_set_source_rgba(cr, background.r, background.g, background.b, background.a);
    cairo_arc(cr, 8, 8, 6.75, 0, 2 * M_PI);
    cairo_fill(cr);
    cairo_set_source_rgba(cr, color.r, color.g, color.b, hovered ? color.a : 0);
    cairo_set_line_width(cr, 1.25);
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND);
    if (symbol == "close") {
        cairo_move_to(cr, 5, 5); cairo_line_to(cr, 11, 11);
        cairo_move_to(cr, 11, 5); cairo_line_to(cr, 5, 11);
    } else if (symbol == "minimize") {
        cairo_move_to(cr, 4.5, 8); cairo_line_to(cr, 11.5, 8);
    } else if (symbol == "restore") {
        cairo_rectangle(cr, 4, 7, 5, 5);
        cairo_move_to(cr, 7, 7); cairo_line_to(cr, 7, 4);
        cairo_line_to(cr, 12, 4); cairo_line_to(cr, 12, 9); cairo_line_to(cr, 9, 9);
    } else {
        cairo_rectangle(cr, 5, 5, 6, 6);
    }
    cairo_stroke(cr);
    cairo_surface_flush(surface);
    auto texture = g_pHyprRenderer->createTexture(surface);
    texture->m_imageDescription = NColorManagement::getDefaultImageDescription();
    cairo_destroy(cr);
    cairo_surface_destroy(surface);
    return texture;
}
