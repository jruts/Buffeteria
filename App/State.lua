local ADDON, ns = ...
-- Local deployments use the same source with an independent add-on identity.
ns.isDev = ADDON == "Buffeteria-Dev"
ns.title = ns.isDev and "Buffeteria-Dev" or "Buffeteria"
ns.globalPrefix = ns.isDev and "BuffeteriaDev" or "Buffeteria"
ns.savedVariable = ns.globalPrefix .. "CharDB"
ns.commandKey = ns.isDev and "BUFFETERIADEV" or "BUFFETERIA"
ns.command = ns.isDev and "/buffdev" or "/buff"
ns.mediaPath = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
