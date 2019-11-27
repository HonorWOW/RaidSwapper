--[[
The purpose of this addon is to quickly swap players in and out of raid groups without having to manually find and swap them.

The expected format is:
In:
name1
Out:
name2

In and Out can be swapped, and any number of names under each is valid.

TODO: Reduce number of redundant GetRaidRosterInfo calls by caching information.
TODO: Perform swaps we can, THEN try moving. Requires less space.
TODO: Add support for popup after encounter success + allow for pre-defining swaps after all fights so they don't need to be entered each time.

]]
local _, RaidSwapper = ...
local notFoundPlayers = {}

RaidSwapper = LibStub("AceAddon-3.0"):NewAddon(RaidSwapper, "RaidSwapper", "AceConsole-3.0", "AceEvent-3.0")

function RaidSwapper:OnInitialize()
  RaidSwapper:RegisterChatCommand('swap', 'HandleChatCommand')
end

function RaidSwapper:HandleChatCommand(input)
  self:OpenInput()
end

function RaidSwapper:OpenInput()
  RaidSwapFrame:Show()
  RaidSwapFrameScroll:Show()
  RaidSwapFrameScrollText:Show()
  RaidSwapFrameScrollText:HighlightText()
  RaidSwapFrameScrollText:SetScript("OnEscapePressed", function(self)
    RaidSwapFrame:Hide()
  end)
  RaidSwapFrameButton:SetScript("OnClick", function(self)
    RaidSwapper:Swap()
    RaidSwapFrame:Hide()
  end)
end

