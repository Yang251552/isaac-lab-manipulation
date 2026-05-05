#!/usr/bin/env bash
# Play + record video for the trained Lift-Cube policy.
# Uses Isaac-Lift-Cube-Franka-Play-v0 (num_envs=50, no domain rand).
#
# Usage:  scripts/play_lift_cube.sh <CHECKPOINT_PATH_ON_EC2>

set -euo pipefail

CKPT="${1:?usage: play_lift_cube.sh <checkpoint_path_on_ec2>}"
HOST="ubuntu@16.171.208.250"
KEY="$HOME/.ssh/excavation-key.pem"

ssh -i "$KEY" "$HOST" "
  set -e
  cd /home/ubuntu/IsaacLab
  source /home/ubuntu/isaaclab_venv/bin/activate
  export OMNI_KIT_ACCEPT_EULA=yes
  export PRIVACY_CONSENT=Y
  ./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/play.py \
    --task Isaac-Lift-Cube-Franka-Play-v0 \
    --headless \
    --video \
    --video_length 400 \
    --num_envs 50 \
    --checkpoint ${CKPT}
"
