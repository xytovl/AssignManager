AssignManager = LibStub("AceAddon-3.0"):NewAddon("AssignManager", "AceConsole-3.0")

AceEvent = LibStub("AceEvent-3.0")
AceGUI = LibStub("AceGUI-3.0")
AceSerializer = LibStub("AceSerializer-3.0")

ChatPrefix = "AssignManager"

local defaults = {
	profile = {
		minimap = {
			hide = false
		},
		reportChannel = {
			type = "raid",
			name = "raid"
		}
	}
}

MinimapIcon = LibStub("LibDataBroker-1.1"):NewDataObject("AssignManager", {
	type = "data source",
	text = "Assign manager",
	icon = "Interface\\Icons\\Spell_Holy_prayerofspirit",
	OnClick = function ()
		AceEvent:SendMessage("TOGGLE_WINDOW")
	end,
	OnTooltipShow = function (tooltip)
		tooltip:AddLine("|cFF0FFF00Assign manager|r", 1, 1, 1);
	end
})

function AssignManager:OnInitialize()
	FrameXML_Debug(1)
	self.db = LibStub("AceDB-3.0"):New("AssignManagerDB", defaults, true)
	C_ChatInfo.RegisterAddonMessagePrefix(ChatPrefix)
	self.minimap_icon = LibStub("LibDBIcon-1.0")
	self.minimap_icon:Register("AssignManager", MinimapIcon, self.db.profile.minimap)
	self:InitAssignments()
	self:CreateWindow()
	self:RegisterChatCommand("assignmanager", "SlashCommand")
	AceEvent:RegisterEvent("GROUP_ROSTER_UPDATE", function() self:UpdateAssignments() end)
	AceEvent:RegisterEvent("CHAT_MSG_ADDON", function(prefix, msg) if prefix == ChatPrefix then self:ReceiveAssignments(msg) end end)
	AceEvent:RegisterMessage("TOGGLE_WINDOW", function() self:ToggleWindow() end)
	self:Print("assign manager initialized")
end

function AssignManager:SlashCommand(input)
	if input == "show" then
		self.main_window:Show()
		return
	end
	if input == "report" then
		self:ReportAssignments()
		return
	end
	self:Print("usage:\n  show show the main window")
end

function AssignManager:SetChannel(name)
	if GetChatTypeIndex(name) ~= 0 and string.upper(name) ~= "CHANNEL"
		then
			self.db.profile.reportChannel = {
				type = name,
				text = name
			}
		return
		end
	local idx, _ = GetChannelName(name)
	if idx
		then
			self.db.profile.reportChannel = {
            type = "CHANNEL",
            text = name,
            channel = idx
         }
		end

end

function AssignManager:ToggleWindow()
	if self.main_window:IsShown() then
		self.main_window:Hide()
	else
		self.main_window:Show()
	end
end

-- Get players we can assign targets to
function AssignManager:GetSubjects(classes)
	if not classes
		then
			classes = {
				PALADIN = true,
				PRIEST = true,
				SHAMAN = true,
				DRUID = true
			}
		end
	local subjects = {}
	for i = 1,MAX_RAID_MEMBERS
		do
			_, class, _ = UnitClass("raid"..i)
			if classes[class]
				then
					name, _ = UnitName("raid"..i)
					subjects[#subjects + 1] = {
						["name"] = name,
						["class"] = class
					}
				end
		end
	return subjects
end

