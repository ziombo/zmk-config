# Sources contributed to the ZMK app by this config repo. See zephyr/module.yml.
if(CONFIG_ZMK_DISPLAY_STATUS_SCREEN_CUSTOM)
  target_sources(app PRIVATE src/custom_status_screen.c)
endif()
