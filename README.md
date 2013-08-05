uptimeChecker
=============

Stores the battery information in a database every time it is called. Prints out information about battery life on demant.

It looks in /sys/class/power_supply/BAT0 and reads the battery data and 
* POWER_SUPPLY_CHARGE_FULL
* POWER_SUPPLY_CHARGE_STATUS
* POWER_SUPPLY_CHARGE=NOW
* POWER_SUPPLY_ENERGY_NOW

stores these data in a sqlite database.
