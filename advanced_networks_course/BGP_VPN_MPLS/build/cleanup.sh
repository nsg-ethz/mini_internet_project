#!/bin/bash

cur_dir=$(pwd)
platform_dir=$HOME/mini_internet_project/platform/

cd $platform_dir

echo "Clean-up the mini-Internet currently running (if any)"
sudo $platform_dir/cleanup/hard_reset.sh
