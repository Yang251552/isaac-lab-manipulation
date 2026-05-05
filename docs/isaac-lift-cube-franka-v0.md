# Isaac-Lift-Cube-Franka-v0 — Reproduction Notes

Franka Panda lifting a cube to a target position, joint-position control,
PPO via `rsl_rl`. Headline metric: **success rate ≥ 90 %** over 256 eval
rollouts (CLAUDE.md §3.3).

## Environment

| Component | Version |
|---|---|
| Isaac Lab repo | v2.3.2 |
| `isaaclab` pkg | 0.54.3 |
| `isaaclab_tasks` | 0.11.16 |
| `isaacsim` | 4.5.0.0 |
| `rsl-rl-lib` | 5.0.1 |
| torch / CUDA | 2.7.0+cu128 |
| GPU | NVIDIA A10G (g5.xlarge) |

## Official config (do not modify; see CLAUDE.md §3.1)

From `IsaacLab/source/isaaclab_tasks/.../lift/config/franka/agents/rsl_rl_ppo_cfg.py`:

- `max_iterations = 1500`, `num_steps_per_env = 24`, `num_envs = 4096`
- actor / critic MLP `[256, 128, 64]`, ELU activation
- PPO: lr=1e-4 adaptive, clip=0.2, ent=0.006, γ=0.98, λ=0.95, target KL=0.01

## Train

From local Mac:

```bash
scripts/train_lift_cube.sh 42        # seed 42, default
```

Or directly on EC2:

```bash
cd /home/ubuntu/IsaacLab && \
  source /home/ubuntu/isaaclab_venv/bin/activate && \
  export OMNI_KIT_ACCEPT_EULA=yes PRIVACY_CONSENT=Y && \
  ./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/train.py \
    --task Isaac-Lift-Cube-Franka-v0 --headless \
    --logger wandb --log_project_name franka-manipulation-rl --seed 42
```

Logs land at `/home/ubuntu/IsaacLab/logs/rsl_rl/franka_lift/<timestamp>/`.

## Play + record video

```bash
scripts/play_lift_cube.sh /home/ubuntu/IsaacLab/logs/rsl_rl/franka_lift/<run>/model_1499.pt
```

Pull video back:

```bash
scp -i ~/.ssh/excavation-key.pem \
  ubuntu@16.171.208.250:/home/ubuntu/IsaacLab/logs/rsl_rl/franka_lift/<run>/videos/play/*.mp4 \
  results/videos/lift_cube_seed42.mp4
```

## Results — seed 42

| Field | Value |
|---|---|
| Run date | 2026-05-03 |
| Wallclock training time | **24.2 min** (1454 s, A10G g5.xlarge) |
| Throughput | ~108 k steps/s, 0.91-0.96 s/iter |
| Final mean reward | 150.94 (vs ~6 at iter 1, ~91 at iter 251) |
| Final mean cube ↔ goal distance | 0.094 m (during training, with domain randomization) |
| Final action std | 0.20 (started at 1.17 — policy converged) |
| **Lift success rate** (cube_z > 4 cm, 256 rollouts × 2 seeds) | **100.00 %** |
| **Reach success @ 5 cm** | 100.00 % |
| **Reach success @ 2 cm** | 100.00 % |
| Mean cube ↔ goal at episode end (eval) | 0.0032 m (3.2 mm), both seeds |
| Wandb run | https://wandb.ai/yangchenghan2515-eth-z-rich/franka-manipulation-rl/runs/kd4z3ral |
| Checkpoint | `results/checkpoints/lift_cube_seed42_model_1499.pt` |
| Saved configs | `configs/lift_cube/{agent,env}.yaml` |
| Training curve | `results/figures/lift_cube_seed42_curves.png` |
| Play-mode video | _pending — recording via Isaac Sim Livestream + QuickTime, blocked on EC2 GL stack on g5.xlarge_ |

### Eval methodology

The 100 % number is computed on the **training distribution**, not on a softer
"play" distribution. The published `Isaac-Lift-Cube-Franka-Play-v0` only differs from
the training config `Isaac-Lift-Cube-Franka-v0` in three places (see
`source/isaaclab_tasks/.../lift/config/franka/joint_pos_env_cfg.py`):

| Field changed in `_PLAY` | Effect |
|---|---|
| `scene.num_envs = 50` | Visualisation-only; we override to 256 in both runs. |
| `scene.env_spacing = 2.5` | Geometric layout; no effect on per-env dynamics. |
| `observations.policy.enable_corruption = False` | Master toggle for obs-noise. **No-op on this task** — the lift obs terms have no `noise=` configured, so this flag is dead. |

The task-level randomization that actually matters — initial cube pose
(`±0.1 m × ±0.25 m`), goal pose (`UniformPoseCommandCfg`) — lives in the **base**
`FrankaCubeLiftEnvCfg` and is inherited by both `_PLAY` and `_v0`. So both eval runs
genuinely test 256 randomized initial states.

**Two seeds for confirmation** (different sample of 256 initial states each):

| Eval | seed | Lift @4cm | Reach @5cm | Reach @2cm | Mean cube z | Mean goal-dist |
|---|---|---|---|---|---|---|
| `_v0` (base) | 0  | 100 % | 100 % | 100 % | 0.3821 m | 0.0032 m |
| `_v0` (base) | 42 | 100 % | 100 % | 100 % | 0.3733 m | 0.0032 m |

Different `mean_cube_z` confirms the seed change does sample different episodes; the
matching success columns confirm the 100 % is not a seed-zero coincidence. Pushing
beyond this would require widening `pose_range` or perturbing dynamics — those are
config-level deviations forbidden by CLAUDE.md §3.1 for a baseline reproduction.

Eval logs: `results/logs/eval_lift_cube_seed{0,42}_randomized.log`.

## Training curve

![training curves](../results/figures/lift_cube_seed42_curves.png)

What to read from the curves:
- **Mean reward** climbs ~6 → 150 over 1500 iters, with the steepest gains in iter 100-400.
- **Lift reward** (gating: cube_z > 4 cm) goes 0 → 13.5 — agent learns to grasp + lift around iter 150.
- **Goal-tracking fine (std=0.05)** is the slow learner: 0 → 3.8. This is the late-stage refinement signal, still climbing past iter 800.
- **Cube ↔ goal distance** drops from 0.17 m to 0.09 m, monotone after iter 200.
- **Drop rate** spikes in iter 100-200 (agent learning to grasp → fumbling) then collapses to ~0 — characteristic of contact-rich PPO training.
- **Value loss** peaks during the same exploration phase, falls as policy stabilises.
