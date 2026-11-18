-- Test runner: defines test/eq/ok, runs every tests/test_*.lua, prints failures and a summary.
package.path = "tests/?.lua;" .. package.path

local passed, failed = 0, 0
local current, currentFailed

local function fail(msg)
    currentFailed = true
    print("FAIL " .. current .. ": " .. msg)
end

function ok(cond, label)
    if not cond then fail("expected truthy" .. (label and (" (" .. label .. ")") or "")) end
end

-- eq compares with ==; two tables are compared shallowly (same keys, values equal with ==).
function eq(actual, expected, label)
    local same = actual == expected
    if not same and type(actual) == "table" and type(expected) == "table" then
        same = true
        for k, v in pairs(actual) do if expected[k] ~= v then same = false end end
        for k, v in pairs(expected) do if actual[k] ~= v then same = false end end
    end
    if not same then
        fail((label or "eq") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

function test(name, fn)
    current, currentFailed = name, false
    local good, err = pcall(fn)
    if not good then fail("error: " .. tostring(err)) end
    if currentFailed then failed = failed + 1 else passed = passed + 1 end
end

local files = {}
local pipe = io.popen('ls tests/test_*.lua 2>/dev/null')
for line in pipe:lines() do files[#files + 1] = line end
pipe:close()
table.sort(files)

for _, file in ipairs(files) do
    current, currentFailed = file, false
    local chunk, err = loadfile(file)
    if not chunk then
        print("FAIL " .. file .. ": " .. tostring(err))
        failed = failed + 1
    else
        local good, runErr = pcall(chunk)
        if not good then
            print("FAIL " .. file .. ": " .. tostring(runErr))
            failed = failed + 1
        end
    end
end

print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
