#!/bin/bash

# Declare a map so we can use easier filenames
# Associative arrays in bash: https://stackoverflow.com/a/3467959
declare -A config_map=(
    # container name: file name
    ["1_LEFTrouter"]="LEFT.cfg"
    ["1_TOProuter"]="TOP.cfg"
    ["1_RIGHTrouter"]="RIGHT.cfg"
    ["1_CENTERrouter"]="CENTER.cfg"
    ["1_BOTTOMRrouter"]="BOTTOMR.cfg"
    ["1_BOTTOMLrouter"]="BOTTOML.cfg"
)

# Get the current script directory, no matter where we are called from.
# https://stackoverflow.com/questions/59895/how-to-get-the-source-directory-of-a-bash-script-from-within-the-script-itself
cur_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
mkdir $cur_dir/saved_configs

for container in ${!config_map[@]}; do
    filename="${config_map[$container]}"

    echo "Saving config of \`$container\`"

    sudo docker exec -it $container vtysh -c "write"
    sudo docker cp $container:/etc/frr/frr.conf $cur_dir/saved_configs/$filename
    sudo chown $USER $cur_dir/saved_configs/$filename
done
