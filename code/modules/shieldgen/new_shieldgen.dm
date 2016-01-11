#define JOULES_PER_RENWICK 100000			// Amount of Joules needed to get one Renwick (HP) of shield integrity
#define POWER_USAGE_MULTIPLIER 1			// Multiplies power usage
#define UPKEEP_PER_RENWICK 10				// Upkeep in Watts for each Renwick this shield has.

/obj/machinery/power/shield_generator
	name = "advanced shield generator"
	desc = "A heavy-duty shield generator and capacitor, capable of generating energy shield at large distance."
	icon = 'icons/obj/machines/shielding.dmi'
	icon_state = "generator0"
	density = 1

	var/enabled = 0
	var/hull_mode = 0 						// 0: Square field. 1: Hull shield (space turfs only), avoids doors, 2: Full hull shield
	var/obj/item/weapon/cell/internal_capacitor = null
	var/list/segments
	var/list/damaged_segments
	var/list/shielded_turfs
	var/_internal_cell_capacity = 500000	// used in New(), capacity of internal cell. Not in joules, in cell charge (CELLRATE)
	var/input_setting = 100000 				// Input setting, in watts. Defaults to 100kW
	var/max_input_setting = 4000000			// 4 MW, max input setting
	var/field_collapsed = 1					// If the field was too damaged it shuts down until it reaches 50% integrity
	var/field_radius = 1					// Field radius
	var/radiuslimit = 255					// This covers whole Z level anyway.
	var/field_capacity						// Maximal renwick capacity of this field.
	var/field_integrity						// Current integrity in renwicks. Basically HP of the shield.
	var/power_setting = 1					// Target shield integrity per segment
	var/max_power_setting = 10				// Maximal target strength of field per segment
	var/power_status = 0					// 0: Internal Only, 1: Partial external, 2: Full external  -- used to display power status in nanoUI
	var/regeneration_renwicks = 1			// How many renwicks to regenerate per tick?
	var/max_regeneration = 50				// Maximal settable value of regeneration_renwicks
	var/update_timer = 0					// Icon update timer, to prevent calling update_icon() every tick
	var/usage_upkeep = 0					// For UI rendering, amount of energy used to keep the field online
	var/usage_regen = 0						// And amount of energy used to regenerate damaged field.

/obj/machinery/power/shield_generator/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open = 1)
	if(stat & (BROKEN))
		user << "\The [src] is broken."
		return

	var/data[0]
	data["enabled"] = enabled
	data["hull"] = hull_mode
	data["failed"] = field_collapsed
	if(enabled)
		data["capacity"] = field_capacity
		data["integrity"] = field_integrity

	data["power_setting"] = power_setting
	data["max_power_setting"] = max_power_setting

	data["cur_regen"] = regeneration_renwicks
	data["max_regen"] = max_regeneration

	data["power_status"] = power_status
	data["max_input"] = max_input_setting
	data["cur_input"] = input_setting
	data["radius"] = field_radius

	data["internal_percent"] = round(internal_capacitor.percent())

	ui = nanomanager.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)
		ui = new(user, src, ui_key, "shieldgen.tmpl", src.name, 500, 400)
		ui.set_initial_data(data)
		ui.open()
		ui.set_auto_update(1)

/obj/machinery/power/shield_generator/attack_hand()
	ui_interact(usr)

/obj/machinery/power/shield_generator/Topic(href, href_list)
	if(..())
		return 1
	if(href_list["modinput"])
		input_setting += text2num(href_list["modinput"])
		input_setting = between(0, input_setting, max_input_setting)
	if(href_list["modrate"])
		regeneration_renwicks += text2num(href_list["modrate"])
		regeneration_renwicks = between(0, regeneration_renwicks, max_regeneration)
	if(href_list["modpower"])
		power_setting += text2num(href_list["modpower"])
		power_setting = between(1, power_setting, max_power_setting)
	if(href_list["modradius"])
		if(enabled)
			return
		field_radius += text2num(href_list["modradius"])
		field_radius = between(1, field_radius, radiuslimit)
	if(href_list["toggle"])
		enabled = !enabled
		if(!enabled)
			collapse_field()
			shielded_turfs = null
			field_integrity = 0
			field_capacity = 0
			field_collapsed = 1
		else
			shielded_turfs = get_turfs()
		update_icon()
	if(href_list["mode"])
		if(enabled)
			return
		hull_mode = !hull_mode

/obj/machinery/power/shield_generator/proc/take_damage(var/damage)
	field_integrity -= min(field_integrity, damage)
	if(damage > 100)
		visible_message("<span class='notice'>\The [src] shudders a bit, as if it was momentarily under heavy stress.</span>")
	update_icon()
	return check_integrity()

/obj/machinery/power/shield_generator/update_icon()
	if(enabled)
		icon_state = "generator1"
	else
		icon_state = "generator0"
	overlays.Cut()
	switch(internal_capacitor.percent())
		if(-1 to 5)
			overlays.Add("pwr_0")
		if(6 to 20)
			overlays.Add("pwr_1")
		if(21 to 40)
			overlays.Add("pwr_2")
		if(41 to 60)
			overlays.Add("pwr_3")
		if(61 to 80)
			overlays.Add("pwr_4")
		if(81 to INFINITY)
			overlays.Add("pwr_5")

	if(!enabled)
		return

	switch(get_field_integrity())
		if(-1 to 5)
			overlays.Add("int_0")
			if(!field_collapsed)
				overlays.Add("overload")
		if(6 to 20)
			overlays.Add("int_1")
			if(!field_collapsed)
				overlays.Add("overload")
		if(21 to 40)
			overlays.Add("int_2")
		if(41 to 60)
			overlays.Add("int_3")
		if(61 to 80)
			overlays.Add("int_4")
		if(81 to INFINITY)
			overlays.Add("int_5")

