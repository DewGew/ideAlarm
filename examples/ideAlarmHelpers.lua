--[[
Edit this file suit your needs 
Place this file in the dzVents scripts folder using the name ideAlarmConfig.lua
See https://github.com/allan-gam/ideAlarm/wiki/configuration
After editing, always verify that it's valid LUA at http://codepad.org/ (Mark your paste as "Private"!!!)
--]]

local _C = {}

-- ideAlarm Custom helper functions. These functions will be called if they exist.
_C.helpers = {

	alarmZoneNormal = function(domoticz, alarmZone)
		-- Normal is good isn't it? We don't have to do anything here.. We could but..
	end,

	alarmZoneArming = function(domoticz, alarmZone)
		-- You can define something to happen here.
		-- This function will be called when arming and waiting for the exit delay.
		-- If the exit delay is 0 seconds, this function will not be called.
	end,

	alarmZoneTripped = function(domoticz, alarmZone)
		-- A sensor has been tripped but there is still no alert
		-- We should inform whoever tripped the sensor so he/she can disarm the alarm
		-- before a timeout occurs and we get an alert
		-- In this example we turn on the kitchen lights if the zones name
		-- is 'My Home' but we could also let Domoticz speak a message or something.

		--local trippedSensors = alarmZone.trippedSensors(domoticz, 1) -- Can be used if we need to. 

		if alarmZone.name == 'My Home' then
			-- Let's do something here
			domoticz.devices('Kitchen Lights').switchOn()
		end
	end,

	alarmZoneError = function(domoticz, alarmZone)
		-- An error occurred for an alarm zone. Maybe a door was open when we tried to
		-- arm the zone. Anyway we should do something about it.
		domoticz.notify('Alarm Zone Error!',
			'There was an error for the alarm zone ' .. alarmZone.name,
			domoticz.PRIORITY_HIGH)
	end,

	alarmZoneArmingWithTrippedSensors = function(domoticz, alarmZone, armingMode)
		-- Tripped sensors have been detected when arming. If canArmWithTrippedSensors has been set
		-- to true in the configuration file for the zone, arming will proceed,
		-- if not, then the alarmZoneError function will be called subsequently and arming will not occur.
		local msg = ''
		local isArming = true
		local trippedSensors = alarmZone.trippedSensors(domoticz, 0, armingMode, isArming)
		for _, sensor in ipairs(trippedSensors) do
			if msg ~= '' then msg = msg..' and ' end
			msg = msg..sensor.name
		end
		if msg ~= '' then
			msg = 'Open sections in '..alarmZone.name..'. '..msg
			domoticz.notify('Open sections when arming',
				msg .. alarmZone.name,
				domoticz.PRIORITY_HIGH)
		end
	end,

	alarmZoneAlert = function(domoticz, alarmZone, testMode)
		local msg = 'Intrusion detected in zone '..alarmZone.name..'. '
		local oneMinute = 1
		for _, sensor in ipairs(alarmZone.trippedSensors(domoticz, oneMinute)) do
			msg = msg..sensor.name..' tripped @ '..sensor.lastUpdate.raw..'. '
		end

		if not testMode then
			domoticz.notify('Alarm Zone Alert!',
				msg, domoticz.PRIORITY_HIGH)
		else
			domoticz.log('(TESTMODE IS ACTIVE) '..msg, domoticz.LOG_INFO)
		end
	end,

	alarmArmingModeChanged = function(domoticz, alarmZone)
		-- The arming mode for a zone has changed. We might want to be informed about that.
		local zoneName = alarmZone.name
		local armingMode = alarmZone.armingMode(domoticz)
		domoticz.notify('Arming mode change',
			'The new arming mode for ' .. zoneName .. ' is ' .. armingMode,
			domoticz.PRIORITY_LOW)
		-- Buy a Fibaro Wall Plug 2 and configure it to display red when off, green when on
		-- You can then use it as in alarm arming mode indicator!
		if armingMode == domoticz.SECURITY_DISARMED then 
			domoticz.devices('Alarm Status Indicator').switchOff() -- Green light on
		else
			domoticz.devices('Alarm Status Indicator').switchOn() -- Red light on
		end
	end,

	alarmNagOpenSensors = function(domoticz, alarmZone, nagSensors, lastValue)
		if alarmZone.name == 'My home' then
			if #nagSensors == 0 and lastValue > 0 then
				domoticz.log('The previously reported sections are now closed! Good work!', domoticz.LOG_INFO)
			elseif #nagSensors > 0 then
				local msg = ''
				for _, sensor in ipairs(nagSensors) do
					if msg ~= '' then msg = msg..' and ' end
					msg = msg..sensor.name
				end
				msg = 'Open sections in zone: '..alarmZone.name..'. '..msg
				domoticz.log(msg, domoticz.LOG_INFO)
			end
		end
	end,

	alarmOpenSensorsAllZones = function(domoticz, alarmZones)
		-- Toggle the big red lamp if there are any open sensors in 'My House'
		for _, alarmZone in ipairs(alarmZones) do
			if alarmZone.name == 'My House' then
				if (alarmZone.openSensorCount > 0) then
					domoticz.devices('Big Red Lamp').switchOn()
				elseif (alarmZone.openSensorCount == 0) then
					domoticz.devices('Big Red Lamp').switchOff()
				end
			end
		end
	end,

}

return _C
