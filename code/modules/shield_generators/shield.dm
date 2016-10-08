/obj/effect/shield
	name = "energy shield"
	desc = "Impenetrable field of energy, capable of blocking anything as long as it's active."
	icon = 'icons/obj/machines/shielding.dmi'
	icon_state = "shieldsparkles"
	anchored = 1
	layer = 4.1		//just above mobs
	density = 1
	invisibility = 0
	var/obj/machinery/power/shield_generator/gen = null
	var/disabled_for = 0
	var/diffused_for = 0
	var/datum/effect/effect/system/spark_spread/s

// Prevents shuttles, singularities and similar things from moving the field segments away.
/obj/effect/shield/Move()
	return 0

/obj/effect/shield/New()
	..()
	update_nearby_tiles()
	s = new /datum/effect/effect/system/spark_spread(src)

/obj/effect/shield/Destroy()
	..()
	if(gen && (src in gen.field_segments))
		gen.field_segments -= src
	if(gen && (src in gen.damaged_segments))
		gen.damaged_segments -= src
	gen = null
	update_nearby_tiles()

// Temporarily collapses this shield segment.
/obj/effect/shield/proc/fail(var/duration)
	if(!duration <= 0)
		return
	if(!disabled_for)
		s.set_up(1, 1, src)
		s.start()
	gen.damaged_segments |= src
	disabled_for += duration
	density = 0
	invisibility = 101
	update_nearby_tiles()

// Regenerates this shield segment.
/obj/effect/shield/proc/regenerate()
	if(!gen)
		return

	disabled_for = max(0, disabled_for - 1)
	diffused_for = max(0, diffused_for - 1)

	if(!disabled_for && !diffused_for)
		density = 1
		invisibility = 0
		update_nearby_tiles()
		gen.damaged_segments -= src


/obj/effect/shield/proc/diffuse(var/duration)
	// The shield is trying to counter diffusers. Cause lasting stress on the shield.
	if(gen.check_mode(MODEFLAG_BYPASS) && !diffused_for && !disabled_for)
		take_damage(damage * rand(8, 12), SHIELD_DAMTYPE_EM)
		return

	if(!diffused_for && !disabled_for)
		s.set_up(1, 1, src)
		s.start()

	diffused_for = max(duration, 0)
	gen.damaged_segments |= src
	density = 0
	invisibility = 101
	update_nearby_tiles()



/obj/effect/shield/attack_generic(var/source, var/damage, var/emote)
	take_damage(damage, SHIELD_DAMTYPE_PHYSICAL)
	..(source, damage, emote)


// Fails shield segments in specific range. Range of 1 affects the shielded turf only.
/obj/effect/shield/proc/fail_adjacent_segments(var/range, var/hitby = null)
	if(hitby)
		visible_message("<span class='danger'>\The [src] flashes a bit as \the [hitby] collides with it, eventually fading out in a rain of sparks!</span>")
	else
		visible_message("<span class='danger'>\The [src] flashes a bit as it eventually fades out in a rain of sparks!</span>")
	fail(range * 2)
	for(var/obj/effect/shield/S in range(range, src))
		// Don't affect shields owned by other shield generators
		if(S.gen != src.gen)
			continue
		// The closer we are to impact site, the longer it takes for shield to come back up.
		S.fail(-(-range + get_dist(src, S)) * 2)


/obj/effect/shield/proc/take_damage(var/damage, var/damtype, var/hitby)
	if(!gen)
		qdel(src)
		return

	if(!damage)
		return

	damage = round(damage)

	switch(gen.take_damage(damage, damtype))
		if(SHIELD_ABSORBED)
			return
		if(SHIELD_BREACHED_MINOR)
			fail_adjacent_segments(rand(1, 3), hitby)
			return
		if(SHIELD_BREACHED_MAJOR)
			fail_adjacent_segments(rand(2, 5), hitby)
			return
		if(SHIELD_BREACHED_CRITICAL)
			fail_adjacent_segments(rand(4, 8), hitby)
			return
		if(SHIELD_BREACHED_FAILURE)
			fail_adjacent_segments(rand(8, 16), hitby)
			for(var/obj/effect/shield/S in gen.field_segments)
				S.fail(1)
			return

