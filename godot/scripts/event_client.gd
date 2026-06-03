extends Node
## Renderer-side adapter client. Subscribes to the daemon's WebSocket event
## stream (one JSON event per message; new connections receive a journal
## replay so the world state survives restarts). Reconnects forever;
## connection state shows on the lobby status totem (truth, not theater).

const URL := "ws://127.0.0.1:8787/ws"

var _ws := WebSocketPeer.new()
var _retry := 0.0
var _was_connected := false

@onready var manager: Node = get_node("../AgentManager")

func _ready() -> void:
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
				_ws.connect_to_url(URL)

func _handle(line: String) -> void:
	var evt: Variant = JSON.parse_string(line)
	if evt is Dictionary:
		manager.handle(evt)
