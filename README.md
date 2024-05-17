# neorg-conceal-wrap

Wrap lines based on their concealed width instead of their unconcealed width.

![image](https://github.com/benlubas/neorg-conceal-wrap/assets/56943754/97dffe9b-305f-4fdc-bff5-f9b59d519ede)

---

## Install

Install this plugin and load it by adding this to your neorg config:

```lua
["external.conceal-wrap"] = {},
```

There is no configuration. `:h textwidth` is used as the target width of a line.

## Usage

This plugin overwrites the `formatexpr` for `.norg` buffers, so formatting is applied with the `gq`
mapping. see `:h 'formatexpr'` and `:h gq` for details here. TL;DR: use `gq<text object>` to format
the text object.

Formatting in insert mode falls back to normal nvim formatting. This is for a few reasons I guess,
the main one being that I don't care to implement it right now. But also, while typing syntax is
often broken and this would result in needing to reformat sometimes anyway.
