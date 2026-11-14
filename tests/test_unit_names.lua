local W = require("wow")
test("two values become one name", function()
    local GL = W.load()
    W.units.target = { "Ooh", "Woo" }
    eq(GL:UnitRosterName("target"), "Ooh Woo", "first and surname")
end)
test("realm is not a surname", function()
    local GL = W.load()
    W.units.target = { "Ooh", "TestRealm" }
    eq(GL:UnitRosterName("target"), "Ooh", "realm dropped")
end)
test("GetUnitName with a space wins", function()
    local GL = W.load()
    W.units.target = { full = "Ooh Woo-Test Realm" }
    eq(GL:UnitRosterName("target"), "Ooh Woo", "full name, realm stripped")
end)
test("grouping flags a newcomer", function()
    local GL = W.load()
    W.setRoster({ { name = "Zev Zev", rank = "Officer", rankIndex = 3, level = 20, class = "WARRIOR" } })
    W.scan(GL)
    W.setRoster({ { name = "Zev Zev", rank = "Officer", rankIndex = 3, level = 20, class = "WARRIOR" }, { name = "Ooh Woo", rank = "Initiate", rankIndex = 8, level = 20, class = "MAGE" } })
    W.scan(GL)
    W.units.party1 = { "Ooh", "Woo" }
    W.party = 1
    W.fire("GROUP_ROSTER_UPDATE")
    local g = GL:Guild()
    ok(g.members["Ooh Woo"] and g.members["Ooh Woo"].week and g.members["Ooh Woo"].week.grouped ~= nil, "grouped flag set")
end)
