# 13 — Push Permission Denied Fix (Forked Repo)

## Concept: Why the Push Is Denied

When you fork a repo on GitHub, your local clone's `origin` remote still points to the
**original upstream repo** (e.g., `scrollloack/practice-nexus`). You do not have write
access to someone else's repo, so GitHub rejects the push.

Notice that GitHub correctly identified you as `ABandelaria` — SSH authentication is
working. The only problem is the **push destination**.

```
ERROR: Permission to scrollloack/practice-nexus.git denied to ABandelaria.
```

You need `origin` to point to **your fork** (`ABandelaria/practice-nexus`), and
optionally keep the original as `upstream` for pulling in future changes.

---

## Step 1 — Confirm the Current Remotes

```bash
git remote -v
```

**Expected (broken) output:**
```
origin  git@github.com:scrollloack/practice-nexus.git (fetch)
origin  git@github.com:scrollloack/practice-nexus.git (push)
```

Both fetch and push point to the original repo — not your fork.

---

## Step 2 — Create Your Fork on GitHub (if not done yet)

If you have not forked yet:
1. Go to `https://github.com/scrollloack/practice-nexus`
2. Click **Fork** → **Create fork**
3. Your fork will live at `https://github.com/ABandelaria/practice-nexus`

If you already forked, skip to Step 3.

---

## Step 3 — Rename `origin` to `upstream`

Keep a reference to the original repo for pulling future changes:

```bash
git remote rename origin upstream
```

Verify:
```bash
git remote -v
# upstream  git@github.com:scrollloack/practice-nexus.git (fetch)
# upstream  git@github.com:scrollloack/practice-nexus.git (push)
```

---

## Step 4 — Add Your Fork as the New `origin`

```bash
git remote add origin git@github.com:ABandelaria/practice-nexus.git
```

Verify both remotes are now set correctly:
```bash
git remote -v
# origin    git@github.com:ABandelaria/practice-nexus.git (fetch)
# origin    git@github.com:ABandelaria/practice-nexus.git (push)
# upstream  git@github.com:scrollloack/practice-nexus.git (fetch)
# upstream  git@github.com:scrollloack/practice-nexus.git (push)
```

---

## Step 5 — Set the Upstream Tracking Branch and Push

The local `main` branch has no tracking branch yet on the new `origin`. Use `-u` to set
it and push in one command:

```bash
git push -u origin main
```

After this, future pushes only need `git push`.

---

## Step 6 — Verify on GitHub

Go to `https://github.com/ABandelaria/practice-nexus` and confirm your commits appear.

---

## Troubleshooting

### `remote: Repository not found`

Your fork does not exist yet or the remote URL has a typo. Double-check the URL:
```bash
git remote get-url origin
# Should be: git@github.com:ABandelaria/practice-nexus.git
```

### `fatal: 'origin' already exists` on Step 4

You skipped Step 3 or already have an `origin`. Either rename it first or update it
directly:
```bash
git remote set-url origin git@github.com:ABandelaria/practice-nexus.git
```

### `rejected — non-fast-forward`

Your fork's `main` is ahead of your local branch (e.g., GitHub initialized the fork
with a README). Pull first, then push:
```bash
git pull upstream main --rebase
git push -u origin main
```

---

## Quick Reference — All Commands Together

```bash
# Confirm current broken state
git remote -v

# Rename original to upstream
git remote rename origin upstream

# Add your fork as origin
git remote add origin git@github.com:ABandelaria/practice-nexus.git

# Push and set tracking branch
git push -u origin main
```

---

## Remote Naming Convention (for reference)

| Remote     | Points to                                      | Purpose                          |
|------------|------------------------------------------------|----------------------------------|
| `origin`   | `git@github.com:ABandelaria/practice-nexus.git` | Your fork — push here            |
| `upstream` | `git@github.com:scrollloack/practice-nexus.git` | Original repo — pull updates from |