-- Get the list of possible targets
function AssignManager:GetTargets()
	local groups = {}
	local MTS = {}
	for i = 1,MAX_RAID_MEMBERS
		do
			name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
			if role == "MAINTANK"
				then
					MTS[#MTS + 1] = {
						["type"] = "PLAYER",
						["name"] = name
					}
				else
					if not groups[subgroup]
						then
							groups[subgroup] = {
								["type"] = "GROUP",
								["name"] = "G"..subgroup
							}
						end
				end
		end
	local targets = MTS
	for k,v in pairs(groups)
		do
			targets[#targets + 1] = v
		end
	return targets
end

function AssignManager:InitAssignments()
	self.targets = self:GetTargets()
	self.subjects = self:GetSubjects()

	self.assignments = {}
	for i, subject in pairs(self.subjects)
		do
			self.assignments[subject["name"]] = {}
		end
	AceEvent:SendMessage("ASSIGNMENTS_CHANGED")
end

function AssignManager:UpdateAssignments()
	self.targets = self:GetTargets()
	self.subjects = self:GetSubjects()

	local old = self.assignments
	self.assignments = {}
	for i, subject in pairs(self.subjects)
		do
			self.assignments[subject["name"]] = {}
			if old[subject["name"]]
				then
					for j, target in pairs(self.targets)
						do
							self.assignments[subject["name"]][target["name"]] = old[subject["name"]][target["name"]]
						end
				end
		end
	AceEvent:SendMessage("ASSIGNMENTS_CHANGED")
end

function AssignManager:ReportAssignments()
	for i, subject in pairs(self.subjects)
		do
			local targets = self.assignments[subject["name"]]
			local msg = subject["name"]..": "
			local activeTargets = {}
			for t, v in pairs(targets)
				do
					if v
						then
							activeTargets[#activeTargets + 1] = t
						end
				end
			if #activeTargets
				then
					SendChatMessage(
						subject["name"]..": "..table.concat(activeTargets, ", "),
						self.db.profile.reportChannel.type,
						nil,
						self.db.profile.reportChannel.channel
						)
				end
		end
end

function AssignManager:ReceiveAssignments(msg)
	print(msg)
	self.assignments = AceSerializer:Deserialize(msg)
	AceEvent:SendMessage("ASSIGNMENTS_CHANGED")
end

function AssignManager:SetAssign(subject, target, value)
	self.assignments[subject["name"]][target["name"]] = value
	msg = AceSerializer:Serialize(self.assignments)
	C_ChatInfo.SendAddonMessage(ChatPrefix, msg, "RAID")
end

function AssignManager:UpdateTable()
	self.table:ReleaseChildren()

	local idx = UnitInRaid("player")
	local rank = 1
	if idx
		then
			_, rank = GetRaidRosterInfo(idx)
		end

	data = {}
	-- First column is subjects, then one per target
	data.columns = {0}
	for i = 1,#self.targets
		do
			data.columns[i+1] = 0
		end
	self.table:SetUserData("table", data)

	self.widgets = {}

	-- Header row
	local l = AceGUI:Create("Label")
	self.table:AddChild(l)
	for j, value in ipairs(self.targets)
		do
			l = AceGUI:Create("Label")
			l:SetText(value["name"])
			self.table:AddChild(l)
		end

	for i, subject in ipairs(self.subjects)
		do
			local w = {}
			l = AceGUI:Create("Label")
			l:SetText(subject["name"])
			local r, g, b, hex = GetClassColor(subject["class"])
			l:SetColor(r, g, b)
			self.table:AddChild(l)
			for j, target in ipairs(self.targets)
				do
					c = AceGUI:Create("CheckBox")
					c:SetDisabled(rank == 0)
					c:SetWidth(20)
					c:SetValue(self.assignments[subject.name][target.name])
					c:SetCallback("OnValueChanged", function(c) self:SetAssign(subject, target, c:GetValue()) end)
					self.table:AddChild(c)
				end
		end
end

function AssignManager:CreateWindow()
	self.main_window = AceGUI:Create("Window")
	--self.main_window:Hide()
	self.main_window:SetTitle("Assign Manager")
	if self.db.profile.window
		then
			self.main_window:SetStatusTable(self.db.profile.window)
		end
	self.db.profile.window = self.main_window.status

	self.table = AceGUI:Create("SimpleGroup")
	self.table:SetLayout("Table")
	self.main_window:AddChild(self.table)
	self:UpdateTable()
	AceEvent:RegisterMessage("ASSIGNMENTS_CHANGED", function() self:UpdateTable() end)

	local reportG = AceGUI:Create("SimpleGroup")
	reportG:SetLayout("Flow")
	self.main_window:AddChild(reportG)
	local b = AceGUI:Create("Button")
	b:SetText("report")
	b:SetAutoWidth(true)
	b:SetCallback("OnClick", function() self:ReportAssignments() end)
	reportG:AddChild(b)
	local e = AceGUI:Create("EditBox")
	e:SetText(self.db.profile.reportChannel.name)
	e:SetWidth(100)
	e:SetCallback("OnTextChanged", function() self:SetChannel(e:GetText()) end)
	reportG:AddChild(e)

end
