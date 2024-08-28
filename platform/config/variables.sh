# Variables to use during setup.

# =============================================================================
# GENERAL
# =============================================================================

# The prefix for the dockerhub images. Leave empty for local images.
# If it isn't empty, it must end with a slash.
DOCKERHUB_PREFIX="miniinterneteth/"

# This URL will be suggested as the default location for students
# to download their configs. It should be publicly accessible via ssh at port
# 2000 + X, where X is each AS number.
SSH_URL="duvel.ethz.ch"

# =============================================================================
# WEBSERVER
# =============================================================================

# Hostname and ACME mail for letsencrypt.
# You need to specify the hostname of the server and an email for
# LetsEncrypt to be enabled.
# UPDATE THOSE VARIABLES. WEBSERVER_HOSTNAME -> hostname of the server and EMAIL -> empty string (for http)
WEBSERVER_HOSTNAME="duvel.ethz.ch"
WEBSERVER_ACME_MAIL="nsg@ethz.ch"
# Hostname and ports for the webserver and krill on the host.
# (must be publicly available)
# you can change http and https ports, but letsencrypt won't work, so its not recommended.
WEBSERVER_PORT_HTTP="80"
WEBSERVER_PORT_HTTPS="443"
# Use the one you want, make sure to make it reachable from outside.
WEBSERVER_PORT_KRILL="3000"
# Put your timezone here.
WEBSERVER_TZ="Europe/Zurich"

# =============================================================================
# Connections
# =============================================================================

# default parameters for the links
DEFAULT_THROUGHPUT=10mbit
DEFAULT_DELAY=10ms
DEFAULT_BUFFER=50ms



# =============================================================================
# MATRIX
# =============================================================================
# The matrix parameters can be changed without restarting the container.
# Within the container, change the environment variables `FREQUENCY`,
# `CONCURRENT_PINGS`, or `PING_FLAGS`. The container re-loads these variables
# at the start of every ping cycle.

# Interval for pings in seconds.
MATRIX_FREQUENCY=300
# Number of ping processes to run concurrently.
MATRIX_CONCURRENT_PINGS=500
# Flags to pass to the ping command.
MATRIX_PING_FLAGS="-c 3 -i 0.01"  # Three pings, 10ms interval.
# Whether to pause the matrix container after starting it.
# Can reduce load when the mini internet is not used immediately.
# Unpause container at any time with `docker container unpause MATRIX`
MATRIX_PAUSE_AFTER_START=false

# =============================================================================
# History collector.
# =============================================================================

# Whether to enable the history collector.
HISTORY_ENABLED=true
# Whether to pause the matrix container after starting it.
# Can reduce disk usage when the mini internet is not used immediately.
# Unpause container at any time with `docker container unpause HISTORY`
HISTORY_PAUSE_AFTER_START=false
# How often to fetch update configs and matrix state.
HISTORY_UPDATE_FREQUENCY=$(( 60*60 ))  # every hour (in seconds)
# Timeout for ./save_configs.sh
HISTORY_TIMEOUT="300s"
# Username and email that will show up on the commit.
HISTORY_GIT_USER=""
HISTORY_GIT_EMAIL=""
# URL of the git repository to push the snapshots to; should be accessible.
# For example, create a gitlab access token and use it in the URL.
# The token needs to have write access to the repository.
# HISTORY_GIT_URL="https://gitlab-ci-token:<TOKEN HERE>@gitlab.ethz.ch/nsg/lectures/lec_commnet/projects/2024/routing_project/test_history.git"
HISTORY_GIT_URL=""
HISTORY_GIT_BRANCH="main"
# switch.db and rpki.cache are binaries that cannot be stored easily in git.
# If this option is "true" (recommend), we re-write the git history at every
# update to remove old versions of these files; we always keep the most
# recent update.
# You must allow force pushing on the remove branch for this to work.
HISTORY_FORGET_BINARIES="true"
