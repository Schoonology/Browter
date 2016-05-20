# Browter

The Browser Router: Use multiple browsers at once! When a URL is opened by the
OS (current Mac-only), Browter opens an application by name, passing the URL as
the only argument.

## Installation

For now, this project assumes you're either a developer or sufficiently
technically minded, so it requires you to build from source. Ensure you have
[XCode][xcode] installed, then run:

    make
    make install

The first `make` command builds Browter itself, while `make install` makes the
companion `browter` script available on the command-line.

## Commands

- `browter add RULE BROWSER` — Adds a new rule. If the current URL contains
  `RULE`, then `BROWSER` will be used to open it. See `Recommendations`, below,
  for more information.
- `browter remove RULE` — Removes the associated rule. If a server was running,
  it will shut down to pick up the changes.
- `browter default BROWSER` — Sets the default browser to use if no rule
  matches the current URL. If none is otherwise specified, Safari is used as
  the default.
- `browter status` — Displays the current status of Browter: whether or not
  the server is running, what rules are currently enabled, and the default
  browser.
- `browter quit` — Shuts down the current server, if any. _For debugging only._

## Example

```
# Open all Google-y things in the Google Browser™.
browter add google "Google Chrome"
# Use Opera by default.
browter default Opera
# No longer shall I open internal links in a different browser.
browter remove private.mycompany.com
# See the current status of Browter.
browter status
Server: Stopped
Rules:
  google => Google Chrome
  browserquest => Firefox
Default: Opera
```

## Recommendations

- Rules should not overlap. The first rule to match the opened URL wins. Since
rules are not given an order, Browter runs them in a theoretically arbitrary
order, so either of the overlapping rules could be run first, match the URL,
and open its associated application.

[xcode]: https://developer.apple.com/xcode/download/
