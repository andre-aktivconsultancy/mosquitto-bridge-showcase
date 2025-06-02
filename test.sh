#!/bin/bash

# This script continuously monitors the memory usage of a specified Docker container
# and publishes MQTT messages of approximately 1KB with QoS 0 and QoS 2 to a
# specified broker. This can be useful for load testing or observing broker behavior
# under sustained message flow and varying quality of service levels.

# --- Configuration ---
DEFAULT_CONTAINER_NAME="mosquitto-bridge" # Default, assuming your context
DEFAULT_BROKER_HOST="localhost"           # Default MQTT broker host
DEFAULT_TOPIC_PREFIX="system_monitor/data" # Base topic for messages
PAYLOAD_RAW_BYTES=750 # Number of raw bytes to generate before base64 encoding.
                      # (750 / 3) * 4 = 1000 base64 characters, which is approx 1KB.
SLEEP_INTERVAL=1      # Seconds to wait between iterations

# --- Functions ---
usage() {
  echo "Usage: $0 [CONTAINER_NAME] [BROKER_HOST]"
  echo "  CONTAINER_NAME: Name of the Docker container to monitor (default: $DEFAULT_CONTAINER_NAME)."
  echo "  BROKER_HOST:    Hostname or IP of the Mosquitto broker (default: $DEFAULT_BROKER_HOST)."
  exit 1
}

check_command() {
  # Verifies that a given command is available in the system PATH.
  if ! command -v "$1" &> /dev/null; then
    echo "Error: Required command '$1' not found. Please install it and ensure it's in your PATH."
    exit 1
  fi
}

generate_payload() {
  # Creates a base64 encoded string from a specified number of random bytes.
  # The resulting string length will be approximately (input_bytes / 3) * 4.
  head -c "$PAYLOAD_RAW_BYTES" /dev/urandom | base64 -w 0
}

# --- Argument Parsing and Validation ---
CONTAINER_NAME="${1:-$DEFAULT_CONTAINER_NAME}"
BROKER_HOST="${2:-$DEFAULT_BROKER_HOST}"

check_command "docker"

# Ensure the target Docker container is running before entering the main loop.
if ! docker ps -q --filter "name=^/${CONTAINER_NAME}$" | grep -q .; then
    if ! docker ps -aq --filter "name=^/${CONTAINER_NAME}$" | grep -q .; then
        echo "Error: Docker container '$CONTAINER_NAME' not found."
    else
        echo "Error: Docker container '$CONTAINER_NAME' exists but is not currently running."
    fi
    echo "Please ensure the container is started before running this script."
    exit 1
fi

TOPIC="test/outbound"

echo "Starting monitoring and publishing loop..."
echo "Target container: $CONTAINER_NAME"
echo "MQTT Broker: $BROKER_HOST"
echo "Topic: $TOPIC"
echo "Raw payload bytes (pre-base64): $PAYLOAD_RAW_BYTES"
echo "Loop interval: $SLEEP_INTERVAL seconds"
echo "Press [CTRL+C] to stop."
echo ""

# Gracefully exit on SIGINT (Ctrl+C) or SIGTERM.
trap 'echo ""; echo "Exiting script due to user request."; exit 0' INT TERM

# --- Main Loop ---
iteration_counter=0
is_remote_connected=true # Assume remote is initially connected
NETWORK_NAME="mosquitto-bridge_mqtt-network" # Network to disconnect/connect from/to
REMOTE_CONTAINER_NAME="mosquitto-remote"     # The container to affect

echo "Will attempt to disconnect/reconnect '$REMOTE_CONTAINER_NAME' from/to '$NETWORK_NAME' every 500 iterations."

while true; do
  ((iteration_counter++))
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  # 1. Print Docker container memory usage.
  # `docker stats --no-stream` provides a single snapshot of resource usage.
  mem_usage=$(docker stats --no-stream --format "{{.Name}}: {{.MemUsage}}" "$CONTAINER_NAME")
  if [ -n "$mem_usage" ]; then
    echo "Iteration: ${iteration_counter} @ ${ts} Memory Usage: $mem_usage"
  else
    # This might happen if the container stops during script execution.
    echo "Warning: Could not retrieve memory usage for '$CONTAINER_NAME'. It may have stopped."
  fi

  # mem usoge of mosquitto itself
  docker exec -t mosquitto-bridge cat /proc/1/status | grep VmSize

  # Check if it's time to toggle network state
  if (( iteration_counter % 500 == 0 )); then
    if [ "$is_remote_connected" = true ]; then
      echo "Iteration ${iteration_counter}: Disconnecting '$REMOTE_CONTAINER_NAME' from '$NETWORK_NAME'..."
      docker network disconnect "$NETWORK_NAME" "$REMOTE_CONTAINER_NAME"
      if [ $? -eq 0 ]; then
        is_remote_connected=false
        echo "'$REMOTE_CONTAINER_NAME' disconnected."
      else
        echo "ERROR: Failed to disconnect '$REMOTE_CONTAINER_NAME' from '$NETWORK_NAME'."
      fi
    else
      echo "Iteration ${iteration_counter}: Connecting '$REMOTE_CONTAINER_NAME' to '$NETWORK_NAME'..."
      docker network connect "$NETWORK_NAME" "$REMOTE_CONTAINER_NAME"
      if [ $? -eq 0 ]; then
        is_remote_connected=true
        echo "'$REMOTE_CONTAINER_NAME' connected."
      else
        echo "ERROR: Failed to connect '$REMOTE_CONTAINER_NAME' to '$NETWORK_NAME'."
      fi
    fi
  fi

  # 2. Generate distinct payloads for each message.
  payload_for_qos0="${ts} iter ${iteration_counter} q0 $(generate_payload)"
  payload_for_qos2="${ts} iter ${iteration_counter} q2 $(generate_payload)"

  # 3. Publish Mosquitto message with QoS 0.
  # QoS 0 (At Most Once): Messages are sent without acknowledgment. They might be lost
  # if network issues occur or the broker is temporarily unavailable.
  docker exec -it mosquitto-bridge mosquitto_pub -h "$BROKER_HOST" -t "$TOPIC" -m "$payload_for_qos0" -q 0
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to publish QoS 0 message to $BROKER_HOST on topic ${TOPIC}."
  fi

  # 4. Publish Mosquitto message with QoS 2.
  # QoS 2 (Exactly Once): Guarantees that the message is delivered once and only once,
  # involving a four-part handshake. This is the most reliable but also highest overhead QoS.
  docker exec -it mosquitto-bridge mosquitto_pub -h "$BROKER_HOST" -t "$TOPIC" -m "$payload_for_qos2" -q 2
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to publish QoS 2 message to $BROKER_HOST on topic ${TOPIC}."
  fi
  sleep "$SLEEP_INTERVAL"
done