/obj/machinery/power/shield_generator/Destroy()
	collapse_field()
	..()

/obj/machinery/power/shield_generator/New()
	..()
	internal_capacitor = new()
	internal_capacitor.maxcharge = _internal_cell_capacity
	shielded_turfs = list()
	segments = list()
	damaged_segments = list()
	if(anchored)
		connect_to_network()

/obj/machinery/power/shield_generator/process()
	if(!anchored)
		return
	if(!powernet)
		connect_to_network()
	field_capacity = shielded_turfs.len * power_setting
	field_integrity = between(0, field_integrity, field_capacity)
	// Power needed to sustain the field and charge it
	var/power_demand = get_passive_power_usage() + charge_shield()
	// Power needed to FULLY charge our internal cell
	var/power_charging = (internal_capacitor.maxcharge - internal_capacitor.charge) / CELLRATE
	// Actual amount of power we received from the network, capped by our input setting.
	var/power_input = draw_power(min(power_demand + power_charging, input_setting))

	// No power input, run fully from internal cell.
	if(!power_input)
		power_status = 0
		internal_capacitor.use(power_demand * CELLRATE)
	// Partial power, but insufficient to run the generator.
	else if(power_input < power_demand)
		power_status = 1
		internal_capacitor.use((power_demand - power_input)*CELLRATE)
	// Full external power, give the excess input to our internal cell.
	else
		power_status = 2
		internal_capacitor.give((power_input - power_demand)*CELLRATE)

	update_timer++
	if(update_timer >= 10)
		update_icon()
		update_timer = 0

	if(!enabled)
		return

	if(field_collapsed && (get_field_integrity() > 50))
		visible_message("\The [src] hums as it slowly turns on.")
		field_collapsed = 0
		generate_field()

	check_integrity()

	for(var/obj/effect/energy_shield/E in damaged_segments)
		E.regenerate()

// Checks field's integrity, returns 0 on field collapse due to overload, and 1 when the field is OK
/obj/machinery/power/shield_generator/proc/check_integrity()
	if(get_field_integrity() <= 0)
		visible_message("\The [src] emits multiple electrical noises as it shuts down.")
		field_collapsed = 1
		collapse_field()
		return 0
	return 1

/obj/machinery/power/shield_generator/proc/charge_shield()
	if(!enabled)
		usage_regen = 0
	if(get_field_integrity() >= 100)
		usage_regen = 0
	if(
	var/needed_renwicks = min(regeneration_renwicks, round(field_capacity - field_integrity))
	field_integrity += needed_renwicks
	usage_regen = needed_renwicks * JOULES_PER_RENWICK
	return usage_regen

// Returns percentage based strength of this shield.
/obj/machinery/power/shield_generator/proc/get_field_integrity()
	if(field_integrity && field_capacity)
		return (field_integrity/field_capacity)*100
	else
		return 0

/obj/machinery/power/shield_generator/proc/get_passive_power_usage()
	if(!enabled)
		return 0

	// Passive power usage always assumes each shield segment has integrity of at least 1 renwick.
	return round(max(UPKEEP_PER_RENWICK * segments.len, UPKEEP_PER_RENWICK * round(field_integrity)))

// Mostly recycled code from old shields, with an extra benefit of not blocking doors
/obj/machinery/power/shield_generator/proc/get_turfs()
	var/list/out = list()
	var/turf/gen_turf = get_turf(src)
	if (!gen_turf)
		return
	var/turf/T

	if(hull_mode)	// Shield only exterior turfs
		for (var/x_offset = -field_radius; x_offset <= field_radius; x_offset++)
			for (var/y_offset = -field_radius; y_offset <= field_radius; y_offset++)
				T = locate(gen_turf.x + x_offset, gen_turf.y + y_offset, gen_turf.z)
				if (istype(T, /turf/space))
					//check neighbors of T
					// Blast door or airlock - let's don't generate shield around those, as they usually need clear way outside.
					if ((hull_mode == 1) && (locate(/obj/machinery/door/blast) in orange(1, T)) || (locate(/obj/machinery/door/airlock) in orange(1, T)))
						continue
					if (locate(/turf/simulated/) in orange(1, T))
						out += T
	else			// Square shield
		if (!gen_turf)
			return

		for (var/x_offset = -field_radius; x_offset <= field_radius; x_offset++)
			T = locate(gen_turf.x + x_offset, gen_turf.y - field_radius, gen_turf.z)
			if (T) out += T
			T = locate(gen_turf.x + x_offset, gen_turf.y + field_radius, gen_turf.z)
			if (T) out += T

		for (var/y_offset = -field_radius+1; y_offset < field_radius; y_offset++)
			T = locate(gen_turf.x - field_radius, gen_turf.y + y_offset, gen_turf.z)
			if (T) out += T
			T = locate(gen_turf.x + field_radius, gen_turf.y + y_offset, gen_turf.z)
			if (T) out += T
	return out

// Generates the shield and creates the field's objects.
/obj/machinery/power/shield_generator/proc/generate_field()
	for(var/turf/T in shielded_turfs)
		var/obj/effect/energy_shield/E = new(T)
		E.gen = src
		segments.Add(E)

/obj/machinery/power/shield_generator/proc/collapse_field()
	for(var/obj/effect/energy_shield/E in segments)
		qdel(E)
