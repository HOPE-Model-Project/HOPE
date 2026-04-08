# [Developer documentation](@id dev_docs)

!!! note "Contributing guidelines"
    If you haven't, please read the [Contributing guidelines](90-contributing.md) first.

If you want to make contributions to this package that involves code, then this guide is for you.

## Current branch plan

The repository branch transition is complete:

1. `main` is the active development branch. All contributions go here.
2. The legacy `master` (pre-v2, Maryland-focused) is archived as a separate repository: [HOPE-MD](https://github.com/HOPE-Model-Project/HOPE-MD).

Contributors should branch from and open pull requests into `main`.

## First time clone

!!! tip "If you have write access"
    If you have write access to the main repository, you can clone it directly and skip the fork workflow.

If this is the first time you work with this repository, the safest setup is:

1. Fork the repository if you do not have write access.
2. Clone your fork, which creates a git remote called `origin`.
3. Add the main repository as `upstream`:

   ```bash
   git remote add upstream https://github.com/HOPE-Model-Project/HOPE.git
   ```

4. Fetch the latest branches:

   ```bash
   git fetch upstream
   ```

5. Create your working branch from `upstream/main`:

   ```bash
   git switch -c my-change upstream/main
   ```

## Linting and formatting

Install a plugin on your editor to use [EditorConfig](https://editorconfig.org).
This will ensure that your editor is configured with important formatting settings.

We use [https://pre-commit.com](https://pre-commit.com) to run the linters and formatters.
In particular, the Julia code is formatted using [JuliaFormatter.jl](https://github.com/domluna/JuliaFormatter.jl), so please install it globally first:

```julia-repl
julia> # Press ]
pkg> activate
pkg> add JuliaFormatter
```

To install `pre-commit`, we recommend using [pipx](https://pipx.pypa.io) as follows:

```bash
# Install pipx following the link
pipx install pre-commit
```

With `pre-commit` installed, activate it as a pre-commit hook:

```bash
pre-commit install
```

To run the linting and formatting manually, enter the command below:

```bash
pre-commit run -a
```

**Now, you can only commit if all the pre-commit tests pass**.

## Testing

For standard validation, open Julia in the repository folder, activate the environment, and run `test`:

```julia-repl
julia> # press ]
pkg> activate .
pkg> test
```

For documentation changes, also validate the docs environment when practical:

```bash
julia --project=docs docs/make.jl
```

If your change touches workflow files, verify the target branch names and trigger conditions at the same time.

## Working on a new issue

We try to keep a linear history in this repo, so it is important to keep your branches up-to-date.

1. Fetch from the remote and fast-forward your local `main`

   ```bash
   git fetch upstream
   git switch main
   git merge --ff-only upstream/main
   ```

2. Branch from `main` to address the issue (see below for naming)

   ```bash
   git switch -c 42-add-answer-universe
   ```

3. Push the new local branch to your personal remote repository

   ```bash
   git push -u origin 42-add-answer-universe
   ```

4. Create a pull request targeting `main`.

### Branch naming

- If there is an associated issue, add the issue number.
- If there is no associated issue, **and the changes are small**, add a prefix such as "typo", "hotfix", "small-refactor", according to the type of update.
- If the changes are not small and there is no associated issue, then create the issue first, so we can properly discuss the changes.
- Use dash separated imperative wording related to the issue (e.g., `14-add-tests`, `15-fix-model`, `16-remove-obsolete-files`).

### Commit message

- Use imperative or present tense, for instance: *Add feature* or *Fix bug*.
- Have informative titles.
- When necessary, add a body with details.
- If there are breaking changes, add the information to the commit message.

### Before creating a pull request

!!! tip "Atomic git commits"
    Try to create "atomic git commits" (recommended reading: The Utopic Git History by Carlos Martinez Ortiz, Netherlands eScience Center).

- Make sure the tests pass.
- Make sure the pre-commit tests pass.
- Fetch any `main` updates from upstream and rebase your branch, if necessary:

  ```bash
  git fetch upstream
  git rebase upstream/main BRANCH_NAME
  ```

- Then you can open a pull request and work with the reviewer to address any issues.

## Building and viewing the documentation locally

Following the latest suggestions, we recommend using `LiveServer` to build the documentation.
Here is how you do it:

1. Run `julia --project=docs` to open Julia in the environment of the docs.
1. If this is the first time building the docs
   1. Press `]` to enter `pkg` mode
   1. Run `pkg> dev .` to use the development version of your package
   1. Press backspace to leave `pkg` mode
1. Run `julia> using LiveServer`
1. Run `julia> servedocs()`

## Making a new release

- Create a branch `release-x.y.z` from `main`
- Update `version` in `Project.toml`
- Update release notes or changelog material if you are maintaining one for the release.
- Create a release PR targeting `main`.
- Verify test, lint, and docs workflows on that PR.
- Merge only after the release branch strategy, docs deployment branch, and badges all agree.
