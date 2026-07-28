local Session = require "engine.runtime.session"

local feature = {
    id = "session",
    requires = {"engine.features.world"},
}

function feature:register(host)
    local service = Session.new(host.session_store)

    host:registerService("session", service)
    host:registerBootValidator("zz.session.sections", function()
        return service:validateKnown()
    end)
    host:registerWorldInspector("session", function()
        return service:inspect()
    end)
end

return feature
