# Changelog

What changed in each version. [`VALIDATION.md`](VALIDATION.md) records how each one was verified.

## 2.5.1 — 2026-10-12

Security fix from the [marketplace review](https://github.com/omacom/omarchy-plugin-marketplace/issues/11292).

- **The token is never sent before the server's identity is verified.** If the connection failed at the identity check itself, the HTTP fallback used to poll with the token anyway. A process from another local account listening on T3's vacant port could answer the check with an error and receive the token. The fallback now runs only after the pinned identity matched, and every poll re-checks it.
- **Loopback secrets only go to your own listener.** Before a token, socket ticket or pairing credential is sent to a loopback address, T3 Loupe checks `/proc/net/tcp` and `tcp6` and requires the listening socket to belong to the current user. The new state "Port owned by another user" reports a refusal.
- Four new tests cover the reported scenario, re-verification on every poll, and listener ownership.

## 2.5.0 — 2026-10-12

Ready for the [Omarchy plugin marketplace](https://plugins.omarchy.org/).

- **Installs with Omarchy's own plugin manager.** The plugin now sits at the repository root, so `omarchy plugin add https://github.com/AmbitiousRealism2025/t3-loupe.git --enable` installs it, `omarchy plugin update` updates it and `omarchy plugin remove` removes it. The custom `tools/install.sh` is gone.
- **Smaller download.** Screenshots, the promo video and its source moved to [t3-loupe-media](https://github.com/AmbitiousRealism2025/t3-loupe-media), and the repository history was rewritten without them.
- **Marketplace preview.** `preview.webp` shows the two-pane window.
- Added this changelog and a [security policy](SECURITY.md).

## 2.4.0 — 2026-10-12

- **Visual polish.** Colour only for needs-you, working and done-unseen; status sections (**Needs you / Working / Done**) in the shell's own heading style; flat rows on the shell's state fills; a facts strip in the two-pane detail; linear run charts and step-style plan progress; an ink ring in the bar with only the needs-you slice coloured.
- **Reliable Focus T3 (`o`).** Focuses the T3 window through Hyprland by window class instead of the `t3code://` link.
- **Adjustable text size.** `+` / `-` or the footer control step through four sizes; the choice is saved.
- **Stronger backdrop** behind the centered window, and shaded thread rows.

## 2.3.0 — 2026-10-12

- **Two-pane window** as the default panel: every thread on the left, the selected one's live detail on the right. `f` switches to the compact dropdown, and the `presentation` setting picks the default.

## 2.2.0 — 2026-10-12

- **Idle fold.** Idle and stopped threads collapse behind an **Idle (n)** line.
- **Done tab** between Active and All: finished threads, newest first.

## 2.1.0 — 2026-10-12

- Renamed to **T3 Loupe** (plugin id `ambitiousrealism.t3-loupe`, config in `~/.config/t3-loupe`). The bar shows "T3 Loupe" beside the ring; both open the panel.

## 2.0.0 — 2026-10-12

- First release: a live, read-only view of T3 Code threads across paired machines, with the activity ring, per-thread activity using T3's icons, approval text, usage limits and notifications.
