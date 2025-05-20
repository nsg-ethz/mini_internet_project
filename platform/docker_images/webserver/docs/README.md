# Traceroute Visualization Feature

This document summarizes the introduced traceroute visualization functionality.

## Overview

This feature allows students to:
- Trigger traceroutes from the web UI
- Visualize paths across autonomous systems (ASes)
- Detect BGP policy violations (e.g. non-valley-free paths)

## Technologies Used

- Backend: Flask (Python), multithreaded traceroute execution in containers
- Frontend: vis.js for interactive AS path visualization
- Measurement logic: traceroute parsing, IP-to-AS mapping, policy check

## Documentation

For detailed information about implementation, see the full [PDF documentation](routing_path_visualization_documentation.pdf).
