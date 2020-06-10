--[[
ideAlarm.lua
Please read: https://github.com/dewgew/ideAlarm/wiki
Copyright (C) 2017  BakSeeDaa
		This program is free software: you can redistribute it and/or modify
		it under the terms of the GNU General Public License as published by
		the Free Software Foundation, either version 3 of the License, or
		(at your option) any later version.
		This program is distributed in the hope that it will be useful,
		but WITHOUT ANY WARRANTY; without even the implied warranty of
		MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
		GNU General Public License for more details.
		You should have received a copy of the GNU General Public License
		along with this program.  If not, see <http://www.gnu.org/licenses
--]]

local config = require "ideAlarmConfig"
local custom = require "ideAlarmHelpers"

local scriptVersion = '2.4.0'
local ideAlarm = {}

-- Possible Zone statuses
local ZS_NORMAL = 'Normal'
ideAlarm.ZS_NORMAL = ZS_NORMAL
local ZS_ARMING = 'Arming'
ideAlarm.ZS_ARMING = ZS_ARMING
local ZS_ALERT = 'Alert'
ideAlarm.ZS_ALERT = ZS_ALERT
local ZS_ERROR = 'Error'
ideAlarm.ERROR = ZS_ERROR
local ZS_TRIPPED = 'Tripped'
ideAlarm.TRIPPED = ZS_TRIPPED
local ZS_TIMED_OUT = 'Timed out'
ideAlarm.ZS_TIMED_OUT = ZS_TIMED_OUT

local SECURITY_PANEL_NAME = config.SECURITY_PANEL_NAME or 'Security Panel' 

local SENSOR_CLASS_A = 'a' -- Sensor active in both arming modes. E.g. "Armed Home" and "Armed Away".
ideAlarm.SENSOR_CLASS_A = SENSOR_CLASS_A
local SENSOR_CLASS_B = 'b' -- Sensor active in arming mode "Armed Away" only.
ideAlarm.SENSOR_CLASS_B = SENSOR_CLASS_B

local function isActive(sensor)
	if sensor.switchType == 'Door Lock' then return (not sensor.active) else return sensor.active end
end

local function callIfDefined(f)
	return function(...)
		local error, result = pcall(custom.helpers[f], ...)
		if error then -- f exists and is callable
			return result
		end
	end
end

