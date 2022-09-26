#!/bin/bash

# ------------------------------------------------------------
#
# Quick script to wrap the locust command, and
# pass in the host URL from the environment variables
#

TARGET_HOST="${HOST:-http://localhost}"

locust -H "${TARGET_HOST}"
