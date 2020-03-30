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
	self.db = LibStub("AceDB-3.0"):New("AssignManagerDB", defaults, true)
	C_ChatInfo.RegisterAddonMessagePrefix(ChatPrefix)
	self.minimap_icon = LibStub("LibDBIcon-1.0")
	self.minimap_icon:Register("AssignManager", MinimapIcon, self.db.profile.minimap)
	self.assignments = {}
	self:CreateWindow()
	self:RegisterChatCommand("assignmanager", "SlashCommand")
	AceEvent:RegisterEvent("GROUP_ROSTER_UPDATE", function() self:UpdateRoster() end)
	AceEvent:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, msg, _, sender)
		if prefix ~= ChatPrefix then
			return
		end
		self:ReceiveAssignments(msg)
	end)
	AceEvent:RegisterMessage("TOGGLE_WINDOW", function() self:ToggleWindow() end)
	self:Print("assign manager initialized")
end

function AssignManager:SlashCommand(input)
	input, arg1, arg2 = self:GetArgs(input, 3)
	if input == "show" then
		self.main_window:Show()
		return
	end
	if input == "report" then
		self:ReportAssignments()
		return
	end
	if input == "fake" then
		self:FakeAssignments(tonumber(arg1), tonumber(arg2))
		return
	end
	self:Print([[
usage:
  show show the main window
  report report assignments to configured channel
  fake set fake assginments for debug]])
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
function AssignManager:GetSubjectsTargets(classes)
	if not classes then
		classes = {
			PALADIN = true,
			PRIEST = true,
			SHAMAN = true,
			DRUID = true
		}
	end

	local classNames = {}
	for i = 1,8 do
		local classInfo = C_CreatureInfo.GetClassInfo(i)
		if classInfo and classes[classInfo.classFile] then
			classNames[classInfo.className] = true
		end
	end

	local subjects = {}
	local groups = {}
	local MTS = {}
	for i = 1,MAX_RAID_MEMBERS do
		name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
		if name then
			if role == "MAINTANK" then
				MTS[#MTS + 1] = {
					["type"] = "PLAYER",
					["name"] = name
				}
			else 
				if not groups[subgroup] then
					groups[subgroup] = {
						["type"] = "GROUP",
						["name"] = "G"..subgroup
					}
				end
			end
			if classNames[class] then
				subjects[#subjects + 1] = {
					["name"] = name,
					["class"] = class
				}
			end
		end
	end
	local targets = MTS
	for k,v in pairs(groups) do
		targets[#targets + 1] = v
	end
	return subjects, targets
end

function AssignManager:FakeAssignments(groups, subjects)
	if not groups then
		groups = 8
	end
	if not subjects then
		subjects = 4
	end
	self.targets = {
		{
			type = "PLAYER",
			name = "Firsttank"
		},
		{
			type = "PLAYER",
			name = "Secondtank"
		},
	}
	for i= 1,groups do
		self.targets[#self.targets + 1] = {
			type = "GROUP",
			name = "G"..i
		}
	end
	self.subjects = {
		{
			name = "Paladin",
			class = "PALADIN"
		},
		{
			name = "Priest",
			class = "PRIEST"
		},
		{
			name = "Druid",
			class = "DRUID"
		},
		{
			name = "Shaman",
			class = "SHAMAN"
		}
	}
	for i= 1,subjects - 4 do
		self.subjects[#self.subjects + 1] = {
			name = "Heal"..i,
			class = "PRIEST"
		}
	end
	self.assignments = {}
	for i, s in pairs(self.subjects) do
		self.assignments[s.name] = {}
	end
	self:UpdateTable()
	AceEvent:SendMessage("ASSIGNMENTS_CHANGED")
end

function AssignManager:UpdateRoster()
	self.subjects, self.targets = self:GetSubjectsTargets()

	local old = self.assignments
	self.assignments = {}
	for i, subject in pairs(self.subjects) do
		self.assignments[subject["name"]] = {}
		if old[subject["name"]] then
			for j, target in pairs(self.targets) do
				self.assignments[subject["name"]][target["name"]] = old[subject["name"]][target["name"]]
			end
		end
	end
	self:UpdateTable()
	AceEvent:SendMessage("ASSIGNMENTS_CHANGED")
end

function AssignManager:UpdateAssignments()
	for i, subject in pairs(self.subjects) do
		for j, target in pairs(self.targets) do
			self.checkboxes[subject.name][target.name]:SetValue(self.assignments[subject.name][target.name])
		end
	end
end

function AssignManager:ReportAssignments()
	local assigns = {}
	for i, target in pairs(self.targets) do
		local s = {}
		for j, subject in pairs(self.subjects) do
			if self.assignments[subject.name][target.name] then
				s[#s + 1] = subject.name
			end
		end
		if #s > 0 then
			local msg = table.concat(s, ", ")
			local found = false
			for _, a in pairs(assigns) do
				if a.msg == msg then
					found = true
					a.targets[#a.targets + 1] = target.name
					break
				end
			end
			if not found then
				assigns[#assigns + 1] = {
					msg = msg,
					targets = {target.name}
				}
			end
		end
	end

	for _, a in pairs(assigns) do
		SendChatMessage(
			table.concat(a.targets, ", ").." -> "..a.msg,
			self.db.profile.reportChannel.type,
			nil,
			self.db.profile.reportChannel.channel
			)
	end
end

function AssignManager:ReceiveAssignments(msg)
	local success, assignments = AceSerializer:Deserialize(msg)
	if success then
		self.assignments = assignments
	end
	AceEvent:SendMessage("ASSIGNMENTS_CHANGED")
end

function AssignManager:SetAssign(subject, target, value)
	if (not not self.assignments[subject.name][target.name]) == value then
		return
	end
	self.assignments[subject.name][target.name] = value
	msg = AceSerializer:Serialize(self.assignments)
	C_ChatInfo.SendAddonMessage(ChatPrefix, msg, "RAID")
end

function AssignManager:UpdateTable()
	self.checkboxes = {}
	if not self.table then
		return
	end
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
	l:SetWidth(0)
	self.table:AddChild(l)
	local subjectW = 0
	local colW = 0
	for j, value in ipairs(self.targets)
		do
			l = AceGUI:Create("Label")
			l:SetText(value["name"])
			l:SetJustifyH("CENTER")
			local w = math.max(22, l.label:GetStringWidth())
			colW = colW + w
			l:SetWidth(w)
			self.table:AddChild(l)
		end

	for i, subject in ipairs(self.subjects)
		do
			self.checkboxes[subject.name] = {}
			l = AceGUI:Create("Label")
			l:SetText(subject["name"])
			local w = l.label:GetStringWidth()
			l:SetWidth(w)
			subjectW = math.max(subjectW, w)
			local r, g, b, hex = GetClassColor(subject["class"])
			l:SetColor(r, g, b)
			self.table:AddChild(l)
			for j, target in ipairs(self.targets)
				do
					c = AceGUI:Create("CheckBox")
					c:SetDisabled(rank == 0)
					c:SetWidth(16)
					c:SetHeight(20)
					c:SetValue(self.assignments[subject.name][target.name])
					self.checkboxes[subject.name][target.name] = c
					c:SetCallback("OnValueChanged", function(c) self:SetAssign(subject, target, c:GetValue()) end)
					self.table:AddChild(c)
				end
		end
	self.main_window:SetHeight(self.fixed_el_height + self.table.frame:GetHeight())
	self.main_window:SetWidth(math.max(200, subjectW + colW + 20))
end

function AssignManager:CreateWindow()
	self.main_window = AceGUI:Create("Window")
	self.main_window:Hide()
	self.main_window:SetTitle("Assign Manager")
	self.main_window:EnableResize(false)
	if self.db.profile.window
		then
			self.main_window:SetStatusTable(self.db.profile.window)
		end
	self.db.profile.window = self.main_window.status

	self.table = AceGUI:Create("SimpleGroup")
	self.table:SetLayout("Table")
	self.main_window:AddChild(self.table)

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

	self.fixed_el_height = 50 + reportG.frame:GetHeight()

	self:UpdateRoster()
	AceEvent:RegisterMessage("ASSIGNMENTS_CHANGED", function() self:UpdateAssignments() end)
end
