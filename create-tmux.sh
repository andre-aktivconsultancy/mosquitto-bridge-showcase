#!/bin/bash

tmux new-session \; \
  split-window -h \; \
  split-window -v \; \
  select-pane -t 0 \; \
  split-window -v \; \
  select-pane -t 0 \; \
  send-keys 'docker exec -it mosquitto-remote mosquitto_sub -h localhost -t "#" -t "\$SYS/connect/#" -v' C-m \; \
  select-pane -t 1 \; \
  send-keys 'docker exec -it mosquitto-bridge mosquitto_sub -h localhost -t "#" -t "\$SYS/connect/#" -v' C-m \; \
  select-pane -t 2 \; \
  send-keys 'docker exec -it mosquitto-remote mosquitto_pub -h localhost -t "test/topic" -m "hello from remote"' \; \
  select-pane -t 3 \; \
  send-keys 'docker exec -it mosquitto-bridge mosquitto_pub -h localhost -t "test/topic" -m "hello from bridge"'