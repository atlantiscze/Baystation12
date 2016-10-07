/obj/machinery/power/shield_generator
	name = "advanced shield generator"
	desc = "A heavy-duty shield generator and capacitor, capable of generating energy shield at large distance."
	icon = 'icons/obj/machines/shielding.dmi'
	icon_state = "generator0"
	density = 1
	var/list/field_segments = list()	// List of all shield segments owned by this generator.
	var/list/damaged_segments = list()	// List of shield segments that have failed and are currently regenerating.
	var/shield_modes = 0				// Enabled shield mode flags
	var/mitigation_em = 0				// Current EM mitigation
	var/mitigation_physical = 0			// Current Physical mitigation
	var/mitigation_burn = 0				// Current Burn mitigation
	var/mitigation_max = 0				// Maximal mitigation reachable with this generator. Set by RefreshParts()
	var/max_energy = 0					// Maximal stored energy. In joules. Depends on the type of used SMES coil when constructing this generator.
	var/current_energy = 0				// Current stored energy.
	var/field_radius = 1				// Current field radius.
	var/running = SHIELD_OFF			// Whether the generator is enabled or not.
	var/input_cap = 1 MEGAWATT			// Currently set input limit. Set to 0 to disable limits altogether. The shield will try to input this value per tick at most
	var/upkeep_power_usage = 0			// Upkeep power usage last tick.
	var/power_usage = 0					// Total power usage last tick.
	var/overloaded = 0					// Whether the field has overloaded and shut down to regenerate.

/obj/machinery/power/shield_generator/New()
	..()

	component_parts = list()
	component_parts += new /obj/item/weapon/circuitboard/shield_generator(src)
	component_parts += new /obj/item/weapon/stock_parts/capacitor(src)			// Capacitor. Improves shield mitigation when better part is used.
	component_parts += new /obj/item/weapon/stock_parts/micro_laser(src)
	component_parts += new /obj/item/weapon/smes_coil(src)						// SMES coil. Improves maximal shield energy capacity.
	component_parts += new /obj/item/weapon/stock_parts/console_screen(src)
	RefreshParts()


/obj/machinery/power/shield_generator/Destroy()
	shutdown()
	field_segments = null
	damaged_segments = null
	..()


/obj/machinery/power/shield_generator/RefreshParts()
	max_energy = 0
	for(var/obj/item/weapon/smes_coil/S in component_parts)
		max_energy += (S.ChargeCapacity / CELLRATE)
	stored_energy = between(0, stored_energy, max_energy)

	mitigation_max = MAX_MITIGATION_BASE
	for(var/obj/item/weapon/stock_parts/capacitor/C in component_parts)
		mitigation_max += MAX_MITIGATION_RESEARCH * C.rating
	mitigation_em = between(0, mitigation_em, mitigation_max)
	mitigation_physical = between(0, mitigation_physical, mitigation_max)
	mitigation_burn = between(0, mitigation_burn, mitigation_max)


// Shuts down the shield, removing all shield segments and unlocking generator settings.
/obj/machinery/power/shield_generator/proc/shutdown()
	for(var/obj/effect/shield/S in field_segments)
		qdel(S)

	running = 0
	current_energy = 0
	mitigation_em = 0
	mitigation_physical = 0
	mitigation_burn = 0


/obj/machinery/power/shield_generator/process()
	// We're turned off.
	if(!running)
		return

	upkeep_power_usage = (field_segments.len - damaged_segments.len) * ENERGY_UPKEEP_PER_TILE

	if(powernet && (running == SHIELD_RUNNING))
		var/energy_buffer = 0
		energy_buffer = draw_power(upkeep_power_usage)
		power_usage += round(energy_buffer)

		if(energy_buffer_power < upkeep_power_usage)
			current_energy -= round(upkeep_power_usage - energy_buffer)	// If we don't have enough energy from the grid, take it from the internal battery instead.

		// Now try to recharge our internal energy.
		var/energy_to_demand
		if(input_cap)
			energy_to_demand = between(0, max_energy - current_energy, input_cap)
		else
			energy_to_demand = max(0, max_energy - current_energy)
		energy_buffer = draw_power(energy_to_demand)
		current_energy += round(energy_buffer)
	else
		current_energy -= round(upkeep_power_usage)	// We are shutting down, or we lack external power connection. Use energy from internal source instead.

	if(current_energy < 0)
		current_energy = 0
		overloaded = 1
		for(var/obj/effect/shield/S in field_segments)
			S.fail(1)

	if(!overloaded)
		for(var/obj/effect/shield/S in damaged_segments)
			S.regenerate()
	else if (field_integrity() > 25)
		overloaded = 0



