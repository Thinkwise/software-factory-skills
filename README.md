# Thinkwise Software Factory skills library

This repository contains a collection of [Claude Code](https://code.claude.com) **skills** for working with **Thinkwise Software Factory** models. Each skill is a reference guide or workflow that Claude loads automatically when a relevant task comes up — for example, creating a control procedure, setting up a cube, configuring a process flow, or reviewing a data model against Thinkwise naming conventions.

These skills are intended to be used together with an MCP connector that provides Software Factory access.

## What's in here

This repo is a Claude Code **plugin marketplace** (`thinkwise`) that ships one plugin, `thinkwise-sf`, containing all the skills. Each skill lives in its own folder under [`skills/`](skills/) and contains a `SKILL.md` file describing what it does and when Claude should use it, plus any supporting reference material it needs.

## Installing the skills

### As a plugin (recommended)

In Claude Code, run:

```
/plugin marketplace add Thinkwise/software-factory-skills
/plugin install thinkwise-sf@thinkwise
```

These are Claude Code slash commands: type them in a Claude Code session, not in your shell. From a terminal (PowerShell, bash) use the CLI equivalent instead:

```
claude plugin marketplace add Thinkwise/software-factory-skills
claude plugin install thinkwise-sf@thinkwise
```

To pull in new or updated skills later:

```
/plugin marketplace update thinkwise
```

### Rolling it out to a team

To have everyone who works in a given project prompted to install the plugin, add this to that project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "thinkwise": {
      "source": { "source": "github", "repo": "Thinkwise/software-factory-skills" }
    }
  },
  "enabledPlugins": {
    "thinkwise-sf@thinkwise": true
  }
}
```

### Manual install (fallback)

You can also copy (or symlink) individual skill folders from [`skills/`](skills/) into one of Claude Code's skill locations, keeping the folder name intact:

| Scope | Path | Applies to |
|---|---|---|
| **Personal** | `~/.claude/skills/<skill-name>/` | All your projects |
| **Project** | `<your-project>/.claude/skills/<skill-name>/` | Just that one project |

```
~/.claude/skills/thinkwise-sf-cubes/SKILL.md
~/.claude/skills/thinkwise-sf-tasks/SKILL.md
...
```

If you installed skills manually before, remove those copies once you install the plugin so you don't end up with duplicates.

For claude.ai, each skill is also available as a zip in [`zip files/`](zip%20files/) for upload.

## Using a skill

Most of these skills are reference guides Claude invokes automatically based on their `description` when your request matches (e.g. asking it to create a cube, a process flow, or a control procedure). You generally don't need to invoke them by name — just describe what you want to do in your Software Factory model, and Claude will pull in the relevant skill before making changes.

When installed as a plugin, skills are namespaced if you invoke them explicitly, e.g. `/thinkwise-sf:thinkwise-sf-cubes`.

## Contributing

- Add a new skill as a new folder under `skills/` with a `SKILL.md`.
- Bump `version` in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json) when you change or add skills, so installed users receive the update.
