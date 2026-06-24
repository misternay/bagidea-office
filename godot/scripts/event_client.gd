extends Node
## Renderer-side adapter client. Subscribes to the daemon's WebSocket event
## stream (one JSON event per message; new connections receive a journal
## replay so the world state survives restarts). Reconnects forever;
## connection state shows on the lobby status totem (truth, not theater).

const URL := "ws://127.0.0.1:8787/ws"
# roster.sync carries every agent's full persona prompt, so a full team easily
# tops Godot's 64 KB default inbound buffer — the whole message is then dropped
# and the office shows only the CEO (the rest never get a body). Give it room.
const IN_BUF := 1 << 20  # 1 MB

var _ws := WebSocketPeer.new()
var _retry := 0.0
var _was_connected := false

@onready var manager: Node = get_node("../AgentManager")

func _ready() -> void:
	_ws.inbound_buffer_size = IN_BUF
	_ws.connect_to_url(URL)

func _process(delta: float) -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	var connected := state == WebSocketPeer.STATE_OPEN

	if connected != _was_connected:
		_was_connected = connected
		manager.set_connected(connected)

	match state:
		WebSocketPeer.STATE_OPEN:
			while _ws.get_available_packet_count() > 0:
				_handle(_ws.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_retry -= delta
			if _retry <= 0.0:
				_retry = 3.0
				_ws = WebSocketPeer.new()
				_ws.inbound_buffer_size = IN_BUF
				_ws.connect_to_url(URL)

func _handle(line: String) -> void:
	var evt: Variant = JSON.parse_string(line)
	if evt is Dictionary:
		# Office Editor saves → re-apply the custom layout (skip replay).
		if evt.get("type") == "layout.changed" and not evt.get("replay", false):
			var loader := get_node_or_null("../OfficeFloor/LayoutLoader")
			if loader == null:
				loader = get_tree().get_root().find_child("LayoutLoader", true, false)
			if loader and loader.has_method("reload"):
				loader.reload()
			return
		manager.handle(evt)
