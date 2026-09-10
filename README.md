# newbox — the published site

This repository is an artifact. Everything here under `docs/` is written by CI
and served by GitHub Pages at <https://newbox.stevenmliss.com>.

**Nothing here is edited by hand.** The source — `src/`, `publish.ps1`, the
installers, the templates — lives in the private `devnext` repository under
`newbox/`, alongside the layers it publishes. It moved there because the two
changed together on nearly every commit, so two repositories were buying
coordination rather than independence.

What keeps the layers apart is not the repository boundary. It is
`payload.psd1` in each layer and the single `pack.ps1` entry point: a layer
publishes what its manifest declares and nothing else. That rule is what lets a
private repository feed a public site at all, and it works the same wherever
the files live.

Releases are tags on devnext. A tag builds, tests, and overwrites `docs/` here.
