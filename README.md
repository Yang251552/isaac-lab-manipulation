# Isaac Lab Manipulation

Reproductions of canonical robotic manipulation RL baselines in
[NVIDIA Isaac Lab](https://isaac-sim.github.io/IsaacLab/) using the
[`rsl_rl`](https://github.com/leggedrobotics/rsl_rl) PPO implementation.

The goal is reproduction, not novelty. Trained policies should match the
reference behaviour and success rates reported in Isaac Lab's official
benchmarks, with no modifications to the official task configurations.

This is **act 1** of a three-repository portfolio arc:

| Repo | Role |
|---|---|
| this repo | act 1: reproduce a standard Isaac Lab manipulation baseline cleanly |
| [`excavation-rl`](https://github.com/Yang251552/excavation-rl) | act 2: push into granular-media excavation with a custom substrate; did not converge, but produced a detailed failure diagnosis |
| [`cluttered-lift`](https://github.com/Yang251552/cluttered-lift) | act 3: keep the granular-manipulation question, but move it back onto the Isaac Lab stack with a smaller rigid-body proxy |

The checkpoint from this repo is reused directly in act 3 as the zero-shot and
warm-start baseline. So this project is not only a standalone reproduction; it
is also the controlled reference point for the later granular-manipulation
diagnosis.

## Why this exists

This is a structured reproduction project, not a tutorial run-through. Each
task is reproduced under strict discipline: no reward shaping, no custom
hyperparameters, no shipping at "looks reasonable" reward curves. A task
counts as done only when the reference success target is matched on the
evaluation distribution.

The intent is to demonstrate three things:

1. Competence with the production-style RL stack used in current robot-learning
   work: Isaac Lab for scalable simulation, `rsl_rl` for PPO training, and
   seed-replicated evaluation rather than reward-curve eyeballing.
2. Precise reading of upstream code. See
   [`docs/isaac-lift-cube-franka-v0.md`](docs/isaac-lift-cube-franka-v0.md),
   "Eval methodology" section, for why the obvious "Play vs base config"
   distinction is mostly cosmetic on this task, and what the actual
   randomization surface is.
3. Honest, seed-replicated reporting. Every headline is computed from N
   randomized rollouts on a fresh seed, not declared from a rising
   training-reward curve.

## Status

- [x] `Isaac-Lift-Cube-Franka-v0`: trained 1500 iters in **24.2 min** on A10G,
  eval **100% success @ 2 cm goal** over 256 rollouts × 2 seeds, on the
  randomized training distribution.
  ([details](docs/isaac-lift-cube-franka-v0.md),
  [wandb](https://wandb.ai/yangchenghan2515-eth-z-rich/franka-manipulation-rl/runs/kd4z3ral),
  [mp4](results/videos/lift_cube_seed42.mp4))

![Lift-Cube policy rollout, 16 parallel envs, 12 s @ 15 fps](results/videos/lift_cube_seed42.gif)

![Lift-Cube training curves](results/figures/lift_cube_seed42_curves.png)

## Tech stack

- Isaac Lab / Isaac Sim
- `rsl_rl` PPO
- Wandb / TensorBoard logging
- A10G GPU on EC2 g5.xlarge for training

## Reproduction targets

| Task | Env ID | Reference success |
|---|---|---|
| Franka Lift Cube | `Isaac-Lift-Cube-Franka-v0` | > 90% (Isaac Lab default) |

## Layout

```
isaac-lab-manipulation/
├── configs/        # any per-task config overrides (kept minimal)
├── scripts/        # launchers (train.sh, play.sh, record_video.sh)
├── docs/
│   └── session_handoffs/
└── results/
    ├── figures/    # training curves, eval plots
    └── videos/     # play-mode videos
```

Detailed install and repro commands per task live in `docs/<task>.md`.
