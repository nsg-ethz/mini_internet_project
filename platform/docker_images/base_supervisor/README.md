# Supervisord base image

This base image is based on apline and comes with a basic configuration to run
supervisord as init. Use this image for all images which must run multiple
processes in parallel. 

The base configuration ensures that all configured processes run properly. If
one of the configured processes exits unexpectedly or cannot be started after
multiple failed attempts, supervisor terminates itself which terminates the
whole container.

## How to use this base image:

1. You can use your own bootstrapping script by adding it as entrypoint.
   Make sure to append `exec "$@"` at the end of your script so that
   supervisord starts properly.
2. Mount your custom process configurations for supervisord to the
   directory `/etc/supervisor/conf.d/`. This way, the configuration is
   loaded automatically on startup.
