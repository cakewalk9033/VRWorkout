extends Spatial

signal level_finished
var gu = GameUtilities.new()
var CueState = GameVariables.CueState
var CueSelector = GameVariables.CueSelector
var PushupState = GameVariables.PushupState
var SquatState = GameVariables.SquatState

var exercise_state_model_template
var pushup_state_model
var squat_state_model


var song_index_parameter = 0
var audio_filename = ""

export var random_seed = true

var beats = []
var state_list = []
var state_list_index = 0

var bpm = 60 #only used in freeplay mode
var first_beat = 0 #only used in freeplay mode
var beat_index = 0
var selected_song = 0
var stream
var fly_time = 3.0
var emit_early = 0 #Time it takes the cue to reach the target area. autocalculated
var fly_distance = 0.0 #How far the cue flies, autocalculated
var hand_cue_offset = 0.60
var jump_offset = 0.42
var player_height = 0
var run_point_multiplier = 1
var beast_mode = false
var ducking_mode = false
var kneesaver_mode = false
var stand_avoid_head_cue = 0.5
var redistribution_speed = 0.025
var song_current_bpm = 0
var state_duration = 0


var target_hr = 140
var low_hr = 130
var high_hr = 150
var auto_difficulty = false
var avg_hr = 60	
	
var hud_enabled = false	
	
var running_speed = 0
	
var current_difficulty = 0
var exercise_changed = true

var next_exercise = CueState.STAND
var rebalance_exercises = true


var groove_display
var trophy_list


var cue_horiz = preload("res://cue_h_obj.tscn")
var cue_vert = preload("res://cue_v_obj.tscn")
var cue_head = preload("res://cue_head_obj.tscn")
var cue_head_avoid = preload("res://cue_head_obj_avoid.tscn")
var environment = preload("res://outdoor_env.tres")
var infolayer

var cue_emitter
var target
var boxman1
var boxman2
	
var cue_parameters = {}

#Populate the cue parameters according to difficulty and player height
func setup_cue_parameters(difficulty, player_height):
	cue_parameters = {
		CueState.STAND : {
			CueSelector.HEAD : {
				"xrange" : 1.0,
				"yoffset" : 0.0
			},
			CueSelector.HAND : {
				"xoffset" : 0.2,
				"xrange" : 0.45,
				"yoffset" : -0.2 - difficulty * 0.1,
				"yrange" : 0.3 + difficulty * player_height/8.0
			}
		},	
		CueState.SQUAT : {
			CueSelector.HEAD : {
				"yoffset" : 0.0,
				"yrange" : player_height * 0.3,
			},
			CueSelector.HAND :  {
				"xspread" : 0.6
			}		
		},	
		CueState.PUSHUP : {
			CueSelector.HEAD : {
				"xrange" : 0.4,
				"yoffset" : 0.25,
				"yrange" : 0.55
			},
			CueSelector.HAND : {
			}
		},	
		CueState.CRUNCH : {
			CueSelector.HEAD : {
				"xrange" : 0.3,
				"yoffset": 0.35,
				"yrange": 0.1
			},
			CueSelector.HAND : {
				"rotation_range": difficulty*35, #increase core rotation with difficulty
				"xrange" : 0.1,
				"xspread" : max(0.1, 0.2 - difficulty/10.0), #If core rotation increases, decrease spread
				"yoffset" : player_height * 0.526 + difficulty * player_height/20.0,
				"yrange" : 0.2
			}
		},	
		CueState.JUMP : {
			CueSelector.HEAD : {
				"yoffset" : jump_offset,
			},
			CueSelector.HAND : {
				"has_hand" : difficulty > 0.9,
				"yoffset" : jump_offset,
				"xspread" : player_height / 5.0,
			}
		},
		CueState.BURPEE : {
			CueSelector.HEAD : {
				"yoffset" : 0.6
			},
			CueSelector.HAND : {
			}
		},	
		CueState.YOGA : {
			CueSelector.HEAD : {
			},
			CueSelector.HAND : {
			}
		}	
	}
	if kneesaver_mode:
		cue_parameters[CueState.SQUAT][CueSelector.HEAD]["yoffset"] = player_height * 0.18


var cue_emitter_state = CueState.STAND
var cue_selector = CueSelector.HEAD

var level_min_cue_space = 1.0
var level_min_state_duration = 10.0


var min_cue_space = 1.0 #Hard: 1.0 Medium: 2.0 Easy: 3.0
var min_state_duration = 10.0 #Hard 5 Medium 15 Easy 30

var temporary_cue_space_extension = 0.0

var beast_chance = 0.1
var last_emit = 0.0
var state_transition_pause = 1.5
var head_y_pos = 0
var last_state_change = 0.0

var rng = RandomNumberGenerator.new()

func state_string(state):
	if state == CueState.STAND:
		return "stand"
	elif state == CueState.JUMP:
		return "jump"
	elif state == CueState.SQUAT:
		return "squat"
	elif state == CueState.PUSHUP:
		return "pushup"
	elif state == CueState.CRUNCH:
		return "crunch"
	elif state == CueState.BURPEE:
		return "burpee"
	elif state == CueState.SPRINT:
		return "sprint"
	elif state == CueState.YOGA:
		return "yoga"
	
	return "unknown"

func string_to_state(s):
	var  retVal = CueState.STAND
	if s == "stand":
		retVal = CueState.STAND
	elif s == "jump":
		retVal = CueState.JUMP
	elif s == "squat":
		retVal = CueState.SQUAT
	elif s == "pushup":
		retVal = CueState.PUSHUP
	elif s == "crunch":
		retVal = CueState.CRUNCH
	elif s == "burpee":
		retVal = CueState.BURPEE
	elif s == "sprint":
		retVal = CueState.SPRINT
	elif s == "yoga":
		retVal = CueState.YOGA
	return retVal


