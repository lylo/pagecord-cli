# Pagecord CLI

Publish local Markdown and HTML files to [Pagecord](https://pagecord.com).

## Install

```bash
gem install pagecord-cli
```

## Login

Generate an API key from **Settings > API** in Pagecord, then save it locally:

```bash
pagecord login myblog
```

The name should be your Pagecord subdomain. The API key is stored in
`~/.pagecord.yml`.

For local testing there is an undocumented `--base-url` option:

```bash
pagecord login myblog --base-url http://localhost:3000
```

## Publishing

Publish a file:

```bash
pagecord publish hello.md
```

Save or update a draft:

```bash
pagecord draft notes/idea.md
```

The first publish creates a post and writes Pagecord metadata back into the
file. Later publishes update the same post.

If you have one blog configured, `publish`, `draft`, and `logout` can omit the
subdomain. If you have more than one, pass the subdomain as the final argument:

```bash
pagecord publish hello.md myblog
```

See configured blogs:

```bash
pagecord blog list
```

Remove a saved blog:

```bash
pagecord logout myblog
```

## Choosing a blog

With several blogs configured, pick a default once:

```bash
pagecord blog use myblog
```

Every command works out which blog to use in this order: the subdomain passed
as a positional argument, then `--blog myblog`, then the `PAGECORD_BLOG`
environment variable, then the default set by `pagecord blog use`, and finally
the only configured blog if there is just one.

## Appearance

```bash
pagecord appearance show
pagecord appearance update --theme sand --font serif
```

Fields: `--theme`, `--font`, `--width`, `--layout`, the six
`--custom-theme-*` colours, and `--show-branding true|false`.

## Custom code

```bash
pagecord custom-code show --css > blog.css
pagecord custom-code update --css @blog.css
```

Fields: `--css`, `--footer-html`, `--head-html`, `--body-html`, and
`--enabled true|false`. A value can be given literally, as `@path` to read a
file, or as `@-` to read standard input:

```bash
cat blog.css | pagecord custom-code update --css @-
```

`custom-code show` prints JSON, or the raw field when you name one, so
redirecting it to a file round-trips.

## Global options

Accepted by every command, before or after the command name:

```bash
--blog SUBDOMAIN   # which blog to act on
--json             # machine-readable output
--quiet            # suppress confirmation messages
```

## Publish options

`publish` and `draft` accept:

```bash
--title TITLE
--slug SLUG
--published-at TIME
--tags TAGS
--canonical-url URL
--hidden
--locale LOCALE
```

## Front Matter

Markdown files can include Pagecord-compatible front matter:

```yaml
---
title: My Post
slug: my-post
tags:
  - ruby
  - cli
published_at: 2026-01-02T03:04:05Z
canonical_url: https://example.com/original
hidden: false
locale: en
---
```

If `title` is omitted, the CLI uses the filename. Use `title:` or
`title: ""` to publish without a title.

After publishing, the CLI manages the same front matter fields as the Obsidian
plugin:

```yaml
pagecord_token: 65b82933
pagecord_blog_fingerprint: c92376aeb770
pagecord_attachments:
status: published
```

`pagecord_token` links the file to the remote post. Delete it if you want the
next publish to create a new post.

## Images

Markdown image references to local files are uploaded to Pagecord and sent as
Action Text attachments:

```markdown
![Alt text](photo.jpg)
![[photo.jpg]]
```

Supported local image types are JPEG, PNG, GIF, and WebP. External image URLs
and HTML `<img>` tags are left alone.

## Development

```bash
rake test
ruby -Ilib bin/pagecord help
gem build pagecord-cli.gemspec
```
