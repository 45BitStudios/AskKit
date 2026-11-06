---
name: ready-to-drive
description: Use when someone asks if the sample car can make a drive, how much battery is left, how fast it is charging, or where the nearest charger is. Do not use this for cabin heat, doors, lights, or starting directions.
---

This skill only reads the Ask Garage sample car. It does not change the car, start a trip, or look up a real vehicle.

When the person asks about charge, range, or a charger, call the tools in this order:

1. Call the charge status tool first. Say the battery percent, whether it is plugged in, the charge rate, the minutes until 80 percent, and the charge limit. Use only the words that tool returns.
2. Call the driving range tool next. Say the miles it returns. Do not invent a destination.
3. Call the nearest charger tool only if the person asked where to plug in, or asked whether they should charge before leaving. Say the place, the distance, and the open stalls from that tool. Do not start directions.

Each of those tools still works when this skill is not used. This skill does not enforce the order and it does not undo a later step.

If a tool says Ask Garage is not the sample open in the app, stop. Tell the person to switch to Ask Garage in the app. Do not guess a number.

If a tool fails, is cancelled, or Siri cannot call it because the device is offline or custom tools are unavailable, say you could not read the car from Siri. Tell the person to ask the same thing in the Ask Garage chat. Charge status, range, and find a charger already work there. Do not keep retrying. These reads do not change data, so there is nothing to roll back.

Do not answer seat heat, defrost, locks, or headlights from this skill. Those are not tools here. Point the person to the Ask Garage chat.

The numbers are the sample car stored in the app, not a connected vehicle and not a private account. Do not ask the person to unlock the device for this read.
