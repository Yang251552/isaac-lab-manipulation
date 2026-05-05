#!/usr/bin/env bash
# Launch official PPO training for Isaac-Lift-Cube-Franka-v0 on EC2.
# Run from local Mac. Backgrounds the run via nohup; ssh exits immediately.
#
# Usage:  scripts/train_lift_cube.sh [SEED]   (default seed=42)
#
# Verify CLAUDE.md §1.1 invariants before changing anything in this file.

set -euo pipefail

SEED="${1:-42}"
HOST="ubuntu@16.171.182.227"
KEY="$HOME/.ssh/excavation-key.pem"
TS="$(date +%Y%m%d_%H%M%S)"
REMOTE_LOG="/home/ubuntu/isaac-lab-manipulation/logs/lift_cube_seed${SEED}_${TS}.log"

ssh -i "$KEY" "$HOST" "
  set -e
  mkdir -p /home/ubuntu/isaac-lab-manipulation/logs
  cd /home/ubuntu/IsaacLab
  source /home/ubuntu/isaaclab_venv/bin/activate
  export OMNI_KIT_ACCEPT_EULA=yes
  export PRIVACY_CONSENT=Y
  nohup ./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/train.py \
    --task Isaac-Lift-Cube-Franka-v0 \
    --headless \
    --logger wandb \
    --log_project_name franka-manipulation-rl \
    --seed ${SEED} \
    > ${REMOTE_LOG} 2>&1 &
  echo \"PID=\$!\"
  echo \"LOG=${REMOTE_LOG}\"
  disown
"