func display_state(state):
	var psign = get_node("PositionSign")
	if state == CueState.STAND:
		psign.stand()
	elif state == CueState.JUMP:
		psign.jump()
	elif state == CueState.SQUAT:
		psign.squat()
	elif state == CueState.PUSHUP:
		psign.pushup()
	elif state == CueState.CRUNCH:
		psign.crunch()
	elif state == CueState.BURPEE:
		psign.burpee() 
	elif state == CueState.SPRINT:
		psign.sprint() 
	elif state == CueState.YOGA:
		#TODO: Add sign
		pass
		
	
	get_node("ExerciseSelector").select(state_string(state))
	
	
var update_counter = 0
func update_info(hits, max_hits, points):
	var song_pos = int(cue_emitter.current_playback_time)
	var total = int(stream.stream.get_length())
	
	var elapsed_string = gu.seconds_to_timestring(song_pos)
	
	infolayer.print_info("Hits %d/%d - Song: %s (%.1f%%) - Points: %d - Speed: %.1f"% [hits,max_hits,elapsed_string,float(100*song_pos)/total,points,running_speed])
	if update_counter % 5 == 0:
		infolayer.print_info("Player height: %.2f Difficulty: %.1f/%.2f/%.2f - E: %.2f"%[player_height, current_difficulty, min_cue_space, min_state_duration,state_duration], "debug")
	update_counter += 1
	infolayer.get_parent().render_target_update_mode = Viewport.UPDATE_ONCE

func load_audio_resource(filename):
	var resource = null
	
	if filename.find("res://") == 0:
		resource = ResourceLoader.load(filename)
	else:
		var f = File.new()
		
		if  f.file_exists(filename):
			print ("External resource exists")
			f.open(filename, File.READ)
			var buffer = f.get_buffer(f.get_len())
			resource = AudioStreamOGGVorbis.new()
			resource.data = buffer
		else:
			print ("External resource does not exist")

	return resource

var last_update = 0
func _on_HeartRateData(hr):
	avg_hr = 0.1 * hr + 0.9  * avg_hr
	get_node("heart_coin").set_hr(hr)
	get_node("heart_coin").set_marker("actual", avg_hr)
	
	if auto_difficulty:
		var now = OS.get_ticks_msec()
		if now - last_update > 5000:
			setup_difficulty(-1)

func setup_game_data():
	GameVariables.level_statistics_data = {}
	if len(GameVariables.exercise_state_list) > 0:
		state_list = GameVariables.exercise_state_list	
	
	if ProjectSettings.get("game/exercise/strength_focus"):
		exercise_state_model_template = GameVariables.exercise_model["strength"]["exercise_state_model"]
		pushup_state_model = GameVariables.exercise_model["strength"]["pushup_state_model"]
		squat_state_model = GameVariables.exercise_model["strength"]["squat_state_model"]
		rebalance_exercises = GameVariables.exercise_model["strength"]["rebalance_exercises"]
	else:
		exercise_state_model_template = GameVariables.exercise_model["cardio"]["exercise_state_model"]
		pushup_state_model = GameVariables.exercise_model["cardio"]["pushup_state_model"]
		squat_state_model = GameVariables.exercise_model["cardio"]["squat_state_model"]
		rebalance_exercises = GameVariables.exercise_model["cardio"]["rebalance_exercises"]

	populate_state_model()

	beast_mode = ProjectSettings.get("game/beast_mode")
	ducking_mode = ProjectSettings.get("game/exercise/duck")
	kneesaver_mode = ProjectSettings.get("game/exercise/kneesaver")	
	target_hr = ProjectSettings.get("game/target_hr")	
	hud_enabled = ProjectSettings.get("game/hud_enabled")	
	
	low_hr = target_hr - 10
	high_hr = target_hr + 10

	cue_emitter_state = get_start_exercise()

	current_difficulty = GameVariables.difficulty
	setup_difficulty(current_difficulty)

	
		
	
func _ready():
	if random_seed:
		rng.randomize()
	else:
		rng.set_seed(0)
	GameVariables.reset_ingame_id()
		
	infolayer = get_node("Viewport/InfoLayer")
	cue_emitter = get_node("cue_emitter")
	target = get_node("target")
	
	boxman1 = get_node("boxman")
	boxman2 = get_node("boxman2")
	
	trophy_list = get_node("TrophyList")
	
	groove_display = get_node("GrooveDisplay")

	setup_game_data()

	get_tree().current_scene.set_detail_selection_mode(false)

	get_tree().get_current_scene().get_node("HeartRateReceiver").connect("heart_rate_received", self,"_on_HeartRateData")	


	if not ProjectSettings.get("game/equalizer"):
		self.remove_child(get_node("SpectrumDisplay"))

	print ("Rebalance exercises: %s"%(str(rebalance_exercises)))

	get_node("heart_coin").set_marker("low", low_hr)
	get_node("heart_coin").set_marker("high", high_hr)
	
		
	beat_index = 0

	beats = []
	
	print ("Initializing AUDIO")
	print ("File: %s"%audio_filename)
	
	if song_index_parameter < 0:
		#freeplay mode
		stream = DummyAudioStream.new(abs(song_index_parameter)*100)
		selected_song = "Freeplay"
		print ("BPM %.2f"%bpm)
		stream.connect("stream_finished", self, "_on_AudioStreamPlayer_finished")
		self.add_child(stream)
	else:
		selected_song = audio_filename
				
		var beat_file = File.new()
		var error = beat_file.open("%s.json"%audio_filename, File.READ)
		beats = []
		
		if error == OK:
			var tmp = JSON.parse(beat_file.get_as_text()).result
			beat_file.close()
			beats = tmp.get("beats", [])
			print ("%d beats loaded"%len(beats))
		else: 
			print ("Could not open beat list")

		#var audio_file = File.new()
		
		infolayer.print_info("Loading song %s"%audio_filename)
		print ("Loading song: %s"%audio_filename)
		#error = audio_file.open(audio_filename,File.READ)
		#infolayer.append_info(" / File opened %s" % str(audio_file.is_open()))
		infolayer.print_info(state_string(cue_emitter_state).to_upper(), "main")
		infolayer.print_info("Player height: %.2f Difficulty: %.2f/%.2f"%[player_height, min_cue_space, min_state_duration], "debug")
		infolayer.get_parent().render_target_update_mode = Viewport.UPDATE_ONCE
		var audio_resource = load_audio_resource(audio_filename)
		stream = get_node("AudioStreamPlayer")

		if audio_resource:
			stream.stream = audio_resource
		else:
			print ("Could not load audio")
			emit_signal("level_finished")	
	
	#If the song has no beats use the default beats
	if (GameVariables.override_beatmap or len(beats) == 0) and stream.stream:
		beats = []
		var delta = max(0.1, 60.0/float(max(1,bpm)))
		var now = OS.get_ticks_msec()	
		var pos = 0
		#get the correct starting time
		var elapsed = (now - first_beat)/1000.0
		pos =  (ceil(elapsed/delta) - elapsed/delta)*delta
		print ("Start at: %.2f"%pos)
				
		while pos < stream.stream.get_length()-delta:
			beats.append(pos)
			pos += delta

	if stream.stream:
		stream.play()
		
	update_safe_pushup()
	
