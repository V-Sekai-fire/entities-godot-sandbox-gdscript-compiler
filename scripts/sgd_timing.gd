extends SceneTree

# Times each loop function of census.py's timing_plan.json both ways: the .gd through GDScript
# and the same source written beside it as .sgd through the godot_sandbox addon, which the
# project must carry. Arguments are synthesized from the declared parameter types; a function
# the plan could not synthesize is recorded as skipped. Every call is bracketed by a "## begin"
# and "## end" line so the log attributes errors to the call that raised them: a timing with
# errors inside its bracket is not a loop timing, and the report must say so.
# Usage: godot --headless --path <project> -s <this> -- --plan=<json> --out=<json> [--n=20] [--len=4096]

var n := 20
var len := 4096
var out_path := ""


func _arg(name: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return default


func _synth(t: String) -> Variant:
	match t:
		"int": return 7
		"float": return 0.5
		"bool": return true
		"String", "StringName": return "probe"
		"Vector2": return Vector2(1, 2)
		"Vector3": return Vector3(1, 2, 3)
		"Vector4": return Vector4(1, 2, 3, 4)
		"Color": return Color(0.5, 0.25, 0.125, 1)
		"Quaternion": return Quaternion.IDENTITY
		"Basis": return Basis.IDENTITY
		"Transform3D": return Transform3D.IDENTITY
		"Transform2D": return Transform2D.IDENTITY
		"Dictionary": return {}
		"Array": return []
		"PackedByteArray":
			var a := PackedByteArray(); a.resize(len)
			for i in len: a[i] = i % 251
			return a
		"PackedInt32Array":
			var a := PackedInt32Array(); a.resize(len)
			for i in len: a[i] = i
			return a
		"PackedInt64Array":
			var a := PackedInt64Array(); a.resize(len)
			for i in len: a[i] = i
			return a
		"PackedFloat32Array":
			var a := PackedFloat32Array(); a.resize(len)
			for i in len: a[i] = float(i) * 0.5
			return a
		"PackedFloat64Array":
			var a := PackedFloat64Array(); a.resize(len)
			for i in len: a[i] = float(i) * 0.5
			return a
		"PackedStringArray":
			var a := PackedStringArray()
			for i in len: a.append("--key%d=value%d" % [i, i])
			return a
		"PackedVector2Array":
			var a := PackedVector2Array(); a.resize(len)
			for i in len: a[i] = Vector2(i, i)
			return a
		"PackedVector3Array":
			var a := PackedVector3Array(); a.resize(len)
			for i in len: a[i] = Vector3(i, i, i)
			return a
		"PackedColorArray":
			var a := PackedColorArray(); a.resize(len)
			for i in len: a[i] = Color(0.1, 0.2, 0.3)
			return a
		_: return null


func _target(script, is_static: bool):
	if is_static:
		return script
	if script == null or not script.can_instantiate():
		return null
	return script.new()


func _time(script, fname: String, is_static: bool, args: Array, label: String) -> Dictionary:
	var target = _target(script, is_static)
	if target == null:
		return {"us": -1.0, "note": "could not instantiate"}
	if not is_static and not target.has_method(fname):
		if target is Node: target.free()
		return {"us": -1.0, "note": "no such method on the instance"}
	print("## begin %s" % label)
	var result = null
	for i in 3:
		result = target.callv(fname, args)
	var t0 := Time.get_ticks_usec()
	for i in n:
		target.callv(fname, args)
	var dt := float(Time.get_ticks_usec() - t0) / n
	print("## end %s" % label)
	if target is Node:
		target.free()
	return {"us": dt, "note": "", "result": _summary(result)}


# What a call returned, small enough to compare across the two runs: the type, a size where
# there is one, and the first 80 characters of its text. Equal summaries say both sides did
# the same work; a sandbox call that aborted returns null and shows it.
func _summary(v) -> String:
	var size := ""
	if v is Array or v is Dictionary or v is String or v is PackedByteArray or v is PackedInt32Array or v is PackedInt64Array or v is PackedFloat32Array or v is PackedFloat64Array or v is PackedStringArray or v is PackedVector2Array or v is PackedVector3Array or v is PackedColorArray:
		size = " size=%d" % v.size()
	return "%s%s %s" % [type_string(typeof(v)), size, str(v).left(80)]


func _init() -> void:
	n = int(_arg("n", str(n)))
	len = int(_arg("len", str(len)))
	out_path = _arg("out", "")
	var plan: Array = JSON.parse_string(FileAccess.get_file_as_string(_arg("plan", "res://timing_plan.json")))
	var records := []

	# Control: a loop whose answer is known. Both sides must return the sum of the synthesized
	# array, so a sandbox that received an empty argument, or aborted its loop, is caught before
	# any timing is believed. A control that fails ends the run with nothing reported.
	var probe_src := "extends RefCounted\nfunc count(a: PackedInt32Array) -> int:\n\tvar s := 0\n\tfor i in a.size():\n\t\ts += a[i]\n\treturn s\n"
	for ext in [".gd", ".sgd"]:
		var pf := FileAccess.open("res://sgd_timing_probe" + ext, FileAccess.WRITE)
		pf.store_string(probe_src)
		pf.close()
	var probe_args := [_synth("PackedInt32Array")]
	var expected := 0
	for i in len:
		expected += i
	var probe_gd = _time(load("res://sgd_timing_probe.gd"), "count", false, probe_args, "gd probe count")
	var probe_sgd = _time(ResourceLoader.load("res://sgd_timing_probe.sgd", "", ResourceLoader.CACHE_MODE_IGNORE), "count", false, probe_args, "sgd probe count")
	var want := _summary(expected)
	print("control: expected %s, gd %s, sgd %s" % [want, probe_gd.get("result", ""), probe_sgd.get("result", "")])
	if probe_gd.get("result", "") != want or probe_sgd.get("result", "") != want:
		push_error("CONTROL FAILED: the probe loop did not return its sum on both sides; nothing below is a timing")
		quit(2)
		return
	records.append({"script": "sgd_timing_probe", "func": "count", "static": false, "skip": null, "sites": 1, "gd": probe_gd, "sgd": probe_sgd, "same_result": true, "control": true})
	print("%-70s gd %10.1f us   sgd %10.1f us" % ["control probe count (%d ints)" % len, probe_gd["us"], probe_sgd["us"]])

	for entry in plan:
		var gd_path: String = "res://" + entry["script"]
		var sgd_path: String = gd_path.get_basename() + ".sgd"
		var f := FileAccess.open(sgd_path, FileAccess.WRITE)
		f.store_string(FileAccess.get_file_as_string(gd_path))
		f.close()
		var gd = load(gd_path)
		var sgd = ResourceLoader.load(sgd_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		for fname in entry["funcs"]:
			var spec: Dictionary = entry["funcs"][fname]
			var rec := {"script": entry["script"], "func": fname, "static": spec["static"], "skip": spec["skip"], "sites": spec["sites"].size()}
			if spec["skip"] != null:
				records.append(rec)
				continue
			var args := []
			for t in spec["params"]:
				args.append(_synth(t))
			var label := "%s %s" % [entry["script"], fname]
			rec["gd"] = _time(gd, fname, spec["static"], args, "gd " + label)
			rec["sgd"] = _time(sgd, fname, spec["static"], args, "sgd " + label) if sgd != null else {"us": -1.0, "note": ".sgd did not load"}
			records.append(rec)
			rec["same_result"] = rec["gd"].get("result", "") == rec["sgd"].get("result", "")
			print("%-70s gd %10.1f us   sgd %10.1f us   same=%s" % [label, rec["gd"]["us"], rec["sgd"]["us"], rec["same_result"]])
	if out_path != "":
		var o := FileAccess.open(out_path, FileAccess.WRITE)
		o.store_string(JSON.stringify({"n": n, "len": len, "records": records}, "  "))
		o.close()
	quit()
