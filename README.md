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
pagecord list
```

Remove a saved blog:

```bash
pagecord logout myblog
```

## Options

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
