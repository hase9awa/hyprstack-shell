# Liquid animation runtime

`core.js` is the production bundle used by Hyprstack's Qt Quick renderer.
It contains the adapted goopUI simulation and carries the upstream MIT notice.
The upstream repository and pinned revision are recorded in `UPSTREAM.json`.
The original TypeScript project and development tooling are not distributed.

Hyprstack supplies panel geometry, window lifecycle, frame timing and the
Qt renderer. No browser, Node.js or network access is needed at runtime.
