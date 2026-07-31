/*
 * Custom status screen.
 *
 * Overrides the weak zmk_display_status_screen() in ZMK's app/src/display/main.c.
 * Selecting CONFIG_ZMK_DISPLAY_STATUS_SCREEN_CUSTOM stops ZMK compiling its own
 * status_screen.c, so this definition wins at link time.
 *
 * Layout on the 128x32 OLED (right half):
 *   left  - two-line greeting
 *   right - battery status, unchanged from the built-in screen
 *
 * SPDX-License-Identifier: MIT
 */

#include <zephyr/kernel.h>
#include <lvgl.h>

#include <zmk/display/status_screen.h>
#include <zmk/display/widgets/battery_status.h>

#if IS_ENABLED(CONFIG_ZMK_WIDGET_BATTERY_STATUS)
static struct zmk_widget_battery_status battery_status_widget;
#endif

lv_obj_t *zmk_display_status_screen() {
    lv_obj_t *screen;
    screen = lv_obj_create(NULL);

#if IS_ENABLED(CONFIG_ZMK_WIDGET_BATTERY_STATUS)
    /* Same placement the built-in screen uses, so this side looks unchanged. */
    zmk_widget_battery_status_init(&battery_status_widget, screen);
    lv_obj_align(zmk_widget_battery_status_obj(&battery_status_widget), LV_ALIGN_TOP_RIGHT, 0, 0);
#endif

    lv_obj_t *greeting = lv_label_create(screen);
    lv_label_set_text(greeting, "Bonsoir,\nElliot.");
    /* Name the font rather than going through lv_theme_get_font_small(), so the
     * layout does not depend on a theme being active at init time. */
    lv_obj_set_style_text_font(greeting, &lv_font_montserrat_12, LV_PART_MAIN);
    lv_obj_set_style_text_align(greeting, LV_TEXT_ALIGN_LEFT, LV_PART_MAIN);
    lv_obj_align(greeting, LV_ALIGN_TOP_LEFT, 0, 0);

    return screen;
}
