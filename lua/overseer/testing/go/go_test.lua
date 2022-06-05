local files = require("overseer.files")
local parser = require("overseer.parser")
local tutils = require("overseer.testing.utils")
local TEST_STATUS = require("overseer.testing.data").TEST_STATUS

local M = {
  name = "go_test",
  is_workspace_match = function(self, dirname)
    for _, fname in ipairs({ "go.mod" }) do
      if files.exists(files.join(dirname, fname)) then
        return true
      end
    end
    return false
  end,
  get_cmd = function(self)
    return { "go", "test" }
  end,
  run_test_dir = function(self, dirname)
    return {
      cmd = self:get_cmd(),
      args = { "-v", string.format("%s/...", dirname) },
    }
  end,
  run_test_file = function(self, filename)
    return {
      cmd = self:get_cmd(),
      args = { "-v", filename },
    }
  end,
  run_single_test = function(self, test)
    return {
      cmd = self:get_cmd(),
      args = { "-v", "-run", string.format("^%s$", test.name) },
    }
  end,
  find_tests = function(self, bufnr)
    return tutils.get_tests_from_ts_query(
      bufnr,
      "go",
      "overseer_go_test",
      [[
(package_clause (package_identifier) @name) @group

(function_declaration
  name: (identifier) @name (#lua-match? @name "^Test")) @test
]],
      function(item)
        return item.name
      end
    )
  end,
}

local status_map = {
  FAIL = TEST_STATUS.FAILURE,
  PASS = TEST_STATUS.SUCCESS,
  SKIP = TEST_STATUS.SKIPPED,
}
local qf_type_map = {
  [TEST_STATUS.FAILURE] = "E",
  [TEST_STATUS.SUCCESS] = "I",
  [TEST_STATUS.SKIPPED] = "W",
}
local status_field = {
  "status",
  function(value)
    return status_map[value]
  end,
}
local duration_field = {
  "duration",
  function(x)
    return tonumber(x)
  end,
}
M.parser = function()
  return {
    tests = {
      parser.extract({
        append = false,
        regex = true,
        postprocess = function(item)
          item.id = item.name
        end,
      }, "\\v^\\=\\=\\= RUN\\s+([^[:space:]]+)$", "name"),
      parser.always(parser.parallel(
        -- Stop parsing output if we hit the end line
        parser.invert(parser.test({ regex = true }, "\\v^--- (FAIL|PASS|SKIP)")),
        parser.extract_nested(
          { append = false },
          "diagnostics",
          parser.loop(
            { ignore_failure = true },
            parser.extract("^%s+([^:]+%.go):(%d+):%s?(.*)$", "filename", "lnum", "text")
          )
        ),
        parser.extract_multiline({ append = false }, "(.*)", "text")
      )),
      parser.extract(
        {
          regex = true,
          append = false,
          postprocess = function(item)
            if item.diagnostics then
              for _, diag in ipairs(item.diagnostics) do
                diag.type = qf_type_map[item.status]
              end
            end
          end,
        },
        "\\v^--- (FAIL|PASS|SKIP): ([^[:space:]]+) \\(([0-9\\.]+)s\\)",
        status_field,
        "name",
        duration_field
      ),
      parser.always(
        parser.sequence(
          parser.test("^panic:"),
          parser.skip_until("^goroutine%s"),
          parser.extract_nested(
            { append = false },
            "stacktrace",
            parser.loop(
              parser.sequence(
                parser.extract({ append = false }, { "^(.+)%(.*%)$", "^created by (.+)$" }, "text"),
                parser.extract("^%s+([^:]+.go):([0-9]+)", "filename", "lnum")
              )
            )
          )
        )
      ),
      parser.append(),
    },
  }
end

return M
