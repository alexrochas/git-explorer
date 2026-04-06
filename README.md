# Git Explorer

`git-explorer` scans local repositories and prints prompt-friendly git metadata.

The tool now understands:

- the checked-out branch
- the repository default branch (`origin/HEAD` first, then `main`, then `master`)
- whether the current branch is `in-sync`, `ahead`, `behind`, or `diverged` from that default branch
- whether the remote owner looks like a personal or company GitHub account
- configurable output templates for shell/prompt usage

## Installation

This project now targets Ruby 3.0+ and ships with a `.ruby-version` pinned to `3.2.6` for local development.

```sh
bundle install
bundle exec rake spec
```

To install the gem globally:

```sh
gem install git_explorer
```

## Commands

Inspect the current repository:

```sh
git-explorer current
```

Inspect a specific path with a custom output template:

```sh
git-explorer current ~/code/my-repo \
  --format '$status $currentBranch main:$mainBranch sync:$sync owner:$ownerType'
```

Explore repositories recursively:

```sh
git-explorer explore ~/code
```

Include nested repositories such as vendored checkouts or submodules:

```sh
git-explorer explore ~/code --nested
```

Decorate the direct children of a folder:

```sh
git-explorer explore ~/code --light
```

Override the branch used for sync comparison:

```sh
git-explorer current --default-branch main
```

Use a different remote than `origin`:

```sh
git-explorer current --remote upstream
```

Refresh the remote before computing sync:

```sh
git-explorer current --fetch
git-explorer explore ~/code --fetch
```

Force or disable ANSI colors:

```sh
git-explorer current --color
git-explorer explore ~/code --no-color
```

## Format Tokens

Templates work like simple string interpolation. Any token below can be embedded inside `--format`:

```text
$status         # symbols like ✔, ✚, ●, ✖
$statusText     # clean, staged, unstaged, conflicted, untracked
$project        # repository folder name
$path           # absolute repository path
$currentBranch  # checked-out branch
$mainBranch     # detected default branch
$defaultBranch  # alias for $mainBranch
$sync           # in-sync, ahead, behind, diverged, detached, unknown
$remote         # remote URL
$host           # remote host, e.g. github.com
$owner          # remote owner/org name
$ownerType      # personal, company, unknown
```

Examples:

```sh
git-explorer current --format '$status $currentBranch -> $mainBranch [$sync]'
git-explorer explore ~/code --format '$project $currentBranch $mainBranch $sync'
git-explorer explore ~/code --light --format '[$ownerType] [$currentBranch|$mainBranch|$sync] $status'
```

Colors are enabled automatically on a TTY and suppressed when piped. Use `--color` to force them on or `--no-color` to force them off. `NO_COLOR=1` also disables color output.

## Filtering Colored Output

When you pipe output through `grep` or `rg`, force colors on in both commands:

```sh
git-explorer explore ~/code --color \
  --format '$project $status $currentBranch $mainBranch $sync $ownerType $owner' \
  | grep --color=always 'diverged\|behind\|ahead'
```

```sh
git-explorer explore ~/code --color \
  --format '$project $status $currentBranch $mainBranch $sync $ownerType $owner' \
  | rg --color=always 'diverged|behind|ahead'
```

If you want to page through the filtered results without losing ANSI colors:

```sh
git-explorer explore ~/code --color \
  --format '$project $status $currentBranch $mainBranch $sync $ownerType $owner' \
  | rg --color=always 'personal|company|unknown' \
  | less -R
```

You can also set reusable environment variables:

```sh
export GIT_EXPLORER_FORMAT='$status $project $currentBranch $mainBranch $sync'
export GIT_EXPLORER_LIGHT_FORMAT='[$currentBranch|$mainBranch|$sync] $status'
```

## Ownership Detection

`$ownerType` uses the GitHub repository API when the remote host is `github.com`.

- `Organization` is mapped to `company`
- `User` is mapped to `personal`
- private or unsupported remotes fall back to `unknown`

Owner lookups are cached on disk between runs in `XDG_CACHE_HOME/git-explorer/owner_types.json` or `~/.cache/git-explorer/owner_types.json` by default. The cache TTL is 7 days and can be adjusted with `GIT_EXPLORER_OWNER_CACHE_TTL`.

If you need better GitHub API access for private repositories, set `GITHUB_TOKEN` or `GH_TOKEN`.

## Sync Semantics

`$sync` compares the current branch against the repository default branch.

By default, it uses the refs already present in your local clone, such as `origin/HEAD` or `origin/main`.

If you want the latest remote state first, pass `--fetch`.