func next_state_from_list():
	state_list_index = (state_list_index + 1) % len(state_list)
	cue_emitter_state = string_to_state(get_current_state_from_list())
	state_duration = get_current_duration_from_list()
	level_min_state_duration = state_duration
	min_state_duration = state_duration
	print ("State duration %.2f"%float(state_duration)) 
	
func get_current_state_from_list():
	var retVal = "stand"
	if len(state_list) > 0 and state_list_index < len(state_list):
		retVal = state_list[state_list_index][0]
	return retVal

func get_current_duration_from_list():
	var retVal = 1.0
	if len(state_list) > 0 and state_list_index < len(state_list):
		retVal = state_list[state_list_index][1]
	return retVal	
	
func setup_difficulty(diff):

	if diff < 0:
		auto_difficulty = true
	
	if auto_difficulty:
		diff = 1.0 + min(1.0,max(-1.0,(target_hr - avg_hr)/10.0))
	else:
		#Keep the difficulty in the supported bounds	
		diff = min(2,max(0,diff))
	
	var d = diff
	
	if len(state_list) > 0:
		level_min_state_duration = get_current_duration_from_list()
	else:		
		level_min_state_duration = 20 - d * 5.0 
	beast_chance = 0.1 + d/10.0
	level_min_cue_space = 1.5 - d*0.5
	fly_time = 3.5-(d/2	)
	
			
	min_cue_space = level_min_cue_space
	min_state_duration = level_min_state_duration
	state_duration = min_state_duration
	current_difficulty = d

	update_cue_timing()

	setup_cue_parameters(d, player_height)

func update_groove_iteration():
	if beat_index > 0:
		var beat_delta = beats[beat_index]-beats[beat_index-1]
		if beat_delta > 0:
			song_current_bpm = (3*song_current_bpm + 60/beat_delta)/4
	if beat_index % 2 == 0:
		if beat_index < len(beats)-2:
			groove_display.set_next_beat(beats[beat_index+2]-cue_emitter.current_playback_time, 1)
	groove_display.set_next_beat(beats[beat_index]-cue_emitter.current_playback_time, 0)	
	
func update_duration_indicator(progress):
	get_node("MeshInstance/DurationIndicator").scale.x = progress		
		
var last_playback_time = 0
func _process(delta):
	#cue_emitter.current_playback_time += delta
	cue_emitter.current_playback_time = stream.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	if beat_index < len(beats)-1 and cue_emitter.current_playback_time + emit_early > beats[beat_index]:	
		update_groove_iteration()
		
		if state_duration > 0:
			update_duration_indicator( (cue_emitter.current_playback_time - last_state_change) / state_duration )
		
		
		if last_emit + min_cue_space < cue_emitter.current_playback_time and last_state_change + state_transition_pause < cue_emitter.current_playback_time:		
			if last_emit + temporary_cue_space_extension <  cue_emitter.current_playback_time:
				temporary_cue_space_extension = 0
				emit_cue_node(beats[beat_index])
				last_emit = cue_emitter.current_playback_time
		beat_index += 1
	elif beat_index == len(beats)-1:
		beat_index += 1
		infolayer.print_info("FINISHED", "main")
		infolayer.get_parent().render_target_update_mode = Viewport.UPDATE_ONCE
		
	if cue_emitter.current_playback_time < last_playback_time - 1.0:
		stream.stop()
	else:		
		last_playback_time = cue_emitter.current_playback_time
	
func _on_exit_timer_timeout():
	print ("End of level going back to main")
	emit_signal("level_finished")
	

func _on_tween_completed(obj,path):
	if obj.has_method("should_be_avoided") and obj.should_be_avoided():
		cue_emitter.score_avoided(obj)
	else:
		cue_emitter.score_miss(obj)
	obj.queue_free()

func switch_floor_sign(type):
	var sign_node = get_node("FloorSign")
	if type == "hands":
		sign_node.show_feet(false)
		sign_node.show_hands(true)
	elif type == "feet":
		sign_node.show_hands(false)
		sign_node.show_feet(true)
	else:
		sign_node.show_hands(false)
		sign_node.show_feet(false)
		
