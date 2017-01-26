/obj/machinery/power/bluespace_drive
	name = "bluespace drive"
	desc = "A very complex machine that is capable of moving a ship through bluespace. This one is commonly used on smaller shuttles and ships."

	icon = 'icons/obj/bluespace.dmi'
	icon_state = "bluedrive"
	var/jump_power_requirement = 20 MEGAWATTS 		// Energy required to perform a jump.
	var/input_cap = 5 MEGAWATTS						// Input cap per tick
	var/stored_power = 0							// Currently stored energy for this cycle.
	var/sequence_status = DRIVE_IDLE				// DRIVE_IDLE, DRIVE_CHARGING or DRIVE_JUMPING
	var/datum/shuttle/shuttle = null				// Shuttle to which this drive is linked to.

/obj/machinery/power/bluespace_drive/update_icon()¨
	overlays.Cut()
	if(sequence_status)
		overlays += image('icons/obj/bluespace.dmi', "bluedrive-on")

/obj/machinery/power/bluespace_drive/process()
	if(sequence_status == DRIVE_IDLE)
		return

	if(!shuttle)
		abort_jump()
		return

	if(sequence_status == DRIVE_CHARGING)
		// No powernet, no charging.
		if(!powernet)
			return

		// Charging rate is not capped, so it is possible to upgrade shuttle by giving the SMES there more IO, allowing for faster jumps.
		var/needed_energy = between(0, jump_power_requirement - stored_power, input_cap)
		stored_power += powernet.draw_power(needed_energy)

		if(stored_power >= jump_power_requirement)
			sequence_status = DRIVE_JUMPING

	if(sequence_status != DRIVE_JUMPING)
		return

	shuttle.drive_charged()
	stored_power = 0


/obj/machinery/power/bluespace_drive/proc/abort_jump()
	stored_power = 0
	sequence_status = DRIVE_IDLE
