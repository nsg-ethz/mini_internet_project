# Variables to use during setup.

# =============================================================================
# GENERAL
# =============================================================================

# The prefix for the dockerhub images. Leave empty for local images.
# If it isn't empty, it must end with a slash.
DOCKERHUB_PREFIX="miniinterneteth/"

# =============================================================================
# WEBSERVER
# =============================================================================

# Hostname and ACME mail for letsencrypt.
# You need to specify the hostname of the server and an email for
# LetsEncrypt to be enabled.
# UPDATE THOSE VARIABLES. WEBSERVER_HOSTNAME -> hostname of the server and EMAIL -> empty string (for http)
WEBSERVER_HOSTNAME="duvel.ethz.ch"
WEBSERVER_ACME_MAIL=""

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
MATRIX_PAUSE_AFTER_START=false

# =============================================================================
# Snapshots: TODO
# =============================================================================