func update_cue_timing():
	fly_distance = abs(cue_emitter.translation.z-target.translation.z) + 2	
	var time_to_target = abs(cue_emitter.translation.z-target.translation.z) / fly_distance
	emit_early = fly_time * time_to_target

func add_statistics_element(state_string, cue_type, difficulty, points, hit, starttime, targettime, hr):
	var ingame_id = GameVariables.get_next_ingame_id()
	var statistics_element = {"e": state_string, "t": cue_type, "d": difficulty, "p": points, "h": hit, "st": starttime,"tt": targettime, "hr": hr}	
	GameVariables.level_statistics_data [ingame_id] = statistics_element
	return ingame_id	


# Create the actual cue node add it to the scene and the statistics
func create_and_attach_cue(cue_type, x, y, target_time, fly_offset=0, fly_time = 0, cue_subtype=""):
	cue_emitter.max_hits += 1
	var cue_node
	if cue_type == "right" or cue_type == "right_hold":
		cue_node = cue_horiz.instance()
	elif cue_type == "left" or cue_type == "left_hold":
		cue_node = cue_vert.instance()
	else:
		head_y_pos = y
		if cue_type == "head_avoid":
			cue_node = cue_head_avoid.instance()
		else:
			cue_node = cue_head.instance()
			if cue_type == "head_extended":
				cue_node.extended = true
	if cue_type in ["right_hold", "left_hold"]:
		cue_node.is_hold_cue = true
		cue_node.hold_time = 0.5
	cue_node.target_time = target_time
	cue_node.start_time = cue_emitter.current_playback_time
	var actual_flytime = fly_time
	if fly_time == 0:
		actual_flytime = self.fly_time
	
	var main_node = get_node("cue_emitter")
	var move_modifier = Tween.new()
	move_modifier.set_name("tween")
	cue_node.add_child(move_modifier)
	main_node.add_child(cue_node)
	cue_node.translation = Vector3(x,y,0+fly_offset)
	if cue_type == "head_inverted":
		cue_node.set_transform( cue_node.get_transform().rotated(Vector3(0,0,1), 3.1415926))
	elif cue_type == "head_left":
		cue_node.set_transform( cue_node.get_transform().rotated(Vector3(0,0,1), 3.1415926/2))
	elif cue_type == "head_right":
		cue_node.set_transform( cue_node.get_transform().rotated(Vector3(0,0,1), 3*3.1415926/2))
	
	if cue_type in ["left", "right", "left_hold", "right_hold"]:
		var alpha = atan2(x,y-head_y_pos)
		cue_node.set_transform(cue_node.get_transform().rotated(Vector3(0,0,1),-alpha))
		
	#var statistics_element = {"exercise": cue_emitter_state, "type": cue_type, "difficuly": current_difficulty, "points": 0, "hit": false, "start_time": cue_emitter.current_playback_time,"target_time": target_time}	
	#Heartrate is stored with the start of the cue because that's the only definitive timestamp we know
	
	var ingame_id = add_statistics_element(state_string(cue_emitter_state)+"/%s"%cue_subtype, cue_type, current_difficulty, 0, false, cue_emitter.current_playback_time, target_time, GameVariables.current_hr)
	cue_node.ingame_id = ingame_id
	move_modifier.interpolate_property(cue_node,"translation",Vector3(x,y,0+fly_offset),Vector3(x,y,fly_distance+fly_offset),actual_flytime,Tween.TRANS_LINEAR,Tween.EASE_IN_OUT,0)
	move_modifier.connect("tween_completed",self,"_on_tween_completed")
	move_modifier.start()
	return cue_node

	
var exercise_state_model = {}

func get_start_exercise():
	var retVal = CueState.STAND
	
	if len(state_list) > 0:
		retVal = string_to_state(get_current_state_from_list())
		state_duration = get_current_duration_from_list()
		min_state_duration = state_duration
		print ("Using preset workout  %s/%s"%[cue_emitter_state,state_duration])

	else:
		var states = { 	CueState.STAND  : ProjectSettings.get("game/exercise/stand"),
						CueState.SQUAT  : ProjectSettings.get("game/exercise/squat"),
						CueState.PUSHUP  : ProjectSettings.get("game/exercise/pushup"),
						CueState.CRUNCH  : ProjectSettings.get("game/exercise/crunch"),
						CueState.JUMP  : ProjectSettings.get("game/exercise/jump"),
						CueState.BURPEE  : ProjectSettings.get("game/exercise/burpees"),
						CueState.SPRINT  : ProjectSettings.get("game/exercise/sprint"),
						CueState.YOGA  : ProjectSettings.get("game/exercise/yoga"),
					}
		for key in states:
			if states[key]:
				retVal = key
				break
	return retVal


func populate_state_model():
	exercise_state_model.clear()
	var states = { 	CueState.STAND  : ProjectSettings.get("game/exercise/stand"),
					CueState.SQUAT  : ProjectSettings.get("game/exercise/squat"),
					CueState.PUSHUP  : ProjectSettings.get("game/exercise/pushup"),
					CueState.CRUNCH  : ProjectSettings.get("game/exercise/crunch"),
					CueState.JUMP  : ProjectSettings.get("game/exercise/jump"),
					CueState.BURPEE  : ProjectSettings.get("game/exercise/burpees"),
					CueState.SPRINT  : ProjectSettings.get("game/exercise/sprint"),
					CueState.YOGA  : ProjectSettings.get("game/exercise/yoga"),
				}
				
	for key in states:
		exercise_state_model[key] = {}
		for key_2 in states:
			if exercise_state_model_template[key].has(key_2):
				var val = exercise_state_model_template[key][key_2]
				if key != key_2 and states[key_2]:
					exercise_state_model[key][key_2] = val
	print (str(exercise_state_model))

