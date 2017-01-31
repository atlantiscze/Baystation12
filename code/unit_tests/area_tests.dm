/datum/unit_test/areas_shall_be_coherent
	name = "AREA: Areas shall be coherent"

/datum/unit_test/areas_shall_be_coherent/start_test()
	var/incoherent_areas = 0
	for(var/area/A)
		if(!A.contents.len)
			continue
		if(A.type in using_map.area_coherency_test_exempt_areas)
			continue
		var/list/area_turfs = list()
		for(var/turf/T in A)
			area_turfs += T

		var/actual_number_of_sub_areas = 0
		var/expected_number_of_sub_areas = (A.type in using_map.area_coherency_test_subarea_count) ? using_map.area_coherency_test_subarea_count[A.type] : 1
		do
			actual_number_of_sub_areas++
			area_turfs -= get_turfs_fill(area_turfs[1])
		while(area_turfs.len)

		if(actual_number_of_sub_areas != expected_number_of_sub_areas)
			incoherent_areas++
			log_bad("[log_info_line(A)] is incoherent. Expected [expected_number_of_sub_areas] subarea\s, fill gave [actual_number_of_sub_areas].")

	if(incoherent_areas)
		fail("Found [incoherent_areas] incoherent area\s.")
	else
		pass("All areas are coherent.")

	return 1

/datum/unit_test/areas_shall_be_coherent/proc/get_turfs_fill(var/turf/origin)
	. = list()
	var/datum/stack/turfs_to_check = new()
	turfs_to_check.Push(origin)
	while(!turfs_to_check.is_empty())
		var/turf/T = turfs_to_check.Pop()
		. |= T
		for(var/direction in cardinal)
			var/turf/neighbour = get_step(T, direction)
			if(neighbour && neighbour.loc == T.loc && !(neighbour in .))
				turfs_to_check.Push(neighbour)

/datum/unit_test/areas_shall_be_pure
	name = "AREA: Areas shall be pure"

/datum/unit_test/areas_shall_be_pure/start_test()
	var/impure_areas = 0
	for(var/area/A)
		if(!A.contents.len)
			continue
		if(A.name != initial(A.name))
			log_bad("[log_info_line(A)] has an edited name.")
			impure_areas++

	if(impure_areas)
		fail("Found [impure_areas] impure area\s.")
	else
		pass("All areas are pure.")

	return 1

/datum/unit_test/areas_shall_be_used
	name = "AREA: Areas shall be used"

/datum/unit_test/areas_shall_be_used/start_test()
	var/unused_areas = 0
	for(var/area_type in subtypesof(/area))
		if(area_type in using_map.area_usage_test_exempted_areas)
			continue
		var/area/located_area = locate(area_type)
		if(located_area && !located_area.z)
			log_bad("[log_info_line(located_area)] is unused.")
			unused_areas++

	if(unused_areas)
		fail("Found [unused_areas] unused area\s.")
	else
		pass("All areas are used.")
	return 1

/datum/unit_test/areas_need_roofs
	name = "AREA: Interior areas should have ceiling"

/datum/unit_test/areas_need_roofs/start_test()
	set background = 1	// Loops through a lot of turfs, often triggering infinite loop checks.
	var/bad_turfs = 0

	for(var/turf/space/T in world)
		if(!isPlayerLevel(T.z))
			continue

		var/turf/below = GetBelow(T)
		if(!below)
			continue

		if(below.type in list(/turf/space, /turf/simulated/open))
			continue

		var/area/A = get_area(below)

		if(A.flags & AREA_EXTERNAL)
			continue

		log_bad("----- Missing ceiling tile on x[T.x] y[T.y] z[T.z].")
		bad_turfs++

	if(bad_turfs)
		fail("Found [bad_turfs] missing ceiling tile\s.")
	else
		pass("All areas have a ceiling.")

	return 1