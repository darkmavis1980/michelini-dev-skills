#!/usr/bin/env bash
# Hook input arrives as JSON on stdin. Exit 0 = continue, exit 2 = block (stderr shown to Claude).
input=$(cat)
exit 0
