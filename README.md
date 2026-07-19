# tips

## cross compile packages from aarch64 MacOS host to armv7hf (Raspberry Pi Compute Module 3) using nix

On host:
```
nix run nixpkgs#darwin.linux-builder
```

Add to `/etc/nix/nix.custom.conf`:
```
trusted-users = root mike
builders = ssh://builder@localhost aarch64-linux,x86_64-linux,armv7l-linux - 4 1 kvm,benchmark,big-parallel
```

On Organelle:
```
ssh music@192.168.86.37 'sudo ~/fw_dir/scripts/remount-rw.sh && echo \'export PATH="$PATH:$HOME/.local/bin"\' > ~/.bash_aliases'
```

Build ripgrep:
```
nix build --impure -L \
  --builders "ssh://builder@localhost:31022 aarch64-linux,armv7l-linux,x86_64-linux /etc/nix/builder_ed25519 4 1 kvm,benchmark,big-parallel" \
  --expr '(import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-unstable.tar.gz") { localSystem = "aarch64-linux"; }).pkgsCross.armv7l-hf-multiplatform.pkgsStatic.ripgrep'
```

Copy to Organelle
```
scp ./result/bin/rg music@192.168.86.37:~/.local/bin/
```

## start web server automatically on boot

Add `network-target-online` to ogweb systemd service:
```
+++ b/platforms/organelle_cm/rootfs/etc/systemd/system/ogweb.service
@@ -1,6 +1,7 @@
 [Unit]
 Description=Organelle Web
-After=rc-local.service
+After=rc-local.service network-online.target
+Wants=network-online.target
```

Run `systemctl enable ogweb.service` to enable it on boot.
