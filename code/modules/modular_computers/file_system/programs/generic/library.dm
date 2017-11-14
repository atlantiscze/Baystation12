/*
In reply to this set of comments on lib_machines.dm:
// TODO: Make this an actual /obj/machinery/computer that can be crafted from circuit boards and such
// It is August 22nd, 2012... This TODO has already been here for months.. I wonder how long it'll last before someone does something about it.

The answer was five and a half years -ZeroBits
*/

/datum/computer_file/program/library
	filename = "library"
	filedesc = "Library"
	extended_desc = "This program can be used to view e-books from an external archive."
	program_icon_state = "word"
	program_menu_icon = "note"
	size = 6
	requires_ntnet = 1
	available_on_ntnet = 1

	nanomodule_path = /datum/nano_module/program/computer_library/
	var/error_message = ""
	var/current_book
	var/obj/machinery/libraryscanner/scanner
	var/sort_by = "id"

/datum/computer_file/program/library/kill_program()
	..()
	current_book = null
	sort_by = "id"
	error_message = ""

/datum/computer_file/program/library/proc/view_book(var/id)
	if(current_book)
		return 0

	generate_network_log("Viewed e-book USBN: \"[id]\" from the External Archives.")

	var/sqlid = sanitizeSQL(id)
	establish_old_db_connection()
	if(!dbcon_old.IsConnected())
		error_message = "Network Error: Connection to the Archive has been severed."
		return 0

	var/DBQuery/query = dbcon_old.NewQuery("SELECT * FROM library WHERE id=[sqlid]")
	query.Execute()

	while(query.NextRow())
		current_book = list(
			"id" = query.item[1],
			"author" = query.item[2],
			"title" = query.item[3],
			"content" = query.item[4]
			)
		break

/datum/computer_file/program/library/Topic(href, href_list)
	if(..())
		return 1
	if(href_list["PRG_viewbook"])
		view_book(href_list["PRG_viewbook"])
		return 1
	if(href_list["PRG_viewid"])
		var/bookid = input("Enter USBN:") as num|null
		if(bookid && isnum(bookid))
			view_book(bookid)
	if(href_list["PRG_closebook"])
		current_book = null
		return 1
	if(href_list["PRG_connectscanner"])
		if(computer.hardware_flag != PROGRAM_CONSOLE)
			error_message = "Hardware Error: This device is unable to interface with a scanner."
			return 0
		for(var/d in GLOB.cardinal)
			var/obj/machinery/libraryscanner/scn = locate(/obj/machinery/libraryscanner, get_step(src, d))
			if(scn && scn.anchored)
				scanner = scn
				return 1

		return 0
	if(href_list["PRG_uploadbook"])
		if(!scanner || !scanner.anchored)
			scanner = null
			error_message = "Hardware Error: No scanner detected. Unable to access cache."
			return 0
		if(!scanner.cache)
			error_message = "Interface Error: Scanner cache does not contain any data. Please scan a book."
			return 0

		var/obj/item/weapon/book/B = scanner.cache

		if(B.unique)
			error_message = "Interface Error: Cached book is copy-protected."
			return 0

		if(!B.author)
			B.author = "Anonymous"
		var/choice = input(usr, "Upload [B.name] by [B.author] to the External Archive?") in list("Yes", "No")

		if(choice == "Yes")
			establish_old_db_connection()
			if(!dbcon_old.IsConnected())
				error_message = "Network Error: Connection to the Archive has been severed."
				return 0

			var/upload_category = input(usr, "Upload to which category?") in list("Fiction", "Non-Fiction", "Reference", "Religion")

			var/sqltitle = sanitizeSQL(B.name)
			var/sqlauthor = sanitizeSQL(B.author)
			var/sqlcontent = sanitizeSQL(B.dat)
			var/sqlcategory = sanitizeSQL(upload_category)
			var/DBQuery/query = dbcon_old.NewQuery("INSERT INTO library (author, title, content, category) VALUES ('[sqlauthor]', '[sqltitle]', '[sqlcontent]', '[sqlcategory]')")
			if(!query.Execute())
				to_chat(usr, query.ErrorMsg())
				error_message = "Network Error: Unable to upload to the Archive. Contact your system Administrator for assistance."
				return 0
			else
				log_and_message_admins("has uploaded the book titled [B.name], [length(B.dat)] signs")
				log_game("[usr.name]/[usr.key] has uploaded the book titled [B.name], [length(B.dat)] signs")
				alert("Upload Complete.")
			return 1

		return 0

	if(href_list["PRG_printbook"])
		if(!current_book)
			error_message = "Software Error: Unable to print; book not found."
			return 0

		//PRINT TO BINDER FROM CONSOLE
		if(computer.hardware_flag == PROGRAM_CONSOLE)
			for(var/d in GLOB.cardinal)
				var/obj/machinery/bookbinder/bndr = locate(/obj/machinery/bookbinder, get_step(src, d))
				if(bndr && bndr.anchored)
					var/obj/item/weapon/book/B = new(bndr.loc)
					B.name = current_book["title"]
					B.title = current_book["title"]
					B.author = current_book["author"]
					B.dat = current_book["content"]
					B.icon_state = "book[rand(1,7)]"
					B.desc = current_book["author"]+", "+current_book["title"]+", "+"USBN "+current_book["id"]
					bndr.visible_message("[bndr] whirs as it prints and binds a new book.")
					return 1

		//PRINT TO NANO-PRINTER
		if(!computer.nano_printer)
			error_message = "Hardware Error: No printer detected. Unable to print document."
			return 0
		if(!computer.nano_printer.print_text("<i>Author:"+current_book["author"]+"<br>USBN: "+current_book["id"]+"</i><br><br>"+current_book["content"], current_book["title"]))
			error_message = "Hardware Error: Printer was unable to print this document. It may be out of paper."
			return 0
		return 1
	if(href_list["PRG_sortby"])
		sort_by = href_list["PRG_sortby"]
	if(href_list["PRG_reseterror"])
		if(error_message)
			current_book = null
			sort_by = "id"
			error_message = ""
		return 1
	return 0

/datum/nano_module/program/computer_library
	name = "Library"

/datum/nano_module/program/computer_library/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open = 1, var/datum/topic_state/state = GLOB.default_state)
	if(!program)
		return
	var/datum/computer_file/program/library/PRG = program
	if(!istype(PRG))
		return

	var/list/data = PRG.get_header_data()

	if(PRG.error_message)
		data["error"] = PRG.error_message
	if(PRG.current_book)
		data["current_book"] = PRG.current_book

	var/list/all_entries[0]

	establish_old_db_connection()
	if(!dbcon_old.IsConnected())
		PRG.error_message = "Unable to contact External Archive. Please contact your system administrator for assistance."
	else
		var/DBQuery/query = dbcon_old.NewQuery("SELECT id, author, title, category FROM library ORDER BY [PRG.sort_by]")
		query.Execute()

		while(query.NextRow())
			all_entries.Add(list(list(
			"id" = query.item[1],
			"author" = query.item[2],
			"title" = query.item[3],
			"category" = query.item[4]
			)))

	data["book_list"] = all_entries

	ui = GLOB.nanomanager.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)
		ui = new(user, src, ui_key, "library.tmpl", "Library Program", 575, 700, state = state)
		ui.auto_update_layout = 1
		ui.set_initial_data(data)
		ui.open()
