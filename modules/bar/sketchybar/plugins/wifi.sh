#!/bin/bash
# wifi.sh — the Wi-Fi status pill (hausfold.co/docs/haus/rooms/bar-widgets).
# widget: interval = 10

BAR_ITEM=wifi
source "$HOME/.config/sketchybar/barlib.sh"

fetch() {
    local info status ssid
    info=$(ipconfig getsummary en0)
    status=$(echo "$info" | grep "LinkStatusActive" | awk -F': ' '{print $2}')
    ssid=$(echo "$info" | grep "SSID" | awk -F': ' '{print $2}')
    emit status="${status:-FALSE}" ssid="$ssid"
}

# No label ever draws — the pill is icon-only — so both branches pass an
# empty --label, which is `pill`'s own "absent" case rather than a second
# label.drawing=off spelled here.
render() {
    if [ "$status" = TRUE ]; then
        # teal is the palette's own hex the raw pill used to set, laundered
        # through the identity axis rather than a status rung: connected is
        # not a verdict, it is what this pill IS when it has something to say.
        pill --icon 󰖩 --label "" --mark teal
    else
        pill --icon 󰖪 --label "" --tone bad
    fi
}

on_click() {
    open -a 'System Settings' 'x-apple.systempreferences:com.apple.wifi-settings-extension'
}

barlib_main "$@"
