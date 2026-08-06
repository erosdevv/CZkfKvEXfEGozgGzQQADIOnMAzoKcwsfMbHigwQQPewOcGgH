-- boot.lua
-- Shared boot notifications for LLSPLOIT.

function __llsploitBootNotify(text)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {
			Title = "LLSPLOIT",
			Text = tostring(text),
			Duration = 4,
		})
	end)
	warn("[LLSPLOIT] " .. tostring(text))
end

_G.__llsploitBootNotify = __llsploitBootNotify

__llsploitBootNotify("Loading...")
print("[LLSPLOIT] Loading...")

return { name = "boot" }
