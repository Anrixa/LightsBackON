extends "res://tests/test_case.gd"
## QA52 regression: a local offline host must release its RefCounted
## transport graph when a game scene ends. WeakRef does not own the target.

const OfflineSession := preload("res://scripts/gameplay/offline_c01_session.gd")


func test_QA52_lifetime_offline_host_outbox_do_not_keep_abandoned_session_alive() -> void:
	var session: RefCounted = OfflineSession.new()
	var errors: Array = session.call("setup",
		func(_player: String, _target: String) -> bool: return true,
		func(_player: String) -> Vector3i: return Vector3i(450, 100, 1500))
	assert_true(errors.is_empty(), "real C01 host session must initialize")

	var weak_session: WeakRef = weakref(session)
	var weak_host: WeakRef = weakref(session.get("host") as RefCounted)
	var weak_outbox: WeakRef = weakref(session.get("outbox") as RefCounted)
	# No scene- or test-held strong references should remain. In particular,
	# an outbox callback/signal must not create a session -> outbox -> session cycle.
	session = null

	assert_true(weak_session.get_ref() == null, "abandoned session must be collectible")
	assert_true(weak_host.get_ref() == null, "host graph must be released with the session")
	assert_true(weak_outbox.get_ref() == null, "outbox must not own its previous session")
