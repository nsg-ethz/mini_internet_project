# Variables to use during setup.

# =============================================================================
# GENERAL
# =============================================================================

# The prefix for the dockerhub images. Leave empty for local images.
# If it isn't empty, it must end with a slash.
DOCKERHUB_PREFIX="miniinterneteth/"
# DOCKERHUB_PREFIX="miniinterneteth/"


# This URL will be suggested as the default location for students
# to download their configs. It should be publicly accessible via ssh at port
# 2000 + X, where X is each AS number.
SSH_URL="westvleteren.ethz.ch"

# =============================================================================
# WEBSERVER
# =============================================================================

# Hostname and ACME mail for letsencrypt.
# You need to specify the hostname of the server and an email for
# LetsEncrypt to be enabled.
# UPDATE THOSE VARIABLES. WEBSERVER_HOSTNAME -> hostname of the server and EMAIL -> empty string (for http)
WEBSERVER_HOSTNAME=""
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
# If you want to use the files from the docker image, set this variable to "":
# WEBSERVER_SOURCEFILES=""
# If you want your own webserver files instead add the filepath here (relative to the platform/config folder)
WEBSERVER_SOURCEFILES="/webserver"

# This year we are adding a chatbot to help the students with the project
# By enabling this a new tab will be added which is used to connect to the chatbot webserver
CHATBOT_INTEGRATION=false
CHATBOT_URL="https://de.wikipedia.org/wiki/Chatbot"


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
MATRIX_FREQUENCY=120
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
HISTORY_ENABLED=false
# Whether to pause the matrix container after starting it.
# Can reduce disk usage when the mini internet is not used immediately.
# Unpause container at any time with `docker container unpause HISTORY`
HISTORY_PAUSE_AFTER_START=false
# How often to fetch update configs and matrix state.
HISTORY_UPDATE_FREQUENCY=$(( 60*60 ))  # every hour (in seconds)
# Timeout for ./save_configs.sh
HISTORY_TIMEOUT="300s"
# Username and email that will show up on the commit.
HISTORY_GIT_USER="Mini-internet History"
HISTORY_GIT_EMAIL="mini-internet-history@ethz.ch"
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


# =============================================================================
# VPN 
# =============================================================================

# Enable/Disable VPN
VPN_ENABLED=false

# Enable/Disable DNS for wireguard clients
VPN_DNS_ENABLED=true

# Enable/Disable VPN website
# VPN_WEBSITE_ENABLED=false
VPN_WEBSITE_ENABLED=${VPN_ENABLED}

# The file for the vpn database
VPN_DB_FILE="vpn.db"

# Path to the file where the vpn passwords for the webinterface are stored (relative to groups folder).
VPN_PASSWD_FILE="passwords.txt"

# Each router container has an observer process that gets the interface status in a fixed interval
VPN_OBSERVER_SLEEP=30

# Restrict the number of clients that can connect to each interface:
VPN_NO_CLIENTS=1

# Rate limits for wireguard interface
VPN_LIMIT_ENABLED=true
VPN_LIMIT_RATE="1mbit"
VPN_LIMIT_BURST="32kbit"
VPN_LIMIT_LATENCY="40ms"

# Note: The IP subnets for the VPN are declared in config/subnet_config.sh 