function RaidSwapper:Swap()
    if (UnitIsGroupAssistant("player") == false and UnitIsGroupLeader("player") == false) then
        print("|CFFFF0000[RaidSwapper]: You do not have the required permissions to swap players.")
        return
   end
   if (RaidSwapFrameScrollText ~= nil and RaidSwapFrameScrollText:GetText() ~= nil) then
        local playersToRemove = {}
        local playersToAdd = {}
        -- Set up counts for all the subgroups to make non-swapping moves more consistent.
        local counts = RaidSwapper:PopulateSubgroupCounts()

        RaidSwapper:ParseInput(playersToRemove, playersToAdd)

        -- If there are equal amounts of removes and adds, we can just try swaps, which are nice and easy.
        if (#playersToRemove == #playersToAdd) then
            RaidSwapper:SwapPlayers(playersToRemove, playersToAdd, counts)
        else
            -- Else, let's try to move all the players to remove out and then swap players in.
            RaidSwapper:MovePlayers(playersToRemove, playersToAdd, counts)
        end
        
        if (#playersToRemove > 0) then
            local removedPlayers = table.concat(playersToRemove, ", ")
            SendChatMessage("Players (" .. removedPlayers .. ") have been swapped out.", "RAID")
        end
        
        if (#playersToAdd > 0) then
            local addedPlayers = table.concat(playersToAdd, ", ")
            SendChatMessage("Players (" .. addedPlayers .. ") have been swapped in.", "RAID")
        end

        if (#notFoundPlayers > 0) then
            local missingPlayers = table.concat(notFoundPlayers, ", ")
            SendChatMessage("Players (" .. missingPlayers .. ") could not be found in the raid.", "RAID")
            notFoundPlayers = {}
        end
   end
end

function RaidSwapper:PopulateSubgroupCounts()
    local counts = {0, 0, 0, 0, 0, 0, 0, 0}
    for i = 1, MAX_RAID_MEMBERS do
        local name, _, subgroup = GetRaidRosterInfo(i)
        -- If the unit doesn't exist, name will be nil.
        if (name ~= nil) then
            counts[subgroup] = counts[subgroup] + 1
        else
            return counts
        end
    end
    return counts
end

function RaidSwapper:ParseInput(playersToRemove, playersToAdd, raid)
    local input = RaidSwapFrameScrollText:GetText()
    local removingPlayers = true
    local parsedInput = string.gmatch(input, "[^\r\n]+")
    for entry in parsedInput do
        if (entry == "Out:") then
            removingPlayers = true
        elseif (entry == "In:") then
            removingPlayers = false
        elseif (removingPlayers and string.len(entry) > 2 and RaidSwapper:FindPlayer(entry) ~= nil) then
            playersToRemove[#playersToRemove + 1] = entry
        elseif (string.len(entry) > 2 and RaidSwapper:FindPlayer(entry) ~= nil) then
            playersToAdd[#playersToAdd + 1] = entry
        end
    end 
end

-- Swap two players in the raid group.
function RaidSwapper:SwapPlayers(playersToRemove, playersToAdd, counts)
    for i = 1, #playersToRemove do
        local removeId = RaidSwapper:FindPlayer(playersToRemove[i])
        local addId = RaidSwapper:FindPlayer(playersToAdd[i])
        -- In case either of the users can't be found *somehow*, try perform moves instead.
        if (removeId ~= nil and addId == nil) then
            local subGroup = RaidSwapper:FindOpenSubgroupForRemoval(playersToAdd[i], counts)
            SetRaidSubgroup(removeId, subGroup)
        elseif (removeId == nil and addId ~= nil) then
            local subGroup = RaidSwapper:FindOpenSubgroupForAddition(playersToAdd[i], counts)
            SetRaidSubgroup(addId, subGroup)
        else
            -- Else, let's just perform our swaps!
            local _, _, subGroupRemove = GetRaidRosterInfo(removeId)
            local _, _, subGroupAdd = GetRaidRosterInfo(addId)
            if (subGroupRemove <= 4 and subGroupAdd > 4) then
                counts[subGroupRemove] = counts[subGroupRemove] - 1
                counts[subGroupAdd] = counts[subGroupAdd] + 1
                SwapRaidSubgroup(removeId, addId)
            end
        end

    end
    
    print("|CFF00FF00[RaidSwapper]: Finished swapping players!")
end

-- Moves players to remove out, then moves players to add in.
function RaidSwapper:MovePlayers(playersToRemove, playersToAdd, counts)
    for i = 1, #playersToRemove do
        local removeId = RaidSwapper:FindPlayer(playersToRemove[i])
        local group = RaidSwapper:FindOpenSubgroupForRemoval(removeId, counts)
        if (removeId ~= nil and group ~= nil) then
            SetRaidSubgroup(removeId, group)
        end
    end
    
    for i = 1, #playersToAdd do
        local addId = RaidSwapper:FindPlayer(playersToAdd[i])
        local group = RaidSwapper:FindOpenSubgroupForAddition(addId, counts)
        if (addId ~= nil and group ~= nil) then
            SetRaidSubgroup(addId, group)
        end
    end
end

-- Find the raid index of a player.
function RaidSwapper:FindPlayer(player)
    for i = 1, 40 do
        local name = GetRaidRosterInfo(i)
        if (name == player) then
            return i
        end
    end
    print("|CFFFF0000[RaidSwapper]: Could not find player: " .. player)
    notFoundPlayers[#notFoundPlayers + 1] = player
end

-- Find an open subgroup to move a player to, favoring the last groups (e.g to remove a player from the first four)
function RaidSwapper:FindOpenSubgroupForRemoval(player, counts)
    for i = 8, 1, -1 do
        if (counts[i] == nil or counts[i] < 5) then
            local _, _, subgroup = GetRaidRosterInfo(player)
            counts[subgroup] = counts[subgroup] - 1
            counts[i] = counts[i] + 1
            return i
        end
    end
end

-- Find an open subgroup to move a player to, favoring the first groups (e.g. to add a player to the first four)
function RaidSwapper:FindOpenSubgroupForAddition(player, counts)
    for i = 1, 8 do
        if (counts[i] == nil or counts[i] < 5) then
            local _, _, subgroup = GetRaidRosterInfo(player)
            counts[subgroup] = counts[subgroup] - 1
            counts[i] = counts[i] + 1
            return i
        end
    end
end
