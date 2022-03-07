-- InFlight uses FlightMapFrame directly, so it's necessary to change references
FlightMapFrame = WorldMapFrame
WorldFlightMapMixin = CreateFromMixins(FlightMap_FlightPathDataProviderMixin)

-- Return whether we're currently interacting with a flight master
function WorldFlightMapMixin:IsTaxiOpen()
	return not not GetTaxiMapID()
end

-- Use original taxi map as a fallback if we can't find a better one
function WorldFlightMapMixin:GetFallbackMap()
	return GetTaxiMapID() or C_Map.GetFallbackWorldMapID()
end

-- Try to find the most suitable map to show flight points on
-- Parent zone, continent, or taxi map
function WorldFlightMapMixin:GetBestFlightMap(uiMapID)
	if uiMapID then
		-- Return taxi map if player is in a raid
		-- We can't zoom out and the player shoudln't have to click through dungeon floors to find a flight point
		if IsInInstance() then
			return self:GetFallbackMap()
		end

		local zoneMapInfo = MapUtil.GetMapParentInfo(uiMapID, Enum.UIMapType.Zone, true)
		if zoneMapInfo and self:GetNumTaxiNodesOnMap(zoneMapInfo.mapID) > 0 then
			return zoneMapInfo.mapID
		end

		local continentMapInfo = MapUtil.GetMapParentInfo(uiMapID, Enum.UIMapType.Continent)
		if continentMapInfo then
			return continentMapInfo.mapID
		end
	end
	return self:GetFallbackMap()
end

function WorldFlightMapMixin:SetMapToBestFlightMap()
	self:GetMap():SetMapID(self:GetBestFlightMap(C_Map.GetBestMapForUnit("player")))
end

-- Return list of reachable flight nodes on map
function WorldFlightMapMixin:GetTaxiNodesForMap(uiMapID)
	-- Excludes current flight node that player is interacting with
	-- Only usable while interacting with a flight master
	local mapTaxiNodes = {}
	local allTaxiNodes = C_TaxiMap.GetAllTaxiNodes(uiMapID)
	for _, node in ipairs(allTaxiNodes) do
		if node.state == Enum.FlightPathState.Reachable and
		(node.position.x >= 0 and node.position.x <= 1 and node.position.y >= 0 and node.position.y <= 1) then
			-- 'node' is reachable and inside map boundaries
			table.insert(mapTaxiNodes, node)
		end
	end
	return mapTaxiNodes
end

-- Return count of reachable taxi nodes on map
function WorldFlightMapMixin:GetNumTaxiNodesOnMap(uiMapID)
	return #self:GetTaxiNodesForMap(uiMapID)
end

-- Initialize plugin
function WorldFlightMapMixin:OnAdded(mapFrame, ...)
	mapFrame.ResetTitleAndPortraitIcon = nop -- FIXME: FlightPathDataProvider calls methods that don't exist on WorldMapFrame
	FlightMap_FlightPathDataProviderMixin.OnAdded(self, mapFrame, ...)
	TaxiFrame:UnregisterAllEvents() -- Registers TAXIMAP_CLOSED in TaxiFrame_OnLoad
	UIParent:UnregisterEvent("TAXIMAP_OPENED")

	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("TAXIMAP_OPENED")
	self:RegisterEvent("TAXIMAP_CLOSED")
end

-- Clean up plugin (currently unused)
function WorldFlightMapMixin:OnRemoved()
	self:UnregisterEvent("TAXIMAP_CLOSED")
	self:UnregisterEvent("TAXIMAP_OPENED")
	self:UnregisterEvent("ADDON_LOADED")

	TaxiFrame:RegisterEvent("TAXIMAP_CLOSED")
	UIParent:RegisterEvent("TAXIMAP_OPENED")
	FlightMap_FlightPathDataProviderMixin.OnRemoved(self)
end

function WorldFlightMapMixin:OpenMap()
	if not InCombatLockdown() and not self:GetMap():IsShown() then
		ToggleWorldMap()
		self:SetMapToBestFlightMap()
	end
	self:OnShow()
end

function WorldFlightMapMixin:CloseMap()
	if not InCombatLockdown() and self:GetMap():IsShown() then
		ToggleWorldMap()
	end
end

-- Remove data provider to hide POI icons for unknown flight points (little red & yellow boots)
local FlightPinDataProvider = nil
function WorldFlightMapMixin:OnShow()
	if self:IsTaxiOpen() then
		for dataProvider in pairs(self:GetMap().dataProviders) do
			if dataProvider.ShouldShowTaxiNode then
				FlightPinDataProvider = dataProvider
				self:GetMap():RemoveDataProvider(dataProvider)
			end
		end
		FlightMap_FlightPathDataProviderMixin.OnShow(self)
	end
	self:RefreshAllData()
end

-- End interaction with flight master if map is closed
function WorldFlightMapMixin:OnHide()
	if self:IsTaxiOpen() then
		CloseTaxiMap()
		-- Re-add data provider for flight point POIs after we close the taxi map
		if FlightPinDataProvider then
			self:GetMap():AddDataProvider(FlightPinDataProvider)
			FlightPinDataProvider = nil
		end
		FlightMap_FlightPathDataProviderMixin.OnHide(self)
	end
end

do
	-- Raise lines and flight points above other icons on the map and fix their scales
	-- FIXME: Find a way to let the blizzard code handle drawing these on the correct layers at the correct scales

	local function OnRelease(framePool, frame)
		frame.RevealAnim:Stop()
		if frame.FadeAnim then
			frame.FadeAnim:Stop()
		end
		frame:Hide()
	end

	function WorldFlightMapMixin:CalculateLineThickness()
		self.lineThickness = 1 / self:GetMap():GetCanvasScale() * 45
	end

	local LinePoolParentFrame = CreateFrame("Frame", nil, WorldMapFrame:GetCanvas())
	LinePoolParentFrame:SetAllPoints()
	LinePoolParentFrame:SetFrameLevel(2200)

	WorldFlightMapMixin.highlightLinePool = CreateFramePool("FRAME", LinePoolParentFrame, "FlightMap_BackgroundFlightLineTemplate", OnRelease)
	WorldFlightMapMixin.backgroundLinePool = CreateFramePool("FRAME", LinePoolParentFrame, "FlightMap_BackgroundFlightLineTemplate", OnRelease)

	-- Raise flight button frame level above other map POIs
	local _FlightMap_FlightPointPinMixin__OnLoad = FlightMap_FlightPointPinMixin.OnLoad
	function FlightMap_FlightPointPinMixin:OnLoad()
		_FlightMap_FlightPointPinMixin__OnLoad(self)
		self:UseFrameLevelType("PIN_FRAME_LEVEL_TOPMOST")
	end
end

function WorldFlightMapMixin:OnEvent(event, ...)
	if event == "TAXIMAP_OPENED" then
		self:OpenMap()
	elseif event == "TAXIMAP_CLOSED" then
		self:CloseMap()
	end
end

WorldMapFrame:AddDataProvider(CreateFromMixins(WorldFlightMapMixin))
