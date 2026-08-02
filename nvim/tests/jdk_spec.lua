local jdk = require("util.jdk")

describe("jdk.parse_release", function()
  it("reads a quoted JAVA_VERSION", function()
    assert_eq(jdk.parse_release('IMPLEMENTOR="Oracle"\nJAVA_VERSION="25.0.1"\n'), "25.0.1")
  end)

  it("reads an unquoted JAVA_VERSION", function()
    assert_eq(jdk.parse_release("JAVA_VERSION=17.0.20\n"), "17.0.20")
  end)

  it("ignores JAVA_VERSION_DATE, which sorts before it in some releases", function()
    assert_eq(jdk.parse_release('JAVA_VERSION_DATE="2025-10-21"\nJAVA_VERSION="25.0.1"\n'), "25.0.1")
  end)

  it("returns nil for a file with no version", function()
    assert_nil(jdk.parse_release('MODULES="java.base"\n'))
  end)
end)

describe("jdk.major", function()
  it("takes the first component of a modern version", function()
    assert_eq(jdk.major("25.0.1"), 25)
    assert_eq(jdk.major("21"), 21)
  end)

  it("takes the second component of a legacy 1.x version", function()
    assert_eq(jdk.major("1.8.0_402"), 8)
  end)

  it("returns nil for nonsense", function()
    assert_nil(jdk.major("banana"))
    assert_nil(jdk.major(nil))
  end)
end)

describe("jdk.parse_sdkmanrc", function()
  it("reads the java candidate", function()
    assert_eq(jdk.parse_sdkmanrc("# comment\njava=21.0.5-tem\nkotlin=2.0.0\n"), "21.0.5-tem")
  end)

  it("ignores a commented-out java line", function()
    assert_nil(jdk.parse_sdkmanrc("#java=21.0.5-tem\n"))
  end)

  it("returns nil when there is no java line", function()
    assert_nil(jdk.parse_sdkmanrc("kotlin=2.0.0\n"))
  end)
end)

describe("jdk.sort_installs", function()
  it("orders by major descending", function()
    local sorted = jdk.sort_installs({
      { path = "/a", version = "17.0.20", major = 17 },
      { path = "/b", version = "25.0.1", major = 25 },
      { path = "/c", version = "21.0.5", major = 21 },
    })
    assert_eq(sorted[1].major, 25)
    assert_eq(sorted[2].major, 21)
    assert_eq(sorted[3].major, 17)
  end)

  it("breaks a major tie with the full version string, newest first", function()
    local sorted = jdk.sort_installs({
      { path = "/a", version = "25.0.1", major = 25 },
      { path = "/b", version = "25.0.2", major = 25 },
    })
    assert_eq(sorted[1].version, "25.0.2")
  end)
end)

describe("jdk.runtime_name", function()
  it("names a runtime the way the jdtls settings schema wants", function()
    assert_eq(jdk.runtime_name(25), "JavaSE-25")
    assert_eq(jdk.runtime_name(8), "JavaSE-1.8")
  end)
end)

describe("jdk.pick_for_jdtls", function()
  it("takes the newest install at or above the floor", function()
    local pick = jdk.pick_for_jdtls({
      { path = "/new", version = "25.0.1", major = 25 },
      { path = "/old", version = "17.0.20", major = 17 },
    }, 21)
    assert_eq(pick.path, "/new")
  end)

  it("returns nil when nothing meets the floor", function()
    assert_nil(jdk.pick_for_jdtls({ { path = "/old", version = "17.0.20", major = 17 } }, 21))
  end)
end)

describe("jdk.pick_for_kotlin_lsp", function()
  it("skips a JDK above the ceiling in favour of one inside the range", function()
    local pick = jdk.pick_for_kotlin_lsp({
      { path = "/too-new", version = "25.0.1", major = 25 },
      { path = "/good", version = "21.0.5", major = 21 },
    }, 17, 24)
    assert_eq(pick.path, "/good")
  end)

  it("takes the newest install inside the range, not just any", function()
    local pick = jdk.pick_for_kotlin_lsp({
      { path = "/older", version = "17.0.20", major = 17 },
      { path = "/newer", version = "21.0.5", major = 21 },
    }, 17, 24)
    assert_eq(pick.path, "/newer")
  end)

  it("returns nil when every install is above the ceiling", function()
    assert_nil(jdk.pick_for_kotlin_lsp({ { path = "/too-new", version = "25.0.1", major = 25 } }, 17, 24))
  end)

  it("returns nil when every install is below the floor", function()
    assert_nil(jdk.pick_for_kotlin_lsp({ { path = "/too-old", version = "11.0.1", major = 11 } }, 17, 24))
  end)

  it("defaults to the module's own floor and ceiling", function()
    local pick = jdk.pick_for_kotlin_lsp({
      { path = "/too-new", version = "25.0.1", major = 25 },
      { path = "/good", version = "17.0.20", major = 17 },
    })
    assert_eq(pick.path, "/good")
  end)
end)
