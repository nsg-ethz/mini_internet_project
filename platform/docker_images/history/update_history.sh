#!/bin/bash


# =============================================================================
# Fetch all configs from all *_ssh containers.
# =============================================================================

fetch_all_configs() {  # Output directory, [timeout]
    if [ "$#" -lt 1 ]; then
        echo "Usage: $0 <output_directory> [timeout=300s]"
        exit 1
    fi
    local output_dir=$(readlink -f $1)
    local timeout=${2:-"300s"}

    # Fetch all *_ssh containers.
    readarray -t ssh_containers < <(docker ps --format '{{.Names}}' | grep '_ssh$')

    echo "Fetching configs from ${#ssh_containers[@]} ssh containers."
    for container in "${ssh_containers[@]}"; do
        group=${container%_ssh}
        group_output_dir="${output_dir}/g${group}"
        fetch_config $group_output_dir $container $timeout &
    done
    wait
}

fetch_config() {  # Group output directory, container name, timeout
    local output_dir=$1
    local container=$2
    local timeout=$3
    # Get a fixed suffix to identify the correct config dump.
    local suffix=$(uuidgen)

    mkdir -p $output_dir

    # Dump config.
    timeout $timeout docker exec -t $container ./root/save_configs.sh $suffix > /dev/null

    # Copy files
    docker cp "${container}:/configs_${suffix}/." $output_dir > /dev/null

    # Clean up files in container.
    docker exec $container rm -rf /configs_${suffix} /configs_${suffix}.tar.gz > /dev/null
}


# =============================================================================
# Prepare output directory, fetch history, commit; push if remote exists.
# =============================================================================

update_history() {
    local output_dir=$(readlink -f $1)
    local matrix_dir=$(readlink -f $2)
    local timeout=$3
    local git_user=$4
    local git_mail=$5
    local git_url=$6
    local git_branch=$7
    local forget_binaries=$8

    # If a git url is provided, test if it exists, otherwise print error.
    git ls-remote "$git_url" > /dev/null 2>&1
    if [ "$?" -ne 0 ]; then
        echo "Error! Unable to access '$git_url'"
        # Reset to ignore it in the rest of the script. Makes things easier.
        git_url=""
    fi


    # Get git directory ready and cd into it.
    if [ -d $output_dir/.git ]; then
        echo "Directory $output_dir is already a git repository."
        cd $output_dir
        git switch -c $git_branch > /dev/null 2>&1 || git switch $git_branch
        if [ -n "$git_url" ]; then
            # Update remote url (or set up new remote).
            git remote set-url origin $git_url || git remote add origin $git_url
            # Set upstream.
            if git fetch origin $git_branch > /dev/null 2>&1 ; then
                # Branch exists.
                git branch -u origin/$git_branch
            else
                # Branch does not exist.
                git push --set-upstream origin $git_branch
            fi
        fi
        # Ensure we are up-to-date. Ignore errors (no repo).
        git pull --rebase -X theirs 2>/dev/null
        git push 2>/dev/null
    elif [ -n "$git_url" ]; then
        if git clone -b $git_branch $git_url $output_dir ; then
            # Remote branch exists, we are ready.
            cd $output_dir
        else
            # Clone and set up new branch.
            git clone $git_url $output_dir
            cd $output_dir
            git switch -c $git_branch
            git push --set-upstream origin $git_branch
        fi
    else
        echo "Initializing new git repository in $output_dir."
        # Initialize empty git repository.
        mkdir -p $output_dir
        cd $output_dir
        git init
        git branch -m $git_branch
    fi
    # If the update was interrupted, there may be some changes left.
    # Clean up the working directory. Ignore errors (empty repo).
    git reset --hard HEAD 2>/dev/null


    # Git repository is ready!

    # Before we add new files, remove old versions of switch.db and rpki.cache.
    if [ "$forget_binaries" = "true" ]; then
        echo "Remove old versions of switch.db and *.rpki_cache"
        FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch \
        -f --index-filter \
        'git rm --cached --ignore-unmatch **/switch.db **/*.rpki_cache >/dev/null' HEAD
    fi

    mkdir -p configs
    mkdir -p matrix

    # Copy the matrix status.
    cp -r "${matrix_dir}/." matrix

    # Fetch all configs.
    fetch_all_configs configs $timeout

    # Add changes.
    git add configs matrix

    # Commit.
    git config user.name "$git_user"
    git config user.email "$git_mail"
    git commit -m "Update configs and matrix state."

    # Try to push. First check if we _can_ push (have remote etc.)
    if  git push --force-with-lease --dry-run > /dev/null 2>&1; then
        git push --force-with-lease
    else
        echo "No remote set up, not pushing."
    fi
}

# =============================================================================
# Run the script.
# =============================================================================

if [ "$#" -lt 5 ]; then
    echo "Usage: $0 <output_directory> <matrix_directory> <timeout> <git_user> <git_mail> <git_url> <git_branch>"
    exit 1
fi

output_dir=$(readlink -f $1)
matrix_dir=$(readlink -f $2)
timeout=$3
git_user=$4
git_mail=$5
git_url=$6
git_branch=$7
forget_binaries=$8

update_history \
"$output_dir" "$matrix_dir" "$timeout" \
"$git_user" "$git_mail" "$git_url" "$git_branch" "$forget_binaries"
