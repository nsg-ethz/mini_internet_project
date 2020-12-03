#!/bin/bash

# Important for VLC streaming later:
# Make sure that the VM does not filter multicast packets, otherwise we won't
# see anything outside of the mini-Internet.
sudo sysctl -w "net.ipv4.conf.default.rp_filter=0"

# Get the current script directory, no matter where we are called from.
# https://stackoverflow.com/questions/59895/how-to-get-the-source-directory-of-a-bash-script-from-within-the-script-itself
cur_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
platform_dir=$HOME/mini_internet_project/platform/

# Pull the latest version of the platform
echo "Pull the mini-Internet repository"
git -C $platform_dir checkout .
git -C $platform_dir pull

# Building the topology
echo "Copy the configuration files"
cp -r $cur_dir/topo/* $platform_dir/config/

echo "Clean-up the mini-Internet currently running (if any)"
(cd $platform_dir; sudo $platform_dir/cleanup/hard_reset.sh)
echo "Run the new mini-Internet"
(cd $platform_dir; sudo $platform_dir/startup.sh)

# Apply default configuration
echo "Apply initial configuration"
($cur_dir/default_config/configure.sh)

# Copy the video directory into top-host
echo "Copying videos to TOP-host."
docker cp "$cur_dir/videos" 1_TOPhost:/home
docker exec 1_TOPhost chown vlc /home/videos

# Collect VPN credentials.
echo "Collecting VPN credentials."
($cur_dir/collect_vpn_info.sh)
