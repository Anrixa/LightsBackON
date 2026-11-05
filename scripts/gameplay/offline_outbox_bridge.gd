extends RefCounted
## Offline host adapter for the UI intent outbox.
##
## Both sides are weak references on purpose. An OfflineSession owns its
## IntentOutbox, and that outbox keeps its send Callable and replied listener
## alive. Pointing either Callable back at the owning session creates a
## RefCounted cycle that prevents whole C01 host graphs from being released.
##
## No authority is moved here: the host still validates the same envelope
## bytes and the same trusted local peer ID as an ordinary host-local action.

var _host: WeakRef
var _owner: WeakRef
var _peer_id: int


func _init(host: RefCounted, owner: RefCounted, peer_id: int) -> void:
	_host = weakref(host)
	_owner = weakref(owner)
	_peer_id = peer_id


func send(bytes: PackedByteArray) -> Dictionary:
	var active_host: RefCounted = _host.get_ref() as RefCounted
	if active_host == null:
		return {"ok": false, "code": "SESSION_GONE"}
	return active_host.call("receive", _peer_id, bytes) as Dictionary


func on_reply(envelope: Dictionary, reply: Dictionary) -> void:
	var active_owner: RefCounted = _owner.get_ref() as RefCounted
	if active_owner != null:
		active_owner.call("_on_reply", envelope, reply)
