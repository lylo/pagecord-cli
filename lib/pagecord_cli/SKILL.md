---
name: pagecord
description: Manage a Pagecord blog with the `pagecord` CLI. Use when the user wants to list, read, write or edit posts, pages or drafts, publish a local Markdown or HTML file, restyle their blog (theme, font, layout, colours, custom CSS), or add custom head or footer code.
allowed-tools: Bash, Read, Write, Edit, WebFetch
---

# Pagecord

Everything here runs through the `pagecord` command. `pagecord --help` lists
every command and flag; `pagecord version` says which version is installed.

## Rules

1. **Draft unless told to publish.** Pass `--status draft` to `post create` and
   `post update`, and use `pagecord draft FILE` rather than `publish`, unless
   the user asked to publish.
2. **Posts and pages are addressed by token**, eight hex characters such as
   `aaa33a9b`. `post list` shows them.
3. **Content is HTML.** `post show` returns HTML; edit it as HTML and send it
   back with `--content-file`. A file ending `.md` is sent as Markdown.
4. **`custom-code update` replaces the whole field.** Save the current value
   first and keep it as the backup.
5. **Never create an API key.** If `pagecord blog list` prints nothing, ask the
   user to run `pagecord login SUBDOMAIN` with a key from Settings > API.
6. **Pass `--json` when you need to parse output.**

## Quick reference

| To | Run |
|----|-----|
| List posts | `pagecord post list [--drafts\|--published] [--page N]` |
| Read a post | `pagecord post show TOKEN` |
| Edit a post | `pagecord post update TOKEN --content-file F [--title T] [--status draft]` |
| Write a post | `pagecord post create --title T --content-file F --status draft` |
| Delete a post | `pagecord post delete TOKEN [--permanent]` |
| Pages | `pagecord page list\|show\|create\|update\|delete`, as for posts |
| Publish a file | `pagecord publish FILE` or `pagecord draft FILE` |
| Theme and fonts | `pagecord appearance show\|update` |
| Custom CSS, head, footer | `pagecord custom-code show\|update` |
| Blogs | `pagecord blog list`, `pagecord blog use SUBDOMAIN` |

With several blogs configured, pass `--blog SUBDOMAIN` or set a default with
`pagecord blog use`. Lists return 15 at a time, newest first; `--page 2` gets
the next 15. The home page isn't covered by the CLI yet.

## Editing posts

```bash
pagecord post show TOKEN --json      # fields plus the HTML content
pagecord post update TOKEN --content-file post.html --status draft
```

`update` changes only the flags given. Other fields: `--slug`,
`--published-at`, `--tags "a, b"`, `--canonical-url`, `--locale`,
`--hidden`/`--no-hidden`. Delete moves a post to the bin unless you pass
`--permanent`, which can't be undone: confirm with the user first.

## Publishing files

```bash
pagecord publish hello.md            # publish or update
pagecord draft notes/idea.md         # save as a draft
```

The first run writes a `pagecord_token` into the file's front matter, and later
runs update that same post. Front matter can set `title`, `slug`, `tags`,
`published_at`, `canonical_url`, `hidden` and `locale`. Local images written as
`![alt](photo.jpg "Caption")` are uploaded with their alt text and
optional caption.

## Restyling a blog

Read https://help.pagecord.com/custom-css before the first CSS change. It
documents every class you can target and what Pagecord accepts. Don't work out
the structure by scraping a blog: comments load on demand and are missing from
the page source.

Look at the theme first, since your CSS has to work with it:

```bash
pagecord appearance show
pagecord custom-code show --css > blog.css
cp blog.css blog.css.orig
```

Edit `blog.css`, show the user a diff, then save it:

```bash
pagecord custom-code update --css blog.css
```

Undoing is `pagecord custom-code update --css blog.css.orig`; tell the user.

Pagecord rejects CSS that is over 16KB, nested (`.post { .title { } }`), or
`@import`s anything but HTTPS Google Fonts or Bunny Fonts. A rejected update
changes nothing. Custom properties, `@supports` and `@layer` are fine.

Prefer overriding the theme's custom properties, which work in light and dark
mode, over restyling elements one by one:

```css
:root {
  --theme-bg: #faf7f0;
  --theme-text: #2b2b2b;
  --theme-accent: #8c5a3c;
  --font-body: Georgia, serif;
  --font-size-base: 112.5%;
}
```

Scope rules with the attributes on `<body>`: `data-page-type` is `index`,
`home-page`, `page` or `post`, and `data-slug` is the slug being viewed. Target
`.post-body`, never classes containing `lexxy`, which may be renamed.

Whole-theme changes belong in `appearance update`, not CSS:
`--theme`, `--font`, `--width`, `--layout`, the six `--custom-theme-*` colours
and `--show-branding true|false`. The Theme Garden in Settings > Appearance
applies curated designs in one click.

`--footer-html`, `--head-html` and `--body-html` work like `--css` and each
take a file path. `--enabled false` switches head and body code off without
deleting it.

## Always verify

After any change, load the blog and check it. A successful update only means
the change was saved.
