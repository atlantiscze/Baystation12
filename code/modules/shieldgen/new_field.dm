/obj/effect/energy_shield
	name = "energy shield"
	desc = "Impenetrable field of energy, capable of blocking anything as long as it's active."
	icon = 'icons/obj/machines/shielding.dmi'
	icon_state = "shieldsparkles"
	anchored = 1
	layer = 4.1		//just above mobs
	density = 1
	invisibility = 0
	var/obj/machinery/power/shield_generator/gen = null
	var/overload_collapse = 0
	var/datum/effect/effect/system/spark_spread/s

// Prevents shuttles, singularities and similar things from moving the field segments away.
/obj/effect/energy_shield/Move()
	return 0

/obj/effect/energy_shield/New()
	..()
	update_nearby_tiles()
	s = new /datum/effect/effect/system/spark_spread

/obj/effect/energy_shield/Destroy()
	if(gen && (src in gen.segments))
		gen.segments.Remove(src)
	if(gen && (src in gen.damaged_segments))
		gen.damaged_segments.Remove(src)
	gen = null
	update_nearby_tiles()
	..()

/obj/effect/energy_shield/ex_act(var/severity)
	take_damage(severity * rand(8,12))

/obj/effect/energy_shield/bullet_act(var/obj/item/projectile/Proj)
	take_damage(Proj.get_structure_damage())

/obj/effect/energy_shield/emp_act(var/severity)
	take_damage(severity * rand(24,36), 1)

/obj/effect/energy_shield/attackby(var/obj/item/weapon/I as obj, var/mob/user as mob)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(I.damtype == BRUTE || I.damtype == BURN)
		user.do_attack_animation(src)
		user.visible_message("<span class='danger'>\The [user] hits \the [src] with \the [I]!</span>")
		take_damage(I.force)


// Takes damage to the shield. Strong results in larger chance for the shield to fail temporarily.
/obj/effect/energy_shield/proc/take_damage(var/damage, var/strong)
	// No generator? Fail immediately.
	if(!gen || !gen.enabled)
		qdel(src)
		return

	// This returns false when generator took too much damage and collapsed. That automatically brings down ALL shields, no need to continue.
	if(!gen.take_damage(damage))
		return

	playsound(src.loc, 'sound/effects/EMPulse.ogg', 25, 1)
	flick("shieldsparkles_hit", src)

	switch(gen.get_field_integrity())
		// Above 75% total integrity, the shield is stable.
		if(75 to INFINITY)
			return
		// Above 50% total integrity, part of the shield may go down temporarily.
		if(50 to 74)
			if(strong && prob(10))
				fail_adjacent(rand(2,4))
			return
		// Above 25% total integrity, it is quite likely that the shield will go down temporarily.
		if(25 to 49)
			if(strong)
				if(prob(25))
					fail_adjacent(rand(3,6))
			else if(prob(10))
				fail_adjacent(rand(2,4))
			return
		// Above 5% total integrity, strong hits always cause failure, other hits are probable
		if(5 to 24)
			if(strong)
				fail_adjacent(rand(4,8))
			else if(prob(25))
				fail_adjacent(rand(3,6))
			return
		// Below 5% total integrity, each hit causes a partial failure.
		else
			fail_adjacent(rand(6, 12))

/obj/effect/energy_shield/proc/fail_adjacent(var/distance)
	visible_message("<span class='danger'>\The [src] flashes a bit as it eventually fades out in a rain of sparks!</span>")
	fail(distance * 2)
	for(var/obj/effect/energy_shield/E in range(distance, src))
		// The closer we are to impact site, the longer it takes for shield to come back up.
		E.fail(-(-distance + get_dist(src, E)) * 2)

// Temporarily collapses this shield segment.
/obj/effect/energy_shield/proc/fail(var/time)
	if(!overload_collapse)
		s.set_up(time, 1, src)
		s.start()
	gen.damaged_segments.Add(src)
	overload_collapse += time
	density = 0
	invisibility = 101
	update_nearby_tiles()

// Called by our shield generator if this segment is in it's damaged_segments list.
/obj/effect/energy_shield/proc/regenerate()
	if(!overload_collapse)
		return
	overload_collapse--
	if(!overload_collapse)
		gen.damaged_segments.Remove(src)
		invisibility = 0
		density = 1
		update_nearby_tiles()

/obj/effect/energy_shield/Bumped(atom/hit)
	if(istype(hit, /obj/effect/meteor))
		var/obj/effect/meteor/M = hit
		var/damage = M.get_shield_damage()
		take_damage(damage, damage >= 50 ? 1 : 0)
		visible_message("<span class='danger'>\The [M] breaks into dust as it hits \the [src]!</span>")
		qdel(M)
		return
	return ..()

