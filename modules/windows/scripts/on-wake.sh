#!/bin/bash
# Invoked by sleepwatcher on system wake. Brief delay lets macOS finish
# rehydrating windows before we re-sort them.

sleep 2
exec "$HOME/.config/aerospace/resort-windows.sh"
