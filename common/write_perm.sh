#!/usr/bin/sudo bash

# --- FIX: DO NOT chmod level2/ contents! ---
# level2/ contains extracted filesystem data with preserved UID/GID/permissions.
# Running chmod -R ugo+rwx on it destroys SELinux contexts and permissions,
# causing kernel panic on boot.

# Only fix top-level directory access and output directories
for entry in level1 level3 out dump; do
  if [ -d "$entry" ]; then
    sudo chmod -R ugo+rwx "$entry"
  fi
done

# For level2: only fix the config directory and top-level access
# DO NOT touch the partition content directories (system/, vendor/, etc.)
if [ -d level2 ]; then
  sudo chmod ugo+rwx level2
  if [ -d level2/config ]; then
    sudo chmod -R ugo+rwx level2/config
  fi
  # Fix permissions on .img files in level2 (intermediate build artifacts)
  for f in level2/*.img level2/*.txt; do
    [ -f "$f" ] && sudo chmod ugo+rw "$f" || true
  done
fi

# Always exit successfully
exit 0

