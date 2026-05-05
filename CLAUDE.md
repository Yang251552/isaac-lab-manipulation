# Claude Code Operating Notes — isaac-lab-manipulation

This file is auto-loaded by Claude Code when working in this repo.

**This repo is a reproduction project, not a research project.** The goal is
to match published Isaac Lab benchmarks using their official configs. The
mindset is the opposite of `excavation-rl/` (the sibling repo where we
explored a self-invented BC + KL-anchor system and got stuck for 36
versions). Read §3 carefully — it codifies the discipline that prevents the
same dead-ends here.

If something in this file is wrong or stale, fix it. It is the single source
of truth for "how do we work on this project."

---

## 1. Environment & Access

- **Local working dir**: `/Users/yangchenghan/Downloads/isaac-lab-manipulation/` (Mac, zsh, no GPU)
- **Training EC2**: `ubuntu@16.171.208.250` (g5.xlarge, NVIDIA A10G 22 GB, CUDA 12.2)
  - Project mirror: `/home/ubuntu/isaac-lab-manipulation/`
  - Isaac Lab repo: `/home/ubuntu/IsaacLab/` (release **v2.3.2**, separate from this repo)
  - venv: `/home/ubuntu/isaaclab_venv/` (Python 3.10.12, torch 2.7.0+cu128, isaacsim 4.5.0.0, isaaclab 0.54.3, isaaclab_tasks 0.11.16, rsl-rl-lib 5.0.1, wandb 0.26.1)
  - `~/.netrc` already has wandb credentials