--- Initialize the alarm zones table with config values and some additional functions 
local function initAlarmZones()
	local zones = {}
	for i, alarmZone in ipairs(config.ALARM_ZONES) do

		alarmZone.zoneNumber = i

		alarmZone.armingMode =
		--- Gets the arming mode for the zone 
		-- @param domoticz The Domoticz object
		-- @return String. One of domoticz.SECURITY_DISARMED, domoticz.SECURITY_ARMEDAWAY
		-- and domoticz.SECURITY_ARMEDHOME
		function(domoticz)
			return(domoticz.devices(alarmZone.armingModeTextDevID).state)
		end

		alarmZone.status =
		--- Gets the alarm zone's status 
		-- @param domoticz The Domoticz object
		-- @return String. One of alarm.ZS_NORMAL, alarm.ZS_ARMING, alarm.ZS_ALERT, alarm.ERROR,
		-- alarm.ZS_TRIPPED or alarm.ZS_TIMED_OUT
		function(domoticz)
			return(domoticz.devices(alarmZone.statusTextDevID).state)
		end

		alarmZone.isArmed =
		--- Returns true if the zone is armed 
		-- @param domoticz The Domoticz object
		-- @return Boolean
		function(domoticz)
			return(alarmZone.armingMode(domoticz) ~= domoticz.SECURITY_DISARMED)  
		end

		alarmZone.isArmedHome =
		--- Returns true if the zone is armed home
		-- @param domoticz The Domoticz object
		-- @return Boolean
		function(domoticz)
			return(alarmZone.armingMode(domoticz) == domoticz.SECURITY_ARMEDHOME)  
		end

		alarmZone.isArmedAway =
		--- Returns true if the zone is armed away 
		-- @param domoticz The Domoticz object
		-- @return Boolean
		function (domoticz)
			return(alarmZone.armingMode(domoticz) == domoticz.SECURITY_ARMEDAWAY)  
		end

		alarmZone.trippedSensors =
		--- Gets all tripped sensor devices for the zone 
		-- @param domoticz The Domoticz object
		-- @param mins Integer 0-9999 Number of minutes that the sensor must have been updated within.
		-- A 0 value will return sensor devices who are currently tripped. 
		-- @param armingMode String One of domoticz.SECURITY_ARMEDAWAY, domoticz.SECURITY_ARMEDHOME or domoticz.SECURITY_DISARMED
		-- A sensor is regarded to be tripped only in the context of an arming mode. Defaults to the zones current arming mode. 
		-- @param isArming Boolean. In an arming scenario we don't want to include sensors that are set not to warn when arming.
		-- @return Table with tripped Domoricz devices
		function(domoticz, mins, armingMode, isArming)
			mins = mins or 1
			armingMode = armingMode or alarmZone.armingMode(domoticz)
			isArming = isArming or false
			local trippedSensors = {}
			if armingMode == domoticz.SECURITY_DISARMED then return trippedSensors end
			-- Get a list of all open and active sensors for this zone
			for sensorName, sensorConfig in pairs(alarmZone.sensors) do
				local sensor = domoticz.devices(sensorName)
				if ((mins > 0 and sensor.lastUpdate.minutesAgo <= mins)
				or (mins == 0 and isActive(sensor))) then
					local includeSensor = (type(sensorConfig.enabled) == 'function') and sensorConfig.enabled(domoticz) or sensorConfig.enabled
					if includeSensor and isArming then includeSensor = sensorConfig.armWarn end
					if includeSensor then
						includeSensor = (armingMode == domoticz.SECURITY_ARMEDAWAY) 
							or (armingMode == domoticz.SECURITY_ARMEDHOME and sensorConfig.class ~= SENSOR_CLASS_B)
					end 
					if includeSensor then
						table.insert(trippedSensors, sensor)
					end
				end
			end
			return trippedSensors
		end

		alarmZone._updateZoneStatus =
		---Function to set the alarm zones status
		-- @param domoticz The Domoticz object
		-- @param newStatus Text (Optional) The new status to set.
		-- @param delay Integer (Optional) Delay in seconds.
		-- One of alarm.ZS_NORMAL, alarm.ZS_ARMING, alarm.ZS_ALERT, alarm.ERROR,
		-- alarm.ZS_TRIPPED or alarm.ZS_TIMED_OUT. Defaults to alarm.ZS_NORMAL
		-- @return Nil
		function(domoticz, newStatus, delay)
			newStatus = newStatus or ZS_NORMAL
			delay = delay or 0
			if (newStatus ~= ZS_NORMAL)
			and (newStatus ~= ZS_ARMING)
			and (newStatus ~= ZS_ALERT)
			and (newStatus ~= ZS_ERROR)
			and (newStatus ~= ZS_TRIPPED)
			and (newStatus ~= ZS_TIMED_OUT) then
				domoticz.log('An attempt has been made to set an invalid status for zone: '
								..alarmZone.name, domoticz.LOG_ERROR)
				newStatus = ZS_ERROR
				delay = 0
			end

			if alarmZone.status(domoticz) ~= newStatus then
				domoticz.devices(alarmZone.statusTextDevID).updateText(newStatus).afterSec(delay)
				domoticz.log(alarmZone.name..' new status: '..newStatus
					..(delay>0 and ' with a delay of '..delay..' seconds' or ' immediately'), domoticz.LOG_INFO)
			end
		end

		alarmZone.disArmZone =
		--- Disarms the zone unless it's already disarmed.
		-- @param domoticz The Domoticz object
		-- @return Nil
		function(domoticz)
			if alarmZone.armingMode(domoticz) ~= domoticz.SECURITY_DISARMED then
				domoticz.devices(alarmZone.armingModeTextDevID).updateText(domoticz.SECURITY_DISARMED)
			end
		end

		alarmZone.armZone =
		--- Arms a zone to the given arming mode after an optional delay.
		-- Arming a zone also resets it's status
		-- @param domoticz The Domoticz object
		-- @param z integer/string/table (Optional) The zone to look up. 
		-- @param armingMode String. The new arming mode to set.
		-- Should be one of domoticz.SECURITY_ARMEDAWAY and domoticz.SECURITY_ARMEDHOME
		-- @param delay Integer. (Optional) Number of seconds to delay the arming action. Defaults to the
		-- zone objects defined exit delay. 
		-- @return Nil
		function(domoticz, armingMode, delay)
			delay = delay or (armingMode == domoticz.SECURITY_ARMEDAWAY and alarmZone.exitDelay or 0)
			armingMode = armingMode or domoticz.SECURITY_ARMEDAWAY
			if (armingMode ~= domoticz.SECURITY_ARMEDAWAY)
			and (armingMode ~= domoticz.SECURITY_ARMEDHOME) then
				domoticz.log('An attempt has been made to set an invalid arming mode for zone: '
								..alarmZone.name, domoticz.LOG_ERROR)
				return
			end 
			if alarmZone.armingMode(domoticz) ~= armingMode then
				local isArming = true
				local trippedSensors = alarmZone.trippedSensors(domoticz, 0, armingMode, isArming)
				if (#trippedSensors > 0) then
					callIfDefined('alarmZoneArmingWithTrippedSensors')(domoticz, alarmZone, armingMode)
					if not alarmZone.canArmWithTrippedSensors then
						local msg = ''
						for _, sensor in ipairs(trippedSensors) do
							if msg ~= '' then msg = msg..' and ' end
							msg = msg..sensor.name
						end
						domoticz.log('An arming attempt has been made with tripped sensor(s) in zone: '
							..alarmZone.name..'. Tripped sensor(s): '..msg..'.', domoticz.LOG_ERROR)
						alarmZone._updateZoneStatus(domoticz, ZS_ERROR)
						return
					end
				end
				if delay > 0 then
					alarmZone._updateZoneStatus(domoticz, ZS_ARMING)
				end
				domoticz.log('Arming zone '..alarmZone.name..
					' to '..armingMode..(delay>0 and ' with a delay of '..delay..' seconds' or ' immediately'), domoticz.LOG_INFO)
				domoticz.devices(alarmZone.armingModeTextDevID).updateText(armingMode).afterSec(delay)
			end
		end

		alarmZone.toggleArmingMode =
		---Function to toggle the zones arming mode between 'Disarmed' and armType
		function(domoticz, armingMode)
			armingMode = armingMode or domoticz.SECURITY_DISARMED 
			local newArmingMode
			newArmingMode = (alarmZone.armingMode(domoticz) ~= domoticz.SECURITY_DISARMED and domoticz.SECURITY_DISARMED or armingMode)

			if newArmingMode == domoticz.SECURITY_DISARMED then
				alarmZone.disArmZone(domoticz)
			else
				alarmZone.armZone(domoticz, newArmingMode)
			end
		end

		alarmZone.sensorConfig =
		--- Looks up and returns the sensor configuration object by given sensor name.
		-- Generates an error if a sensor can not be found.
		-- @param sensorName String. The sensor to look up.
		-- @return The sensor object table
		function(sName)
			for sensorName, sensorConf in pairs(alarmZone.sensors) do
				if sensorName == sName then return sensorConf end
			end
			print('Error: Can\'t find a sensor with name: \''..sName..'\' defined in '..alarmZone.name..'.')
		end

		table.insert(zones, alarmZone)
	end
	return zones
end

--- The alarm zones table 
local alarmZones = initAlarmZones()

--- Looks up the zone object for a zone given by name or index.
-- If a zone object is given it will just return it.
-- Generates an error if a zone given by name can not be found.
-- @param z (integer/string/table (Optional) The zone to look up.
-- If not given, the ideAlarm main zone will be used.
-- @return The Zone table
function ideAlarm.zones(z)
	local function mainZoneIndex()
		for index, z in ipairs(alarmZones) do
			if z.mainZone then return index end
		end
		return(nil)
	end
	z = z or mainZoneIndex()
	if type(z) == 'number' then
		return(alarmZones[z])
	elseif type(z) == 'string' then
		for _, zone in ipairs(alarmZones) do
			if zone.name == z then return zone end
		end
		print('Error: Can\'t find an alarm zone with name: \''..z..'\' in the configuration.')
	elseif type(z) == 'table' then
		return(z)
	end
end

local function toggleSirens(domoticz, device, alertingZones)
	local allAlertDevices = {}
	for _, alarmZone in ipairs(alarmZones) do
		for _, alertDevice in ipairs(alarmZone.alertDevices) do
			allAlertDevices[alertDevice] = 'Off'
		end
	end

	for _, zoneNumber in ipairs(alertingZones) do
		local alarmZone = ideAlarm.zones(zoneNumber)
		domoticz.log('Turning on noise for zone '..alarmZone.name, domoticz.LOG_FORCE)
		for _, alertDevice in ipairs(alarmZone.alertDevices) do
			if not config.ALARM_TEST_MODE then allAlertDevices[alertDevice] = 'On' end
		end
	end

	for alertDevice, newState in pairs(allAlertDevices) do
		if (domoticz.devices(alertDevice) ~= nil)
		and domoticz.devices(alertDevice).state ~= newState then
			domoticz.devices(alertDevice).toggleSwitch().silent()
			if newState == 'On' and config.ALARM_ALERT_MAX_SECONDS > 0 then
				domoticz.devices(alertDevice).switchOff().afterSec(config.ALARM_ALERT_MAX_SECONDS).silent()
			end
		end
	end
end

local function onToggleButton(domoticz, device)
	-- Checking if the toggle buttons have been pressed
	for _, alarmZone in ipairs(alarmZones) do
		if device.active and (device.name == alarmZone.armAwayToggleBtn or device.name == alarmZone.armHomeToggleBtn) then
			local armType
			if device.name == alarmZone.armAwayToggleBtn then
				armType = domoticz.SECURITY_ARMEDAWAY
			else
				armType = domoticz.SECURITY_ARMEDHOME
			end
			domoticz.log(armType.. ' Alarm mode toggle button for zone "'..alarmZone.name..'" was pushed.', domoticz.LOG_INFO)
			alarmZone.toggleArmingMode(domoticz, armType)
		end
	end
end

local function onStatusChange(domoticz, device)
	local alertingZones = {}

	-- Loop through the Zones
	-- Check if any alarm zones status has changed

	for i, alarmZone in ipairs(alarmZones) do

		-- Deal with alarm status changes
		if device.id == alarmZone.statusTextDevID then
			domoticz.log('Deal with alarm status changes '.. 'for zone '..alarmZone.name, domoticz.LOG_DEBUG)

			if alarmZone.status(domoticz) == ZS_NORMAL then
				callIfDefined('alarmZoneNormal')(domoticz, alarmZone)
			elseif alarmZone.status(domoticz) == ZS_ARMING then
				callIfDefined('alarmZoneArming')(domoticz, alarmZone)
			elseif alarmZone.status(domoticz) == ZS_ALERT then
				callIfDefined('alarmZoneAlert')(domoticz, alarmZone, config.ALARM_TEST_MODE)
				table.insert(alertingZones, i)
			elseif alarmZone.status(domoticz) == ZS_ERROR then
				callIfDefined('alarmZoneError')(domoticz, alarmZone)
			elseif alarmZone.status(domoticz) == ZS_TRIPPED then
				callIfDefined('alarmZoneTripped')(domoticz, alarmZone)

			elseif alarmZone.status(domoticz) == ZS_TIMED_OUT then
				if alarmZone.armingMode(domoticz) ~= domoticz.SECURITY_DISARMED then
					-- A sensor was tripped, delay time has passed and the zone is still armed so ...
					alarmZone._updateZoneStatus(domoticz, ZS_ALERT)
				else
					domoticz.log('No need for any noise, the zone is obviously disarmed now.', domoticz.LOG_INFO)
					alarmZone._updateZoneStatus(domoticz, ZS_NORMAL)
				end
			end

		end
	end

	toggleSirens(domoticz, device, alertingZones)
end

local function onArmingModeChange(domoticz, device)
	-- Loop through the Zones
	-- Check if any alarm zones arming mode changed
	local zonesToSyncCheck = 0

	for _, alarmZone in ipairs(alarmZones) do
		-- Deal with arming mode changes
		-- E.g. the text device text for arming mode has changed
		if (device.id == alarmZone.armingModeTextDevID) then
			domoticz.devices(alarmZone.statusTextDevID).cancelQueuedCommands()
			domoticz.log(alarmZone.name..' cancelled queued commands if any', domoticz.LOG_INFO)
			alarmZone._updateZoneStatus(domoticz, ZS_NORMAL) -- Always set to normal when arming mode changes
			callIfDefined('alarmArmingModeChanged')(domoticz, alarmZone)

			local armingMode = alarmZone.armingMode(domoticz)
			if alarmZone.syncWithDomoSec then
				zonesToSyncCheck = zonesToSyncCheck + 1
				if zonesToSyncCheck > 1 then
					domoticz.log('Configuration file error. Only a single zone can be set up to synchronize with the Domoticz\'s security panel.', domoticz.LOG_ERROR)
					return
				end
				if armingMode ~= domoticz.security then
					domoticz.log('Syncing Domoticz\'s built in Security Panel with the zone '..alarmZone.name..'\'s arming status', domoticz.LOG_INFO)
					if armingMode == domoticz.SECURITY_DISARMED then
						domoticz.devices(SECURITY_PANEL_NAME).disarm()
					elseif armingMode == domoticz.SECURITY_ARMEDHOME then
						domoticz.devices(SECURITY_PANEL_NAME).armHome()
					elseif armingMode == domoticz.SECURITY_ARMEDAWAY then
						domoticz.devices(SECURITY_PANEL_NAME).armAway()
					end
				end
			end

		end

	end

end

local function onSensorChange(domoticz, device)
	-- A sensor was tripped.
	for i, alarmZone in ipairs(alarmZones) do
		for sensorName, sensorConfig in pairs(alarmZone.sensors) do
			if sensorName == device.name then
				local isEnabled
				if type(sensorConfig.enabled) == 'function' then
					isEnabled = sensorConfig.enabled(domoticz)
				else
					isEnabled = sensorConfig.enabled
				end
				if isEnabled
				and (alarmZone.armingMode(domoticz) == domoticz.SECURITY_ARMEDAWAY or
						(alarmZone.armingMode(domoticz) == domoticz.SECURITY_ARMEDHOME and sensorConfig.class == SENSOR_CLASS_A)) then
					domoticz.log(sensorName..' in zone '..alarmZone.name..' was tripped', domoticz.LOG_INFO)
					local alarmStatus = domoticz.devices(alarmZone.statusTextDevID).state
					if  alarmStatus ~= ZS_TRIPPED and alarmStatus ~= ZS_TIMED_OUT and alarmStatus ~= ZS_ALERT then
						if (alarmZone.entryDelay > 0) then  -- Skip ZS_TRIPPED status if 0 secs entry delay
							alarmZone._updateZoneStatus(domoticz, ZS_TRIPPED)
						end
						alarmZone._updateZoneStatus(domoticz, ZS_TIMED_OUT, alarmZone.entryDelay) 
					end
				end
				break -- Let this sensor trigger only once in this zone
			end
		end
	end
end

local function onSecurityChange(domoticz, item)
	-- Domoticz built in Security state has changed, shall we sync the new arming mode to any zone?

	local zonesToSyncCheck = 0
	for i, alarmZone in ipairs(alarmZones) do

		if alarmZone.syncWithDomoSec then
			zonesToSyncCheck = zonesToSyncCheck + 1
			if zonesToSyncCheck > 1 then
				domoticz.log('Configuration file error. Only a single zone can be set up to synchronize with the Domoticz\'s security panel.', domoticz.LOG_ERROR)
				return
			end
			local newArmingMode = item.trigger
			if alarmZone.armingMode(domoticz) ~= newArmingMode then
				domoticz.log('The Domoticz built in Security\'s arming mode changed to '..newArmingMode, domoticz.LOG_INFO)
				domoticz.log('Syncing the new arming mode to zone '..alarmZone.name, domoticz.LOG_INFO)
				if newArmingMode == domoticz.SECURITY_DISARMED then
					alarmZone.disArmZone(domoticz)
				else
					alarmZone.armZone(domoticz, newArmingMode)
				end
			end

		end

	end
end

--- Checks how many open sensors there are in each zone.
-- Inserts the openSensorCount item into each alarmZone object
-- If defined, calls the ideAlarm custom helper function alarmOpenSensorsAllZones
-- @param domoticz The Domoticz object
-- @return Nil
local function countOpenSensors(domoticz)
	for i, alarmZone in ipairs(alarmZones) do
		local openSensorCount = 0
		for sensorName, sensorConfig in pairs(alarmZone.sensors) do
			local sensor = domoticz.devices(sensorName)
			if sensor then
				local includeSensor = (type(sensorConfig.enabled) == 'function') and sensorConfig.enabled(domoticz) or sensorConfig.enabled
				if includeSensor and sensorConfig.nag and isActive(sensor) then
					openSensorCount = openSensorCount + 1
				end
			end
		end
		alarmZone.openSensorCount = openSensorCount
	end
	callIfDefined('alarmOpenSensorsAllZones')(domoticz, alarmZones)
end

--- Nags periodically about open sensors 
-- @param domoticz The Domoticz object
-- @param item
-- @return Nil
local function nagCheck(domoticz, item)
	-- You just came here to nag about open doors, didn't you?
	local nagEventData = domoticz.data.nagEvent
	local nagEventItem = nagEventData.getLatest()
	if not nagEventItem then
		nagEventData.add('dzVents rocks!1')
		nagEventItem = nagEventData.getLatest()
	end

	if item.isTimer then
		-- Triggered by a timer  event
		-- First check if we have nagged recently.
		local lastNagMinutesAgo = nagEventItem.time.minutesAgo
		if lastNagMinutesAgo < ideAlarm.nagInterval() then
			return
		end
	end

	local zonesNagSensors = {}
	local totalSensors = 0
	for _, alarmZone in ipairs(alarmZones) do
		local nagSensors = {}
		for sensorName, sensorConfig in pairs(alarmZone.sensors) do
			local sensor = domoticz.devices(sensorName)
			if sensor then
				local includeSensor = (type(sensorConfig.enabled) == 'function') and sensorConfig.enabled(domoticz) or sensorConfig.enabled
				if includeSensor then
					includeSensor = ((alarmZone.armingMode(domoticz) == domoticz.SECURITY_DISARMED) 
						or (alarmZone.armingMode(domoticz) == domoticz.SECURITY_ARMEDHOME and sensorConfig.class == SENSOR_CLASS_B))
				end
				local minutesAgo = sensor.lastUpdate.minutesAgo
				if includeSensor and sensorConfig.nag
				and isActive(sensor)
				and minutesAgo >= sensorConfig.nagTimeoutMins then
					-- This sensor is worth nagging about
					table.insert(nagSensors, sensor)
					totalSensors = totalSensors + 1
				end
			end
		end
		table.insert(zonesNagSensors, nagSensors)
	end
	
	-- Exit if triggered by device and not all sections in all zones are closed/off 
	if totalSensors > 0 and item.isDevice then return end

	local hasNagged = false
	for i, nagSensors in ipairs(zonesNagSensors) do
		local lastValue = domoticz.data['nagZ'..tostring(i)]
		if #nagSensors > 0 then hasNagged = true end
		if (#nagSensors > 0) or (#nagSensors == 0 and lastValue > 0) then 
			callIfDefined('alarmNagOpenSensors')(domoticz, alarmZones[i], nagSensors, lastValue)
		end
		domoticz.data['nagZ'..tostring(i)] = #nagSensors
	end

	if hasNagged then
		nagEventData.add('dzVents krocks!2') -- Reset
	end
end

function ideAlarm.execute(domoticz, item)

	local devTriggerSpecific

	-- What caused this script to trigger?
	if item.isDevice then
		for _, alarmZone in ipairs(alarmZones) do
			if item.deviceSubType == 'Text' then
				if item.id == alarmZone.statusTextDevID then
					devTriggerSpecific = 'status' -- Alarm Zone Status change
					break
				elseif item.id == alarmZone.armingModeTextDevID then
					devTriggerSpecific = 'armingMode' -- Alarm Zone Arming Mode change
					break
				end
			elseif item.active and (item.name == alarmZone.armAwayToggleBtn or item.name == alarmZone.armHomeToggleBtn) then
				devTriggerSpecific = 'toggleSwitch'
				break
			end
		end
		devTriggerSpecific = devTriggerSpecific or 'sensor'
	end

	if item.isDevice then
		if devTriggerSpecific == 'toggleSwitch' then
			onToggleButton(domoticz, item)
			return
		elseif devTriggerSpecific == 'status' then
			onStatusChange(domoticz, item)
			return
		elseif devTriggerSpecific == 'armingMode' then
			onArmingModeChange(domoticz, item)
			return
		elseif devTriggerSpecific == 'sensor' then
			if isActive(item) then
				onSensorChange(domoticz, item) -- Only Open or On states are of interest
			else
				nagCheck(domoticz, item) -- Only Closed or Off states are of interest
			end
			countOpenSensors(domoticz)
			return
		end
	elseif item.isSecurity then
		onSecurityChange(domoticz, item)
	elseif item.isTimer then
		nagCheck(domoticz, item)
	end

end

function ideAlarm.version()
	return('ideAlarm V'..scriptVersion)
end

--- Lists all defined alarm zones and sensors
-- @param domoticz (Table). The domoticz table object.
-- @return (String) The listing string.
function ideAlarm.statusAll(domoticz)
	local statusTxt = '\n\n'..ideAlarm.version()..'\nListing alarm zones and sensors:\n\n'
	for i, alarmZone in ipairs(alarmZones) do
		statusTxt = statusTxt..'Zone #'..tostring(i)..': '..alarmZone.name
			..((alarmZone.mainZone) and ' (Main Zone) ' or '')
			..((alarmZone.syncWithDomoSec) and ' (Sync with Domoticz\'s Security Panel) ' or '')
			..', '..alarmZone.armingMode(domoticz)
			..', '..alarmZone.status(domoticz)..'\n===========================================\n'
		-- List all sensors for this zone
		for sensorName, sensorConfig in pairs(alarmZone.sensors) do
			local sensor = domoticz.devices(sensorName) 
			local isEnabled
			if type(sensorConfig.enabled) == 'function' then
				isEnabled = sensorConfig.enabled(domoticz)
			else
				isEnabled = sensorConfig.enabled
			end
			statusTxt = statusTxt..sensor.name
				..(isEnabled and ': Enabled,' or ': Disabled,')
				..(isActive(sensor) and ' Tripped' or ' Not tripped')..'\n'
		end
		statusTxt = statusTxt..'\n'
	end
	return statusTxt
end

function ideAlarm.testAlert(domoticz)

	if config.ALARM_TEST_MODE then
		domoticz.log('Can not test alerts when ALARM_TEST_MODE is enabled in configuration file.' , domoticz.LOG_ERROR)
		return false
	end

	local allAlertDevices = {}

	for _, alarmZone in ipairs(alarmZones) do
		for _, alertDevice in ipairs(alarmZone.alertDevices) do
			allAlertDevices[alertDevice] = 'On'
		end
	end

	local tempMessage = ideAlarm.statusAll(domoticz)
	callIfDefined('alarmAlertMessage')(domoticz, tempMessage, config.ALARM_TEST_MODE)
	domoticz.log(tempMessage, domoticz.LOG_FORCE)

	for alertDevice, _ in pairs(allAlertDevices) do
		domoticz.log(alertDevice, domoticz.LOG_FORCE)
		domoticz.devices(alertDevice).switchOn().silent()
		domoticz.devices(alertDevice).switchOff().afterSec(5).silent()
	end

	return true
end

--- Get the quantity of defined ideAlarm zones
-- @return Integer
function ideAlarm.qtyAlarmZones()
	return(#alarmZones)
end

--- Get the timer triggers
-- @return table
function ideAlarm.timerTriggers()
	local nagTriggerInterval = config.NAG_SCRIPT_TRIGGER_INTERVAL or {'every minute'}
	return nagTriggerInterval
end

--- Get the logging level if defined in config file.
-- @return integer
function ideAlarm.loggingLevel(domoticz)
	return (config.loggingLevel ~= nil and config.loggingLevel(domoticz) or nil)
end

--- Get the nag interval
-- @return integer
function ideAlarm.nagInterval()
	return (config.NAG_INTERVAL_MINUTES or 6)
end

--- Get all devices that ideAlarm shall trigger upon
-- @return The trigger devices table
function ideAlarm.triggerDevices()
	local tDevs = {}
	for _, alarmZone in ipairs(alarmZones) do
		if alarmZone.armAwayToggleBtn ~= '' then table.insert(tDevs, alarmZone.armAwayToggleBtn) end
		if alarmZone.armHomeToggleBtn ~= '' then table.insert(tDevs, alarmZone.armHomeToggleBtn) end
		table.insert(tDevs, alarmZone.statusTextDevID)
		table.insert(tDevs, alarmZone.armingModeTextDevID)
		-- We don't have a domoticz object at this stage. Otherwise we could check the arming mode and insert
		-- only the trigger devices relevant to the alarm zones current arming mode
		for sensorName, _ in pairs(alarmZone.sensors) do
			table.insert(tDevs, sensorName)
		end
	end
	return(tDevs)
end

return ideAlarm