func update_distribution(distribution, index, delta):
	var tmp = delta / len(distribution)
	var total = 0
	for k in distribution.keys():
		if k != index:
			distribution[k] = min(0.99, distribution[k] + tmp)
			total = total + distribution[k]
	distribution[index] = max (0.01, distribution[index]-delta)
	total = total + distribution[index]
	for k in distribution.keys():
		distribution[k] = distribution[k] / total
	return distribution
	

# If current_distribution is set the probabilities are normalized by the actual distribution
func state_transition(old_state, state_model, current_distribution = null, allow_self_transition = true):
	var probabilities = state_model[old_state]

	print ("Probabilities pre: %s"%str(probabilities))
	if len(probabilities) < len(state_model):
		var sum = 0
		for k in probabilities.keys():
			sum = sum + probabilities[k]
		probabilities[old_state] = max(0,100-sum)

	#If the actual state must not be the target state remove it
	if not allow_self_transition:
		print ("Remove old state %d"%old_state)
		if probabilities.has(old_state):
			print ("Remove")
			probabilities.erase(old_state)
			print ("Probabilities mid: %s"%str(probabilities))
			
	if current_distribution != null:
		if len(current_distribution) < len(state_model):
			current_distribution.clear()
			for k in state_model.keys():
				current_distribution[k] = 1.0/len(state_model)
		var total = 0
		for k in probabilities.keys():
			probabilities[k] = probabilities[k] * current_distribution[k]
			total = total + probabilities[k]
		for k in probabilities.keys():
			probabilities[k] = 100 * probabilities[k] / total
		print ("Probabilities: %s"%str(probabilities))
	var state_selector = rng.randi()%100
	var new_state = old_state

	var sum = 0
	for p in probabilities:
		sum += p
	
	#If the probabilities don't add up to 1 rescale them
	var factor = 1.0
	if sum > 0 and sum < 1.0:
		factor = 1.0/sum	
	
	if len(probabilities) > 0:
		var cumulative_probability = 0
		new_state = probabilities.keys()[0]
		for k in probabilities.keys():
			cumulative_probability += factor * probabilities[k]
			if state_selector < cumulative_probability:
				new_state = k
				break
	
	if current_distribution != null:
		current_distribution = update_distribution(current_distribution, new_state, redistribution_speed)
		print ("Distribution: %s"%str(current_distribution))
	return new_state
	
var sprint_multiplier = 10.0
var last_sprint_update = 0
func handle_sprint_cues(target_time):
	switch_floor_sign("feet")
	var now = OS.get_ticks_msec()
	var delta = now - last_sprint_update
	var points = sprint_multiplier * running_speed * delta / 1000.0
	last_sprint_update = now
	var ingame_id = add_statistics_element(state_string(cue_emitter_state), "", current_difficulty, points, true, cue_emitter.current_playback_time, cue_emitter.current_playback_time, GameVariables.current_hr)
	cue_emitter.score_points(points)


enum YogaState {
	LEFT = 0,
	RIGHT = 1,
};	

var yoga_state_model = { YogaState.LEFT : { YogaState.RIGHT: 100},
						YogaState.RIGHT : { YogaState.LEFT: 100},
					};
var yoga_state = YogaState.LEFT

func handle_yoga_cues(target_time):
	switch_floor_sign("feet")
	yoga_state = state_transition(yoga_state, yoga_state_model)

	if yoga_state == YogaState.LEFT:
		create_and_attach_cue("left_hold", -0.3*player_height, 0.85 * player_height, target_time, 0, target_time+0.5)
	else:
		create_and_attach_cue("right_hold", 0.3*player_height, 0.85 * player_height, target_time, 0, target_time+0.5)
	
func handle_stand_cues(target_time):
	switch_floor_sign("feet")
	
	var node_selector = rng.randi()%100
	
	var y_hand = player_height + cue_parameters[cue_emitter_state][CueSelector.HAND]["yoffset"] + rng.randf() * cue_parameters[cue_emitter_state][CueSelector.HAND]["yrange"]
	var y_head = player_height + cue_parameters[cue_emitter_state][CueSelector.HEAD]["yoffset"]
	var x = cue_parameters[cue_emitter_state][CueSelector.HAND]["xoffset"] + rng.randf() * cue_parameters[cue_emitter_state][CueSelector.HAND]["xrange"]
	var x_head = rng.randf() * cue_parameters[cue_emitter_state][CueSelector.HEAD]["xrange"] - cue_parameters[cue_emitter_state][CueSelector.HEAD]["xrange"]/2.0
	
	if cue_selector == CueSelector.HAND and node_selector < 20:
		cue_selector = CueSelector.HEAD
	elif cue_selector == CueSelector.HEAD and node_selector < 50:	
		cue_selector = CueSelector.HAND
	
	var double_punch = rng.randf() < 0.5
	var double_punch_delay = 0.25
	var dd_df = fly_distance/fly_time
	
	if cue_selector == CueSelector.HAND:
		if node_selector < 50:	
			var n = create_and_attach_cue("left", -x,y_hand, target_time, -hand_cue_offset)
			if double_punch:
				var n2 = create_and_attach_cue("left", -x*rng.randf(),(y_hand+player_height*(0.5+rng.randf()*0.2))/2, target_time , -hand_cue_offset-double_punch_delay*dd_df)
				n2.activate_path_cue(n)
		else:			
			var n = create_and_attach_cue("right", x,y_hand, target_time, -hand_cue_offset)
			if double_punch:
				var n2 = create_and_attach_cue("right", x*rng.randf(),(y_hand+player_height*(0.5+rng.randf()*0.2))/2, target_time , -hand_cue_offset-double_punch_delay*dd_df)
				n2.activate_path_cue(n)
	else:
		if ducking_mode and rng.randf() < stand_avoid_head_cue:
			temporary_cue_space_extension = 1.0
			if abs(x_head) > 0.3:
				#If the head is far out, make the blockade diagonal
				create_and_attach_cue("head_avoid", x_head-sign(x_head)*0.4, y_head, target_time)
				create_and_attach_cue("head_avoid", x_head-sign(x_head)*0.2, y_head, target_time, 0.4)
			else:
				#Otherwise make it straight
				create_and_attach_cue("head_avoid", x_head-0.3, y_head, target_time, 0.8)
				create_and_attach_cue("head_avoid", x_head+0.3, y_head, target_time, 0.8)
				
			create_and_attach_cue("head_avoid", x_head, y_head, target_time, 0.8)
		create_and_attach_cue("head", x_head, y_head, target_time)
	
	
	
