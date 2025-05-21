This is showcasing the mosquitto bridge functionality.

The dockercompose.yaml defines two mosquitto brokers. One is configured to
bridge to the remote broker.

# Run
In one terminal run `docker compose up` to start the brokers.

In a second terminal run `./create-tmux.sh` to create a tmux session with 4
terminals to experiment.

Reconnect behavior of the bridge can be tried by running
`docker stop mosquitto-remote` to simulate the remote broker being offline. Run
`docker start mosquitto-remote` to see the reconnect succeed (after max 1 minute)
