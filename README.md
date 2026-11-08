# outside-heartbeat

A watcher that lives outside both of our machines. GitHub never queued this repo's cron (0 scheduled runs in 92 min
on 2026-11-08), so the timer is a **self-renewing chain**: each run waits 10 minutes on the `tick` environment's wait
timer (no runner held), runs the check, then starts the next run with `workflow_dispatch`. `concurrency` keeps one
running plus one pending, so chains merge. If the chain ever breaks, the Mini's `com.blrb.outside-beat` restarts it
whenever the Mini is up (nothing in flight and the newest run older than 25 min). Each check, on a GitHub-hosted runner:

1. probes the VPS sites in `targets.txt` (any answer under 500 means the VPS is up; it retries once after 90 s),
2. reads `MINI_BEAT`, a repository variable the Mac Mini sets every 10 minutes (LaunchAgent `com.blrb.outside-beat`,
   source `yopick hub/heartbeat/outside-beat.mjs`; it alerts through the hub itself if its writes keep failing),
3. when the VPS is down and the Mini's beat is over 30 minutes old, opens ONE issue labelled `both-down`, assigned to
   @ajgins (GitHub email and push), and fails that run. Later runs stay quiet while it is open. When either host
   answers again, the issue gets a recovery comment and closes.

Each machine already watches the other (the Mini's uptime-probe watches the VPS, the VPS's jairy-standby watches the
Mini). This repo covers the one case neither can see: both down at once.

Drill: Actions → heartbeat → Run workflow → drill `both-down` opens a `[drill]` issue (nobody assigned, run green).
The next scheduled run closes it.

The repo is public so its Actions minutes are free. The logs print only up/down words, and no secrets are stored here.
Survey and design: `agent-review/survey-outside-heartbeat-20261108.md`. Report: `agent-review/vps-restore-drill-20261108.md`.