func handle_jump_cues(target_time):
	switch_floor_sign("feet")
	var y_hand = player_height + cue_parameters[cue_emitter_state][CueSelector.HAND]["yoffset"]
	var y_head = player_height + cue_parameters[cue_emitter_state][CueSelector.HEAD]["yoffset"]
	var x = 0
	var x_head = 0
	
	var hand_delay = 0.15
	var dd_df = fly_distance/fly_time				
	
	create_and_attach_cue("head", x_head, y_head, target_time)
	if cue_parameters[cue_emitter_state][CueSelector.HAND]["has_hand"]:
		create_and_attach_cue("left", x-cue_parameters[cue_emitter_state][CueSelector.HAND]["xspread"], y_hand, target_time+hand_delay, -hand_delay * dd_df)
		create_and_attach_cue("right", x+cue_parameters[cue_emitter_state][CueSelector.HAND]["xspread"], y_hand, target_time+hand_delay, -hand_delay * dd_df)

	
enum BurpeeState {
	PUSHUP_HIGH = 0,
	PUSHUP_LOW = 1,
	JUMP = 2,
};	

var burpee_state_model = { BurpeeState.PUSHUP_LOW : { BurpeeState.JUMP: 100},
						BurpeeState.PUSHUP_HIGH : { BurpeeState.PUSHUP_LOW: 100},
						BurpeeState.JUMP : { BurpeeState.PUSHUP_HIGH: 100},
					};
	
var burpee_state = BurpeeState.JUMP


func handle_burpee_cues(target_time):
	if exercise_changed:
		burpee_state = BurpeeState.JUMP
		
	burpee_state = state_transition (burpee_state, burpee_state_model)
	var y_head = 0
	var x_head = 0

	if burpee_state == BurpeeState.PUSHUP_HIGH:
		switch_floor_sign("hands")
		y_head = cue_parameters[cue_emitter_state][CueSelector.HEAD]["yoffset"]
	elif burpee_state == BurpeeState.PUSHUP_LOW:
		switch_floor_sign("hands")
		y_head = 0.3
		temporary_cue_space_extension = 1.2
	else:
		switch_floor_sign("feet")
		y_head = player_height + jump_offset
		temporary_cue_space_extension = 1.2
	
	if burpee_state == BurpeeState.JUMP:
		create_and_attach_cue("head_extended", x_head, y_head, target_time)
	else:
		create_and_attach_cue("head", x_head, y_head, target_time)
	
var squat_state = SquatState.HEAD
	
func handle_squat_cues(target_time):
	switch_floor_sign("feet")
	
	squat_state = state_transition (squat_state, squat_state_model)
	
	var node_selector = rng.randi()%100
	
	var y_head = player_height/2 + cue_parameters[cue_emitter_state][CueSelector.HEAD]["yoffset"] + rng.randf() * cue_parameters[cue_emitter_state][CueSelector.HEAD]["yrange"]
	var y_hand = y_head + (rng.randf() * 0.4 - 0.2)
	var x = 0.3 + rng.randf() * 0.45
	var x_head = rng.randf() * cue_parameters[cue_emitter_state][CueSelector.HAND]["xspread"] - cue_parameters[cue_emitter_state][CueSelector.HAND]["xspread"]/2
	
	if squat_state == SquatState.LEFT_HAND:
		var n = create_and_attach_cue("left", -x,y_hand, target_time, -hand_cue_offset)
	elif squat_state == SquatState.RIGHT_HAND:
		var n = create_and_attach_cue("right", x,y_hand, target_time, -hand_cue_offset)
	else:
		create_and_attach_cue("head", x_head, y_head, target_time)
	
	
