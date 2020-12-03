#!/bin/bash

# Declare a map so we can use easier filenames
# Associative arrays in bash: https://stackoverflow.com/a/3467959
declare -A config_map=(
    # container name: file name
    ["1_LEFTrouter"]="LEFT.sh"
    ["1_LEFThost"]="LEFT-host.sh"
    ["1_TOProuter"]="TOP.sh"
    ["1_TOPhost"]="TOP-host.sh"
    ["1_RIGHTrouter"]="RIGHT.sh"
    ["1_RIGHThost"]="RIGHT-host.sh"
    ["1_CENTERrouter"]="CENTER.sh"
    ["1_CENTERhost"]="CENTER-host.sh"
    ["1_BOTTOMRrouter"]="BOTTOMR.sh"
    ["1_BOTTOMLrouter"]="BOTTOML.sh"
)

# Get the current script directory, no matter where we are called from.
# https://stackoverflow.com/questions/59895/how-to-get-the-source-directory-of-a-bash-script-from-within-the-script-itself
cur_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

for container in ${!config_map[@]}; do
    script="${config_map[$container]}"
    full_script="$cur_dir/$script"

    if [ -f $full_script ]; then
        echo "Configuring \`$container\` using \`$script\`"
        sudo docker cp $full_script $container:/home/
        sudo docker exec -it $container chmod 755 /home/$script
        sudo docker exec -it $container /home/$script
    fi
done
