#!/bin/sh
exec lsblk -J -b -o PATH,SIZE,FSTYPE,PARTTYPE,LABEL,PARTLABEL,TYPE "$1" 2>/dev/null
