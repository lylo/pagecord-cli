# AGENTS.md

Ruby gem providing the `pagecord` command for publishing local files to
[Pagecord](https://pagecord.com). No runtime dependencies beyond the standard
library.

## Structure

```
bin/pagecord                  – entrypoint
lib/pagecord_cli/
  cli.rb                      – command parsing, help and output
  client.rb                   – Pagecord API client (Net::HTTP)
  config.rb                   – blogs and API keys in ~/.pagecord.yml
  post_file.rb                – front matter, tokens and content for local files
  image_uploads.rb            – uploads local images, swaps in attachment tags
  SKILL.md                    – agent skill shipped with the gem (`pagecord skill`)
  version.rb
test/                         – Minitest, with FakeClient in test_helper.rb
```

## Commands

```bash
rake test                                              # full suite
ruby -Itest test/cli_test.rb -n test_login_saves_blog_with_base_url  # one test
ruby -Ilib bin/pagecord help                           # run from the checkout
gem build pagecord-cli.gemspec
```

Against a local Pagecord server, log in with
`ruby -Ilib bin/pagecord login SUBDOMAIN --base-url http://api.localhost:3000` –
the `api.` host is required.

## Ruby versions

`.ruby-version` pins development to the latest Ruby, but the gemspec supports
`>= 3.2`. Standard library APIs differ between those versions (on 3.2,
`cgi/escape` alone doesn't provide `CGI.unescapeURIComponent`, for example), so
before finishing, run the suite on the oldest supported version as well as the
current one:

```bash
RBENV_VERSION=3.2.2 rake test
```

## Checks

A change is done when `rake test` passes on both Ruby 3.2 and the current Ruby,
and every user-facing change is reflected in:

- `README.md`
- `lib/pagecord_cli/SKILL.md` – ships with the gem, so a stale skill misleads
  agents as soon as it's released
- `~/dev/pagecord/docs/help-guide/pagecord-cli.md` – the help site page, in the
  Pagecord repo

## API

API reference: `~/dev/pagecord/docs/help-guide/api.md`.

The CLI talks to `https://api.pagecord.com` with `Authorization: Bearer <api_key>`.
All requests go through `Client#request`. The server side lives in `~/dev/pagecord`
(`app/controllers/api/`, `app/models/api/post_params.rb`); check it before relying
on a parameter or attachment attribute.

- `GET/POST /posts`, `GET/PATCH/DELETE /posts/:token` – posts and pages, sent with
  `content_format=markdown`
- `POST /attachments` – multipart image upload, returns `attachable_sgid`
- `GET/PATCH /settings/appearance` and `/settings/custom_code`

**Posts and pages are addressed by token, not id.** `pagecord post show abc123`
takes the token the API returns, which is also what `publish` writes into a file's
front matter as `pagecord_token`.

## Choosing a blog

Every command that talks to a blog resolves it in `CLI#resolve_blog`, highest first:

1. The `SUBDOMAIN` argument to `publish`, `draft` and `logout`
2. `--blog SUBDOMAIN`
3. `PAGECORD_BLOG`
4. The default set by `pagecord blog use`
5. The only blog, when just one is configured

Otherwise it errors. Blogs, API keys and base URLs live in `~/.pagecord.yml`.

## Behaviour shared with the Obsidian plugin

`~/dev/obsidian-pagecord` publishes the same files to the same API. Keep the two
consistent: front matter keys, `pagecord_token` and `pagecord_blog_fingerprint`
write-back, the `pagecord_attachments` cache, and how image embeds become
`<action-text-attachment sgid="..." alt="..." caption="...">`. When changing one
of these, check how the plugin does it first.

## Principles

- **Minimal code**: fewer lines when clarity is maintained. Simple over clever.
  No premature abstraction.
- **Extractions must be paid for**: a new class or method earns its place with a
  second caller, a net deletion, or a bug it fixes.
- **No new dependencies**: stick to the standard library.
- **Match existing patterns**: don't restructure while doing something else.
  Suggest refactorings instead of silently widening the change.

## Code Style

- British English in user-facing copy and documentation
- Double quotes for strings
- En-dashes (–), never em-dashes (—)
- Private methods indented one additional level after `private`
- Write almost no comments. One line, only when a future reader would otherwise
  make a mistake. Explanations of a change belong in the commit message.

## Testing

Minitest. Focused tests for behaviour; don't test Ruby or the standard library.
No test makes a real HTTP request.

CLI tests swap `FakeClient` in for `PagecordCLI::Client`, give the CLI a config in
a temp directory, and assert on the recorded requests:

```ruby
include ClientSwap

with_fake_client do
  Dir.mktmpdir do |dir|
    config = PagecordCLI::Config.new(File.join(dir, ".pagecord.yml"))
    config.save_blog("olly", api_key: "secret", base_url: "https://api.pagecord.com")
    output = StringIO.new

    status = PagecordCLI::CLI.new([ "post", "list" ], config: config, output: output).run

    assert_equal 0, status
    assert_equal :list, FakeClient.requests.last.action
  end
end
```

- `FakeClient.requests` records each call as a `Request` (`action`, `args`,
  `api_key`, `base_url`)
- `FakeClient.upload_token` sets the returned `attachable_sgid`
- `update_error`, `verify_error` and `custom_code_error` make those calls raise
- Tests that pass a `FakeClient` directly, like `PostFile#content_for`, call
  `FakeClient.reset!` in an `ensure`

## Releases

Bump `lib/pagecord_cli/version.rb` in its own `Bump to x.y.z` commit at the end of
the branch.

## Git Commits

- Use plain branch names without prefixes (`image-captions`, not `feature/...`)
- **NEVER** add "Co-Authored-By", "Generated with Claude Code", or any AI
  attribution to commits, PR descriptions or code comments.
- **NEVER** put customer data in commits, PRs, comments or test data.
