# RemoteFrameDiag retired in R4OS 0.86.77

Use `SPECTRA CHECK REMOTEFRAME [/EXITOWNED] [/JSON]`. The single snapshot
oracle lives in the public `R4OSDev/r4os-diagnostic-spectra` repository at
`src/checks/remote_frame.zig`; explicit child completion/reap/retirement is
in `src/remote_frame_check.zig`. Desktop capture scenes use
`SPECTRA CHECK DESKTOP /CAPTURE` with an isolated Desktop.

RFDIAG has no active manifest, source entry, build or image/export target.
The last transitional source was commit
`55bb2896993ded9767be0b228b78cc08cf8d67f9` (RFDIAG 0.1.4), calling the
qualified shared Spectra oracle. The 0.86.75/76 replacement is available at
Spectra commit `91e5b3ffb9112d2b2266f55d1beca5db57bd779e`.
Scoped qualification and current commands: `R4OSDev/r4os-docs`,
`Diagnostics/Spectra.txt`. There is no replacement hardware/visibility claim.

This public repository and its history remain available. Original license,
notices and provenance are retained here and copied to
`Spectra/Provenance/RemoteFrameDiag`. Historical exports remain readable;
they do not require the old module to be installed.
