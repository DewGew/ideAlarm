--[[
Edit this file suit your needs 
-- Place this file in the dzVents scripts folder using the name ideAlarmConfig.lua
-- See https://github.com/allan-gam/ideAlarm/wiki/configuration
-- After editing, always verify that it's valid LUA at http://codepad.org/ (Mark your paste as "Private"!!!)
--]]

local _C = {}

local SENSOR_CLASS_A = 'a' -- Sensor can be triggered in both arming modes. E.g. "Armed Home" and "Armed Away".
local SENSOR_CLASS_B = 'b' -- Sensor can be triggered in arming mode "Armed Away" only.

--[[
-------------------------------------------------------------------------------
DO NOT ALTER ANYTHING ABOVE THIS LINE
-------------------------------------------------------------------------------
--]]

_C.ALARM_TEST_MODE = false -- if ALARM_TEST_MODE is set to true it will prevent audible alarm

-- Interval for how often we shall trigger the script to check if nagging about open doors needs to be made 
_C.NAG_SCRIPT_TRIGGER_INTERVAL = {'every other minute'} -- Format as defined by dzVents timers
-- Interval for how often we shall repeat nagging.
_C.NAG_INTERVAL_MINUTES = 6 

-- Number of seconds which after the alert devices will be turned off
-- automatically even if an active alert situation still exists.
-- 0 = Disable automatic turning off alert devices.   
_C.ALARM_ALERT_MAX_SECONDS = 15

--	Uncomment 3 lines below to override the default logging level
--	_C.loggingLevel = function(domoticz)
--		return domoticz.LOG_INFO -- Select one of LOG_DEBUG, LOG_INFO, LOG_ERROR, LOG_FORCE to override system log level
--	end

--	If You named your Domoticz Security Panel different from "Security Panel", uncomment the line below to specify the name.
-- _C.SECURITY_PANEL_NAME = 'Security Panel Fancy Name'

_C.ALARM_ZONES = {
	-- Start configuration of the first alarm zone
	{
		name='My Home',
		armingModeTextDevID=550,
		statusTextDevID=554,
		entryDelay=15,
		exitDelay=20,
		alertDevices={'Siren', 'Garden Lights'},
		sensors = {
			['Entrance Door'] = {['class'] = SENSOR_CLASS_A, ['nag'] = true, ['nagTimeoutMins'] = 5, ['armWarn'] = true, ['enabled'] = true},
			['Another Door'] = {['class'] = SENSOR_CLASS_A, ['nag'] = true, ['nagTimeoutMins'] = 5, ['armWarn'] = true, ['enabled'] = true},

			-- enabled can be a boolean or a function as in the example below
			-- The sensor below will only trigger the alarm if
			-- "Master" is not at home and it's dark
			['Garden Shed Door'] = {['class'] = SENSOR_CLASS_A, ['nag'] = true, ['nagTimeoutMins'] = 5, ['armWarn'] = true, ['enabled'] =
				function(domoticz)
					return (domoticz.devices('Master Present').state ~= 'On'
						and domoticz.time.isNightTime)	
				end},

		},
		armAwayToggleBtn='Toggle Z1 Arm Away',
		armHomeToggleBtn='Toggle Z1 Arm Home',
		mainZone = true,
		canArmWithTrippedSensors = true,
		syncWithDomoSec = true, -- Only a single zone is allowed to sync with Domoticz's built in Security Panel
	},
	-- End configuration of the first alarm zone

	-- Start configuration of the second alarm zone
	{
		name = 'Pembridge Square Residence',
		armingModeTextDevID = 551,
		statusTextDevID = 555,
		entryDelay = 15,
		exitDelay = 15,
		alertDevices={'Notting Hill Alert Horn', 'Big Ben Chimes'},
		sensors = {
			['Big Gate'] = {['class'] = SENSOR_CLASS_A, ['nag'] = true, ['nagTimeoutMins'] = 5, ['armWarn'] = true, ['enabled'] = true},
			['Patio Door'] = {['class'] = SENSOR_CLASS_B, ['nag'] = true, ['nagTimeoutSecs'] = 5, ['armWarn'] = true, ['enabled'] = true},
		},
		armAwayToggleBtn = 'Toggle Z2 Arm Away',
		armHomeToggleBtn = 'Toggle Z2 Arm Home',
		mainZone = false,
		canArmWithTrippedSensors = true,
		syncWithDomoSec = false, -- Only a single zone is allowed to sync with Domoticz's built in Security Panel
	},
	-- End configuration of the second alarm zone
}

return _C
