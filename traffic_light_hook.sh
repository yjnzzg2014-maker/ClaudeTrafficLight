#!/bin/bash
STATE="${1:-idle}"
echo "$STATE" > /tmp/claude_traffic_light_state
