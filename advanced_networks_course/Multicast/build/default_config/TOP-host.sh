#!/bin/bash

# Start he multicast router daemon.
smcroute -d

# Add a non-root user so we can run vlc (otherwise, it complains)
useradd vlc