/obj/machinery/power/shield_generator/proc/field_integrity()
	if(current_energy)
		return current_energy / max_energy
	return 0

// Takes specific amount of damage
/obj/machinery/power/shield_generator/proc/take_damage(var/damage, var/shield_damtype)
	var/energy_to_use = damage * ENERGY_PER_HP
	mitigation_em -= MITIGATION_HIT_LOSS
	mitigation_burn -= MITIGATION_HIT_LOSS
	mitigation_physical -= MITIGATION_HIT_LOSS

	switch(shield_damtype)
		if(SHIELD_DAMTYPE_PHYSICAL)
			mitigation_physical += MITIGATION_HIT_LOSS + MITIGATION_HIT_GAIN
			energy_to_use *= 1 - (mitigation_physical / 100)
		if(SHIELD_DAMTYPE_EM)
			mitigation_em += MITIGATION_HIT_LOSS + MITIGATION_HIT_GAIN
			energy_to_use *= 1 - (mitigation_em / 100)
		if(SHIELD_DAMTYPE_HEAT)
			mitigation_heat += MITIGATION_HIT_LOSS + MITIGATION_HIT_GAIN
			energy_to_use *= 1 - (mitigation_heat / 100)

	current_energy -= energy_to_use

	// Overload the shield, which will shut it down until we recharge above 25% again
	if(current_energy < 0)
		current_energy = 0
		overloaded = 1
		return SHIELD_BREACHED_FAILURE

	if(prob(10 - field_integrity()))
		return SHIELD_BREACHED_CRITICAL
	if(prob(20 - field_integrity()))
		return SHIELD_BREACHED_MAJOR
	if(prob(35 - field_integrity()))
		return SHIELD_BREACHED_MINOR
	return SHIELD_ABSORBED


// Checks whether specific flags are enabled
/obj/machinery/power/shield_generator/proc/check_flag(var/flag)
	return (shield_modes & flag)

/obj/machinery/power/shield_generator/proc/toggle_flag(var/flag)
	shield_modes ^= flag

