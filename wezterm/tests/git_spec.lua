local git = require("modules.git")
local glyph = require("glyph")

-- nf-fa-check (U+F00C): the glyph git.render uses for a clean, up-to-date
-- branch. Constructed from the codepoint rather than pasted as a literal
-- character -- literals in this range get silently stripped in transit
-- (see Task 2's fix round), which would make a find("<glyph>", ...)
-- assertion a no-op that passes on empty content.
local CLEAN_MARKER = glyph.u(0xf00c)

local CLEAN = table.concat({
  "# branch.oid cc3e0dbabc1234567890abcdef1234567890abcd",
  "# branch.head main",
  "# branch.upstream origin/main",
  "# branch.ab +0 -0",
}, "\n")

local DIRTY = table.concat({
  "# branch.oid cc3e0dbabc1234567890abcdef1234567890abcd",
  "# branch.head feat/wezterm-bar",
  "# branch.upstream origin/feat/wezterm-bar",
  "# branch.ab +2 -0",
  "1 .M N... 100644 100644 100644 aaa bbb wezterm/modules/bar.lua",
  "1 M. N... 100644 100644 100644 ccc ddd wezterm/modules/git.lua",
  "? wezterm/local.lua",
}, "\n")

local DETACHED = table.concat({
  "# branch.oid cc3e0dbabc1234567890abcdef1234567890abcd",
  "# branch.head (detached)",
}, "\n")

describe("git.parse", function()
  it("reads a clean branch", function()
    local info = git.parse(CLEAN)
    assert_eq(info.branch, "main")
    assert_eq(info.detached, false)
    assert_eq(info.dirty, 0)
    assert_eq(info.ahead, 0)
  end)

  it("counts changed and untracked files", function()
    local info = git.parse(DIRTY)
    assert_eq(info.branch, "feat/wezterm-bar")
    assert_eq(info.dirty, 3)
    assert_eq(info.ahead, 2)
    assert_eq(info.behind, 0)
  end)

  it("detects a detached head", function()
    local info = git.parse(DETACHED)
    assert_eq(info.detached, true)
    assert_eq(info.branch, nil)
    assert_eq(info.oid, "cc3e0dbabc1234567890abcdef1234567890abcd")
  end)

  it("returns zeroed counts for empty output", function()
    local info = git.parse("")
    assert_eq(info.dirty, 0)
    assert_eq(info.detached, false)
  end)
end)

describe("git.render", function()
  it("hides the section outside a repository", function()
    assert_nil(git.render(nil))
  end)

  it("shows a tick in aqua when clean", function()
    local seg = git.render(git.parse(CLEAN))
    assert_eq(seg.color, "#7AA89F")
    assert_true(seg.text:find("main", 1, true) ~= nil, "branch name missing")
    assert_true(seg.text:find(CLEAN_MARKER, 1, true) ~= nil, "clean marker missing")
  end)

  it("shows the dirty count in amber and wins over ahead", function()
    local seg = git.render(git.parse(DIRTY))
    assert_eq(seg.color, "#E6C384")
    assert_true(seg.text:find(" 3", 1, true) ~= nil, "dirty count missing")
    assert_true(seg.text:find(" 2", 1, true) ~= nil, "ahead count missing")
  end)

  it("shows only the ahead marker in blue when committed but unpushed", function()
    local info = git.parse(CLEAN)
    info.ahead = 2
    local seg = git.render(info)
    assert_eq(seg.color, "#7E9CD8")
    assert_true(seg.text:find(" 2", 1, true) ~= nil, "ahead count missing")
  end)

  it("shows a short hash in red when detached", function()
    local seg = git.render(git.parse(DETACHED))
    assert_eq(seg.color, "#E46876")
    assert_true(seg.text:find("cc3e0db", 1, true) ~= nil, "short hash missing")
  end)
end)

describe("git.repo_key", function()
  it("is stable and filename safe", function()
    local key = git.repo_key("C:\\Projects\\rust\\solstice")
    assert_eq(key, git.repo_key("C:\\Projects\\rust\\solstice"))
    assert_nil(key:match("[\\/:]"), "key must not contain path separators")
  end)

  it("differs between repositories", function()
    assert_true(git.repo_key("/a") ~= git.repo_key("/b"))
  end)
end)
