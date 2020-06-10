--[[
ideAlarm.lua
Please read: https://github.com/allan-gam/ideAlarm/wiki
Do not change anything in this file.
--]]

local alarm = require "ideAlarmModule"

local triggerDevices = alarm.triggerDevices()

local data = {}
data['nagEvent'] = {history = true, maxItems = 1}
for i = 1, alarm.qtyAlarmZones() do
	data['nagZ'..tostring(i)] = {initial=0}
end

return {
	active = true,
	logging = {
		level = alarm.loggingLevel(domoticz), -- Can be set in the configuration file
		marker = alarm.version()
	},
	on = {
		devices = triggerDevices,
		security = {domoticz.SECURITY_ARMEDAWAY, domoticz.SECURITY_ARMEDHOME, domoticz.SECURITY_DISARMED},
		timer = alarm.timerTriggers()
	},
	data = data,
	execute = function(domoticz, item)
		domoticz.log('Triggered by '..(item.isDevice and ('device: '..item.name..', device state is: '..item.state)  or (item.isTimer and ('timer: '..item.trigger)  or (item.isSecurity and 'Domoticz Security' or 'unknown'))), domoticz.LOG_INFO)
		alarm.execute(domoticz, item)
	end
}