// Gets NanoUI format of existing flags, with user-friendly descriptions and names, as well as current status.
/obj/machinery/power/shield_generator/proc/get_flag_descriptions()
	var/list/all_flags = list()
	all_flags.Add(list(list(
		"name" = "Hyperkinetic Projectiles",
		"desc" = "This mode blocks various fast moving physical objects, such as bullets, blunt weapons, meteors and other.",
		"flag" = MODEFLAG_HYPERKINETIC,
		"status" = check_flag(MODEFLAG_HYPERKINETIC),
		"hacked" = 0,
		"multiplier" = MODEUSAGE_HYPERKINETIC
		)))
	all_flags.Add(list(list(
		"name" = "Photonic Dispersion",
		"desc" = "This mode blocks majority of light. This includes beam weaponry and most of the visible light spectrum.",
		"flag" = MODEFLAG_PHOTONIC,
		"status" = check_flag(MODEFLAG_PHOTONIC),
		"hacked" = 0
		"multiplier" = MODEUSAGE_PHOTONIC
		)))
	all_flags.Add(list(list(
		"name" = "Unknown Lifeforms",
		"desc" = "This mode blocks various non-human and non-silicon lifeforms. Typical uses include blocking carps.",
		"flag" = MODEFLAG_NONHUMANS,
		"status" = check_flag(MODEFLAG_NONHUMANS),
		"hacked" = 0
		"multiplier" = MODEUSAGE_NONHUMANS
		)))
	all_flags.Add(list(list(
		"name" = "Humanoid Lifeforms",
		"desc" = "This mode blocks various humanoid lifeforms. Does not affect fully synthetic humanoids.",
		"flag" = MODEFLAG_HUMANOIDS,
		"status" = check_flag(MODEFLAG_HUMANOIDS),
		"hacked" = 0
		"multiplier" = MODEUSAGE_HUMANOIDS
		)))
	all_flags.Add(list(list(
		"name" = "Silicon Lifeforms",
		"desc" = "This mode blocks various silicon based lifeforms.",
		"flag" = MODEFLAG_ANORGANIC,
		"status" = check_flag(MODEFLAG_ANORGANIC),
		"hacked" = 0
		"multiplier" = MODEUSAGE_ANORGANIC
		)))
	all_flags.Add(list(list(
		"name" = "Atmospheric Containment",
		"desc" = "This mode blocks air flow and acts as atmosphere containment.",
		"flag" = MODEFLAG_ATMOSPHERIC,
		"status" = check_flag(MODEFLAG_ATMOSPHERIC),
		"hacked" = 0
		"multiplier" = MODEUSAGE_ATMOSPHERIC
		)))
	all_flags.Add(list(list(
		"name" = "Hull Shielding",
		"desc" = "This mode recalibrates the field to cover surface of the installation instead of projecting a bubble shaped field.",
		"flag" = MODEFLAG_HULL,
		"status" = check_flag(MODEFLAG_HULL),
		"hacked" = 0
		"multiplier" = MODEUSAGE_HULL
		)))
	all_flags.Add(list(list(
		"name" = "Diffuser Bypass",
		"desc" = "This mode disables the built-in safeties which allows the generator to counter effect of various shield diffusers. This tends to create a very large strain on the generator.",
		"flag" = MODEFLAG_BYPASS,
		"status" = check_flag(MODEFLAG_BYPASS),
		"hacked" = 1
		"multiplier" = MODEUSAGE_BYPASS
		)))
	all_flags.Add(list(list(
		"name" = "Field Overcharge",
		"desc" = "This mode polarises the field, causing damage on contact.",
		"flag" = MODEFLAG_OVERCHARGE,
		"status" = check_flag(MODEFLAG_OVERCHARGE),
		"hacked" = 1
		"multiplier" = MODEUSAGE_OVERCHARGE
		)))

// These two procs determine tiles that should be shielded given the field range.
/obj/machinery/power/shield_generator/proc/fieldtype_square()
	var/list/out = list()
	var/turf/gen_turf = get_turf(src)
	var/turf/T
	if (!gen_turf)
		return

	for (var/x_offset = -field_radius; x_offset <= field_radius; x_offset++)
		T = locate(gen_turf.x + x_offset, gen_turf.y - field_radius, gen_turf.z)
		if(T)
			out += T
		T = locate(gen_turf.x + x_offset, gen_turf.y + field_radius, gen_turf.z)
		if(T)
			out += T

	for (var/y_offset = -field_radius+1; y_offset < field_radius; y_offset++)
		T = locate(gen_turf.x - field_radius, gen_turf.y + y_offset, gen_turf.z)
		if(T)
			out += T
		T = locate(gen_turf.x + field_radius, gen_turf.y + y_offset, gen_turf.z)
		if(T)
			out += T
	return out

/obj/machinery/power/shield_generator/proc/fieldtype_hull()
	var/list/out = list()
	var/turf/gen_turf = get_turf(src)
	var/turf/T
	if (!gen_turf)
		return

	for (var/x_offset = -field_radius; x_offset <= field_radius; x_offset++)
		for (var/y_offset = -field_radius; y_offset <= field_radius; y_offset++)
			T = locate(gen_turf.x + x_offset, gen_turf.y + y_offset, gen_turf.z)
			if (istype(T, /turf/space) && (locate(/turf/simulated/) in orange(1, T)))
				out += T