- **SSH key**: `~/.ssh/excavation-key.pem`
- **IP changes** when EC2 stops/starts. If `ssh ubuntu@...` fails, ask user for the current IP and update this file.
- **EBS disk**: extend to ≥100 GB before Isaac Lab install (Isaac Sim assets ~30 GB + cache). Currently 35 G used / 97 G total.
- **Permissions** for ssh/scp pre-allowed in `.claude/settings.local.json`.
- **GPU driver pre-requisite for video / offscreen rendering**: Isaac Sim 4.5's RTX renderer rejects driver 535.288.x because NVIDIA's Vulkan version encoding truncates `patch` to 8 bits — `535.288.01` is reported to Vulkan as `535.32.01`, fails the `>= 535.129` whitelist check. Headless training works fine on the rejected driver, but `play.py --video` and any DISPLAY-bound rendering will hang at MDL/TLAS init. Fix once: `sudo apt install -y nvidia-driver-550-server libglu1-mesa freeglut3-dev && sudo reboot`. (apt's metapackage often pulls in 580.x.y, which is also fine — the requirement is "patch < 256 in the kernel driver version".)

### 1.1 Launching Isaac Lab scripts — the only correct invocation

Always run training / play / list_envs through the IsaacLab wrapper, **not** raw `python`:

```bash
cd /home/ubuntu/IsaacLab && \
source /home/ubuntu/isaaclab_venv/bin/activate && \
export OMNI_KIT_ACCEPT_EULA=yes && \
export PRIVACY_CONSENT=Y && \
./isaaclab.sh -p scripts/reinforcement_learning/rsl_rl/train.py --task Isaac-Lift-Cube-Franka-v0 --headless --logger wandb --log_project_name franka-manipulation-rl --seed 42
```

Why each piece is load-bearing:
- `./isaaclab.sh -p` — injects Isaac Sim's bundled Python paths so `from pxr import Usd` works. Raw `venv/bin/python` will fail with `ModuleNotFoundError: pxr`.
- `OMNI_KIT_ACCEPT_EULA=yes` + `PRIVACY_CONSENT=Y` — without these, headless Isaac Sim hangs on the EULA prompt.
- `--headless` — required on EC2 (no display).
- Default num_envs = 4096 (from `lift_env_cfg.py`); do not pass `--num_envs` unless §3.1 escalation is triggered.

---

## 2. Reading Training Data — DO and DON'T

**DO**: Pull metric history via `wandb.Api` from a script that runs on EC2.
For Isaac Lab + rsl_rl runs the relevant keys are `Train/mean_reward`,
`Train/mean_episode_length`, `Loss/value_function`, `Loss/surrogate`,
`Loss/learning_rate`, `Episode_Reward/<term>`, plus task-specific
`Metrics/success_rate`. `tensorboard` event files in `logs/` are also
authoritative.

**DON'T**: grep wandb summary blocks (truncates per-key hidden state).

---

## 3. Reproduction Discipline (the load-bearing section)

This repo's success is **defined as** matching the official Isaac Lab
baseline. That means:

### 3.1 Don't deviate from official config
- Use the env ID and `--algorithm rsl_rl_ppo` exactly as the Isaac Lab tutorial / `IsaacLab/scripts/reinforcement_learning/rsl_rl/train.py` documents.
- Don't change reward weights, observation lists, action scales, network sizes, or PPO hyperparameters in the first run. Match the reference first; ablations come **after** a passing run.
- If the result differs from the published benchmark by more than ~10 %, **the answer is almost always "config or version mismatch"**, not "the reward needs tuning". Escalation order in §6.

### 3.2 No self-invented mechanisms
- No BC pretraining, no KL anchor, no reverse curriculum, no custom reward shaping, no normalization tricks beyond what `rsl_rl` ships with.
- If a paper-published technique seems relevant, log it as a follow-up after the baseline passes — never bake it into the baseline run.

### 3.3 The "match the headline number" gate
For each task, the headline number is taken from the Isaac Lab task documentation or the upstream paper. Examples:

| Task | Headline metric | Threshold |
|---|---|---|
| `Isaac-Lift-Cube-Franka-v0` | success rate over 256 eval rollouts | ≥ 90 % |

A task is "done" when its headline metric is matched on **a single seed**. We do not multi-seed reproduction runs unless the result is below threshold (then multi-seed is to confirm whether the gap is variance or systematic).

### 3.4 Single sanity check before any "tuning"
If the headline is missed, check **in this order** before changing anything:
1. Isaac Lab version matches the version the benchmark was reported on (`pip show isaaclab`).
2. The launch command matches the official tutorial verbatim (compare to `IsaacLab/scripts/reinforcement_learning/rsl_rl/train.py`).
3. Number of envs matches the official config (`--num_envs`).
4. `rsl_rl` version matches.
5. CUDA / driver mismatch warnings in stdout.

90 % of "RL not converging" in reproduction projects is one of the above. Only if all five are clean is it OK to look at hyperparameters.

---

## 4. Standard Iteration Loop

1. **Edit locally** (Mac).
2. **Push to EC2**: `scp -i ~/.ssh/excavation-key.pem <files> ubuntu@<ip>:/home/ubuntu/isaac-lab-manipulation/<dest>/`
3. **Verify scp landed** before training: `ssh ... grep <new-symbol> <file>`.
4. **Clear pycache** before each run if Python files changed: `find . -name __pycache__ -type d -exec rm -rf {} +`.
5. **Use Isaac Lab's own `train.py`** for training — do not write our own training loop.
6. **Long runs**: `nohup ... &` + `ScheduleWakeup` (Lift-Cube ~1-2 h on A10G; Anymal flat ~30-60 min).
7. **After run**: pull metrics via wandb API (§2). Visualize via `play.py` mode that ships with Isaac Lab.

---

## 5. Per-task documentation

Each reproduced task gets one file at `docs/<env_id_slug>.md` containing:
- exact install + launch commands
- training duration + GPU usage
- final headline metric
- training curve PNG
- play-mode video link (in `results/videos/`)

This is the portfolio surface — keep it short, factual, command-pasteable.

---

## 6. When You're Stuck

In a reproduction project, "stuck" almost always means "config drift". Apply
in order; do not skip:

1. Re-run §3.4's 5-point sanity check.
2. Search [Isaac Lab GitHub Issues](https://github.com/isaac-sim/IsaacLab/issues) for the env ID + symptom.
3. Diff your launch command against the most recent Isaac Lab tutorial for the task.
4. Check the `rsl_rl` repo for known regressions on the algorithm version.
5. **Only after 1-4 are clean**: post the situation to the user and decide whether to step away from the official config (this is a scope-changing decision and is not autonomous).

The §4.6 step-back / death-spiral discipline that exists in `excavation-rl/CLAUDE.md` is **not active here** — by design, this repo doesn't iterate enough to enter a death spiral. If you find yourself iterating a hyperparameter, you have skipped step 1 of §6.

---

## 7. README / CLAUDE.md Consistency

When a task is added to / removed from the reproduction targets in
`README.md`, update §3.3's table here in the same edit pass. Otherwise this
file rarely needs structural edits.

---

## 8. Session Handoff

Same convention as `excavation-rl/`: files live in `docs/session_handoffs/`,
named `<YYYY-MM-DD>_<topic-slug>.md`. To read the latest:

```bash
ls -t docs/session_handoffs/*.md | head -1
```

Only write a handoff when the user explicitly triggers it.

---

## 9. Relationship to `excavation-rl/`

The sibling repo `../excavation-rl/` is a separate portfolio piece — a
self-built RL substrate (custom Gymnasium env, Warp particles, hand-written
PPO, BC pretraining). Its policy did not converge to a working scoop; it is
positioned as engineering / lessons-learned material. **Do not import code
from it. Do not apply its tuning history here.** The two repos exist for
different reasons.

If a question crosses repos, mention it explicitly.