// As we have various shield modes, this handles whether specific things can pass or not.
/obj/effect/shield/CanPass(var/atom/movable/mover, var/turf/target, var/height=0, var/air_group=0)
	// Somehow we don't have a generator. This shouldn't happen. Delete the shield.
	if(!gen)
		qdel(src)
		return 1

	if(disabled_for)
		return 1

	// Atmosphere containment.
	if(air_group)
		return !gen.check_flag(MODEFLAG_ATMOSPHERIC)

	// Humanoid mobs
	if(istype(mover, /mob/living/carbon/human))
		var/mob/living/carbon/human/H = mover
		// IPCs, FBPs
		if(H.IsSynthetic())
			return !gen.check_flag(MODEFLAG_ANORGANIC)
		return !gen.check_flag(MODEFLAG_HUMANOIDS)

	// Silicon mobs
	if(istype(mover, /mob/living/silicon))
		return !gen.check_flag(MODEFLAG_ANORGANIC)

	// Other mobs
	if(istype(mover, /mob/living))
		return !gen.check_flag(MODEFLAG_NONHUMANS)

	// Beams
	if(istype(mover, /obj/item/projectile/beam))
		return !gen.check_flag(MODEFLAG_PHOTONIC)

	// Projectiles. Separated from /obj/ for clarity.
	if(istype(mover, /obj/item/projectile))
		return !gen.check_flag(MODEFLAG_HYPERKINETIC)

	// Meteors. Once again separated from /obj/ for clarity
	if(istype(mover, /obj/effect/meteor))
		return !gen.check_flag(MODEFLAG_HYPERKINETIC)

	// Other objects
	if(istype(mover, /obj))
		return !gen.check_flag(MODEFLAG_HYPERKINETIC)

	// Let anything else through, but log it in the debug log. Pretty much every case should already be handled at this point.
	log_debug("[mover] collided with shield. Not defined type in CanPass().")
	return 1


// EMP. It may seem weak but keep in mind that multiple shield segments are likely to be affected.
/obj/effect/shield/emp_act(var/severity)
	if(!disabled_for)
		take_damage(rand(30,60) / severity, SHIELD_DAMTYPE_EM)


// Explosions
/obj/effect/shield/ex_act(var/severity)
	if(!disabled_for)
		take_damage(rand(10,15) / severity, SHIELD_DAMTYPE_PHYSICAL)


// Fire
/obj/effect/shield/fire_act()
	if(!disabled_for)
		take_damage(rand(5,10), SHIELD_DAMTYPE_HEAT)


// Projectiles
/obj/effect/shield/bullet_act(var/obj/item/projectile/proj)
	if(proj.damage_type == BURN)
		take_damage(proj.get_structure_damage(), SHIELD_DAMTYPE_HEAT)
	else if (proj.damage_type == BRUTE)
		take_damage(proj.get_structure_damage(), SHIELD_DAMTYPE_PHYSICAL)
	else
		take_damage(proj.get_structure_damage(), SHIELD_DAMTYPE_EM)


// Attacks with hand tools. Blocked by Hyperkinetic flag.
/obj/effect/shield/attackby(var/obj/item/weapon/I as obj, var/mob/user as mob)
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	user.do_attack_animation(src)

	if(gen.check_flag(MODEFLAG_HYPERKINETIC)
		user.visible_message("<span class='danger'>\The [user] hits \the [src] with \the [I]!</span>")
		if(I.damtype == BURN)
			take_damage(I.force, SHIELD_DAMTYPE_HEAT)
		else if (I.damtype == BRUTE)
			take_damage(I.force, SHIELD_DAMTYPE_PHYSICAL)
		else
			take_damage(I.force, SHIELD_DAMTYPE_EM)
	else
		user.visible_message("<span class='danger'>\The [user] tries to attack \the [src] with \the [I], but it passes through!</span>")


// Special treatment for meteors because they would otherwise penetrate right through the shield.
/obj/effect/shield/Bumped(var/atom/movable/mover)
	if(istype(mover, /obj/effect/meteor))
		// We don't block meteors. Let it pass as if we weren't here.
		if(!gen.check_flag(MODEFLAG_HYPERKINETIC)
			return ..()
		var/obj/effect/meteor/M = mover
		take_damage(M.get_shield_damage(), SHIELD_DAMTYPE_PHYSICAL, M)
		visible_message("<span class='danger'>\The [M] breaks into dust!</span>")
		qdel(M)
		return 0
	return ..()


// Called when a flag is toggled. Can be used to add on-toggle behavior, such as visual changes.
/obj/effect/shield/proc/flags_updated()
	if(!gen)
		return

	// Update airflow
	update_nearby_tiles()
	update_icon()

	// Photonic flag blocks vision
	opacity = 0
	if(gen.check_flag(MODEFLAG_PHOTONIC))
		opacity = 1