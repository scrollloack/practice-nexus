# 12 — GPG Commit Signing Fix (WSL Ubuntu)

## Concept: Why GPG Signing Fails on WSL

Git signs commits by invoking `gpg` which needs a **TTY** to display a passphrase
prompt. On WSL, the default `pinentry` program is `pinentry-gtk2` or `pinentry-gnome3`,
which require a GUI/X server that WSL does not have. This causes the signing to silently
fail with `error: gpg failed to sign the data`.

Two things must be true for signing to work on WSL:
1. `GPG_TTY` environment variable must point to the current terminal.
2. `pinentry` must use a TTY-based program, not a GUI one.

---

## Step 1 — Verify the Error

Reproduce the failure to confirm it is a GPG pinentry issue:

```bash
echo "test" | gpg --clearsign
```

**Expected failure output:**
```
gpg: signing failed: Inappropriate ioctl for device
gpg: [stdin]: clear-sign failed: Inappropriate ioctl for device
```

The phrase `Inappropriate ioctl for device` confirms GPG cannot access the TTY.

---

## Step 2 — Find Your GPG Key ID

```bash
gpg --list-secret-keys --keyid-format=long
```

**Example output:**
```
sec   rsa4096/ABCD1234EFGH5678 2024-01-01 [SC]
      FINGERPRINT...
uid   [ultimate] Your Name <you@example.com>
```

Copy the key ID after the `/` on the `sec` line (e.g., `ABCD1234EFGH5678`).

---

## Step 3 — Configure Git to Use Your GPG Key

```bash
git config --global user.signingkey ABCD1234EFGH5678
git config --global commit.gpgsign true
git config --global gpg.program gpg
```

Verify:
```bash
git config --global --list | grep -E "sign|gpg"
```

---

## Step 4 — Set `GPG_TTY` in Your Shell Profile

Without this, GPG does not know which terminal to use for the passphrase prompt.

```bash
# Append to ~/.bashrc (or ~/.zshrc if using zsh)
echo 'export GPG_TTY=$(tty)' >> ~/.bashrc
source ~/.bashrc
```

Confirm it is set:
```bash
echo $GPG_TTY
# Should print something like: /dev/pts/0
```

---

## Step 5 — Switch `pinentry` to TTY Mode

Install a TTY-compatible pinentry program and tell `gpg-agent` to use it.

```bash
# Install pinentry-curses (terminal-based passphrase prompt)
sudo apt-get update && sudo apt-get install -y pinentry-curses
```

Create or update the `gpg-agent` config:

```bash
mkdir -p ~/.gnupg
cat > ~/.gnupg/gpg-agent.conf << 'EOF'
pinentry-program /usr/bin/pinentry-curses
EOF
chmod 600 ~/.gnupg/gpg-agent.conf
```

---

## Step 6 — Restart the GPG Agent

The agent caches the old `pinentry` config. Kill it so it reloads.

```bash
gpgconf --kill gpg-agent
```

The agent restarts automatically on next use. No manual start needed.

---

## Step 7 — Test Signing

```bash
# Test GPG directly
echo "test" | gpg --clearsign

# Test git commit signing
git commit --allow-empty -m "test: verify gpg signing"
```

You should see a passphrase prompt in the terminal. After entering it, the
commit should succeed without errors.

---

## Troubleshooting

### Still failing after the steps above

```bash
# Check which pinentry binary is actually being used
gpg-agent --debug-all --daemon 2>&1 | grep pinentry

# Confirm the correct path
which pinentry-curses
```

### `pinentry-curses` not found at `/usr/bin/pinentry-curses`

```bash
# Find where it was installed
which pinentry-curses
# Then update gpg-agent.conf with the correct path
```

### Passphrase prompt never appears (agent has cached key)

```bash
# Clear the agent's cached credentials and retry
gpgconf --kill gpg-agent
echo "test" | gpg --clearsign
```

### `gpg: skipped "KEY_ID": No secret key`

The `user.signingkey` in git config does not match any key in your GPG keyring.
Re-run Step 2 and Step 3 with the correct key ID.

---

## Quick Reference — All Commands Together

```bash
# Step 4: Shell profile
echo 'export GPG_TTY=$(tty)' >> ~/.bashrc && source ~/.bashrc

# Step 5: Install and configure pinentry
sudo apt-get install -y pinentry-curses
mkdir -p ~/.gnupg
echo "pinentry-program /usr/bin/pinentry-curses" > ~/.gnupg/gpg-agent.conf
chmod 600 ~/.gnupg/gpg-agent.conf

# Step 6: Restart agent
gpgconf --kill gpg-agent

# Step 7: Verify
echo "test" | gpg --clearsign
```