func handle_crunch_cues(target_time):
	switch_floor_sign("none")
	
	var node_selector = rng.randi()%100
	
	var rot = (rng.randf()-0.5) * deg2rad(cue_parameters[cue_emitter_state][CueSelector.HAND]["rotation_range"])
		
	var x_head = rng.randf() * cue_parameters[cue_emitter_state][CueSelector.HEAD]["xrange"] - cue_parameters[cue_emitter_state][CueSelector.HEAD]["xrange"]/2
	var y_head = cue_parameters[cue_emitter_state][CueSelector.HEAD]["yoffset"] + rng.randf() * cue_parameters[cue_emitter_state][CueSelector.HEAD]["yrange"]
	
	var rot_distance_reduction = max(0.4, 1.0 - (1.5 * abs(rot)/PI))
	var y_hand = rot_distance_reduction *  cue_parameters[cue_emitter_state][CueSelector.HAND]["yoffset"] + rng.randf() * cue_parameters[cue_emitter_state][CueSelector.HAND]["yrange"]
	var x = rng.randf() * cue_parameters[cue_emitter_state][CueSelector.HAND]["xrange"] - cue_parameters[cue_emitter_state][CueSelector.HAND]["xrange"]/2
	
	print ("Crunch Spread %.2f"%(cue_parameters[cue_emitter_state][CueSelector.HAND]["xspread"]))
	
	if cue_selector == CueSelector.HAND and node_selector < 80:
		cue_selector = CueSelector.HEAD
	elif cue_selector == CueSelector.HEAD and node_selector < 80:
		cue_selector = CueSelector.HAND
	
	if cue_selector == CueSelector.HAND:
		var spread = cue_parameters[cue_emitter_state][CueSelector.HAND]["xspread"]/2.0+rng.randf()*cue_parameters[cue_emitter_state][CueSelector.HAND]["xspread"]
		var t = Transform(Vector3(1,0,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(0,0,0)).rotated(Vector3(0,0,1), rot)
		var tmp = t.xform(Vector3(x+spread,y_hand,0))		
		create_and_attach_cue("right", tmp.x, tmp.y, target_time)
		tmp = t.xform(Vector3(x-spread,y_hand,0))		
		create_and_attach_cue("left", tmp.x,tmp.y, target_time)
	else:
		create_and_attach_cue("head", x_head, y_head, target_time)

	


var pushup_state = PushupState.REGULAR
var pushup_distribution = {}

func handle_pushup_cues(target_time):
	switch_floor_sign("hands")
	
	
	if rebalance_exercises:
		pushup_state = state_transition (pushup_state, pushup_state_model, pushup_distribution)
	else:
		pushup_state = state_transition (pushup_state, pushup_state_model)
		
	var node_selector = rng.randi()%100

	var y_head = cue_parameters[cue_emitter_state][CueSelector.HEAD]["yoffset"] + rng.randf() * cue_parameters[cue_emitter_state][CueSelector.HEAD]["yrange"]
	var x = 0.3 + rng.randf() * 0.25
	var x_head = rng.randf() * cue_parameters[cue_emitter_state][CueSelector.HEAD]["xrange"] - cue_parameters[cue_emitter_state][CueSelector.HEAD]["xrange"]/2
	var y_hand = 0.3 + rng.randf() * 0.4
	
	if pushup_state == PushupState.REGULAR:
		create_and_attach_cue("head", x_head, y_head, target_time)
	elif pushup_state == PushupState.LEFT_HAND:
			var n = create_and_attach_cue("left", -x,y_hand, target_time, -hand_cue_offset,0,"onehanded")
	elif pushup_state == PushupState.RIGHT_HAND:
			var n = create_and_attach_cue("right", x,y_hand, target_time, -hand_cue_offset,0,"onehanded")
	elif pushup_state == PushupState.LEFT_SIDEPLANK or pushup_state == PushupState.RIGHT_SIDEPLANK:
		#side plank
		x_head = 0
		x = 0
		y_head = player_height * 0.5
		y_hand = player_height * 0.9

		var hand_delay = 0.15
		var dd_df = fly_distance/fly_time				
				
		if pushup_state == PushupState.LEFT_SIDEPLANK:
			create_and_attach_cue("head_left", x_head-0.3, y_head, target_time,0,0,"sideplank")
			create_and_attach_cue("right", x, y_hand, target_time+hand_delay, -hand_delay * dd_df,0,"sideplank")
		else:
			create_and_attach_cue("head_right", x_head+0.3, y_head, target_time,0,0,"sideplank")
			create_and_attach_cue("left", x, y_hand, target_time + hand_delay, -hand_delay * dd_df,0,"sideplank")
		temporary_cue_space_extension = 2.5



func internal_state_change():
	state_changed = true
	last_state_change = cue_emitter.current_playback_time
	infolayer.print_info(state_string(cue_emitter_state).to_upper(), "main")
	infolayer.get_parent().render_target_update_mode = Viewport.UPDATE_ONCE
	get_node("PositionSign").start_sign(cue_emitter.translation, get_node("target").translation, emit_early)
	if not boxman1.in_beast_mode:
		switch_boxman(cue_emitter_state,"boxman")
	if not boxman2.in_beast_mode:
		switch_boxman(cue_emitter_state,"boxman2")
	display_state(cue_emitter_state)


func reset_cue_spacing():
	min_cue_space = level_min_cue_space

func adjust_cue_spacing():
	# Increase the cue speed for hand cues
	if cue_selector == CueSelector.HAND:
		min_cue_space = level_min_cue_space / 2
	else:
		min_cue_space = level_min_cue_space

var state_changed = false
func emit_cue_node(target_time):
	print ("State: %s"%state_string(cue_emitter_state))
	if last_state_change + state_duration < cue_emitter.current_playback_time:
		var old_state = cue_emitter_state
		if len(state_list) > 0:
			print ("Take preset state")
			next_state_from_list()
		else:
			print ("Take random state")
			cue_emitter_state = state_transition(cue_emitter_state, exercise_state_model, null, false)
			state_duration = min_state_duration * (1 + current_difficulty*current_difficulty*rng.randf()/5)

		internal_state_change()		

	if cue_emitter_state == CueState.STAND and beast_mode:
		if not boxman1.in_beast_mode and not boxman2.in_beast_mode:
			var beast_tmp = rng.randf()
			if beast_tmp < beast_chance:
				var boxman = boxman1 
				if rng.randf() < 0.5:
					 boxman = boxman2
				boxman.activate_beast(Vector3(0,0,1),1.8)

	reset_cue_spacing()
	if not state_changed:
		if cue_emitter_state == CueState.STAND:
			adjust_cue_spacing()
			handle_stand_cues(target_time)
		elif cue_emitter_state == CueState.JUMP:
			handle_jump_cues(target_time)
		elif cue_emitter_state == CueState.SQUAT:
			adjust_cue_spacing()
			handle_squat_cues(target_time)
		elif cue_emitter_state == CueState.CRUNCH:
			adjust_cue_spacing()
			handle_crunch_cues(target_time)
		elif cue_emitter_state == CueState.BURPEE:
			handle_burpee_cues(target_time)
		elif cue_emitter_state == CueState.SPRINT:
			handle_sprint_cues(target_time)
		elif cue_emitter_state == CueState.YOGA:
			handle_yoga_cues(target_time)
		else: #CueState.PUSHUP
			handle_pushup_cues(target_time)
		exercise_changed = false
	else:
		if cue_emitter_state == CueState.BURPEE or cue_emitter_state == CueState.PUSHUP:
			update_safe_pushup()
			
		exercise_changed = true
		state_changed = false
		
func update_safe_pushup():
	if hud_enabled:
		var main_camera = get_viewport().get_camera()
		if cue_emitter_state == CueState.BURPEE or cue_emitter_state == CueState.PUSHUP:
			main_camera.show_hud(true)
			get_node("MainStage/mat").open_mat()
		else:
			get_node("MainStage/mat").close_mat()
			main_camera.show_hud(false)
		
func switch_boxman(state, name):
	var boxman = get_node(name)
	if cue_emitter_state == CueState.STAND:
		if name == "boxman2":
			boxman.switch_to_run()
		else:
			boxman.switch_to_stand()
	elif cue_emitter_state == CueState.JUMP:
		boxman.switch_to_jumping()
	elif cue_emitter_state == CueState.SQUAT:
		boxman.switch_to_squat()
	elif cue_emitter_state == CueState.CRUNCH:
		boxman.switch_to_situps()
	elif cue_emitter_state == CueState.PUSHUP:
		boxman.switch_to_plank()
	elif cue_emitter_state == CueState.BURPEE:
		boxman.switch_to_plank() #TODO make a burpee animation
	elif cue_emitter_state == CueState.SPRINT:
		boxman.switch_to_run() 


func _on_exit_button_pressed():
	emit_signal("level_finished")

var last_run_update = 0		
func setup_multiplier(running_speed):
	var xx = get_node("RunIndicator")
	if running_speed > 13.5:
		xx.play("hyperspeed")
		run_point_multiplier = 4
	elif running_speed > 10:
		xx.play("runx3")
		run_point_multiplier = 3
	elif running_speed > 7:
		xx.play("runx2")
		run_point_multiplier = 2
	else:
		xx.stop()
		run_point_multiplier = 1

	var now = OS.get_ticks_msec()
	var delta = (now-last_run_update)/1000.0
	if last_run_update > 0 and run_point_multiplier > 1:
		trophy_list.set_runtime(trophy_list.runtime + delta)
	last_run_update = now


func get_points():
	return {"points": cue_emitter.points, "hits": cue_emitter.hits, "max_hits": cue_emitter.max_hits,"time": last_playback_time}

var last_grooove_update = 0
func update_groove(groove_bpm):
	var now = OS.get_ticks_msec()
	var delta = (now - last_grooove_update)/1000.0
	if last_grooove_update > 0:
		if groove_bpm > 0:
			var multiplier = song_current_bpm / groove_bpm
			#print ("Current_bpm: %f Song BPM: %f  Mult: %f"%[groove_bpm, song_current_bpm, multiplier])
			if abs(multiplier-1) < 0.15 or abs(multiplier-2) < 0.2 or abs(multiplier-4) < 0.3:
				#Groove detected
				trophy_list.set_groovetime(trophy_list.groove + delta)
	last_grooove_update = now	

var gui_update = 0
func _on_UpdateTimer_timeout():
	running_speed = self.get_parent().get_running_speed()
	var gauge = get_node("rungauge")
	if cue_emitter_state != CueState.SPRINT and gauge.value_text:
			gauge.hide()

	gauge.set_value(running_speed)
	update_groove(self.get_parent().get_groove_bpm())
	setup_multiplier(running_speed)
	if gui_update % 10 == 0:
		self.update_info(cue_emitter.hits, cue_emitter.max_hits, cue_emitter.points)
	gui_update += 1


func _on_AudioStreamPlayer_finished():
	stream.stop()
	var t = Timer.new()
	t.connect("timeout", self, "_on_exit_timer_timeout")
	t.set_wait_time(5)
	self.add_child(t)
	t.start()

#Returns true if the current state supports claws
func beast_mode_supported():
	return cue_emitter_state == CueState.STAND or boxman1.in_beast_mode or boxman2.in_beast_mode

func _on_boxman_beast_attack_successful():
	cue_emitter.score_negative_hits(10)


func _on_boxman_beast_killed():
	cue_emitter.score_positive_hits(10)


func _on_ExerciseSelector_selected(type):
	cue_emitter_state = string_to_state(type)
	last_state_change = cue_emitter.current_playback_time
	internal_state_change()


func _on_PositionSign_state_change_completed():
	update_safe_pushup()
	var gauge = get_node("rungauge")
	if cue_emitter_state == CueState.SPRINT and not gauge.visible:
		gauge.show()

		
var auto_hit_distance = 0.3
func controller_tracking_lost(controller):
	var node = cue_emitter.get_closest_cue(controller.global_transform.origin, "hand", controller.is_left)
	print ("Tracking lost. Closest object: %s"%str(node))
	if node:
		if node.global_transform.origin.distance_to(controller.global_transform.origin) < auto_hit_distance:
			var type = "right"
			if controller.is_left:
				type = "left"
				
			node.has_been_hit(type)
	
func controller_tracking_regained(controller):
	var node = cue_emitter.get_closest_cue(controller.global_transform.origin, "hand", controller.is_left)
	print ("Tracking regained. Closest object: %s"%str(node))

	if node:
		if node.global_transform.origin.distance_to(controller.global_transform.origin) < auto_hit_distance:
			var type = "right"
			if controller.is_left:
				type = "left"
				
			node.has_been_hit(type)
		
