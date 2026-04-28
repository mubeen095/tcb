#!/bin/sh

# Start the frontend service
# Use server-wrapper.js for runtime environment variable injection
pm2 start server-wrapper.js --cwd /app/web --name learnhouse-web > /dev/null 2>&1

# Check if the services are running and log the status
pm2 status

# Start Nginx in the foreground
nginx -g 'daemon off;'
