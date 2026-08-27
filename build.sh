#!/bin/sh
# Build ts-browser-ext for the local (Arch, Go 1.27) toolchain.
#
# GOEXPERIMENT=nojsonv2 is REQUIRED with Go >= 1.27 until tailscale.com is
# updated for the finalized encoding/json/v2: tailcfg structs (e.g.
# SSHAction.SessionDuration) use the `format` tag option, which Go 1.27's
# new json rejects at *runtime* ("unsupported `format` tag option") when
# unmarshaling the control server's netmap response (PollNetMap fails).
# nojsonv2 restores the legacy v1 json that ignores unknown tag options.
#
# Then deploy:
#   install -m755 ts-browser-ext ~/.config/google-chrome/NativeMessagingHosts/ts-browser-ext.bin
set -e
GOEXPERIMENT=nojsonv2 go build -o ts-browser-ext .
echo "built: $(ls -la ts-browser-ext)"
