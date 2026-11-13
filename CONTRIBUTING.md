# Contributing

## Sign off your commits (DCO)

This project uses the [Developer Certificate of Origin](https://developercertificate.org/)
(DCO). Every commit in a pull request must include a `Signed-off-by` line that
matches the commit author:

```
Signed-off-by: Jane Doe <jane@example.com>
```

By adding it you certify that you wrote the change or otherwise have the right
to submit it under the project's license. Git adds the line for you with `-s`:

```bash
git commit -s -m "fix: describe the change"
```

The [DCO app](https://github.com/apps/dco) checks every commit of a pull request
and fails if a sign-off is missing or its email does not match the author email.
To fix a failing check, add the sign-off and force-push:

```bash
git commit --amend --no-edit -s          # last commit only
git rebase --signoff origin/main         # every commit on the branch
git push --force-with-lease
```

## Checks

Pull requests also run:

- **Lint**: `shellcheck` on `scripts/` and `actionlint` on workflows.
- **E2E**: the action itself on a GitHub-hosted runner (see `.github/workflows/e2e.yml`).
