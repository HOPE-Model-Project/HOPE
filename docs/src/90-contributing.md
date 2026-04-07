# [Contributing guidelines](@id contributing)

First of all, thanks for the interest!

We welcome all kinds of contribution, including, but not limited to code, documentation, examples, configuration, issue creating, etc.

Be polite and respectful, and follow the code of conduct.

## Bug reports and discussions

If you think you found a bug, feel free to open an [issue](https://github.com/HOPE-Model-Project/HOPE/issues).
Focused suggestions and requests can also be opened as issues.
Before opening a pull request, start an issue or a discussion on the topic, please.

## Working on an issue

If you found an issue that interests you, comment on that issue what your plans are.
If the solution to the issue is clear, you can immediately create a pull request (see below).
Otherwise, say what your proposed solution is and wait for a discussion around it.

!!! tip
    Feel free to ping us after a few days if there are no responses.

If your solution involves code (or something that requires running the package locally), check the [developer documentation](91-developer.md).
Otherwise, you can use the GitHub interface directly to create your pull request.

## Branch status

Current active development happens on `master-dev`.
The legacy `master` branch is being retained during the transition and is planned to be archived later as `master-v1`.

Until that transition is complete:

1. Open development pull requests against `master-dev`.
2. Treat `master` as the legacy v1 line.
3. Keep branch-rename work bundled with the workflow and documentation updates that depend on it.
