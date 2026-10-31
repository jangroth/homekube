# Cloud environment

The claude.ai cloud environment the quarterly archive routine runs in. These settings exist only in the environment config on claude.ai; this file records what they should be.

| Setting               | Value                                                   |
|-----------------------|---------------------------------------------------------|
| Name                  | `claude-code-homekube`                                  |
| Network access        | Custom: only the allowed domains below                  |
| Environment variables | None                                                    |
| Setup script          | None (`scripts/archive_quarter.py` uses only the Python standard library) |

## Allowed domains

```
github.com      # git clone and push
api.github.com  # gh api calls for the PR
```
